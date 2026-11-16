# DropOff — Production Audit 2026-11-16
**Commit audited:** `72bb692` (+ `docs/PLAY_STORE.md`) · Worker deploy `c4261a43` (latest, `/maps/route` included — map proxy)
**Release:** `0.5.28+39` · artifacts in `dist/` · `main` pushed.
**Method:** live probes against the production Worker, repo/code inspection, worker typecheck, app analyze/test, dist hygiene, secrets hygiene. Anything marked **UNVERIFIED** needs an owner-side environment check — do not read UNVERIFIED as PASS.

**Legend:** ✅ SHIP · 🟡 SHIP WITH CAVEATS (works; owner action before scale) · 🔴 BLOCKED / MISSING · ⚪ ROADMAP

---

## 0. Verdict summary

| # | Feature area | Verdict |
|---|--------------|---------|
| 1 | Money flow — prepayment holds, counter-fare repayment, payouts | 🟡 |
| 2 | Booking → algorithmic dispatch (no manual pick) | ✅ |
| 3 | Subscriptions / packs / overage flips | 🟡 |
| 4 | Tracking & privacy (account gate, held lock) | ✅ |
| 5 | Rider ops — queue, GPS, KYC selfie AI | 🟡 |
| 6 | Evidence & proof of delivery (camera, OTP, frozen photos) | ✅ |
| 7 | Chat & moderation (threads, blocks, archive) | ✅ |
| 8 | Admin console (roles, deletes, strikes) | ✅ |
| 9 | Map & navigation (in-app, code fully ours) | 🟡 ← the one open production question |
| 10 | SMS | 🟡 |
| 11 | Push (FCM) | 🟡 UNVERIFIED on production |
| 12 | Play release process | ✅ with 2 mandatory hygiene items |
| 13 | Legal & compliance | 🟡 |
| 14 | Security posture | 🟡 |
| 15 | Data & privacy (unlink/purge/deletes) | ✅ |
| 16 | Monitoring & ops | 🔴 |
| 17 | Unit economics | 🟡 |
| 18 | Test coverage | 🔴 |

**Launch-blocking for a public, money-handling production release: §1, §9, §11, §16, §18.** Everything else is fit to run with the caveats noted.

---

## 1. Money flow — prepayment, held bookings, counter-fare repayment — 🟡

**What it does.** Sender's momo is charged a DropOff prepayment (trip price + processing fee). The rider is NEVER the pay-first leg: no prepayment → booking held → no dispatch (server-side; tracking 402s; `redispatchUnassignedPaidJobs` cron re-dispatches when it lands; holds > 24h auto-cancel with `hold_expired`, no money moved). Courier counter fare is partner money — sender repays the *exact receipt* amount + processing after drop-off; never taken in advance. Payout to riders: handled in payroll (weekly, pace-gated K3,000/mo/Light); platform cut 5% over K2,500/mo turnover. Refunds on undelivered/auto-canceled journeys return to original momo.

**Evidence.** `workers/src/index.ts` — `jobPaymentHeld()`, `settlePaymentSuccess()`, `/payments/*`, `/admin/jobs/:ref/delete`; `cancelExpiredHolds` in the minute cron. App: held banner on My Bookings (this release), `_PrepayCard`, `_CounterReceiptCard`, delivery OTP gate. Worker checked OK on live; typecheck clean.

**Why 🟡.** Code paths exist and are hardened, but **no end-to-end live Lipila transaction has been run this session** (needs a real K1 momo prompt + manual confirmation). Lipila is live (`LIPILA_BASE_URL=https://blz.lipila.io`) — confirm:
1. one real collect against production + webhook flips job to dispatched,
2. one counter-fare repayment with a real receipt,
3. one refund (kill a held booking after prepayment; verify auto-refund lands).
Each of those is a 5-minute check with the owner's phone. Also confirm Lipila's fee schedule matches the booking UI processing fee (processor fee is what changes net on every transaction).

**Fraud exposure note.** Dual-approval (two signatures release payroll) is in place on payouts; admins/ops cannot move customer money. `/admin/jobs/:ref/delete` keeps payments untouched and writes an audit event — verify the finance team accepts that ledger shape before first audit.

---

## 2. Booking → dispatch — ✅

**What it does.** Algorithmic dispatch only — `nearestAvailableRider()` with staleness weighting (≤10 min true distance; ≤60 min +12–50 km virtual; older/missing +40 km). Manual assignment endpoint removed. Paid-but-unassigned bookings are re-dispatched by the minute cron when rider capacity appears. Re-dispatch keeps the job instead of canceling on transient capacity loss.

