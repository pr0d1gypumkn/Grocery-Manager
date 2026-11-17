# Mealy web + API

Next.js 15 (app router) with Postgres via Prisma. Serves two things:

1. **The API the iOS app calls for Plus features**: entitlements, household sync, prices, auto-planning, suggestions, social import, checkout links, billing webhooks.
2. **The web app** for signed-in users: plan, recipes, groceries, pantry, prep history, settings and Stripe billing.

Free-tier users never need this server. Their data lives on-device and in their iCloud.

## Run it

```bash
cp .env.example .env            # fill in what you have; everything optional has a mock
docker compose up -d            # Postgres on :5433 (5432 is often taken by a local install)
npm install
npm run db:push                 # create tables
npm run db:seed                 # demo user demo@mealy.local with Plus + invite code DEMO1234
npm run dev                     # http://localhost:3000
```

Sign in with any email. Without `RESEND_API_KEY` the 6-digit code is printed to the server log and shown on the page.

Tests: `npm test` (unit conversion, ingredient merging, pantry deduction, entitlements, planner, prices, suggestions).

## Entitlements

`src/lib/entitlements.ts` is the only place that decides access. `withUser(handler, "feature_key")` in `src/lib/api.ts` returns **402** with `{ feature, upgrade }` when a route needs a feature the user lacks. Pages call `has("feature_key")` and render `<Locked feature="…"/>`, which explains the feature and links to billing; nothing free is blocked.

Subscriptions from both stores land in the `Subscription` table:

- **Stripe** (web): `/api/billing/checkout` creates a Checkout session; `/api/webhooks/stripe` keeps the row in sync.
- **App Store** (iOS): point App Store Server Notifications V2 at `/api/webhooks/appstore`. The app sets `appAccountToken` on purchase and sends it to `PATCH /api/account`, which is how transactions map to users.

A lapsed subscription simply resolves to `free`; no data is touched.

## Price / retailer layer

`src/lib/prices/` is pluggable: `sourcesFor(region)` lists sources in priority order. Adapters for Flipp (flyers), Instacart, Walmart, Kroger and PC Express exist but report "not configured" until their env key is set; `MockPriceSource` always answers so the feature is demoable. Add a region or store there; nothing else hardcodes a retailer.

## Needs partnerships or keys before it is real

| Feature | Blocker |
| --- | --- |
| Flyer / shelf prices | Flipp partner API (`FLIPP_API_KEY`) or per-retailer feeds |
| Checkout hand-off with a filled cart | Instacart Developer Platform, Walmart affiliate API, Kroger API. PC Express has no public API (deep link only) |
| TikTok / Instagram / YouTube import | TikTok Display/Research API, Meta oEmbed token, YouTube Data API. Falls back to oEmbed metadata + on-device extraction from pasted captions / screenshots |
| Email sign-in codes | Resend (or any mailer) |
