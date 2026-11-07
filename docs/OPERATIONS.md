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
  at 3+ parcels/mo with no plan, overage→upgrade nudge when the cap is hit, and
  a one-tap **Renew now** inside the last 3 days of a cycle (re-posts
  `/subscriptions`, worker sends the Lipila prompt).
- **Renewal safety net (cron)**: auto-renewal prompts run 3 days before
  `period_end`. If no prompt is outstanding, `notifyExpiryNudges` SMSes the
  seller once per cycle; lapsed plans get a grace warning until the 7-day
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

## 10. Tracking verification (link ≠ access) and recipient signup

A tracking link proves nothing by itself. Every `/track/:token` route
(GET status, GET/POST chat) requires one of:

1. a signed-in JWT whose phone equals the job's sender or recipient phone,
2. an `X-Track-Grant` header minted by `POST /track/:token/verify` with the
   participant phone (grant = SHA-256 of `${JWT_SECRET}:track:${token}:${phone}`),
   stored in-memory per app session, or
3. staff keys (`X-Admin-Key` / `X-Api-Key`).

**Hardened 2026-11-07:** newly minted tracking tokens expire after **180 days**; `/track/:token/verify`
and `POST /track/:token/chat` are throttled **per token** (10 and 20 per 10 minutes) on top of the per-IP
buckets, so a leaked grant cannot brute-force the phone hint or flood the thread. `POST /track/:token/chat`
is grant-gated like every other track route. `GET /track/:token` reports `you_are: sender|recipient|staff`
so the app can tag the parcel "Addressed to you — belongs to your number".

Unknown token → `404`. Stranger with the link →
`{requires_verification: true, hint_phone: "••••1234"}` only — no parcel data,
no prices, no rider location. The in-app TrackScreen shows a phone-verify card
in exactly that case; the verify call is rate-limited (15/hour per IP, 10/hour per token) to stop
brute-forcing. Chat reuses the same gate.

**Recipients are first-class users now.** A recipient who installs the app signs up with the
**phone the parcel was addressed to** (same create-account flow — no separate role). The server then
matches `jobs.recipient_phone` to their account phone automatically:

- `GET /track/incoming` (JWT required, NOT on the public token bypass) lists every parcel addressed to
  the caller — live or delivered — each with a ready tracking URL. The app renders these under
  **Bookings → "Parcels for you"** with one-tap tracking; no link-pasting needed, ever again.
- Opening the tracking page (from the SMS link or the card) answers immediately with the
  **"Addressed to you"** tag plus a **Predictive ETA** (see §12): "Predicted: around tomorrow 10:30 ·
  high confidence · courier's last 82 parcels (180d)".
- Parcels addressed to you but not yet delivered appear on top of your own bookings (as the sender).

## 11. Support inbox (visible tickets)

Support chats live in `chat_threads.kind='support'` and are no longer hidden:

- `GET /admin/support/threads` — list with last message, last activity and a
  per-ticket unread count (messages since the last `ops` reply),
- `GET /admin/support/threads/:id` — full message history,
- replies reuse `POST /chat/support/:id/reply` (admin / ops / admin key).

The in-app admin console renders both as the **Support inbox** card, with per-ticket
unread badges. Tap a ticket to open the full thread; the reply box sits beside an
**AI draft reply** button (`POST /admin/support/threads/:id/ai-draft`, Workers AI,
never auto-sends — you review and press send) and a one-tap copy of the customer's
phone number. Seller side: Account → *Chat with DropOff support* → `POST /chat/support`
(creates/reuses the `kind='support'` thread for the caller's phone; push notification
on every ops reply). Inbox → support thread shows the full conversation.

**"Why can't I see tickets?" — checklist.** (1) You must be signed in as owner (phone in
`OWNER_PHONE`) or an email account promoted to `admin` — `GET /me` must report role
`admin`/`ops` (the Admin console door on the Account tab appears only then). (2) `OWNER_PHONE`
must match the phone you signed in with — a typo means you're a plain customer with no admin
door. (3) Tickets only appear once at least one seller has opened support chat; the inbox card
renders every `kind='support'` thread regardless of status. (4) If the app shows
"Admin console" but the inbox stays empty while `wrangler d1 execute dropoff-db --remote --command
"SELECT count(*) FROM chat_threads WHERE kind='support'"` shows rows — the build is a store build
without `DROPOFF_ADMIN_KEY` or a stale JWT; sign out/in again.

## 12. Predictive features — Delivery IQ and DropOff Predict

### Delivery IQ (booking screen)
`GET /iq/eta?courier_id=&window=` computes the typical and slow-day
pickup→depot minutes from real `job_events` (picked_up → at_depot) over the
last 90 days (max 300 jobs). Signed-in callers only. The booking screen shows
it beside the pickup-window picker so sellers see real speed before booking.

### DropOff Predict (tracking page, Business tab, Admin console)
Four explainable surfaces — no opaque model, every number carries basis + sample size:

- **Predictive ETA (tracking page).** Included as `predicted` on `GET /track/:token`:
  measured p50 of this courier's last-180-day `picked_up→at_depot` and
  `at_depot→delivered` legs, applied to wherever the parcel is now → `eta_minutes`,
  `arrival_by`, `confidence` (high ≥30 samples, medium ≥8, else low). Completed parcels
  answer `eta_minutes: 0` ("delivered — nothing left to wait for").