**Evidence.** `workers/src/index.ts:~6050–6090`; dispatch cron `* * * * *`; cap rules for day-cycle subscriptions fixed this cycle (`cycle_days ≤ 1 → parcels_per_day`).

**Caveat for scale (not blocking).** `nearestAvailableRider()` does one select per retry — with thousands of concurrent unassigned jobs this needs a partial index check-up, and the query itself should be profiled against real D1 metrics. Fine at current volume.

---

## 3. Subscriptions / packs — 🟡

**What it does.** Silver/Pro/Camel-tier monthly & day-pass packs; overage discount path intentionally hidden by default (`overage_discount_enabled=false`, `door_to_door_enabled=false` in `app_settings`, admin-flippable). `/plans` exposes `feature_flags`; day-cycles cap at `parcels_per_day`, multi-day cycles at `parcels_per_month`; Silver-1/day does not overage-gate monthly packs. Tiers editable live at `/admin/tiers`.

**Why 🟡.** Pricing is inert-visible: nothing can be exercised by this audit without a real plan purchase through the live endpoint. Before launch, verify against prod D1:
1. plan cycle boundary behavior at exactly midnight CAT (billing rolls server-side — check `period_end` handling for a day-pass purchased at 23:55),
2. a Silver-1/day booking against the same account after Silver-1 stays *untaxed* per the promo intent (the fix from this sprint),
3. a monthly subscriber hitting the monthly cap and the fold-to-overage path *staying hidden* at default flags.
Via `/admin/tiers` you can spot-check caps with one K0 promo pack.

**Commercial note.** Pack Codes (offline bulk sales) mint codes redeemable on any device — verify codes are single-use and cannot be brute-forced (code entropy + rate limit) before POS rollout.

---

## 4. Tracking & privacy — ✅

**What it does.** Recipient parcels: tracking SMS deferred until the DropOff prepayment settles (no live link leaks for unpaid bookings) — 402 on `POST /tracking-link`, masked `GET /track/:token`, minted only at settlement. Account gate: stranger with the SMS link 404s at parcel content; recipient must sign in/create account with the addressed phone. `/track/incoming` and sender `/jobs` now exclude `status='deleted'` — deleted bookings are invisible to everyone. Rider ↔ sender live location shared only during active job; recipient sees delayed fix.

**Evidence.** `workers/src/index.ts` — `trackAccess()`, `/track/incoming`, `tracking-link` 402; `track_screen.dart` gate; `bookings_screen.dart` waybill gating. Live: tracking screen renders instructions only after account gate.

**Clean for launch.** No PII beyond what a signed-in recipient needs; photos/custody logs stay token-scoped.

---

## 5. Rider ops — 🟡

**What it does.** Rider queue with proof-of-delivery photos per leg (job requires camera photo to mark delivered; no price-only proof); KYC package + selfie reviewed by owner/admin before any job is assigned; selfie swap demotes rider to pending; AI selfie check (HF inference) is decision-support, not automatic assignment. GPS shared only with senders of their jobs while assigned; broadcast on one tap. Delivery requires recipient 4-digit OTP (door deliveries).

**Why 🟡.**
1. **HF API dependency is unlisted in your P&L**: every KYC selfie + evidence grading hits `HF_API_KEY`. If the HF quota lapses or the model is deprecated, the queue stalls silently unless you watch Workers Logs. Add an explicit "AI on/off" kill-switch confirmation (it exists via feature flag? → **not confirmed** — owner should test with flag off) or budget a monthly HF line.
2. **Selfie swap detection requires re-shoot** — a rider can only be auto-demoted when a mismatch is flagged. Verify the admin console shows the AI verdict with confidence + reason so staff know when to override.
3. Geolocation on rider devices: high-accuracy GPS for navigation holds battery cost; riders must be told (they are; app says GPS sharing is opt-in).

---

## 6. Evidence & proof of delivery — ✅

**What it does.** Camera capture is mandatory for delivery marking; photos are first-write-wins and frozen (proof files on R2 with media prefix scoping); evidence locker per booking; recipient gets delivery call + OTP gate for door jobs; depot-counter repayment path requires the counter receipt photo; hybrid evidence checker (deterministic signals + LLM) flags parcel swaps without blocking dispatch.

**Evidence.** `dropoff_api.ts` handlers: `delivery_photo_required` (400), `otp_required`, POD freeze logic; app evidence locker; this release shipped frozen-post-upload semantics.

