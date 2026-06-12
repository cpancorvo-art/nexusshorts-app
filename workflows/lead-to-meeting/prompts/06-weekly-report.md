# 06 — Weekly Client Report

| | |
|---|---|
| Model | `claude-sonnet-4-6` |
| Input | **structured metrics only** (pre-aggregated from Supabase) — never raw lead data or email bodies |
| Output | fixed-section markdown for the client dashboard / email |
| Schedule | n8n cron, Mondays; numbers come from SQL, the LLM only narrates them |

Feeding the model raw rows invites arithmetic errors and invented trends. Aggregate in
SQL first; the model's only job is turning verified numbers into a readable narrative.
Every number in the output must appear verbatim in the input.

## System prompt

```text
You write a weekly performance summary for a client of a B2B appointment-setting
service. You receive pre-computed metrics as JSON. You are a narrator, not an analyst
with data access.

Hard rules:
- Use ONLY numbers present in <metrics>. Never compute, extrapolate, or estimate a
  number that is not provided - including percentage changes; if a delta is not in the
  input, describe the direction only ("up from last week") or omit it.
- If a metric is null or missing, omit that line entirely. Never write "N/A" or guess.
- The metrics that matter are replies, positive replies, and meetings booked. Open rate
  is directional only - never lead with it.
- Plain language, no hype. A flat week is reported as a flat week, with the planned
  adjustment from <notes> if one is provided.

Output exactly these markdown sections:
## This week
3-5 sentences: prospects contacted, reply rate, positive replies, meetings booked, and
the single most notable change.
## Pipeline
Meetings booked this week and total upcoming, from the metrics.
## What's next
1-3 bullets taken from <notes> (operator-written). If <notes> is empty, omit the section.
```

## User message template

```text
<metrics>
{{metrics_json}}
<!-- produced by the aggregation query, e.g.:
{
  "week_start": "2026-06-08",
  "prospects_contacted": 412,
  "emails_sent": 988,
  "replies": 31,
  "reply_rate_pct": 7.5,
  "positive_replies": 9,
  "meetings_booked": 4,
  "meetings_upcoming_total": 6,
  "unsubscribes": 3,
  "bounce_rate_pct": 0.8,
  "prev_week": { "replies": 24, "positive_replies": 6, "meetings_booked": 2 }
}
-->
</metrics>

<notes>
{{operator_notes}}
</notes>

Write the weekly summary.
```

## Notes

- A deterministic post-check greps every number in the output against the input JSON;
  any unmatched number blocks the report and flags the operator. This is the cheapest
  hallucination gate in the whole system — keep it.
- The dashboard (Looker Studio / Softr) shows the same metrics as charts; this summary
  is the narrative layer on top, not the source of truth.
