# AGENTS.md — DropOff repo guide for coding agents

## Play Store versioning (mandatory)

Every upload to Google Play **must** use a **strictly higher `versionCode`** than every previously uploaded build — Play Console rejects duplicates (`Version code N has already been used`).

**DEFAULT: always increment BOTH `version` and `versionCode` on every release build, even if the app is already built.**
- Version lives in `app/pubspec.yaml` as `version: <semver>+<versionCode>` (e.g. `0.5.49+59`).
- Before ANY Play upload or any build you intend to upload:
  1. Open `app/pubspec.yaml`, read the current `versionCode`.
  2. **Increase it by 1**, even if you didn't change app code — Play locks used codes forever.
  3. Rebuild via `tools/build_release.ps1` (it handles flutter clean + artifact copy).
  4. Upload the freshly built `dist/DropOff-<version>-release.aab`.
- Never reuse a `versionCode` — codes 57, 58 and 59 are already used on Play (as of 2026-11-19).
- **Clean `dist/` on each build**: delete superseded `DropOff-<version>-release.*` so only the newest pair + aliases remain.
- Release artifacts only: `dist/` never carries debug or profile builds.

## Standing delivery checklist (owner directive 2026-11-20 — do EVERY time, no asking)

After every change session, without asking the owner:
1. Apply any new `workers/migrations/*.sql` to live D1:
   `npx wrangler d1 execute dropoff-db --remote --file=./migrations/<n>_<name>.sql --yes`
   (run from `workers/`). Re-running an already-applied migration is harmless if
   it is `IF NOT EXISTS`; a duplicate-column error means it is already live.
2. Deploy the worker: `npx wrangler deploy` (from `workers/`).
3. Verify `flutter analyze` (app/) and `npx tsc --noEmit` (workers/) are clean.
4. Commit and push everything: `git add -A`, `git commit`, `git push origin main`.
   **Never leave work uncommitted or report these steps as "pending"** — just do them.

## 2026-11-21 (third pass) — picked-up item photo rule for normal bookings

- A **standard sender pickup** now enforces the same evidence as a collection:
  one **camera-only, watermarked, CAT-timestamped** photo for **every picked-up
  item** (the app capture path was already camera-only and `PhotoStamp` burns
  the stamp into every upload). The worker now rejects a `picked_up` event with
  `photo_required` unless the unique photo set covers `jobs.parcels` —
  ops/admin may still reconcile without the batch.
- All pickup copy says **"picked-up items"**, never "collected items".
- The booking screen tells senders the rider will photograph every picked-up
  item with a time-stamped DropOff camera photo.

## 2026-11-21 (second pass) — P1 fixes + collection pickup security

