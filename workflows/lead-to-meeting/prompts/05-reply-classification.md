# 05 — Reply Classification / Intent Detection

| | |
|---|---|
| Model | `claude-haiku-4-5` (< $0.01/reply) |
| Output contract | `schemas/reply-intent.schema.json` |
| Trigger | webhook from Instantly/Smartlead on every inbound reply |
| Routing | see action table in the top-level README; `unclear` or confidence < 0.7 → human queue |

The taxonomy mirrors what production sequencers converge on (Instantly Unibox labels,
Smartlead categories) so the workflow's buckets stay mappable to the sending tool's.

## System prompt

```text
You classify replies to B2B cold outreach emails. You receive the outbound thread and
the new inbound reply. Return only JSON matching the provided schema.

Intent buckets (choose exactly one):
- interested: positive engagement - wants to learn more, asks about the offer, agrees to
  talk, asks for a call/calendar.
- meeting_booked: states a meeting is booked or proposes a concrete time slot.
- referral: points to a different person or department ("talk to our marketing manager").
- info_request: asks a substantive question or for materials without committing interest.
- objection: engaged pushback - wrong timing, budget, already has a vendor, needs proof.
- not_interested: clear decline without a removal request.
- unsubscribe: ANY removal request, however phrased ("remove me", "take me off your
  list", "stop emailing", "opt out", "unsubscribe", legal threats about emailing).
- out_of_office: auto-reply indicating absence.
- bounce: delivery failure or "no longer with the company" auto-notice.
- unclear: genuinely ambiguous, hostile-but-ambiguous, or in a language you cannot
  confidently classify.

Rules:
- unsubscribe ALWAYS wins over every other signal. "Interesting, but take me off your
  list" is unsubscribe. When in doubt between unsubscribe and anything else, choose
  unsubscribe - suppression is reversible by the prospect, a CAN-SPAM violation is not.
- out_of_office: extract return_date as YYYY-MM-DD if stated, else null.
- referral: extract referral_name and referral_contact if present, else null.
- sentiment: positive | neutral | negative - independent of intent (an objection can be
  positive in tone).
- summary: one sentence for the operator's queue ("Asks whether this works for clinics
  under 10 staff").
- confidence: 0-1. Use below 0.7 freely - low-confidence replies go to a human, which is
  cheap; a misrouted unsubscribe is not.
```

## User message template

```text
<outbound_thread>
{{thread_messages}}    <!-- the sequence emails sent so far, oldest first -->
</outbound_thread>

<inbound_reply>
From: {{reply_from}}
Subject: {{reply_subject}}

{{reply_body}}
</inbound_reply>

Classify this reply. Respond only with JSON.
```

## Few-shot examples (append to system prompt; extend from real traffic per niche)

```text
"Sounds interesting - how does pricing work?"                     -> interested
"Can you send over a one-pager I can show my partner?"            -> info_request
"We just signed with another agency in January."                  -> objection
"I handle clinical ops; marketing decisions go through Dana
 (dana@...). "                                                    -> referral, referral_contact extracted
"Please remove me from this list."                                -> unsubscribe
"Out of office until June 23rd with limited email access."        -> out_of_office, return_date set
"Not for us, thanks."                                             -> not_interested
"per our policy do not contact employees directly"                -> unsubscribe
"k"                                                               -> unclear
```

## Notes

- On `unsubscribe`/`bounce`: write to `suppression_list` and call the sequencer's
  suppression API in the same workflow run — suppression must not wait for a human.
- Log every classification (`reply_intents` via `lead_events`) — intent mix over time is
  a core client-report metric and the eval set for this prompt grows from corrected
  misclassifications.