**Clean.** This is your strongest fraud surface — depot staff and senders can *verify*, not *rewrite*, the chain.

---

## 7. Chat & moderation — ✅

**What it does.** Per-job threads (WebSocket Durable Object; 4s poll fallback); support channel; block/unblock; report → strike ledger; auto-archive on delivery; partner depot consoles can join only their courier's thread. Messages include sender name/role label, masked phone, photo.

**Evidence.** `chat_screen.dart`, DOs `src/chat_do.ts`, moderation in D1 (`0031_chat.sql`, `0051_chat_moderation.sql`).

**Minor.** Block list lives server-side (`/users/blocks/:phone`) — consistent across devices. Unblocking requires opening the blocked user — keep the UX note for support.

---

## 8. Admin console — ✅ (one hygiene note)

**Shipped in this release:** owner-only account deletion (`/admin/users/:phone`, superadmin required, owner refused, kills sessions + push tokens, job history kept for audit); admin booking deletion (`/admin/jobs/:ref/delete`, soft delete, payments untouched, `admin_deleted` audit event, hidden from all user listings); console cards for both wired. Role minting stays owner-only; admin cannot mint admin. Branch manager, strike ledger (with wipe), pack codes, plan caps, couriers, fraud queue, SMS broadcast, security alerts, XC (tax) reports — all gated `isAdmin`/`isSuperAdmin`.

**Evidence.** `admin_screen.dart` — `_BookingDeleteCard`, delete-account rows, `_setRole`; worker `/admin/*` routes audited 2026-11-15 (all ungated admin routes fixed that day); this release deployed as `c4261a43` re-verified.

**Hygiene.**
- Delete booking is **ref-driven**, not a jobs list — a typo deletes nothing (`not found`) but slower UX for batch deletions. If a bulk "wipe this test account's bookings" tool appears later, keep it owner-only + dry-run mode.
- The 60-account cap on the Users card is intentional scroll protection; it is not a compliance control.

---

## 9. Map & navigation — 🟡 **the open production question**

**What ships today.** DropOff's own vector basemap (Protomaps Zambia/Zimbabwe/Malawi/Mozambique PMTiles on our R2, `fileCacheTtl` 30d) — no Google/MapTiler dependency. Live rider tracking (sender view) with road-following route line; recipient watch page; rider in-app navigator with **road routes (OSRM)**, turn-by-turn cue sheet (A→Z bottom sheet), live GPS pin re-routing every 150 m, zoom controls, re-fit, 30-day offline tile cache; Photon place search biased to Lusaka; dashed straight-line + explicit label when the router is unreachable — never a fake road. Zoom UI, attribution, all in-app.

**Why 🟡 — the routing SLA.** The router chain is: **DropOff Worker `/maps/route` → ORS (key server-side, 2,000 directions/day free tier, cached 15 min per 5dp coordinate pair) → OSRM public demo (evaluation-grade) → labelled straight-line.** The Worker proxy is **deployed and returns 503 `router_not_configured` right now** because `ORS_API_KEY` is not set — the app then uses the OSRM demo.

OSRM's own docs state the demo server **is not for production use** (fair-use, no SLA, could be rate-limited or cut off at any time). That risk is tolerable pre-launch but is **not production-grade** for money-handling routing.

**Owner actions to make this ✅ SHIP (each ≤ 10 minutes):**
1. Sign up at `openrouteservice.org` (free, no card) → Settings → API key.
2. `cd workers && npx wrangler secret put ORS_API_KEY` → paste key.
3. curl check: `curl -sH "Authorization: Bearer <any test JWT>" "https://dropoff-api.godfreymoseskalambo.workers.dev/maps/route?from=28.3228,-15.3875&to=28.2833,-15.4167"` → expect `points`, `steps`, `duration_s`.
4. No rebuild needed — app already calls the proxy first.

**Budget safety:** Cache API dedups identical 5dp-coordinate routes for 15 min; routes only fetch when the rider has moved >150 m; 2,000/day covers ~2× current fleet with headroom. Growth path: self-host OSRM on a $5/mo VPS (geofabrik.de Zambia extract → `osrm-backend` in Docker; point `/maps/route` upstream at it; zero ongoing cost, full ownership). Voice turn-by-turn remains unshipped (OS TTS integration is a separate task).

**Tile availability.** The basemap URL is R2 public bucket — if the bucket rotates, the map degrades to "map could not load" with a last-seen fallback; riders still have job/queue UIs. Consider signed URLs or a custom domain on the bucket once traffic grows (R2 egress is free within the plan).

