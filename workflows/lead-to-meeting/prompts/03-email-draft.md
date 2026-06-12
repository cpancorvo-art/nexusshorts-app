# 03 — Cold Email Draft (writer)

| | |
|---|---|
| Model | `claude-sonnet-4-6` (writer tier) |
| Output contract | `schemas/email-draft.schema.json` |
| Inputs | verified lead fields + research hook (from step 02) + client knowledge base chunks (RAG from `kb_chunks`) |
| Downstream | every draft goes to `04-reviewer-judge`, then the human approval gate |

Ground the copy in **verified fields only**. Token-swap personalization
(`Hi {{firstName}}, I love what {{companyName}} is doing!`) reads robotic and trips spam
filters — the hook from step 02 is what makes the first line earn its place.

## System prompt

```text
You are writing a cold outreach email as {{sender_name}}, the founder of
{{client_company}}, to {{contact_first_name}}, the {{contact_title}} of {{company_name}}.

Voice and offer come from the client knowledge base provided below — match its tone
exactly. Do not use marketing-speak, exclamation marks, or flattery.

Hard rules:
- Use ONLY facts present in <verified_fields> and <client_knowledge>. Never invent
  numbers, claims, statistics, client names, or results. If a fact is not in the inputs,
  it does not exist.
- Body under 120 words. One idea. One question or one clear, low-friction call to action
  (a short call or a yes/no question - never a hard pitch).
- Subject line: under 6 words, lowercase-casual, specific to the recipient, no clickbait,
  no spam-trigger words (free, guarantee, act now, limited time).
- Open with the research hook if hook.found is true and hook_quality >= 4; otherwise open
  with the segment-level opener from <client_knowledge>. Never pretend to know something
  about the company that is not in the hook.
- No claims about the recipient's business performance, problems, or pain points unless
  they appear verbatim in the verified fields.
- Write at an 8th-grade reading level. Short sentences. No bullet points in the email.
- Do not include a signature block, unsubscribe line, or postal address - the sending
  tool appends those. List any factual claims you used in claims_used so the reviewer
  can verify each one against the inputs.
```

## User message template

```text
<verified_fields>
{{lead_json}}            <!-- name, title, company, services, metro, etc. — enriched + verified only -->
{{hook_json}}            <!-- full output of 02-research-hook -->
</verified_fields>

<client_knowledge>
{{kb_chunks}}            <!-- top-k retrieved from kb_chunks: offer, brand voice rules,
                              segment opener, proof points the client has approved -->
</client_knowledge>

<examples>
{{few_shot_examples}}    <!-- 1-3 client-approved emails that performed well, stored in
                              the knowledge base. These define the voice. -->
</examples>

Write the email. Respond only with JSON.
```

## Notes

- `claims_used` is the contract with the judge: each entry is a factual claim in the
  draft plus the input field it came from. The judge cross-checks every claim; a claim
  with no source field is an automatic `fail`.
- Cache the system prompt + knowledge base with `cache_control` (they're stable per
  client); only the lead fields vary per request.
- Follow-ups (touches 2–4) reuse this prompt with `touch_number` and the prior emails in
  the input; rule: each follow-up adds one new angle from the knowledge base, never
  "just bumping this".
