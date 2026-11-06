# DropOff Operations Runbook

Everything below assumes:

```powershell
cd DropOff\workers
```

API: `https://dropoff-api.godfreymoseskalambo.workers.dev`
D1: `dropoff-db` (id `1100c702-d4c2-4114-8926-7e113350ad17`)
R2: `dropoff-backups`

## 1. Deploy

```powershell
npx tsc --noEmit
npx vitest run
npx wrangler d1 migrations apply dropoff-db --remote
npx wrangler deploy
```

Verify after every deploy:

```powershell
curl.exe https://dropoff-api.godfreymoseskalambo.workers.dev/health
```

## 2. Secrets

Set once per environment with `npx wrangler secret put <NAME>`:

| Secret | Purpose | If missing |
| --- | --- | --- |
| `FIREBASE_SERVICE_ACCOUNT` | FCM push notifications | Push is a safe no-op |
| `SENTRY_DSN` | Error forwarding to Sentry | Errors only in Workers Logs |
| `LIPILA_WEBHOOK_SECRET` | Reject unsigned payment webhooks | Header check skipped |
| `API_AUTH_KEY` | Ops/rider service key | Device calls fall back to JWT |

`FIREBASE_SERVICE_ACCOUNT` is the full JSON of a service-account key for
`dropoff-zambia-adminsdk@dropoff-zambia.iam.gserviceaccount.com`. Create it in
Google Cloud Console → IAM → Service Accounts → Keys → Add key → JSON, then:

```powershell
Get-Content .\dropoff-zambia-adminsdk.json -Raw | npx wrangler secret put FIREBASE_SERVICE_ACCOUNT
npx wrangler deploy
```

## 3. Edge rate limiting (Cloudflare WAF)

The Worker already enforces per-IP buckets in D1 (`rate_hits`). Add cheap edge
rules in **Cloudflare dashboard → Security → WAF → Rate limiting rules** so
abusive traffic never reaches D1:

| Rule | Expression | Rate | Action |
| --- | --- | --- | --- |
| OTP request | `http.request.method eq "POST" and http.request.uri.path eq "/auth/request"` | 10 / 1 min per IP | Block 10 min |
| Create job | `http.request.method eq "POST" and http.request.uri.path eq "/jobs"` | 60 / 1 hour per IP | Managed Challenge |
| Create payment | `http.request.method eq "POST" and http.request.uri.path eq "/payments"` | 30 / 1 hour per IP | Managed Challenge |
| Auth verify | `http.request.method eq "POST" and http.request.uri.path eq "/auth/verify"` | 20 / 10 min per IP | Block 10 min |

Turn off "Block" for rules that could hit shared NAT (offices, cyber cafés) if
you see false positives; Managed Challenge is the safer default.

## 4. Scale path

Current shape: one Worker + one D1 database + R2 for backups. It comfortably
handles low-thousands of bookings/day. Move up in this order as load grows:

1. **Offload side effects to Queues** (`dropoff-notify`): SMS, FCM, and receipt
   emails are already wrapped in `waitUntil`; move them into a queue consumer
   when send volume starts adding latency or hitting provider limits.
2. **Read caching at the edge**: `/couriers`, `/cities`, `/quotes`, `/plans`
   already send `s-maxage` + `stale-while-revalidate=0`; keep TTLs short and
   rely on Cache API rules for public GETs only. Never cache `/jobs/*`,
   `/payments/*`, or `/track/*` at the edge (they are `private, no-store`).
3. **D1 read replicas / Sessions API** when read latency dominates; route
   catalog reads with `withSession('first-primary')` and keep writes on primary.
4. **Durable Objects for rider location** if per-second location updates become
   the bottleneck: one DO per active city, batched writes back to D1.
5. **Shard by city** only after 4 — separate D1 databases per operating region,
   with the catalog duplicated per shard.
6. **Queue + Workflow for payouts** so Lipila disbursement retries are durable
   and never tied to a single request lifetime.

Load-test before each step with `tools/k6-smoke.js` (read-only) and a staging
key for write paths.

## 5. Observability

- Every response carries `X-Request-Id` (Cloudflare Ray ID when present) and
  emits a JSON access log line with `req_id`, `path`, `status`, `ms`, `ip`.
- Workers Logs query examples:
  - Errors: `level = "error"`
  - Slow requests: `ms > 1500`
  - One request: `req_id = "<id>"`
- Configure **Logpush** to R2 or your SIEM if you need retention beyond the
  dashboard window.