---

## 10. SMS — 🟡

**What it does.** Delivery milestone SMS (picked_up, at_depot, delivered), recipient tracking SMS with login hint + OTP, rider assignment, capacity reminders, stale-rider nudges — via Africa's Talking (Carpso account, `AT_USERNAME=ChurchOnApp`, `AT_FROM=Carpso`). English-only today.

**Why 🟡.**
1. **Sender ID "Carpso" registration** — AT requires sender IDs (shortcodes/name) to be registered per market. UNVERIFIED whether `Carpso` is registered in Zambia; unregistered name = undelivered SMS on some routes. Confirm in AT dashboard or via a test to a non-test number.
2. **TOI locale (Chitonga)** — not shipped; SMS lands English regardless. Fine for launch; must not ship as if localized.
3. **Cost audit** — every SMS is real money at volume. The nudge/reminder crons (`0 19 * * *`, `0 6 * * MON`) should be sampled once live to confirm no runaway fan-out (e.g., broadcasting "paused reminders" after a user set `reprompt_paused`).
4. **Compliance** — SMS must stay opt-out-able (STOP keyword) under Zambian e-comm norms; UNVERIFIED whether opt-out is handled. Confirm with Carpso legal or fold into §13.

---

## 11. Push (FCM) — 🟡 UNVERIFIED on production

**What it does.** Fully-wired HTTP-v1 FCM sender (service-account JWT signed with WebCrypto, 55-minute TTL), zero dependencies, used for rider_assigned, payment received, delivery completion, push broadcast admin card, chat pings. Code logs + no-ops when `FIREBASE_SERVICE_ACCOUNT` is not set — **the code cannot tell you whether the secret is set in production**.

**Owner must do:**
1. `wrangler secret list` on the production worker → confirm `FIREBASE_SERVICE_ACCOUNT` is present (name only).
2. Trigger a real push to a real device (admin → broadcast → “test” to one number, or assign a job and watch for the push).
3. Check the broadcast card in the admin console shows `queued`, not `failed`.

If unset, riders get SMS only — this is a one-paste fix.

---

## 12. Play release process — ✅ with two mandatory items

**Working.** Dist is the source of truth; 0.5.28+39 built from clean (`flutter clean`, no `DROPOFF_API_KEY` in release builds — verified `tools/build_release.ps1` injects only `DROPOFF_API_URL`); versionCode burned (38 was already used — Play rejected) has been corrected to 39; old pairs purged; unversioned aliases always track latest. `AGENTS.md` now documents the rule. Play command + 10% staged rollout plan documented in `docs/PLAY_STORE.md`.

**Mandatory before next upload:**
1. **Rotate the upload keystore password.** `app/android/local.properties` contains `upload-keystore.jks` password in plaintext and has never been fully removed from this machine. Rotate the keystore password and the key itself (or at minimum the password), re-encrypting `key.properties` — and tell any collaborator/consultant the old password is dead.
2. **Never raise versionCode without bumping both `version` and `versionCode`** — enforced via the AGENTS.md rule; keep it.

Play checklist still true: privacy URL `https://dropoff-api.godfreymoseskalambo.workers.dev/legal/privacy` responds 200 (checked today); production access reviewed; 10% staged rollout in Zambia.

---

## 13. Legal & compliance — 🟡

- Privacy policy **live 200** (checked today) at `/legal/privacy`; Terms at `/legal/terms` **404** — the in-app Terms reference a URL that does not exist. Add the Terms page (mirror privacy) before Play review; otherwise rejection risk on their periodic review.
- **Cover ≠ insurance** — `COVER_NOT_INSURANCE.md` exists and copy is enforced in-app (quoted protection), unverified against marketing pages (Play listing says "protection you can rely on" — is within the rules if the ToS is explicit; confirm with counsel).
- **Data retention**: delivery records kept for law (audit) but identity-stripped on account purge; 180-day ceiling on tracking tokens (good); camera-capture integrity events retained for fraud review. Deletion policy published ✅.
- **ZRA turnover tax**: turnover via D1 live ledger; Z-filing workflow designed for two signatures; no legal sign-off on the *voluntary 5% over K2,500* position — counsel must bless the filing before first submission.
- **Pack codes** are bearer instruments — no refund policy stated in app or web terms; add one (even "all sales final") to avoid chargebacks.

---

## 14. Security posture — 🟡

