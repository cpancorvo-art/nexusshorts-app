-- AI Lead-to-Meeting — Supabase / Postgres schema
-- Run state lives here, not in n8n (n8n "Simple Memory" is lost on restart).
-- Every workflow step reads and writes the per-lead record; every event is logged
-- to lead_events (the audit trail, the dashboard source, and the eval-set feed).
--
-- Apply with: psql $DATABASE_URL -f schema.sql   (or paste into the Supabase SQL editor)

create extension if not exists vector;
create extension if not exists pgcrypto;  -- gen_random_uuid()

-- ---------------------------------------------------------------------------
-- Clients (the agency's customers)
-- ---------------------------------------------------------------------------
create table if not exists clients (
  id            uuid primary key default gen_random_uuid(),
  name          text not null,
  niche         text not null,                       -- e.g. 'med spas'
  target_metro  text,
  sender_name   text not null,                       -- signature identity for drafts
  postal_address text not null,                      -- CAN-SPAM: appended by the sender
  icp_rubric    text not null,                       -- weighted rubric fed to 01-lead-scoring
  voice_rules   text not null,                       -- fed to 03-email-draft / 04-reviewer-judge
  banned_claims text not null default '',            -- fed to 04-reviewer-judge
  segment_opener text not null default '',           -- fallback opener when no hook qualifies
  approval_mode text not null default 'all'
                check (approval_mode in ('all', 'sampling')),  -- 100% until eval thresholds met
  created_at    timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Leads — one row per prospect; the stable per-lead record every step reads
-- ---------------------------------------------------------------------------
create table if not exists leads (
  id              uuid primary key default gen_random_uuid(),
  client_id       uuid not null references clients(id),
  company_name    text not null,
  website_url     text,
  contact_name    text,
  contact_title   text,
  email           text,
  email_verified  boolean not null default false,    -- ZeroBounce/NeverBounce result; never send unverified
  enrichment      jsonb not null default '{}',       -- Clay waterfall output (firmographics etc.)
  -- step 03: scoring (lead-score.schema.json)
  score           integer,
  fit_score       integer,
  intent_score    integer,
  tier            text check (tier in ('A', 'B', 'C')),
  score_reasoning text,
  disqualified    boolean not null default false,
  -- step 04: research hook (research-hook.schema.json)
  hook            jsonb,
  status          text not null default 'new'
                  check (status in ('new', 'enriched', 'scored', 'rejected', 'hooked',
                                    'drafted', 'in_review', 'approved', 'sequenced',
                                    'replied', 'meeting_booked', 'closed', 'suppressed')),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  unique (client_id, email)
);

create index if not exists leads_client_status_idx on leads (client_id, status);

-- ---------------------------------------------------------------------------
-- Drafts — every generated email + its reviewer verdict + approval decision
-- ---------------------------------------------------------------------------
create table if not exists drafts (
  id              uuid primary key default gen_random_uuid(),
  lead_id         uuid not null references leads(id),
  touch_number    integer not null default 1,        -- 1 = first touch, 2+ = follow-ups
  draft           jsonb not null,                    -- email-draft.schema.json
  verdict         jsonb,                             -- reviewer-verdict.schema.json
  revision_count  integer not null default 0,        -- judge retry loop, capped at 2-3
  approval        text not null default 'pending'
                  check (approval in ('pending', 'approved', 'edited', 'rejected', 'auto')),
  approved_by     text,                              -- operator identity for the audit trail
  edited_body     text,                              -- operator edits feed the eval set
  sent_at         timestamptz,
  created_at      timestamptz not null default now()
);

create index if not exists drafts_lead_idx on drafts (lead_id);
create index if not exists drafts_approval_idx on drafts (approval) where approval = 'pending';

-- ---------------------------------------------------------------------------
-- Replies — every inbound reply + its classification
-- ---------------------------------------------------------------------------
create table if not exists replies (
  id              uuid primary key default gen_random_uuid(),
  lead_id         uuid not null references leads(id),
  raw_body        text not null,
  raw_subject     text,
  classification  jsonb not null,                    -- reply-intent.schema.json
  intent          text not null,                     -- denormalized for reporting queries
  human_corrected_intent text,                       -- corrections grow the eval set
  actioned_at     timestamptz,
  created_at      timestamptz not null default now()
);

create index if not exists replies_lead_idx on replies (lead_id);
create index if not exists replies_intent_idx on replies (intent);

-- ---------------------------------------------------------------------------
-- Suppression list — synced to every sending tool; written before any human review
-- ---------------------------------------------------------------------------
create table if not exists suppression_list (
  email       text primary key,
  client_id   uuid references clients(id),           -- null = global suppression
  reason      text not null
              check (reason in ('unsubscribe', 'bounce', 'complaint', 'manual', 'legal')),
  source      text,                                  -- reply id / operator / import
  created_at  timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Event log — append-only; the dashboard source and the compliance audit trail
-- ---------------------------------------------------------------------------
create table if not exists lead_events (
  id          bigint generated always as identity primary key,
  lead_id     uuid references leads(id),
  client_id   uuid not null references clients(id),
  event_type  text not null,                         -- scored / hook_found / drafted /
                                                     -- judge_pass / judge_fail / approved /
                                                     -- sent / reply_classified / suppressed /
                                                     -- meeting_booked / ...
  payload     jsonb not null default '{}',
  created_at  timestamptz not null default now()
);

create index if not exists lead_events_client_time_idx on lead_events (client_id, created_at);
create index if not exists lead_events_type_idx on lead_events (event_type);

-- ---------------------------------------------------------------------------
-- Per-client knowledge base (RAG) — offer, brand voice, FAQs, objection scripts,
-- approved proof points, few-shot example emails. Hundreds to low-thousands of
-- chunks per client: pgvector is more than sufficient; use hybrid search.
-- ---------------------------------------------------------------------------
create table if not exists kb_documents (
  id          uuid primary key default gen_random_uuid(),
  client_id   uuid not null references clients(id),
  doc_type    text not null
              check (doc_type in ('offer', 'voice', 'faq', 'objection_script',
                                  'proof_point', 'example_email', 'qualifying_criteria')),
  title       text not null,
  created_at  timestamptz not null default now()
);

create table if not exists kb_chunks (
  id          uuid primary key default gen_random_uuid(),
  document_id uuid not null references kb_documents(id) on delete cascade,
  client_id   uuid not null references clients(id),
  content     text not null,
  -- 1536 dims matches common embedding models; adjust to your embedding model's
  -- output size and re-embed if you change models.
  embedding   vector(1536),
  fts         tsvector generated always as (to_tsvector('english', content)) stored,
  created_at  timestamptz not null default now()
);

create index if not exists kb_chunks_embedding_idx
  on kb_chunks using hnsw (embedding vector_cosine_ops);
create index if not exists kb_chunks_fts_idx on kb_chunks using gin (fts);
create index if not exists kb_chunks_client_idx on kb_chunks (client_id);

-- Hybrid retrieval: vector similarity + full-text, reciprocal-rank fused.
create or replace function kb_search(
  p_client_id uuid,
  p_query_text text,
  p_query_embedding vector(1536),
  p_limit int default 8
)
returns table (chunk_id uuid, content text, score double precision)
language sql stable as $$
  with vec as (
    select id, row_number() over (order by embedding <=> p_query_embedding) as rnk
    from kb_chunks
    where client_id = p_client_id and embedding is not null
    order by embedding <=> p_query_embedding
    limit 30
  ),
  txt as (
    select id, row_number() over (
      order by ts_rank(fts, websearch_to_tsquery('english', p_query_text)) desc
    ) as rnk
    from kb_chunks
    where client_id = p_client_id
      and fts @@ websearch_to_tsquery('english', p_query_text)
    limit 30
  )
  select c.id, c.content,
         coalesce(1.0 / (60 + vec.rnk), 0) + coalesce(1.0 / (60 + txt.rnk), 0) as score
  from kb_chunks c
  left join vec on vec.id = c.id
  left join txt on txt.id = c.id
  where vec.id is not null or txt.id is not null
  order by score desc
  limit p_limit;
$$;

-- ---------------------------------------------------------------------------
-- Weekly metrics aggregation — feeds prompts/06-weekly-report.md.
-- The LLM narrates these numbers; it never computes its own.
-- ---------------------------------------------------------------------------
create or replace function weekly_metrics(p_client_id uuid, p_week_start date)
returns jsonb language sql stable as $$
  select jsonb_build_object(
    'week_start', p_week_start,
    'prospects_contacted', (
      select count(distinct lead_id) from lead_events
      where client_id = p_client_id and event_type = 'sent'
        and created_at >= p_week_start and created_at < p_week_start + 7
    ),
    'emails_sent', (
      select count(*) from lead_events
      where client_id = p_client_id and event_type = 'sent'
        and created_at >= p_week_start and created_at < p_week_start + 7
    ),
    'replies', (
      select count(*) from replies r join leads l on l.id = r.lead_id
      where l.client_id = p_client_id
        and r.created_at >= p_week_start and r.created_at < p_week_start + 7
    ),
    'positive_replies', (
      select count(*) from replies r join leads l on l.id = r.lead_id
      where l.client_id = p_client_id
        and r.intent in ('interested', 'meeting_booked', 'referral')
        and r.created_at >= p_week_start and r.created_at < p_week_start + 7
    ),
    'meetings_booked', (
      select count(*) from lead_events
      where client_id = p_client_id and event_type = 'meeting_booked'
        and created_at >= p_week_start and created_at < p_week_start + 7
    ),
    'unsubscribes', (
      select count(*) from replies r join leads l on l.id = r.lead_id
      where l.client_id = p_client_id and r.intent = 'unsubscribe'
        and r.created_at >= p_week_start and r.created_at < p_week_start + 7
    )
  );
$$;
