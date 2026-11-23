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

## 2026-11-23 (twenty-third pass) — new-order push alarm + honest payment errors

Owner reports: (a) rider phones do not ring/show a curtain alert for a new
order; (b) a red toast on delivery details says "Could not start the prompt.
Check your connection and balance…" (booking DRO-261121-3ME9J, K5 receipt).

**Push alarm — root causes fixed:**
- `workers/src/push.ts`: `rider_assigned` / `trip_transferred` were routed to
  the ordinary `dropoff_jobs` channel at default priority. New `isOrderAlert()`
  maps them to `dropoff_orders`, and `buildFcmMessage()` now sends orders as
  HIGH-PRIORITY **data-only** with `ttl: 300s` (FCM's own notification payload
  cannot carry a full-screen intent/alarm category). Title/body travel in data.
  Other pushes keep the guaranteed system notification, now at PRIORITY_HIGH.
  Pure helper + 4 vitest tests in `test/push_alerts.test.ts`.
- `app/lib/data/push_service.dart`: background FCM handler never initialized
  `FlutterLocalNotificationsPlugin` in its isolate, so local alarm rendering
  silently failed in a try/catch. Added `_ensureLocalInitialized()` for both
  isolates (skips duplicate local show when FCM already posted a notification),
  captured the POST_NOTIFICATIONS result into `notificationsEnabled`, added
  `refreshPermission()`/`openNotificationSettings()`, and channel repair that
  deletes/recreates channels whose Android importance drifted (importance is
  immutable, so the old comment claiming a wipe was a lie). Added
  `bypassDnd: true` to the alarm channel.
- Cold-start token race: `register()` now awaits a `Completer` completed when
  `init()` finishes, instead of checking `_enabled` before Firebase/permission
  setup. The splash no longer waits on the OS permission dialog.
- `rider_queue_screen.dart`: red "New-order alerts are off" banner with a
  Turn on → system settings action; refreshes permission on resume.

**Payment error honesty:** `AppStore.settleCounterFare()` returned only a bare
status string, flattening network outages, 502 Lipila failures, wrong-account
jobs and stale receipts into one "connection and balance" toast. It now returns
`CounterFareResult` (status + actionable `message` + errorCode/detail) built by
`ui/money_errors.dart: counterFareErrorText()`. All four call sites updated.
Worker `/payments` logs every refused prompt (`paymentFail()` with code/status/
ref) so support can see the real reason. `test/money_errors_test.dart` (5).

**Toast placement:** `AppToast.error` now pins under the app bar via a root
overlay instead of floating at the bottom over the "Pay K5.00 to unlock" /
"Download courier receipt" actions it refers to; tap dismisses. Test at
320/360 px in `test/app_toast_test.dart` measures the position and proves the
lower action stays tappable. Full Flutter suite 49/49, vitest 24/24.

## 2026-11-23 (twenty-first pass) — Business promo card layout pinned by tests