**Good.** PBKDF2-SHA256 100k for passwords; OTP/reminder codes hashed; JWTs HMAC-SHA256 with `token_version` revocation (password reset kills sessions); device sessions with device model in alerts; `/admin/*` uniformly gated on role/key (all 66 routes re-audited 2026-11-15, no longer just 7 fixed ones); endpoints that mint bearer tokens all rate-limited (fixed 2026-11-15); tracking token 180-day TTL; no `DROPOFF_API_KEY` in release builds; secrets gitignored (`key.properties`, `local.properties` both ignored; `upload-keystore.jks` never tracked). Stripe-grade X-Request-Id on failures for Workers Logs.

**Watch items.**
1. **Keystore password leak (see §12) — this is the single biggest standing risk on this machine.**
2. **WiFi-drop corruption class is gone** (cache purge discipline), but never edit in parallel with a build again — it produced a broken AAB last run; rebuilt clean as `72bb692`.
3. AI (HF) on the critical path of rider KYC — an attacker can spam selfie submissions to burn your HF quota (cost DoS). Add rate-limit by rider_id (not confirmed present — check before scale).
4. `X-Request-Id` exists on errors — but **no Sentry/crash reporter** in the app; production crashes are invisible unless the device reports back. See §16.

---

## 15. Data & privacy — ✅

**Good.** Sign-out/unlink purges: bookings cache, riders cache, ratings + analytics outboxes, biometric flag, GPS consent, locale, remember-me, plus `dropoff_acct_v1_<prev>_*` scoped sweep. User delete flows three ways: (1) self-service purge from Account (all verifies), (2) support `/chat/support` — staff can action soft-delete, (3) admin account deletion (this release) kills sessions + push tokens and keeps ledger history. Deleted bookings invisible to all roles; `admin_deleted` audit events retained. Payment and evidence files on R2 with prefix scoping; no external share links (in-app only).

**Feature flags in prod right now** (`app_settings`, migration 0061): `door_to_door_enabled=false`, `overage_discount_enabled=false`, and the debug-mode flags are correctly OFF. Verify once from `/admin/settings` after any deploy.

---

## 16. Monitoring & ops — 🔴

**What exists.** 6 crons (minute dispatch-retry/hold-expiry; 02:00 backup; 19:00 evening job; Sun 14:00; 1st 14:00; Mon 06:00 digest); Workers Logs (real-time); `analytics_events` table; `/health` (200 today); admin fraud queue; admin alerts.

**What is missing — this is your weakest area and it costs nothing to fix:**
1. **No crash reporting on the app.** Ship Flutter `flutter_error_reporting` (or add Sentry free tier) for the next release; right now, if 0.5.28 crashes on Android 8/10 phones, you learn from silence.
2. **No uptime monitor** pinging `/health` (UptimeRobot free, 5-minute interval, WhatsApp alerts to your phone).
3. **No synthetic probe** on the money path: a cron hitting a K1-free “sanity booking → auto-cancel at held” cycle would prove dispatch + hold + cancel together every day (cheap; K0).
4. **Backup restore is untested** — `0 2 * * *` runs; ask yourself *when was a backup last restored?* If never, test it once on a staging D1 (`wrangler d1 execute` a dump) before you need it.
5. Workers Logs retention is short on this plan; forward `5xx` counts to an email/push (admin SMS exists — write the tiny cron, or use Logpush if on the paid tier).

---

## 17. Unit economics — 🟡

Modelled in `UNIT_ECONOMICS_2026-11-15.md`: K45 PAYG trip → K41.80 net (K3.2 Lipila fee + K0.20 processing) → rider K10 take → platform K31.60 at 100% capture. Silver-1/day (K550/mo, 60 parcels) → K420 per 50 trips; Camel-Pro (K1,800, 240 parcels) → ~K1,300 margin if ≥70% redemption; payroll for 4 riders ~K12k vs K25k turnover → K13k headroom. At K25/trip platform and 1,000 trips/mo → K12.5k net before fixed costs.

