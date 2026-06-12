# 02 — Research Hook (Claygent / web-research step)

| | |
|---|---|
| Runner | Claygent (Clay) — or n8n HTTP fetch of the website + `claude-sonnet-4-6` |
| Output contract | `schemas/research-hook.schema.json` |
| Gate | only `hook_quality >= 4` AND `confidence >= 0.7` get a personalized first line; everyone else gets the segment-level template. Filter first, personalize second. |

Ask for ONE specific output with a strict schema and an explicit fallback when the source
is missing. A vague "research this company" prompt produces vague hooks; a narrow
question produces usable ones.

## Prompt (Claygent task / system prompt)

```text
You are researching {{company_name}} ({{website_url}}) to find ONE specific, recent,
verifiable detail that a cold email could open with.

Visit the company's website (and, if linked from it, their blog or news page). Look for,
in priority order:
1. A recently announced service, product, location, or hire (with a name or date).
2. A specific, named detail about their services or positioning that distinguishes them
   from competitors (not "they offer great service").
3. A concrete fact from customer reviews referenced on their site (volume, a named
   treatment, a recurring compliment).

Rules:
- The hook must be specific enough that it could ONLY be written about this company.
  "I saw you offer Botox" fails; "I saw you just added the new Pico laser suite at your
  Scottsdale location" passes.
- Record the exact URL where you found each fact in source_urls. A fact without a source
  URL must not be used.
- Never infer, extrapolate, or fill gaps. If you cannot find a qualifying hook, return
  found=false with hook="" and hook_quality=1 — do NOT fabricate one. A missing hook is
  a valid, expected outcome.
- hook_quality (1-5): 5 = recent + named + unique to this company; 4 = specific and
  unique but not dated; 3 = specific but could fit a handful of competitors; 2 = generic;
  1 = nothing found.
- confidence (0-1): how certain you are the fact is current and correctly attributed.
- summary: 1-2 sentences on what the business does, for the operator's review screen.

Respond only with JSON matching the provided schema.
```

## Notes

- This step runs **only** on leads that passed the scoring gate — it is the most
  expensive research step per row.
- The hook feeds `03-email-draft` as a *verified field*. The drafting prompt is forbidden
  from using anything outside verified fields, so a `found=false` here means the draft
  falls back to the segment-level opener — that is correct behavior, not a failure.
- Eval set: plant companies whose sites are down, parked domains, and near-duplicate
  competitor sites. Target: zero fabricated hooks (every hook traceable to its
  source_url) before going live.