Owner report: the Business promo card body ("Promo adds 25 parcels for K500 —
pro-rated to…") still rendered one character per line beside a small amber
piggy-bank icon.

Investigation: the Business `_banner` already had the correct structure
(fixed 36 px icon rail + `Expanded` title Row, body on its own full-width line,
full-width CTA) — the symptom comes from builds made before that fix, so the
real work was making it impossible to regress:

- Extracted the card to `app/lib/widgets/promo_banner.dart`; `business_screen.dart`
  now delegates to it. Text body has the card's full width, no fixed height,
  `softWrap: true`, and the CTA sits on its own full-width row.
- New `app/test/promo_banner_test.dart` renders the card at **320/360/390 px**,
  measures the painted text (body must be >55% of the viewport width and <150 px
  tall; title >35%; CTA >60%) and fails on any `FlutterError` (RenderFlex
  overflow). 3 tests, all passing; full suite 43/43.
- Repository-wide scan for the same anti-pattern found no high/medium cases;
  hardened the two residuals: `tickets_screen.dart` ticket header (long ref now
  `Expanded`, status `maxLines:1`) and `operations_screen.dart` face-check chip
  (bounded by `ConstrainedBox(maxWidth: 260)` before `Flexible` label, because
  a `Row` inside a `Wrap` has unbounded width).
- Permanent rules added under **Layout invariants — never write a vertical-text
  card again** above. Release `0.5.73+83`.

## 2026-11-23 (twentieth pass) — exact receipt amount, rider attestation, no zero-amount gate

Owner follow-up: confirm the figure the rider types really is the depot receipt
figure and warn riders never to enter an arbitrary amount, so the sender pays
exactly.

**Verified amount flow (no client override):** the only writer of
`jobs.counter_receipt_zmw` is the rider's `delivered` filing (or ops/admin
reconciliation) in `workers/src/index.ts`; `/payments` reads that stored total
verbatim (`receipt = round2(job.counter_receipt_zmw)`), adds only the platform
+ momo processing fees, and the client cannot supply an amount. Each filed
receipt is one photographed document with its own typed figure; the SERVER sums
them. Parsing/validation moved to testable `workers/src/receipts.ts`, with
`test/receipts.test.ts` (5 tests) pinning exact-per-document amounts, 2-decimal
rounding, zero/negative/over-cap/photo-less rejection, and that a client-sent
`total_zmw` is ignored.

**Rider guardrails:** the depot-drop sheet now shows an unmissable amber rule
("Type ONLY the amount printed on the depot receipt. Never guess, round up, or
add your own fee — the sender is charged exactly what you enter"), per-field
helper text, a live total the sender will be asked for, and a REQUIRED checkbox
"I copied the exact amount printed on every depot receipt". Filing is disabled
until it is ticked; validation snacks and the help sheet repeat the rule; the
success toast echoes the filed total so the rider can check it against the
photo. `receipt_amount_confirmed` is sent with the event and recorded in the
D1 audit note.

**Residual dead ends closed:** the counter-fare gate now also requires
`counter_receipt_zmw > 0` — a legacy receipt photo with no amount can neither be
charged nor cleared, so it must never block a booking. The same self-healing
gate was added to `POST /collections` (with `due_ref`/`due_amount_zmw`), so an
owed pickup fare cannot be bypassed by booking a collection; both forms already
turn the 409 into the "Settle your depot fare first" pay sheet. The receipt
button shows an honest "amount pending" card for a filed-but-unpriced row
instead of a dead tap.

Tests: Flutter 40/40, vitest 20/20, `dart analyze` + `tsc --noEmit` clean.
Worker deployed; release `0.5.72+82`.

## 2026-11-23 (nineteenth pass) — unpaid depot counter fare was a dead end

Owner bug: a sender owing a depot counter fare tapped **Download courier
receipt**, got no momo prompt, and could not book another pickup/collection.

Three separate faults, all fixed:

1. **The fare never reached her booking.** `AppStore.syncJobsFromServer` merged
   only stage/lastEvent/riderName/riderPhone into a booking this app created
   locally. `counter_receipt_zmw` / `_url` / `_paid` / `counter_receipts` were
   only read when a job was INSERTED new, so an existing row kept
   `counterFareDue == false` — no banner, no pay card, no prompt. The merge now
   mirrors all four fields (and `Booking.copyWith` carries them, keeping the old
   value when a field is omitted — it used to null them out).
2. **The receipt button disabled itself.** `_CourierReceiptButton` had
   `onPressed: _busy || url.isEmpty ? null : …`, so any row whose photo URL
   hadn't synced — notably a split batch where only `counter_receipts[]` holds
   the photos — was a permanently dead button. Paying no longer depends on the
   photo: while a fare is due the button reads **"Pay the courier bill — unlock
   receipt"** and always starts the prompt; only Download needs the image (with
   an honest "still being filed" toast if it is missing). The URL falls back to
   `counterReceipts.first.$2`.