### Why collection pickup needs NO sender PIN
Collections never mint `pickup_otp_hash` (`/collections` inserts only
`delivery_otp_hash`, the RECIPIENT's door code). The worker used to fall back
`pickup_otp_hash ?? delivery_otp_hash`, so the rider was told to ask a sender
who isn't at the depot for a code only the recipient had — impossible, and the
"security" was theatre (typing any 4 digits failed too). The worker now skips
the pickup OTP gate entirely for `service='collection'`; STANDARD pickups still
require the sender's code server-side. Real collection security is:
prepaid booking + the sender's uploaded proof-of-payment receipt shown at the
counter + camera-only stamped photos of every collected item + the recipient's
4-digit code (intercity) / in-app receipt confirmation (same-city) at the door.

### P1 fixes
- **Voice mute:** `StepSounds.voiceGuidance` (`voice_guidance_enabled`, default
  on) with an Account switch AND a volume icon in the navigator app bar;
  `_speakNextCue()` returns early when muted and re-anchors cues on unmute.
- **One-step lock:** `_busyRef` is now actually SET at the start of pickup,
  depot-drop and door-handover; step rows disable and the branded spinner shows
  until the sheet handler clears it. No more double-tap re-filing.
- **Camera-only proof:** `_pickPodPhoto()` no longer offers a gallery pick —
  handover and receipt photos are captured live, like pickup evidence.
- **Global 401:** `DropOffApi.onAuthFailure` is installed by `AppStore`; any
  non-cacheable 401 triggers one `refreshSession()`, then a real sign-out with
  an honest "session expired" SnackBar. 401 never serves a stale GET cache.
- **Counter-fare copy unified:** the rider fronts the depot fare; the sender
  repays the exact photographed receipt through DropOff to release the photo
  and reimburse the rider fee-free. It is a REIMBURSEMENT, not a DropOff charge.
  Updated tutorial, help, booking, couriers, waybill and thermal print.

## 2026-11-21 — UX audit P0 fixes (riders + senders)

Owner asked for a seamlessness audit; 50+ faults were found across three
parallel reviews. The 11 journey-breaking ones are fixed here:

- **Collection pickup no longer asks for a sender PIN.** `/collections` only
  mints a door code; the rider dialog now says "collect at the depot counter,
  show the receipt" and sends `otp: null`. Resend-PIN tiles are hidden for
  collections. Never restore a 4-digit requirement at collection pickup.
- **Dispatch presence is recoverable.** `shareLocationOn` is re-enabled when
  `/me` resolves role=`rider` after sign-in, and a "Location sharing is OFF —
  tap to turn on" banner sits on the Task Queue. GPS denial/services-off now
  shows a persistent banner with "Open settings" and the position stream
  restarts on app resume (old subscription cancelled first).
- **New-order pushes route riders to `AppShell` (Task Queue index 0)**, not
  sender Bookings.
- **Mojibake (`ΓÇö`, `ΓÇª`) removed** from all counter-fare copy in
  `bookings_screen.dart` (12 + 1 occurrences, verified at byte level).
- **Collection prepayment:** `pending` is no longer reported as "failed / tap
  Pay now"; the retry control stays reachable, stays on screen, and now polls
  `paymentStatus(payment_id)` so approval is actually detected. Internal
  courier IDs no longer leak into the success toast.
- **Waybill tracking links** use the worker's URL directly in print/share
  (no double `…/t/https://` prefix).
- **No green "booked" with a deposit owed** — `paymentOutcome` starts `held`
  whenever `depositRequired || depositInitFailed`.
- **`/auth/link` deep links open in the in-app browser** so the worker's
  single-use verify/reset tokens are consumed (Android App Links claim `/auth`).
- **Cold-start deep links and push taps queue** until `initFuture` completes
  and the navigator is mounted; the old silent `return` is gone.
- **Push taps / links no longer bypass the biometric lock** — `_isLocked()`
  gates the deferred queue and unlock calls flush it.

Remaining P1/P2 findings from the audit are documented in the session report
(voice mute, `_busyRef` lock, gallery policy, 401 handling, copy contradictions).

## 2026-11-20 (final) — step sounds, faster photos, named milestone copy

Owner directives: quicken photo uploads; add a sound on every completed step
WITH an option; and rewrite the "your parcel … was picked up and heading to the
depot" messages to use the item's real name, the real depot name, correct
collection wording, and plain "item" instead of "parcel".

### Faster photo evidence
- `app/lib/data/photo_stamp.dart` now downscales to 1600 px on the long side
  BEFORE stamping and encodes at JPEG 84 — a 5–10 MB camera shot becomes
  ~300–500 KB, so uploads finish several times faster on mobile data.
- `DropOffApi.uploadImage` runs the stamp in a background isolate via
  `compute(_stampInIsolate, _StampJob(...))`; decode/encode no longer freezes the
  UI. Failures still fall back to the original bytes so a capture never blocks.
- `image` stays pinned to `^4.3.0` (4.12 conflicts with pmtiles/archive ^3).

### Step sounds (optional)
- New `app/lib/services/step_sounds.dart`: two short WAV assets under
  `app/assets/sounds/` (`step_done.wav`, `step_error.wav`), played with
  `audioplayers`. Preference `step_sounds_enabled` (default true) is in
  SharedPreferences; Account → Privacy & sign-in has the "Step completion
  sound" switch (with a preview chime when enabled).
- `StepSounds.stepDone()` fires after pickup, depot drop, door handover and
  receipt upload; `stepError()` fires on a rejected step. Audio is best-effort
  and never blocks a delivery.

### Milestone message copy
- Worker `/jobs/:ref/events` selects `description`, `branch` and
  `couriers.depot_name`; helpers `itemNameOf()` (first word of the sender's
  description, e.g. "Books", fallback "item") and `legDestinationOf()`
  (real depot name; collections → "the recipient's door") drive push, SMS and
  the legacy SYSTEM timeline notes.
- Non-English "Kigoda" removed from the delivered push. No "your parcel" or
  generic "the depot" remains in milestone copy.

### Earlier 2026-11-20 fixes in this session
- **No late cancellations (replaces the old no-show auto-cancel):** the minute
  cron `cancelStaleOrders` now ROLLS FORWARD an elapsed window to the next open
  sweep (06:00/10:00/14:00), returns an accepted-but-unstarted parcel to
  `created` with `rider_id = NULL` (claim board), releases the rider's load,
  and records `rolled_forward`. No strike, no refund, no cancellation.
  `nextSweepAfterNow()` does the CAT maths. Do NOT restore the old cancel path.
- **Nearest-first dispatch:** `nearestAvailableRider` scores `km + freshness`
  only; load merely breaks near-exact ties (was `+ load * 0.5`, which could
  pick a rider 10 km further away).
- **Stable order times:** the rider queue chain is anchored to the SLOT START,
  not `max(slot start, now)` — times no longer drift to the current time on
  every 20 s poll. `minutes_on_road = chainMin - clockMin` (real route time,
  fixes "1034 min"); app renders "1 h 20 min".
- **One-shot handover:** the app locks Confirm (spinner + disabled) on tap and
  the worker returns 409 `already_delivered` / `already_picked_up` for replays;
  the app treats those as success.
- **Collection depot pin removed:** `rider_map_screen` hides the warehouse pin
  for `service == 'collection'`; the rider navigator draws no depot context pin
  for collections (only the recipient door at handover); `/jobs/:ref/live`
  exposes `service`/`status`.
- **Collection receipt:** `/media/*` participant guard includes
  `collection_receipt_url`; rider and sender viewers normalise absolute URLs,
  send auth headers and show a branded loading spinner.
- **Plans grey screen:** `_TiersCard` caches `_plansFuture` per mount and shows
  a white loading row with `AppLogoSpinner`, so switching screens and back no
  longer flashes a blank card.
- **Branded spinners:** `app/lib/ui/app_spinner.dart` (`AppLogoSpinner`, const)
  replaces bare `CircularProgressIndicator` loaders across the app.
- **Toast wrap:** `Row(mainAxisSize: max)` + `Flexible` + `softWrap` stops long
  messages (cap-reached) rendering vertically.
- **Rider stats card:** the salary note moved to its own wrapped line so it no
  longer overlaps the card edge.
- **Bookings / every AppShell tab:** white `Scaffold` / `SizedBox.expand` +
  `ColoredBox` wrappers remove the grey band below the last card.

## 2026-11-19 — Tickets replace chat, claim board, route-facing bike, GPS voice

Owner directive: remove chat, keep only support, add tickets; auto-assign stays
but leftover parcels must be claimable and exclusive; fix the bike icon facing
the wrong way; fix turn-by-turn voice reading everything at once. The Arrived
button was explicitly parked ("do nothing first") and was NOT changed.

### Parcel chat removed; support upgraded to tickets
- Deleted `app/lib/screens/chat_screen.dart` and `inbox_screen.dart`. Every
  user-facing entry point now opens `app/lib/screens/tickets_screen.dart`:
  Account "Support tickets", Bookings header (unread badge from `/tickets`),
  "Get help with this delivery", "Get help with this parcel", and push taps.
- Migration `0072_support_tickets.sql`: `chat_threads` gains `subject`,
  `category`, `status` (open/pending/closed) and `updated_at`. Support threads
  ARE the tickets; `chat_messages` is their conversation.
- New worker endpoints: `GET/POST /tickets`, `GET/POST /tickets/:id/reply`,
  `POST /tickets/:id/status`, plus admin status setter
  `POST /admin/support/threads/:id/status`. Admin ticket list/detail now
  expose subject/category/status; the admin sheet shows them + a status menu.
- The legacy parcel-chat worker routes remain registered but are unreachable
  from the app; do not rebuild UI on them.

### Auto-assign kept; claim board for leftovers (exclusive)
- `GET /rider/available` lists only `rider_id IS NULL AND status='created'`
  jobs auto-assign could not place (recent only, no held payments).
- `POST /jobs/:ref/claim` claims atomically with `rider_id IS NULL AND
  status='created'`; a second claim gets 409, loads/rider status/event/push are
  written exactly like algorithmic dispatch. The Rider Queue shows an
  "Available orders" card above the slot batches and refreshes it on the
  same 20 s poll. **Worker-side exclusivity is the authority**: never add a
  client-only "hide for others" rule.

### Bike icon + GPS voice
- `RiderMap._routeHeading` uses the nearest ROAD SEGMENT bearing (not the
  straight line to the final pin), so the 3D bike nose follows every bend.
- Voice is now GPS-progress driven: the worker includes each step's maneuver
  `lat/lng` (OSRM `maneuver.location`, ORS `way_points[0]`), `RouteStep` carries
  it, and the navigator speaks ONE next-turn cue at 400/250/100/30 m bands,
  re-anchoring on re-route. It no longer reads the step list back-to-back.

- **Rider presence fix (the real "not getting orders" bug):** the queue's
  auto-ping used to bail when `batches.isEmpty`, so a rider waiting for a first
  order never refreshed `last_seen_at` and dispatch (15-minute freshness gate)
  could never pick them. It now pings with an empty queue and refreshes at
  least every 60 s even when stationary. Never restore that empty-queue guard.

## 2026-11-20 — Sender photo, sender-only tutorial, private tickets, payout engine

### Homepage + tutorial + ticket privacy
- `HomeScreen` header Account button now shows the signed-in sender's actual
  profile photo (`store.photoUrl` → auth-gated `${baseUrl}/media/...`, initials
  icon fallback). Riders already had this in the queue app bar.
- `TutorialSheet` gained `senderOnly` / `rider`: account entry shows ONLY the
  six sender steps; the rider queue entry shows ONLY rider steps. The old
  two-tab sheet only remains for a caller that passes neither flag.
- Ticket copy now states conversations are private to the sender + DropOff
  support/admin — recipients and riders never see another account's tickets.
  Server scoping was already enforced (`ticket.phone === caller` or staff).

### Chisomo-style refund/settlement payout engine
- Modeled on `chisomo` / `chisomo_flutter` (Kingdom Sponsor): Chisomo does NOT
  pay per contribution; it confirms asynchronously and runs a guarded
  auto-disburse. DropOff's version is for REFUNDS/SETTLEMENTS only — **never**
  per-parcel rider payouts (riders stay salaried, depot fares paid at counter).
- Migration `0073_payout_engine.sql`: `payouts` (durable ledger with UNIQUE
  random-suffix reference, status queued/processing/pending/success/failed,
  attempts, max_attempts 8, next_attempt_at, last_error) + `lipila_logs`
  gateway audit.
- `POST /admin/payments/:id/refund` now ENQUEUES and returns 202 (superadmin
  only) instead of calling Lipila inline. The source payment flips to
  `refunded` only after Lipila confirms.
- Atomic `rider_id`-style guards: `status IN ('queued','failed')` claim before
  each attempt; one payout per source payment; 30-minute backoff; webhook
  (`REF-`/`SET-`/`SWEEP-`) and per-minute status reconciliation; owner push on
  success and each retry; admin ledger + superadmin retry endpoint.
- App: Admin console "Payout queue" card with status, attempt count, last
  error and a Retry button.

## 2026-11-20 (late) — Collection receipt, stats, grey list, plan error

- **Rider stats zeros:** `/rider/stats` SQL referenced `j.id` in an EXISTS but
  the outer table had no `j` alias → SQLite error → empty stats. Aliased
  `FROM jobs j`. Never remove that alias.
- **Grey band at bottom of scroll:** `AppShell`'s `IndexedStack` gives children
  LOOSE constraints, so nested Scaffold/ListView screens shrank to content and
  the canvas background showed through. Each tab is now wrapped in
  `SizedBox.expand`.
- **Collection flow is DEPOT → RECIPIENT** (not sender → depot): `/rider/queue`
  now returns `service`, `dest_address`, `collection_receipt_url`; the rider
  navigates to the depot first, then geocodes the recipient door. Timeline is
  5 steps; `_stageFromJobStatus` is collection-aware. Wording across Bookings,
  movement log, waybill and the rider sheet now says recipient/depot correctly.
- **Collection payment receipt:** migration `0074_collection_receipt.sql` adds
  `jobs.collection_receipt_url`. The collection form (after Deliver to) uploads
  a proof-of-payment receipt; the rider shows it FULL-SCREEN at the depot
  counter, then photographs every collected item on pickup.
- **Depot counter-fare gate RESTORED (owner correction 2026-11-20):** the rider
  fronts the depot fare, files the receipt, and the sender is PROMPTED to pay
  via DropOff momo; the receipt stays blurred/locked until that payment lands.
  This gate protects riders from senders who delay payment. Do NOT remove it
  again based on the "fare paid at counter" rule — the counter fare is never
  a DropOff *charge*, but this reimbursement gate is required.
- **Rider plan purchase:** `/subscriptions` used the JWT phone only for
  `role==='customer'`, so rider/admin accounts 500'd ("internal error" →
  "Could not start the plan"). Any signed-in role now buys for its own phone;
  only staff may pass an explicit `b.phone`.
