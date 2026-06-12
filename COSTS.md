# Running Costs & Subscriptions

Everything NexusShorts currently pays for — what to keep running and what to pause.
Last reviewed: June 2026.

---

## Monthly subscriptions

| Service        | What it does             | Plan         | Cost                   | Can you pause?                    |
|----------------|--------------------------|--------------|------------------------|-----------------------------------|
| **Vercel**     | Hosts nexusshorts.studio | Hobby (free) | **$0/mo**              | No action needed                  |
| **Clerk**      | User authentication      | Free tier    | **$0/mo**              | No action needed                  |
| **Neon**       | PostgreSQL database      | Free tier    | **$0/mo**              | No action needed                  |
| **Railway**    | Render worker (FFmpeg)   | Trial        | **~$5/mo** after trial | Yes — pause or delete the service |
| **ElevenLabs** | Voice generation         | Free tier    | **$0/mo**              | No action needed                  |

**Monthly total: $0–5/mo** depending on Railway usage.

## Pay-as-you-go API credits (loaded balances)

| Service        | Credit loaded            | Cost per video                                            | Approximate videos remaining             |
|----------------|--------------------------|-----------------------------------------------------------|------------------------------------------|
| **OpenAI**     | Whatever was added       | ~$0.01 per script                                         | Thousands                                |
| **Replicate**  | ~$40                     | ~$1.25 per video (AI video clips) or ~$0.015 (images only) | ~30 videos (AI clips) or ~2,600 (images) |
| **ElevenLabs** | Free tier (10k chars/mo) | ~500 chars per video                                      | ~20 videos/month free                    |

These credits don't expire — they sit in the account until used. No recurring
charge unless auto-reload is enabled.

## Domain

| Service        | What                      | Cost         | Renewal                                                            |
|----------------|---------------------------|--------------|--------------------------------------------------------------------|
| **Cloudflare** | nexusshorts.studio domain | ~$15–20/year | Annual auto-renewal — cancel if you don't want to keep the domain |

---

## What to do if you're pausing the project

### Leave running (all free, no action needed)

- **Vercel** — the site stays live at nexusshorts.studio
- **Clerk** — auth keeps working
- **Neon** — database keeps your data
- **Cloudflare DNS** — domain stays pointed at Vercel

### Consider pausing to save money

- **Railway** — railway.app → your project → click the service → Settings →
  scroll down → "Remove Service" (or just pause it). This stops the ~$5/mo
  charge. The site still works — episodes just won't render into MP4s until
  you restart it.

### No action needed

- **OpenAI, Replicate, ElevenLabs** — credits sit there with no recurring
  charge unless auto-billing is enabled. To verify, check each provider's
  billing page and make sure "auto-reload" / "auto-recharge" is **OFF**.

## Checking that auto-billing is off

- **OpenAI:** platform.openai.com → Settings → Billing → "Auto recharge" toggle → turn OFF
- **Replicate:** replicate.com/account/billing → check for an auto-reload setting → turn OFF
- **ElevenLabs:** elevenlabs.io → Profile → Subscription → confirm you're on the free plan, not a paid subscription

With all of those off and Railway paused, the total ongoing cost is
**$0/month** plus the annual domain renewal. The site stays live and users can
sign up and create series — they just can't generate videos until the APIs are
turned back on.

---

## Which services this repo actually touches

This repository is the front-end only (Next.js on Vercel). It directly
integrates with:

- **Clerk** — auth (`@clerk/nextjs`, `middleware.ts`, `app/api/webhooks/clerk/`)
- **Neon** — Postgres via Prisma (`prisma/`, `lib/prisma.ts`)

OpenAI, Replicate, ElevenLabs, and Railway are used by the separate render
pipeline (render worker), not by this codebase.