3. **The booking gate had no way out.** `POST /jobs` returns 409
   `counter_fare_due` while a fare is unpaid. It now also returns `due_ref` and
   `due_amount_zmw`, and both the booking form and the collection form turn that
   error into a **"Settle your depot fare first"** sheet with one
   "Pay K… now" button (same sheet copy in both, form stays filled so she can
   retry immediately). Hooked to the new `AppStore.settleCounterFare()`, which
   uses ONE stable idempotency key per job (`cfare-<ref>`) — the receipt button
   used to include a timestamp, so a retry could open a second prompt.

Tests: `test/counter_fare_test.dart` (7) pins due-detection, the split-batch
shape with an empty primary URL, and that `copyWith` never drops the fare.
Full suite 40/40. Worker deployed; release `0.5.71+81`.

## 2026-11-23 (eighteenth pass) — release 0.5.70+80, sender prefill, PWA cache fix

- **Release `0.5.70+80`** (code 79 was built but never uploaded; 80 keeps the
  Play upload safe). APK 67.1 MB, AAB 51.8 MB, both built with
  `--dart-define=DROPOFF_API_URL=https://api.carpsosolutions.store` and
  `--no-pub` (a pub.dev advisories fetch failed mid-build and killed the first
  AAB run — always build with `--no-pub` after a successful `pub get`).
- **Sender prefill (owner 2026-11-22):** the booking form now fills
  `Sender name` and `Sender mobile number` from the signed-in account
  (`AppStore.fullName` / `AppStore.linkedPhone`) on first frame, but only when
  the field is still empty — a repeat-booking snapshot or typed value always
  wins. Implemented with `addPostFrameCallback` because `AppScope.of` walks an
  InheritedNotifier and must not be read during `initState`'s build phase.
- **PWA domain was serving a stale shell (owner 2026-11-22):** `app/web/sw.js`
  v2 answered `index.html`/shell requests cache-first, so
  `https://dropoff.carpsosolutions.store/` kept running the pre-deploy build.
  v3 is **network-first with cache fallback** for shell + navigation, and the
  cache name changed (`dropoff-web-v3`) so the old cache is dropped on
  activate. Cross-origin API calls are still never intercepted.
- Collection coverage added in `test/collection_flow_test.dart` (11 tests) and
  `AppStore.stageFromJobStatus` made public for it; full suite is 33/33.

## 2026-11-22 (seventeenth pass) — map fully self-hosted on our R2

- The basemap had two external dependencies left: Protomaps glyphs
  (`protomaps.github.io/basemaps-assets/fonts/...`) and sprites
  (`.../sprites/v4/light`). Both now live in **our** R2 bucket
  `dropoff-map-assets` (`https://pub-d23651cb1a9d491f998c73094d54f379.r2.dev`),
  together with the tile archive bucket. Nothing on the map calls another host;
  the only remote strings left in the theme are attribution links, which are
  never fetched.
- Mirrored in R2: `fonts/Noto Sans Regular|Medium|Italic|Devanagari Regular v1/0-255…768-1023.pbf`
  (16 files, the Latin + Devanagari ranges actually used by the light v4 theme)
  and `sprites/v4/light{,@2x}.{json,png}`.
- The light v4 theme layers are bundled in the app as JSON
  (`app/assets/map/theme-light-v4.json`) and loaded with `rootBundle`; the
  vendored 154 KB Dart const copy was removed, so analysis stays fast and the
  theme needs no network round-trip at map start.
- `RiderMap.selfHostedTheme` is gone: `_RiderMapState._assets` now returns the
  PMTiles provider **plus** the parsed theme, and `VectorTileLayer` uses both.
  Street names still come from the `roads`/`roads_labels_*` layers.
