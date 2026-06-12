# AI Lead-to-Meeting Workflows

Build kit for an AI lead-to-meeting agency: deterministic workflows with single-purpose
LLM steps, structured JSON outputs at every step, and a human approval gate before any
message reaches a prospect.

**Architecture rule: workflows, not autonomous agents.** Every step is a predefined code
path (n8n / Make / Clay) that calls an LLM for one narrow job and validates the result in
code. Agent frameworks (LangGraph etc.) are deferred until a specific step proves it needs
dynamic branching deeper than ~3 nodes — for this use case, that's rare.

## What's in this directory

```
workflows/lead-to-meeting/
  README.md                      — this file: architecture, golden path, build order
  prompts/                       — versioned prompt templates, one per LLM step
    01-lead-scoring.md
    02-research-hook.md
    03-email-draft.md
    04-reviewer-judge.md
    05-reply-classification.md
    06-weekly-report.md
  schemas/                       — strict JSON Schemas (the API contract for each step)
    lead-score.schema.json
    research-hook.schema.json
    email-draft.schema.json
    reviewer-verdict.schema.json
    reply-intent.schema.json
  supabase/
    schema.sql                   — Postgres + pgvector: leads, events, drafts, replies,
                                   suppression list, per-client knowledge base (RAG)
  n8n/
    golden-path.workflow.json    — importable skeleton of the end-to-end chain
```

## The golden path (build this ONE chain first)

Pick one niche, one channel (cold email), one workflow chain. Test against your own
inboxes and sample data before pointing it at real prospects.

| # | Step | Tool | LLM step | Contract |
|---|------|------|----------|----------|
| 1 | List build | Clay (seed CSV import) | — | lead rows |
| 2 | Enrich + verify email | Clay waterfall → ZeroBounce/NeverBounce | — | bounce risk < 2%; skip unverified rows |
| 3 | Qualify / score | Clay or n8n → Claude | `01-lead-scoring` | `lead-score.schema.json`; gate: score ≥ threshold |
| 4 | Research hook | Claygent | `02-research-hook` | `research-hook.schema.json`; gate: confidence + hook quality |
| 5 | Draft email | n8n → Claude (writer model) | `03-email-draft` | `email-draft.schema.json`; <120 words, verified fields only |
| 6 | Reviewer / QA | n8n → Claude (different model as judge) | `04-reviewer-judge` | `reviewer-verdict.schema.json` |
| 7 | Human approval gate | n8n Wait node / Slack approve | — | operator approves 100% of sends early on |
| 8 | Send + follow-up | Instantly (solo) / Smartlead (agency) | — | warmed inboxes, 30–50 emails/inbox/day |
| 9 | Classify reply | n8n → Claude Haiku | `05-reply-classification` | `reply-intent.schema.json` → action routing |
| 10 | Book | Cal.com | — | meeting + full thread context → CRM |
| 11 | Report | Supabase → Looker Studio / Softr | `06-weekly-report` | fixed-section summary from structured metrics only |

## Model routing (tiered)

The expensive model writes; a *different* model judges; the cheap model classifies.
Using distinct models for writer and judge keeps the QA step genuinely independent
(cross-vendor — e.g. a GPT writer with a Claude judge — is the strongest version of
this; within one vendor, use different model tiers).

| Role | Default model | Why |
|------|---------------|-----|
| Writer (email drafts, hooks) | `claude-sonnet-4-6` | strong copy/reasoning, 1M context, prompt caching |
| Reviewer / judge | `claude-opus-4-8` | different (stronger) model than the writer; catches hallucinated claims |
| Classification / scoring | `claude-haiku-4-5` | <$0.01 per reply at $1/$5 per MTok |

All calls go through the Anthropic Messages API with **structured outputs**
(`output_config: {format: {type: "json_schema", schema: ...}}`) so responses are
schema-guaranteed — no regex parsing, no "repair" retries on malformed JSON. The schemas
in `schemas/` are written to the structured-outputs subset (`additionalProperties: false`
on every object, no numeric/string constraints).

Note: LLM pricing and model versions shift quarterly. The *relative* tiering (cheap
classifier / mid writer / strong judge) is the stable advice — verify rate cards before
committing volume.

## Reliability layer (non-negotiable)

1. **Every LLM output is an API contract.** Strict schema, validated in code. With native
   structured outputs the validate/repair loop collapses to a single guaranteed-shape call.
2. **Layer cheap deterministic checks before the LLM judge:** banned-word blocklist,
   length cap, required compliance elements (opt-out, postal address), schema validation.
3. **Reviewer-LLM confidence routing:** verdict `pass` + confidence > 0.9 → proceed;
   0.6–0.9 → proceed but flag for async human review; < 0.6 or `fail` → block + escalate.
   Cap automatic revision retries at 2–3.
4. **Human approval is mandatory at two steps:** the *send* step and any
   *booking/pricing-commitment* step. Keep 100% manual approval until: reviewer false-pass
   rate ≈ 0 on your planted-hallucination test set AND manual edit rate on drafts < 10–20%.
   Then move to sampling (review flagged + a random 10–20%).