- **Webhook secret rotated** on the Worker (`LIPILA_WEBHOOK_SECRET`) to the new
  value given by the owner; Lipila dashboard webhook URL must be updated to
  match. Plain (no-secret) callbacks are accepted but always re-checked
  against Lipila before settling, so the un-removable plain URL is harmless.

- **Grey screen on detail/bookings scroll (owner 2026-11-20, second pass):**
  the real cause was the global theme `scaffoldBackgroundColor: AppColors.canvas`.
  `BookingDetailScreen`, Account, Track, Waybill etc. never overrode it, so
  scrolling past the last card exposed grey. Theme default is now **white**;
  AppBars that forced canvas (Navigate, Rider live) are white too. Bottom
  sheets with `backgroundColor: AppColors.canvas` are intentional and kept.
  Every tab in `AppShell` is also wrapped in `SizedBox.expand` +
  `ColoredBox(white)` so a short list can never show a grey band.

- **Plan purchase confirmation (owner 2026-11-20):** choosing/renewing/
  switching a plan must never fire a momo prompt without warning. Added
  `_confirmPlanPrompt` in `account_screen.dart` (`_TiersCardState`) and
  `business_screen.dart` (`_renew`, `_switchToPlan`): shows plan price and
  "nothing is charged until you approve with your PIN", with Not now /
  Send momo prompt. Redeeming an already-paid pack CODE needs no confirmation.