- Set `SENTRY_DSN` to forward 5xx exceptions; the Worker never fails a request
  because Sentry is down.
- Payment sweeper `reconcilePayments` runs on the 5-minute style cron path and
  closes stale `pending` rows; check for `payment_reconcile_failed` logs.

## 6. Backups and restore drill

Nightly cron writes JSONL gzip per table to R2 under
`backups/YYYY-MM-DD/<table>.jsonl.gz` plus `manifest.json`.

Manual backup:

```powershell
node scripts/backup-now.mjs
```

Restore into a scratch database (never straight into production):

```powershell
node scripts/restore-backup.mjs --date 2026-11-05 --config wrangler.drill.toml --apply --clean
```

Validate row counts against `manifest.json`, then swap traffic only after a
clean drill. Insert order is parent-first; delete order is reverse.

## 7. Incident playbook

**Payments stuck in pending**
1. `GET /payments/:id/receipt` with admin key to inspect state.
2. Let the reconciler run; if still stuck, call `POST /admin/payments/:id/refund`
   only after confirming the customer was actually charged.
3. Never mark `paid` by hand without a Lipila reference.

**Webhook spam / forged callbacks**
- Set `LIPILA_WEBHOOK_SECRET`; the handler checks `X-Lipila-Signature` or
  `X-Webhook-Secret` when configured, and always re-verifies with Lipila before
  crediting.

**Fraud flags piling up**
- `GET /admin/fraud?status=open`
- `POST /admin/fraud/:id/review` with `{"status":"cleared"}` or `"confirmed"`.
- Confirmed jobs keep `review_required = 1`; the job itself is not cancelled.

**Suspected data loss**
- Stop writes (`wrangler deploy` a maintenance flag or WAF block on POSTs),
  restore the latest backup into a scratch DB, diff, then backfill.

## 8. Known gaps

- Firebase push requires the service-account secret above.
- Cloudflare WAF rules in section 3 must be created in the dashboard; the API
  does not have zone access.

## 9. Who can do what (roles)

- **Owner = superadmin.** The phone in `OWNER_PHONE` is granted role `admin`
  server-side, and additionally holds immutable superadmin rights. Superadmin
  manages accounts with `GET /admin/users` and
  `POST /admin/users/role {email, role: customer|admin|partner}` — that is how
  an assistant (e.g. a spouse account) is promoted to admin. The owner row can
  never be demoted (server refuses), so there is no self-lockout.
- **Admins** (`role='admin'` or `X-Admin-Key`) run everything operational:
  fraud queue, tiers, branches, broadcasts, support inbox. Admins cannot mint
  more admins — role writes are superadmin-only.
- **Ops** (`role='ops'` devices, or `X-Api-Key` devices) read operational
  endpoints and reply to support tickets but cannot change roles.