- **Seller forecast** `GET /predict/seller`: next-30-day parcels (least-squares over six
  CAT months, blended 50/50 with the trailing 3-month average), month-over-month trend,
  peak window and weekday, plus the **cheapest plan that covers the forecast**
  (`recommended_plan`, with est. savings vs pay-as-you-go) and a Daily-Rider-vs-monthly
  comparison (`daily_option`). Business tab renders this with a one-tap plan switch.
- **Ops demand heatmap** `GET /admin/demand-forecast`: next 7 days per depot branch ×
  pickup window — the same weekday+window parcel average of the trailing 8 weeks (CAT),
  every weekday occurs exactly once — for sweep scheduling and staffing. Admin console →
  "DropOff Predict — next 7 days" card.
- **Prediction honesty rule:** cold start returns labelled fallbacks (`fallback: true` /
  `basis: "advertised window bands…"`), never invented confidence.

## 13. Plan codes and collections (agent sales + last mile)

- **Plan codes** let agents, market-day stalls and the counter sell a plan
  offline. Superadmin mints batches with `POST /admin/pack-codes
  {tier, count<=50, note}` (codes look like `DROP-XXXX-XXXX`; list them with
  `GET /admin/pack-codes`). The seller redeems in the app (Account tab or the
  booking form) via `POST /subscriptions/redeem {code}`: the code is consumed
  atomically, the plan activates immediately on their number for the plan's
  `cycle_days`, and **no payment prompt** is sent. Admin console → Plan codes
  card shows a "Copy all" batch for texting to the agent.
- **Plans in D1** (source of truth, editable live): Daily Rider `rider_daily`
  **K49/day, 2 parcels/day**, Weekly Sprint K399 (7 days), Silver K250 / 10
  parcels, Gold K500 / 25, Platinum K750 / 50 (30 days). Migration
  `0043_rider_daily.sql` seeds Daily Rider; `0039_tier_prices.sql` the price sync.
  `/plans` merges the D1 chargebook over the built-in fallback.
- **One allowance, every normal delivery**: a plan's parcels pay for pickups,
  courier-point collections → door, and the optional last mile — all return
  `plan_inclusion` / `plan_used` / `plan_cap` and consume the same slots. Daily
  plans meter the cap per day; monthly per cycle (`period_start..period_end`).
- **Collections** (courier point → recipient door) are booked from the home
  screen's second button: `POST /collections` creates a Lusaka last-mile job
  (`last_mile=1`, `dest_address`, no counter fare). If the sender holds an active
  plan with slots left it consumes one slot at K0 rider fee; otherwise it bills the
  pay-as-you-go rider fee + processing fee; the app then runs the normal Lipila payment and
  status poll.
- **Booking form simplifications**: DropOff is Lusaka-only (no intercity
  courier-ticket copy), the seller no longer picks a depot branch (the rider
  takes the parcel to the nearest point), and only the three booked windows
  (06:00 / 10:00 / 14:00) are offered except on Daily Rider, which also exposes `now`.
- **Driver pay visibility**: the K3,000/month flat + 30-parcels/day target line
  is shown only on the rider view (`_RiderPayCard`); seller-facing and public
  copy never mentions it.

## 14. Driver KYC, daily targets and AI assist

- **Driver verification** (owner/admins only): ops registers riders via
  `POST /admin/riders` (NRC, licence, plate, vehicle make/colour live on the
  rider row). A driver submits their own documents via the app (`POST
  /rider/profile` + `POST /uploads` → R2 bucket, served through `/media/*`
  behind auth) landing in status `pending`. `POST /admin/riders/:id/verify`
  flips to `verified`/`rejected` (note stored); unverified drivers are excluded
  from auto-assign and manual job assignment (`409 rider_not_verified`).
- **Selfie + seller-visible photo**: the KYC card *requires* a selfie (`photo_url`).
  Sellers see that selfie (with name, vehicle and a "VERIFIED rider" badge when the
  rider is approved) on the tracking page — `GET /track/:token` includes
  `rider.photo_url` and `rider.verified` only on the verified (granted) view, never
  to anonymous link-holders. Unverified riders show "Verification pending" instead.
  Auto-assign also returns the rider's `photo_url` on the booking payload.
- **AI face review**: the rider self-checks their own selfie via
  `POST /rider/profile/ai-face-check` (or automatically right after submit) — Workers
  AI vision answers `{has_face, single_person, real_photo, document_or_id,
  illustration_or_avatar, verdict: pass|review|fail, note}`. The same review is folded
  into `POST /admin/riders/:id/ai-check` (printed next to the plate/NRC verdicts in the
  AI dialog and merged into `ai_check_json.face`). Admins always click Approve/Reject
  themselves; AI only catches the obvious (documents, screenshots, avatars, group
  photos, no face at all) before it reaches the queue.
- **Daily/monthly targets**: sweep target is 30 parcels/day. `GET /rider/targets`
  and `GET /admin/riders` return today vs target and month vs pace (pace =
  30 x day-of-month, hard month = 30 x days-in-month), computed from
  completion events (`at_depot` / `delivered` / `ready_for_collection`) keyed
  to Central Africa Time. A daily 19:00 CAT cron SMSes any driver short on
  their target and sends the owner a shortfall summary.
- **AI assist** (never the auto-decision): `POST /ai/address` parses free-text
  pickup addresses into structured fields (used by an "AI tidy" button on the
  booking form); `POST /admin/support/threads/:id/ai-draft` drafts support
  replies from ticket history; `POST /admin/riders/:id/ai-check` reads a
  driver's plate/NRC photo via Workers AI vision and compares it against what
  the driver submitted (`plate_match`/`nrc_match`) � admins still click
  Approve/Reject themselves.