- **Claim board is an open house (owner 2026-11-20):** `/rider/available` and
  `POST /jobs/:ref/claim` no longer require `verification_status='verified'` —
  the guard is presence (`active`) + capacity only. Unverified-but-online
  riders can now claim leftovers. Note: this slightly weakens the
  ghost-buyer safety net; booking is still paid in advance, so the rider only
  moves money they were promised.
- **Claim board polls every 5 s** (`_claimTimer` in RiderQueueScreen) so a
  rider who comes online/free-up sees claimable jobs quickly.
- **Booking strike hold removed (owner 2026-11-20):** senders with 3+
  `booking_strikes` can book again ("allow both collection and pickup no
  matter what"); strikes now only produce warnings in the app. The
  no-show-based auto-cancel for riders still runs.

- **Rider phone rings + stays awake on new order (owner 2026-11-20):**
  `RiderQueueScreen` now tracks seen job refs and when NEW refs appear (first
  poll after assignment), calls `HapticFeedback.heavyImpact()` +
  `WakelockPlus.enable()` for 45 s. Worker push already alarms the phone; this
  covers a rider with the app foreground-open and an idle phone.
- **No rider earnings anywhere (owner 2026-11-20):** removed the rider stats
  card's earned figure and the "BONUS K" figure from the targets strip —
  riders see only counts, their income is salary.

### Release
- Version bumped to `0.5.59+69` (57–68 are consumed or superseded on Play).
- **Pending network:** migration 0073/apply, worker deploy, git push and the
  release build could not complete while pub.dev/Cloudflare DNS was down —
  retry once connectivity returns. Do NOT change `tools/build_release.ps1`
  (owner directive 2026-11-20); the failure was the network, not the script.

## Repo conventions

- Always `flutter clean` before a release build (build_release.ps1 does).
- No invented courier/depot fares; rates are shown only when publicly verified, otherwise “quoted at counter”.
- Courier/rider partner money is never collected by DropOff; the depot fare is paid at the counter.
- Cover is **quoted protection, not insurance**, until legal/commercial sign-off; never market as insured.
- SMS stays English-only until user locale is applied; TOI = Tonga (Zambia) / Chitonga.
- Ops/admin endpoints are gated (`isAdmin` = admin key | role=admin | admin phone). Never ship `DROPOFF_API_KEY`/`ADMIN_AUTH_KEY` in store builds.

## 2026-11-18 — Rider flow, Lusaka-first gating, custom domain, auth overhaul

Dated engineering log of the fixes shipped 2026-11-18. Release train: 0.5.45+55 → 0.5.46+56 → 0.5.47+57 (in progress).

### Split handover codes (migration 0065, applied live)
- Sender PICKUP code ≠ recipient DOOR code. `pickup_otp_hash` / `pickup_otp_attempts` added; backfilled pickup = delivery for legacy rows.
- Pickup confirms only against the sender's code; door handover only against the recipient's code (intercity only — see below).
- Endpoints: `POST /jobs/:ref/waybill` (assigned rider/ops, money stripped), `POST /jobs/:ref/resend-pin` (fresh split codes, 3/day/phone), `POST /jobs/:ref/confirm-receipt` (recipient session, idempotent, sender push).
- App: "View waybill" opens the order sheet pre-drop; rider stop sheet has a resend-PIN tile; pickup dialog gets resend button on otp_required/otp_locked.

### Lusaka-first city gate (owner directive 2026-11-18)
- Same-city recipients get NO 4-digit PIN SMS. They track live in-app and CONFIRM RECEIPT (optional, from their own session) and rate.
- DOOR codes are minted ONLY for intercity collections (e.g. Ndola). Enforcement keys off `delivery_otp_hash` existing; minting is city-gated everywhere (booking, settle, heal, resend, seed sweep).
- Sweep REGENERATES codes for live jobs; same-city rows get stale door hashes CLEARED.
- 6 live jobs seeded for real (4 geocoded); 6/6 recipient tracking-only SMS sent; 0 sender SMS (pickups done).

### Promos + plans
- Every plan carries a tag now: weekly / silver / gold / platinum all set to `Promo` (live `/plans` shows it).
- Tags editable by admins live via `/admin/tiers` (in-app plans editor has a Tag field); admin plans list now shows the current tag inline.

### API outage 2026-11-18 (root cause + fix)
- Adding `[[routes]]` custom_domain detaches the default workers.dev subdomain — every pre-0.5.47 APK saw 404s: tiers hidden ("Tier prices load when the server is reachable"), rider screens hidden (`/me` unreachable → role null).
- Fix: `workers_dev = true` in wrangler.toml; both hosts verified serving (`/health`, `/plans`). **Lesson: any time you add [[routes]], also set workers_dev = true.**
- Custom domain `api.carpsosolutions.store` added to the DropOff worker. Apex `carpsosolutions.store` = the company site (carpsosolutions.pages.dev) and `www` / `db` / cf-bounce email records are UNTOUCHED. Only the `api.` subdomain is DropOff's.
- Share links and deep links now use the same domain: Android intent-filter hosts (old host kept), iOS `applinks:api.carpsosolutions.store` entitlement, SMS tracking links and referral share text point at the new domain. Android App Links: dropoff-api host retained alongside; iOS AASA 404s until `APPLE_TEAM_ID` is set on the worker (iOS app not shipped yet).
- LIPILA_CALLBACK_URL deliberately still points at workers.dev (works on both; do not touch live payment wiring without a Lipila-side flip).

### OTP/auth resilience + UI overhaul
- Africa's Talking call bounded to 8s in `sms.ts` (was unbounded — could eat the app's 15s timeout → "network error" with no error surfaced).
- App retries `/auth/request` once silently on transport failure before showing the error.
- Truthful errors: client-side phone validation on the OTP screen; "network error" copy now names Private DNS / VPN / ad-blocker.
- Account screen rebuilt: `_CreateAccountSheet` is now fully self-contained (own controllers/state) — it used to swallow all feedback (silent dead create button). OTP send/verify buttons show spinners and progress labels; email sign-in button always tappable with explicit validation errors.

