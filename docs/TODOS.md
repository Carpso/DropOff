# DropOff TODOs (tracked features)

Status: `done` / `in-progress` / `planned` / `blocked-external`. Updated 2026-11-08.

## Anti-false-parcel / anti-ghost kit
- [done] **Seller parcel photo at booking** — `parcel_photo_url` captured at booking (`/jobs`, `/collections`); uploaded via `/uploads` (kind `kyc`). Migration `0048` + worker validation.
- [done] **AI parcel photo compare** — rider depot drop photo vs seller booking photo via `POST /jobs/:ref/parcel-check` (Llama vision describe + text compare); `parcel_mismatch_ai` auto-flags `fraud_flags`; rider app calls after depot drop.
- [done] **Depot counter confirmation** — `/webhooks/partner-status` sets `partner_confirmed=1`; POS webhook documented (`docs/POS_WEBHOOKS.md`).
- [done] **Prepaid booking deposit (pay-as-you-go, first-time only)** — zero-completed paygo senders must approve a small momo deposit (processing fee) before rider dispatch; **subscribers exempt**. Deposit settles to wallet credit (`wallet_ledger` kind `deposit`) then auto-assigns. Collections covered.
- [done] **Auto-cancel + strikes** — minute cron cancels stale assigned (3h, no pickup) and stale unassigned slotted (16h) bookings; records `booking_strikes` (`no_show_pickup`); **3 strikes in 14 days → `booking_on_hold` (403)**. OTP abuse at door handover records a strike.
- [done] **No untimed/unslotted parcels** — `pickup_window` required on every booking (`now`/`06:00`/`10:00`/`14:00`/`tomorrow:06:00`); server rejects missing slot.
- [done] **Tracking link lockdown** — bare `/track/:token` reveals no parcel data; `POST /track/:token/verify` now requires **SMS OTP** to mint a tracking grant (knowing the phone number is not proof). Signed-in sender/recipient and verified grants still work.
- [done] **Recipient handover OTP (last-mile)** — 4-digit code SMSed to recipient at booking; door delivery gated on OTP (`/jobs/:ref/events`), 8 wrong attempts → `otp_locked` + strike. POD photo columns.

## Pay & economics
- [done] **Rider pay revised** — K3,200/month inclusive of K300/week fuel allowance (base K2,000 + K1,200 fuel), performance/pace-gated; `/rider/targets` returns `pay` incl. pace shortfall.
- [done] **Lipila hardening** — narration sanitizer, secret-in-callbackUrl webhook verification, production base.

## Release & ops
- [done] **Versioned release artifacts** — `tools/build_release.ps1` derives names from `pubspec.yaml`; `flutter clean` before build.
- [done] **Play Store listing/docs** — `docs/PLAY_STORE.md` updated (0.5.1+12, `zm.dropoff.dropoff`, listing copy, steps).
- [in-progress] **Fresh APK/AAB rebuild** — rebuild all `dist/` artifacts after parcel-capture app changes.
- [blocked-external] **Play Console production upload** — user action (account credentials).
- [blocked-external] **Lipila payout whitelist** — add business disbursement number `260976847775` in Lipila merchant dashboard (user action).
- [blocked-external] **Physical-device verification** — biometric, device revoke, camera, verification gate, handover OTP, parcel-check flow (user testing).

## Follow-ups / backlog
- [planned] **Ops strike review/clear** — admin UI/API to view and clear `booking_strikes` (server enforces hold; ops override path).
- [planned] **Deposit UX in app** — surface `deposit_required`/prompt status in booking confirmation (server already gates dispatch).
- [planned] **Parcel photo required option** — make seller parcel photo mandatory for high-value/flagged categories (currently recommended).
- [planned] **Collections parity** — ensure `/collections` UI passes parcel photo and shows deposit state (API supports it).
- [planned] **Valuation/benchmark note** — keep a living benchmark in ops docs (competitor pay models; 5k-seller scenario).