# FlipStudy Cloud (Cloudflare Worker)

The card-generation service behind **FlipStudy Cloud** — the code-gated mode
that lets a family member make cards on a phone whose own Apple Intelligence
can't (or won't) run.

Nothing here is reachable without a family code. The app ships no Cloudflare
credentials: it redeems a code for a device token, and this Worker is the only
thing that can spend AI credits.

## What it costs

Workers AI bills in *neurons*: 10,000/day are included, then $0.011 per 1,000
([pricing](https://developers.cloudflare.com/workers-ai/platform/pricing/)). A
scan is a few hundred neurons, so ordinary family use lands inside the daily
allowance. The quotas below exist for the day a code leaks, not for normal use.

## Setup (once)

```bash
cd worker
npm install -g wrangler        # if you don't have it
wrangler login
```

Create the three namespaces, then paste each printed id into `wrangler.toml`:

```bash
wrangler kv namespace create CODES
wrangler kv namespace create TOKENS
wrangler kv namespace create USAGE
```

Deploy:

```bash
wrangler deploy
```

Wrangler prints the service URL. Put it in `CloudCardGenerator.endpoint`
in the app ([FlipStudy/Services/CloudCardGenerator.swift](../FlipStudy/Services/CloudCardGenerator.swift)).

## Handing out a code

```bash
node scripts/mint-code.mjs "Sam's iPhone" --devices 2 --daily 50
```

It prints the code **once** — only its hash is stored, so a dump of KV can't be
turned back into a working code. Write it down before closing the terminal.

For a QR to text or print (the app can scan it instead of typing):

```bash
./scripts/make-qr.swift FLIP-A7K2-9QX4 ~/Desktop/sam.png
```

## One link per tester (the way to invite people)

Send testers a single link by text — no email anywhere:

```
https://flipstudy-cards.richardswheatley.workers.dev/join?code=FLIP-P34Y-3KKF
```

- Without FlipStudy, the link shows a page with an **Install FlipStudy** button
  (the TestFlight public link in `wrangler.toml` → `TESTFLIGHT_URL`) and the code.
- With FlipStudy (1.6 build 14 and later), iOS opens the app instead — a
  universal link, verified by `/.well-known/apple-app-site-association` on this
  Worker — and the app runs the grown-up check, then shows the code ready to
  turn on. It is pre-filled, never redeemed by itself.

Once someone has joined through TestFlight, every build added to the HomePeeps
group reaches them as a TestFlight update.

## Revoking

```bash
# Turn one code off (keeps the record, for an audit trail)
wrangler kv key get "code:<hash>" --binding CODES --remote
wrangler kv key put "code:<hash>" '{"label":"Sam","active":false}' --binding CODES --remote
```

Flipping `active` to `false` kills every device on that code at the next
request. To revoke a single phone instead, delete its token:
`wrangler kv key delete "tok:<token>" --binding TOKENS --remote`.

## API

| Route | Body | Returns |
|---|---|---|
| `POST /v1/redeem` | `{ code, device }` | `{ token, label }` |
| `POST /v1/generate` | `{ mode, ... }` + `Authorization: Bearer <token>` | `{ cards }` or `{ terms }` |
| `GET /health` | — | `{ ok: true }` |

`mode` is one of `qa`, `terms` (both take `text`), `topic`, `concepts` (both
take `topic`; `concepts` also takes `style`). These mirror the four entry points
in `AICardGenerator` so both engines produce the same kind of cards.

Errors are codes, never model internals: `invalid_code`, `device_limit`,
`unauthorized`, `quota_exceeded`, `model_error`, `bad_request`.

## Privacy

The text a user asks to turn into cards is sent to this Worker and on to
Workers AI. **It is never logged** — only a per-code request counter is kept,
and that holds no user content. See [PRIVACY.md](../PRIVACY.md).