### Vehicle fields (booking + collections)
- Half-width Vehicle dropdown clipped labels ("Motor…"). Vehicle + parcels fields are full width now; no ellipsis on vehicle labels anywhere.

### Secrets hygiene (action required)
- `workers/.prod-secrets.txt` was TRACKED IN GIT and contains production secrets (JWT_SECRET, API_AUTH_KEY, ADMIN_AUTH_KEY, LIPILA_API_KEY, upload keystore password). Now untracked + gitignored; the file itself stays local only.
- **History still contains it — rotate:** JWT_SECRET, API_AUTH_KEY, ADMIN_AUTH_KEY (cheap, just re-login), LIPILA_API_KEY (needs Lipila portal — owner), upload keystore password (heavy; evaluate before rotating).
- Admin key earlier synced to live worker secret from .dev.vars (13 chars); rotation still pending.

### Known/parked
- Lipila payouts: HTTP 401 (empty body) — nothing works until Lipila flips it or CSV batch fallback; K1/test payouts pending owner action.
- Webhook secrets + chat-exposed `atsk_2b2c…` AT key rotation: deferred.
- `APPLE_TEAM_ID` to enable iOS AASA; iOS/web recipient registration portal: needs web assets deploy (dist/web built, wrangler assets binding pending).
- Play upload for the current release pair pending owner press.
- FCM device test, keystore rotation, UptimeRobot: open items.
- **dist/ discipline:** never ship artifacts not built from a verified-clean source tree; verify `flutter analyze` before trusting build outputs.