5. **Evals before production.** Wire prompts into Langfuse (OSS) or Braintrust, build a
   test set of messy/adversarial inputs (typos, incomplete data, planted hallucinations,
   banned claims), and gate prompt changes on eval scores. Prompts live in this repo —
   version control is the source of truth, not a vendor prompt store.
6. **Determinism is bounded.** Even at temperature 0, LLMs vary across runs
   (arXiv:2408.04667). That's *why* the judge gate and human approval exist. Never promise
   clients "fully autonomous" — promise reliable, human-supervised automation.

## State and human-in-the-loop mechanics

- **State lives in Supabase, not in n8n.** Every step reads/writes the per-lead record
  (`supabase/schema.sql`); n8n "Simple Memory" is lost on restart. Each node's structured
  JSON output feeds the next node's input.
- **Human gates** (n8n Wait node or Slack approve button) at: (a) first-send to a new
  client's prospect list, (b) any reply classified `unclear` or low-confidence, (c) any
  reviewer `fail` or medium-confidence flag.
- **Every event is logged** to `lead_events` — that table is the source for the client
  dashboard and the audit trail for compliance.

## Reply intent → action routing

| Intent | Action | SLA |
|--------|--------|-----|
| `interested` | route to operator + calendar link + CRM → "engaged" | < 2h |
| `meeting_booked` | handoff with full thread context | immediate |
| `referral` | create new lead + warm intro draft | < 24h |
| `info_request` / `objection` | send resource / objection-typed nurture (re-engage 3–6 mo) | < 4h |
| `not_interested` | polite close + long-term nurture | — |
| `unsubscribe` | **immediate** suppression across all inboxes + CRM (CAN-SPAM) | immediate |
| `out_of_office` | pause sequence, resume on return date | — |
| `bounce` | permanent removal | immediate |
| `unclear` | human review queue | < 4h |

## Compliance (built into the workflow, not bolted on)

- **CAN-SPAM (US):** every email needs a functional opt-out, a physical postal address,
  and accurate sender/subject info. Process opt-outs immediately (legal max: 10 business
  days). Penalties run to ~$53k per violating email — the reviewer judge checks these
  elements on every draft (`04-reviewer-judge`).
- **GDPR (EU/UK):** B2B cold email under legitimate interest only if relevant to the
  recipient's professional role; data minimization (name, business email, company, title);
  document a Legitimate Interest Assessment and the source of every contact.
- **EU AI Act Art. 50 (applicable 2 Aug 2026):** AI-generated outbound content must be
  disclosed *unless it has undergone human review or editorial control* — the human
  approval gate is itself part of the compliance posture. Keep it documented.
- **Operationalize:** `suppression_list` table syncs to every sending tool; spam-complaint
  rate < 0.3%; bounce rate < 2% (verify emails before sending — dead addresses torch the
  domain).

## Build order

- **Stage 0 (week 1):** one niche, one channel. Sending infra first: buy domains, set
  SPF/DKIM/DMARC, warm 10–30 inboxes ≥ 14 days. Stand up Supabase (run
  `supabase/schema.sql`), n8n, Clay, Cal.com, dashboard shell. Draft the client knowledge
  base (offer, brand voice, FAQs, objection scripts) → embed into `kb_chunks`.
- **Stage 1 (weeks 2–3):** build the 11-step chain on sample data; dry-run end-to-end
  sending **only to your own seed inboxes**; verify the judge catches deliberately planted
  hallucinations and banned claims.
- **Stage 2 (week 4):** wire evals (Langfuse/Braintrust), set reviewer pass-rate
  thresholds, keep 100% human approval.
- **Stage 3 (weeks 5–8):** first client at low/no cost for a case study; few hundred
  prospects; human-approved sends; weekly ROI reporting on reply rate, positive-reply
  rate, meetings booked (not open rates).
- **Stage 4:** add LinkedIn, reporting automation, ops workflows; only then clone the
  workflow set for a second niche.

## Thresholds that change the plan

- Reply rate stuck at 1–3% → fix targeting and hooks (Claygent filtering), not volume.
- Opens fall 30–40% → deliverability/infra problem (warmup, DNS), not the LLM.
- Clay credit spend spikes → you're enriching unfiltered lists; move the ICP gate
  *before* enrichment (failed lookups still burn credits).
- A step needs dynamic branching beyond ~3 nodes → consider LangGraph for that step only.

## Realistic MVP cost (one operator, 1–3 clients)

Clay Launch ~$185 · sending tool $40–97 + inboxes $50–150 · n8n $0–50 (self-host) ·
Supabase $0–25 · Cal.com $0 · Looker Studio $0 · Softr $0–49 · LLM tokens typically
$0.001–$0.03/lead (usually < $50/mo at a few thousand leads) · Sales Navigator ~$100 if
doing LinkedIn. **Total: roughly $400–800/month.**
