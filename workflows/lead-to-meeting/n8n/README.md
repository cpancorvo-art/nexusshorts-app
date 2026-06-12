# n8n Golden-Path Workflow

`golden-path.workflow.json` is an importable **skeleton** of the end-to-end chain — it
encodes the topology, gates, and API call shapes, not a turnkey deployment. After
importing (n8n → Workflows → Import from File), wire up:

## 1. Credentials

- **Anthropic API (x-api-key)** — Header Auth credential, header name `x-api-key`,
  value your Anthropic key. Used by all four Claude nodes.
- **Supabase** — project URL + service-role key, used by the save/log/suppress nodes.
- **Slack** — for the approval gate and operator notifications.
- **Instantly/Smartlead** — API key on the sequencer node.

## 2. Variables (`$vars`)

The Claude nodes load prompts and schemas from n8n Variables so the repo stays the
source of truth. Create these (Settings → Variables), pasting from this directory:

| Variable | Source |
|---|---|
| `PROMPT_LEAD_SCORING` | system prompt block in `../prompts/01-lead-scoring.md` |
| `PROMPT_RESEARCH_HOOK` | `../prompts/02-research-hook.md` |
| `PROMPT_EMAIL_DRAFT` | `../prompts/03-email-draft.md` |
| `PROMPT_REVIEWER_JUDGE` | `../prompts/04-reviewer-judge.md` |
| `PROMPT_REPLY_CLASSIFICATION` | `../prompts/05-reply-classification.md` (incl. few-shots) |
| `SCHEMA_LEAD_SCORE` … `SCHEMA_REPLY_INTENT` | the five files in `../schemas/` |
| `CLIENT_ICP_RUBRIC`, `CLIENT_VOICE_RULES`, `CLIENT_BANNED_CLAIMS` | per client, from the `clients` table |
| `INSTANTLY_CAMPAIGN_ID` | per client campaign |

For multi-client operation, replace the `CLIENT_*` variables with a Supabase lookup at
the top of each run (the `clients` table holds the same fields).

## 3. What the skeleton intentionally leaves out

- **Per-step event logging** — every node should append to `lead_events`; only the
  final `sent` log node is included.
- **Revision-retry counter** — the `revise` branch loops back to the draft node; add a
  counter field on the item and route to the human queue after 2 retries.
- **The fail/escalation branch** of the verdict gate and the remaining intent branches
  (referral, objection nurture, out-of-office pause) — stubs are noted on the Switch
  nodes; add one action node per branch following the routing table in the main README.
- **Cal.com booking + CRM write** — trigger from the `interested`/`meeting_booked`
  branches.

## 4. Reminders

- The **Wait (Human Approval)** node is mandatory while `approval_mode='all'`. Its
  resume webhook is what your Slack Approve button calls.
- Webhook URLs (`/lead-in`, `/reply-in`) go into Clay's HTTP API column and the
  sequencer's reply-webhook settings respectively.
- Test the full chain end-to-end against **your own seed inboxes** before any real
  prospect enters the `lead-in` webhook.