- **Riders** log in with their own phone: ops registers the number via
  `POST /admin/riders`, the rider then does the normal phone-OTP sign-in in the
  app. The middleware resolves any JWT phone that matches an active
  `riders.phone` row to `role='rider'`, so the same app shows a personal rider
  view: their task queue (`/rider/queue`, `/rider/route` — both keyed to the
  caller's own phone), GPS broadcasting (`/rider/ping`) and their jobs only.
  Fleet-wide routes/batch endpoints stay ops/admin-only and 403 for riders;
  `GET /me` returns `{phone, role, superadmin, rider:{id,name}}`.
- **Seller/owner Business tab**: every signed-in seller (customer + admin +
  owner identities, not riders) gets a Business dashboard tab built entirely
  from existing endpoints — active plan usage (`/subscriptions`), parcels in
  flight / delivered from `/jobs` (own phone), 30-day DropOff spend, and the
  referral funnel (`/refer/code`). Tapping an in-flight parcel mints the
  tracking link (`/jobs/:ref/tracking-link`) and opens the verified Track
  screen; **Repeat last** clones the latest job into the booking form.
  Retention banners are computed client-side from the same data: pay-for-itself
  at 3+ parcels/mo with no pack, overage→upgrade nudge when the cap is hit, and
  a one-tap **Renew now** inside the last 3 days of a cycle (re-posts
  `/subscriptions`, worker sends the Lipila prompt).
- **Renewal safety net (cron)**: auto-renewal prompts run 3 days before
  `period_end`. If no prompt is outstanding, `notifyExpiryNudges` SMSes the
  seller once per cycle; lapsed packs get a grace warning until the 7-day
  lapse sweep. Dedupe column: `subscriptions.expiry_nudge_period`.
- **Rider COD self-remittance**: `GET /rider/cod` lists the signed-in rider's
  floated COD (`jobs.rider_id`, `cod_collected_zmw`, remitted flag);
  `POST /rider/cod/remit {job_ref}` settles it via Lipila disbursement to the
  sender's momo — only for jobs assigned to that rider. Admins still use
  `/admin/payouts` (`kind=cod_remit`); both share one code path.
- **Rider reputation**: `GET /rider/reviews` returns the rider's verified
  rating average/count + five latest comments; the Team tab shows it.
- **Delivery IQ cold start**: when a courier has no measured pickup→depot
  history, `/iq/eta` returns the advertised window bands with `fallback: true`
  so the app can show an estimate and label it "(advertised)".
- **Jobs now store `from_city`** (migration 0037) so origin city survives for
  repeat-booking prefill, city analytics and destination copy; older rows were
  backfilled to Lusaka.
- `GET /me` returns `{phone, role, superadmin}`; the app drives its Staff tab,
  admin console and Users-and-roles card off this — no role is trusted
  client-side. Admin-console API helpers send `X-Admin-Key` too, so a
  key-only console device works without a JWT (the key header is omitted when
  the build has no key configured).

## 10. Tracking verification (link ≠ access)

A tracking link now proves nothing by itself. Every `/track/:token` route
(GET status, GET/POST chat) requires one of:

1. a signed-in JWT whose phone equals the job's sender or recipient phone,
2. an `X-Track-Grant` header minted by `POST /track/:token/verify` with the
   participant phone (grant = SHA-256 of `${JWT_SECRET}:track:${token}:${phone}`),
   stored in-memory per app session, or
3. staff keys (`X-Admin-Key` / `X-Api-Key`).

Unknown token → `404`. Stranger with the link →
`{requires_verification: true, hint_phone: "••••1234"}` only — no parcel data,
no prices, no rider location. The in-app TrackScreen shows a phone-verify card
in exactly that case; the verify call is rate-limited (15/min) to stop
brute-forcing. Chat reuses the same gate.

## 11. Support inbox (visible tickets)

Support chats live in `chat_threads.kind='support'` and are no longer hidden:

- `GET /admin/support/threads` — list with last message, last activity and a
  per-ticket unread count (messages since the last `ops` reply),
- `GET /admin/support/threads/:id` — full message history,
- replies reuse `POST /chat/support/:id/reply` (admin / ops / admin key).

The in-app admin console renders both as the **Support inbox** card.

## 12. Delivery IQ

`GET /iq/eta?courier_id=&window=` computes the typical and slow-day
pickup→depot minutes from real `job_events` (picked_up → at_depot) over the
last 90 days (max 300 jobs). Signed-in callers only. The booking screen shows
it beside the pickup-window picker so sellers see real speed before booking.

## 13. Pack codes and collections (agent sales + last mile)

- **Pack codes** let agents, market-day stalls and the counter sell a pack
  offline. Superadmin mints batches with `POST /admin/pack-codes
  {tier, count<=50, note}` (codes look like `DROP-XXXX-XXXX`; list them with
  `GET /admin/pack-codes`). The seller redeems in the app (Account tab or the
  booking form) via `POST /subscriptions/redeem {code}`: the code is consumed
  atomically, the pack activates immediately on their number for the plan's
  `cycle_days`, and **no payment prompt** is sent. Admin console ? Pack codes
  card shows a "Copy all" batch for texting to the agent.
- **Revised pack prices** (live in `tiers`): Daily K69 (1 day), Weekly K399
  (7 days), Silver K250 / 10 parcels, Gold K500 / 25, Platinum K750 / 50 (30
  days). Migration `0039_tier_prices.sql` is the price-only sync; `/plans`
  merges the D1 chargebook over the built-in fallback.
- **Collections** (courier point ? recipient door) are booked from the home
  screen's second button: `POST /collections` creates a Lusaka last-mile job
  (`last_mile=1`, `dest_address`, no counter fare) priced at the pay-as-you-go
  rider fee + processing fee; the app then runs the normal Lipila payment and
  status poll.
- **Booking form simplifications**: DropOff is Lusaka-only (no intercity
  courier-ticket copy), the seller no longer picks a depot branch (the rider
  takes the parcel to the nearest point), and only the three booked windows
  (06:00 / 10:00 / 14:00) are offered � no instant "now" or custom time.
- **Driver pay visibility**: the K3,000/month flat + 30-parcels/day target line
  is shown only on the rider view (`_RiderPayCard`); seller-facing and public
  copy never mentions it.