### Release 0.5.47+57 contents
- api.carpsosolutions.store default base URL; auth retry + truthful errors; self-contained create-account sheet; full-width vehicle fields; Promo tag visible in admin list; Auth/OTP bounded; deeplink hosts on the new domain.


### Server-backed address book (owner 2026-11-18)
- Migration 0066 adds `saved_places` (phone, label, lat/lng, source, used_at). Signed-in endpoints: GET/POST `/places`.
- App keeps an offline mirror (SharedPreferences) and merges the server copy when signed in; every navigator pick, booking address and GPS pin is remembered on both.
- In-app navigator shows saved places as a growing list and pins them on the DropOff map (`kind: 'saved'` bookmark markers); Photon results raised 6 to 20.
- Seeded 10 real pickup addresses from existing jobs into the owner's account (never invented).
- Three `prepaid_refund_failed` events from test jobs were VOIDED (note updated) — no real refund owed; financial rows retained.


### Web access for iOS users + uptime monitor (2026-11-19)
- Flutter web build deployed to a NEW Cloudflare Pages project `dropoff-web` (pages.dev: dropoff-web-9gk.pages.dev). Custom domain `dropoff.carpsosolutions.store` attached (CNAME to the Pages project); apex/company site untouched.
- iOS users can open the site in Safari and "Add to Home Screen" (PWA manifest, apple-touch-icon and iOS meta tags already in app/web/index.html).
- No UptimeRobot API key available, so an equivalent runs on the Worker: cron `*/5 * * * *` calls `/health`, logs to D1 `uptime_checks` (migration 0069), and pushes/emails the owner on the first failure and every 6th consecutive failure (30 min).