**Why 🟡.** All model inputs (rider redemption %, Lipila's real fee schedule at your volume, actual delivery density per route) are *estimates*. Lipila invoice your first month; then re-derive. Do not put pack pricing in public channels before the first real-month actuals confirm margin. Pack codes for offline sales work — but they carry the same unit-risk profile.

---

## 18. Test coverage — 🔴

**What exists.** 6 tests / 2 files — `widget_test.dart` + `waybill_smoke_test.dart` (gold: fares never invented, couriers listed, booking round-trip). Worker: `vitest` (run it once to see its count; it exists but this audit never re-ran it).

**What is missing.** No booking E2E (mock Lipila → dispatch → settle → OTP delivered), no payment-held → cancel → refund golden path, no plan-cap enforcement test, no tracking-held-lock test. **Minimum for a production money app: 8 named golden tests** (money: prepay/dispatch/expire/refund; held booking invisible to tracking; rider OTP delivered gate; plan cap; courier search; plus the two existing files). Time-box: 1 dev-day with Playwright + mock Lipila, or use `package:integration_test` on one emulator.

---

## 19. Known recurring hazards (this machine & process)

1. **Editing during a build → shipped a corrupt artifact** (this release cycle). Discipline: commit → build → dist swap → verify → push, always; never edit mid-build.
2. **WiFi drops mid-transfer** (this session: `pub get` aborted twice; OTP probes timed out at 15 s but succeeded at 45 s). All network ops get ≥ 45 s timeouts and one retry; verify before believing failure.
3. **Play versionCode discipline** — bumped to 39 today after Play rejected 38; never again.
4. **Local cache purge hygiene** (npm/yarn/gcache) — keep the nightly purge (~9 GB reclaimed; C: has 12.7 GB free today).
5. **Sk planner memory** — `.scale_tmp/` is gitignored; keep it that way.
6. **GitHub push flakiness** — pushes occasionally hang silently; use `http.postBuffer=524288000` + verbose + retry (worked today).

---

## 20. Pre-launch checklist — owner actions, in order

| # | Action | Est. time | Unblocks |
|---|--------|-----------|----------|
| A | `npx wrangler secret put ORS_API_KEY` (free signup, openrouteservice.org) | 10 min | §9 → ✅ |
| B | `wrangler secret list` → confirm `FIREBASE_SERVICE_ACCOUNT` on production | 2 min | §11 |
| C | Real Lipila: K1 collect → dispatch → delivered → rider paid; one counter-fare repayment; one held-booking expiry | 30 min | §1, §11, §3 |
| D | Add `/legal/terms` (mirror of privacy page) — then re-check Play listing | 30 min | §13 |
| E | Uptime monitor on `/health`; Sentry (or `flutter_error_reporting`) in 0.5.29; alert cron for 5xx | 1 h | §16 |
| F | Rotate keystore password; tell any contractors the old one is dead | 15 min | §12/14 |
| G | 8 golden tests (see §18); gate `dist` upload on them | 1 dev-day | §18 |
| H | Counsel sign-off: cover ToS, ZRA 5% position, SMS STOP, Pack Codes refund | exp. same-week | §10/13 |
| I | Backup restore test against a staging D1 | 30 min | §16 |
| J | Test one full rider shift on a physical phone with 0.5.28 (GPS sharing → navigate → camera proof → OTP → settled) | 1 h | §2/5/6/9 |

**Until A, C, F, H are done, treat this build as "production-candidate, do not invite paying customers yet."** Engineering itself is launch-shaped; the remaining risks are operational and commercial, not architectural.

---

## Appendix — what this session verified end-to-end

| Check | Result | Evidence |
|-------|--------|----------|
| App analyze | 0 errors / 97 infos (pre-existing, style-only) | `flutter analyze` ×3 |
| App tests | 6/6 pass | `flutter test` ×3 |
| Worker typecheck | clean | `npm run typecheck` ✓ |
| Worker deploy | `c4261a43` live; `/maps/route` answers 503 (unkeyed) as designed | `npx wrangler deploy` ✓ |
| Live probes | `/health` 200 ✓ · `/plans` 200 ✓ · `/legal/privacy` 200 ✓ · `/version` / `/status` timed out (machine Wi-Fi flaky — re-probe from a stable connection) | curl-style GETs |
| `/maps/route` gate | not probed without an account JWT — verify after (A) with a real login token | manual |
| Dist hygiene | only 0.5.28 pair + unversioned aliases + web; 0.5.27 pair purged | `dist/` listing ✓ |
| Secrets in repo | no `.env`, keystores, or properties tracked; `key.properties` + `local.properties` gitignored | `git ls-files` ✓ |
| Release build key hygiene | only `DROPOFF_API_URL` injected; no `DROPOFF_API_KEY`/`DROPOFF_ADMIN_KEY` | `build_release.ps1:38` ✓ |
| Map production | routing path built but deliberately unkeyed; every rider still gets *a* directions line, labelled honestly | `map_services.dart` ✓ |

*This audit must be re-run as a single page after items A–J land; expect §1, §9, §11, §13, §16, §18 to flip to ✅.*