- Release `0.5.69+79` (codes 57–78 consumed).
- **Lusaka street-level zoom:** the same R2 bucket that carries the regional
  archive already ships `tiles/lusaka-z0-16.pmtiles` (header read live:
  z0–16, bounds S −15.78 / W 27.66 / N −15.02 / E 28.62 — identical to
  churchonapp_flutter's `MAPS_EXTRA_SOURCES.lusaka`). New
  `app/lib/data/map_tile_sources.dart` adds `CityFirstTileProvider`, which
  serves that archive inside the Lusaka rectangle from z13 up (so z16 detail
  is reachable) and the regional archive everywhere else, falling back to
  regional whenever a city tile is missing. The rider map now reports
  `maximumZoom` 16 and allows the camera to 16.5. Unit-tested in
  `app/test/map_tile_sources_test.dart` (city inside bbox, regional outside,
  regional at low zoom, regional fallback on a missing city tile).
- **Collection tests (owner ask 2026-11-22):** there were none, so
  `app/test/collection_flow_test.dart` now pins the depot → recipient
  contract: `isCollection`/`hasCollectionReceipt` (a standard row never
  surfaces a receipt), the 5-step collection timeline (and that a last-mile
  fee cannot stretch it to 7), the collection stage map
  (`AppStore.stageFromJobStatus(..., collection: true)` — made public for
  this, behaviour unchanged) and the fee prompt (plan-covered = leg only;
  PAYG = leg + platform fee + momo fee, platform floor respected).
  Standard timelines/stages are asserted alongside as regression guards.
- **Vertical-text bugs (owner 2026-11-22):** the Business retention banner now
  keeps its body on its own full-width line (it used to live inside the
  icon+title `Row`), and the depot-drop sheet replaced its `ListTile` +
  `trailing` button with a stacked card and a full-width **File drop** button,
  so neither label can be squeezed into a one-character column.

## 2026-11-21 (sixteenth pass) — evidence stamps, fare-receipt unlock, order ring, vehicle markers

- Photo evidence: `uploadImage` now takes `capturedAt` and every camera/gallery
  call site passes `XFile.lastModified()`, so the burned-in CAT timestamp is
  the REAL capture time (it used to be upload time, making a batch look
  identical). All evidence thumbnails switched from `BoxFit.cover` to
  `BoxFit.contain` on a neutral background — cover was cropping the bottom
  DropOff stamp strip and making photos look zoomed.
- Counter fare / blurred receipt: the Bookings list now carries a clear
  "Counter fare due — receipt locked" banner with the exact amount and a
  FARE DUE pill, so a missed momo prompt is never a dead end. The locked and
  paid receipt images use `AuthedImage` (a plain `Image.network` was 401ing on
  `/media`), the pay button uses a stable idempotency key, and error copy is
  plain-language with no raw codes.
- New-order alarm: dedicated max-importance `dropoff_orders` notification
  channel, `USE_FULL_SCREEN_INTENT`/`WAKE_LOCK`/`VIBRATE` permissions,
  full-screen heads-up + vibration for assignment pushes, an audible
  `StepSounds.orderAlert()` in the rider queue, and cold-start priming so the
  first queue load adopts existing jobs without ringing.
- Map vehicle marker: new `MapVehicleMarker` draws the branded top-down bike/
  car and automatically upgrades to `map_bike_3d.png` / `map_car_3d.png` when
  those sprites are present. `/jobs/:ref/live` now returns `vehicle_class`
  (server-decided car upgrade), and the rider navigator + sender tracking map
  show the same marker.
- **3D art resolved:** the sprite files now exist at `app/assets/brand/map_bike_3d.png`
  and `app/assets/brand/map_car_3d.png` with the DropOff logo composited onto
  the helmet (bike) and roof (car). `MapVehicleMarker` auto-loads them.

## 2026-11-21 (fifteenth pass) — premium navigation voice + smart saved pins

- Voice guidance: 1-second GPS stream replaces the 10 s one-shot (the "turn
  now" cue was skipped at speed); throttle now runs BEFORE a band is consumed;
  maneuver identity (not index) survives re-routes so cues are not re-spoken;
  unmute re-anchors and clears throttle; distinct far/near/now phrasing,
  lowercase TTS prosody, arrival cue, en-GB voice fallback, awaited setup and
  a live visual next-turn banner. Roundabout exit count now uses OSRM `exit`.
- Saved places: new `SavedPlacePin` — DropOff logo on an amber-rimmed forest
  teardrop, selected label bubble, frequent star, tap-to-route. Saved pins no
  longer distort the camera fit. Fixed pin-erasure on null-coordinate merges,
  preserved coordinates on pinless re-booking, live reload after saving, and
  no-pin places are now search-only instead of routing to the current spot.
- **Blocked:** 3D motorcycle/car sprite generation failed — OpenCode image
  credits exhausted (pay-as-you-go). No new art shipped this pass.

## 2026-11-21 (fourteenth pass) — Business promo banner vertical-text fix

- `_banner()` in `business_screen.dart` (used by the Silver/Gold/Platinum promo
  banner and the "outgrew your plan" banner) put a long body Text in an
  `Expanded` beside a `FilledButton`; on 360 px screens the button squeezed the
  text into a 1-character column. The icon now sits in a fixed 40×40 rail, the
  text is a full-width `Expanded` with `softWrap: true`, and the CTA button moved
  to its own row below. Text content unchanged. Other known vertical-text fixes
  (toast, plan tier cards) remain intact.

## 2026-11-21 (thirteenth pass) — premium sender UI/UX copy pass

- Truthfulness: counter fare now says rider pays at the counter and sender
  repays the photographed receipt in DropOff (booking, booking detail, waybill,
  courier directory, collections). "Auto-bill" changed to a momo reminder.
  Canceled-booking copy replaced with the roll-forward message.
- Raw error/ref codes no longer shown: booking, payment, receipt and ticket
  errors are plain next-step sentences. Raw DRO- refs removed from success copy.
- Read-heavy copy cut: counter fare explained once, pin explanation condensed,
  help/tutorial rows shortened to one line each, "item" used consistently.
- Morning window labels corrected to **5:30–7:30 AM** (06:00 is the slot name).
- Sender vehicle selection: removed the "Does it need a car? yes/no" question
  from booking and collections. Motorcycle is the only sender-facing choice;
  the worker still auto-upgrades large/over-cap parcels to a car.
- Home screen: trust strip and 3-step card removed, replaced by one
  "How DropOff works — six quick steps" tile. Version bumped to `0.5.62+72`
  then `0.5.63+73` for the banner fix, then `0.5.64+74` for removing the
  sender vehicle question (codes 57–73 consumed).

## 2026-11-21 (twelfth pass) — Task Queue / Team tab UI polish

- Rider sweep-shift control moved OUT of the Task Queue body into a compact
  ON/OFF pill in the App Bar; full controls open in a bottom sheet. The stats
  card is again the first item in the scrollable area and is never pushed down
  or covered.
- Rider Team tab simplified: removed duplicate link card and empty spacer,
  shortened the explanatory copy on selfie, verification, task queue, reviews,
  targets and live-location cards so it reads as a professional dashboard.

## 2026-11-21 (eleventh pass) — correct pickup windows + next-slot advance claim

- The **06:00 pickup window opens at 05:30 CAT** and closes at **07:30**
  (Platinum's first trip); the sweep target for depot drop-off is 08:30.
  Windows: 05:30–07:30 (06:00), 10:00–11:30, 14:00–15:30.
- Riders **off shift can claim the NEXT sweep's jobs (06:00 / 10:00 / 14:00)
  at any time**: `/rider/available` returns those advance jobs with an
  `off_shift` hint; `POST /claim` allows them via `isUpcomingSweepJob()`.
  Collection starts at 05:30 for the 06:00 sweep, or at 10:00 / 14:00.
  All other jobs remain shift-gated.

## 2026-11-21 (tenth pass) — rider sweep shifts (06:00/10:00/14:00 CAT)

- Migration `0077_rider_shifts.sql`: `riders.shifts` (default ALL THREE),
  `riders.on_shift` (default 1), `riders.shift_terms_accepted`.
- Pickup windows are 05:30–07:30 (06:00 opens early), 10:00–11:30 and
  14:00–15:30 CAT (see SWEEP_SLOTS; the 08:30/12:30/16:30 figures are
  depot drop-off TARGETS, not shift ends). Between windows riders may do other
  work; dispatch (`nearestAvailableRider`) skips them outside an active window
  and the claim board returns only advance next-slot jobs (`off_shift`).
- New endpoints `GET/POST /rider/shifts`: rider can toggle ON/OFF and edit the
  selected windows; going ON requires accepting the sweep-shift terms (daily
  30-parcel target OR monthly target, proof-handover and location rules).
- Rider Task Queue shows a shift card with the active window badge and an
  ON/OFF SHIFT button. Presence pings are unaffected (still run while signed in).

## 2026-11-21 (ninth pass) — money-flow confirmation + promo pricing disclosure

CONFIRMED from the fee engine (`workers/src/fees.ts`) and worker:
- EVERY momo transaction includes BOTH the Lipila collection leg (K2.50, paid
  by the customer) AND our platform cut (`platformFee()` = 1% + K0.98, min K4,
  goes to DropOff). It is NOT just Lipila's fee.
- PAYG rider fees stay with DropOff — riders are salaried (K3,000/mo) and are
  NEVER paid per parcel/plan. `RIDER_TAKE_PCT` machinery is dormant.
- Plan purchases charge `platformFee(plan.price) + MOMO_COLLECTION_FEE` on top
  of the plan price — the sender covers the transaction cost, and our cut is
  included. Counter-fare reimbursements do the same (subscribers exempt from
  the processing fee only there).
- UI now states this plainly at plan purchase (Account + Business dialogs) and
  in the plans help sheet.
- Plan prices are labelled INTRODUCTORY PROMO pricing with explicit notice that
  they rise within 3–6 months (no later than 1 year); existing cycles keep their
  rate. Do not remove this disclosure.

## 2026-11-21 (eighth pass) — feature switches, server-decided vehicle, transfers, PAYG promos, branding, release

- **Migration 0076:** `jobs.needs_car`, `promo_codes.kind`, and 7 new app_settings
  switches. All 10 switches are now generated from one `FLAG_KEYS` list in the
  worker and shown in the admin console (bookings kill switch, auto-assign,
  claim board, rider transfer, photo stamp, step sounds, voice, etc.).
- **Vehicle chosen by the server:** sender UI no longer has a vehicle dropdown
  (booking, collection, fare checker). A "Does it need a car? yes/no" question
  feeds `vehicleClassForParcel()`; large parcels → car, small/medium → motorcycle,
  over-cap → car. Dispatch tries motorcycles first, then cars; car-preferred jobs
  only target car/van riders and show a "Sender prefers a CAR" claim-board badge.
- **Rider transfer:** `POST /jobs/:ref/transfer` atomically moves a pre-pickup
  job to another active rider (loads, assigned_at, ETA, event, route reset,
  pushes). Rider Task Queue has a "Transfer this ride" tile. Everything else
  derives from `jobs.rider_id` and updates automatically.
- **Promo scoping:** FRIEND codes are marked `kind='referral'`, rejected for
  riders/staff, PAYG-only, and work on both pickup bookings and collections.
  `/refer/claim` rejects riders; `/promo/check` needs sender identity.
- **Branding:** forest + logo native splash, "DropOff · " prefix on every push
  title, branded waybill title.
- **Release:** version bumped to `0.5.60+70` — **code 70 was rejected by Play
  ("already used")**, so the uploadable release is `0.5.61+71`. Codes 57–70
  are consumed; never reuse any of them.
- **Destination consolidation:** merged the public Zambia town/city list
  (Wikipedia "List of populated places in Zambia", fetched 2026-11-21) into
  `catalog.dart cities` for the counter-receipt destination picker. Courier-
  specific coverage is not published by the couriers online, so no fare is
  claimed — every counter fare stays "quoted at counter".
- **Transfers at any stage:** the transfer endpoint now accepts every active
  delivery stage (assigned → picked_up → at_depot → departed → arrived →
  ready_for_collection), so a rider stuck in a depot queue can hand the live
  trip to another rider. The rider sheet shows the action until completion.

## 2026-11-21 (seventh pass) — delete requests, tickets crash, parked release, SMS, referrals

- **Delete requests:** `/admin/support/threads/deletion-requests` lists open
  "please delete" tickets with the DRO- ref extracted; the admin Delete card
  shows them with one-tap **Delete** / **Release instead** actions. The soft
  delete already closes matching tickets (audit trail kept).
- **Tickets no longer crash:** defensive `Map` conversion + try/catch in both
  customer ticket lists/detail (the old strict cast produced the "String is
  not a subtype of Map" error); admin sheet now reads the worker's `thread`
  key; `/tickets` added to cache invalidation.
- **Parked bookings:** `POST /admin/jobs/:ref/unpark` releases legacy canceled
  jobs to the next sweep + claim board; "PARKED" copy changed to WARNING — the
  strike hold was removed, strikes are audit-only.
- **SMS/push wording sweep:** collection recipients get in-app confirmation
  (no phantom PIN); collection pushes say depot/recipient; counter-fare SMS
  states the rider fronts the fare and the sender repays; driver→rider,
  parcel→item, honest plan renewal, support-reply push title, stale comments.
- **Referrals:** `/r/CODE` now claims the referral (properly persisted on the
  account screen); reward minting is atomic and the earned FRIEND code is
  returned by `/refer/code`, shown in Account and sent by push+SMS; new owner
  toggle `referral_bonus_enabled` (migration 0075) with an admin switch.
- **Declared package value confirmed:** present in `/jobs/:ref/waybill` and
  evidence, and shown on rider waybill, sender waybill, thermal print and
  booking evidence summary.
- **Roles confirmed:** `customer` covers BOTH sender and recipient — there are
  no separate roles; jobs are gated by `sender_phone`/`recipient_phone`.

## 2026-11-21 (sixth pass) — bold rating copy, admin delete, role management

- **Rating success copy:** `Done — "Thank You" Your rating helps Riders,
  Couriers and Senders build a good name.` — the quoted phrase is bold
  (`RichText` via `_messageText`), role words capitalised.
- **Admin delete after a support ticket:** root cause was the ticket prefill
  using the LOCAL `DO-…` reference, not the server `DRO-…` one. Both the
  deletion-request and help ticket prefills now use
  `booking.serverRef ?? booking.reference`. The worker normalises the ref
  (strips `#`, uppercases), returns `booking_not_found` with an explanatory
  detail, is idempotent for already-deleted jobs, and closes (never deletes)
  matching support threads with a SYSTEM audit note.
- **Role management:** `ASSIGNABLE_ROLES` = customer/rider/partner/ops/admin/cfo
  is the single whitelist; `/admin/users/role` is now `isAdmin`-gated (delegated
  admins can assign every non-superadmin role); owner row cannot be demoted;
  `superadmin` remains an IDENTITY and is never assignable. Partner role now
  REQUIRES a courier depot (admin console prompts for one) so it is functional.
  CFO can open the console (finance-only). Ops no longer sees role controls.
  Added the missing `POST /admin/users/:phone/update` route that the Edit button
  already called. `courier_id` is returned by `GET /admin/users`.

## 2026-11-21 (fifth pass) — link domains, ratings, waybill image

### User-facing links use the PWA domain
- New worker var `APP_PUBLIC_URL = https://dropoff.carpsosolutions.store`
  (kept separate from `APP_URL`, which stays the API base for `/health`).
  `publicLinkBase()` now drives tracking SMS/email, `/track/incoming`,
  `authMagicLink()` and referral share text. App-side hardcoded referral /
  tracking strings updated too.
- PWA proxy: `app/web/_redirects` is kept for reference, but Cloudflare Pages
  did NOT apply its 200 proxies. The working fix is Worker routes in
  `wrangler.toml` for `dropoff.carpsosolutions.store/{track,t,auth,.well-known}/*`
  (zone `carpsosolutions.store`). Verified: `/.well-known/assetlinks.json`
  returns `application/json`, `/track/abc` returns Worker JSON, PWA root is
  still the Flutter site. Do NOT proxy `/r`, `/promo`, `/plans`, `/bookings`.
- Android App Links and iOS Associated Domains now include
  `dropoff.carpsosolutions.store` (old hosts retained for sent links).
- Unchanged on purpose: API `baseUrl`/`fallbackBaseUrl`, `DROPOFF_API_URL`
  dart-define, `LIPILA_CALLBACK_URL`, `[[routes]]` for the API host.

### Ratings
- Worker ratings are now participant-only for ALL roles, with self-rating
  blocked for sender/rider/courier; one `rated` job event per target;
  `/rider/reviews` queries the real stored key (`target_type='driver'`,
  `target_key='rider:<id>'`); hidden ratings filtered; null courier key fixed.
- UI says **Rider / Sender / Courier** (DB tokens `driver`/`seller` retained).
  Submit button becomes **Done** and is disabled until a star/comment changes.
  The recipient now has a **Rate the sender** card in TrackScreen; the sender
  cannot rate himself (server guard + hidden target).

### Waybill share image
- The right-side cut came from a ~64-char unbreakable tracking URL inside the
  fixed-width `RepaintBoundary`. Tracking URL/token now use `FittedBox(scaleDown)`,
  the capture box is `ConstrainedBox(maxWidth: width)` + `ClipRect`, and the
  depot title / row values have maxLines + overflow.

## 2026-11-21 (fourth pass) — rider package value, courier receipt download, target-linked pay

- **Rider waybill package value:** `/jobs/:ref/waybill` now selects and returns
  `declared_value_zmw` inside the waybill map (it was returned only by the
  evidence endpoint, so the rider sheet always showed nothing). The sheet
  always renders a **Package value** row (`Not declared by the sender` when
  absent). The sender side already had it — `waybill_screen.dart:599` and the
  thermal waybill both show **Declared value**.
- **Post-journey "Download courier receipt"** button in booking detail, just
  before "Get help with this delivery". If the courier bill is unpaid it is
  greyed/locked and tapping it prompts the momo payment for the exact amount
  written on the receipt (`counter_receipt_zmw`); when paid it downloads the
  real photographed receipt image.
- **"Your pay" card removed** from the rider view. Pay is now stated with the
  targets it depends on: full K3,000 monthly salary only when the month target
  is reached; below target, pay is calculated from rides actually completed.

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

## Layout invariants — never write a vertical-text card again (owner 2026-11-23)

A long `Text` placed as a DIRECT child of a `Row` receives only the width left
over by its siblings. With a fixed icon/button beside it that can be <20 px, so
the copy renders one character per line down the left edge and clips at the
bottom. This has happened repeatedly (Business promo/retention banner, Business
retention banner, depot-drop sheet). Enforce these rules in EVERY UI change:

1. **A long string never sits directly in a `Row`.** Wrap it in `Expanded`
   (preferred) or `Flexible`, and give fixed siblings a fixed `SizedBox` rail.
   If the Row is inside a `Wrap` (unbounded width), first bound it with
   `ConstrainedBox(maxWidth: …)`, then use `Flexible`.
2. **Body copy goes on its own full-width line** in the parent `Column`, not in
   the icon/title `Row`. Set `softWrap: true`; keep `maxLines` for headings only.
3. **No fixed height around multi-line copy.** Icons/photos may use
   `SizedBox(height: …)`; text may not. Let the card grow with the text.
4. **Full-width CTAs** use `SizedBox(width: double.infinity)` on their own row,
   never a trailing slot in a `Row` with the message.
5. **Regression-test at 320 px, 360 px and 390 px.** Measure the painted text
   (it must be a large fraction of the card width and only a few lines tall)
   and fail on any `FlutterError` / RenderFlex overflow. Reference test:
   `app/test/promo_banner_test.dart`; reference implementation:
   `app/lib/widgets/promo_banner.dart` (extracted from `business_screen.dart`
   so the rule is reusable and testable). Before declaring a layout fix done,
   run `flutter test test/promo_banner_test.dart` and inspect all three widths.

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

