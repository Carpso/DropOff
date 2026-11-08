# DropOff TODOs (tracked features)

Status: `done` / `server-done` / `scaffolded` / `planned` / `blocked-external`. Updated 2026-11-08.

## Hybrid parcel check (implemented)
- [done/server-done] **Hybrid parcel check** — `POST /jobs/:ref/parcel-check` now returns deterministic signals + LLM verdict + rules: `exact_fingerprint_match` (SHA-256 of each image), `booking/dropoff_fingerprint_sha256`, byte sizes, LLM descriptions/verdict (`@cf/meta/llama-3.2-11b-vision-instruct` + `llama-3.1-8b-instruct-fast`), `rules` (`needs_review`, `risk_score`, reasons incl. `partner_confirmed`/`otp_verified` context), `perceptual_hash: null` (pluggable). Mismatch still auto-flags `parcel_mismatch_ai`; `needs_review` items are queued for human review.
- [done/server-done] **Human review + training data loop** — `POST /jobs/:ref/parcel-review` (ops/admin, `confirm_match|confirm_mismatch|inconclusive`) stores review on the job and writes `parcel_check_feedback` (signals/decision) for eval/training. Migration `0049`.
- [planned] **True pHash/embedding upgrade** — add pixel decode (WASM) for pHash/dHash and/or an image/text-embedding similarity (Workers AI/Vectorize/external) alongside the LLM verdict; tune thresholds using `parcel_check_feedback`.

## 11 value-add features (status)
1. [server-done/app-planned] **Proof-of-condition chain / evidence locker** — `GET /jobs/:ref/evidence` returns an access-controlled, shareable timeline (booking/pickup/dropoff/handover photos, parcel check + review, partner_confirmed, OTP/POD/waybill, declared value/cover, events). **App:** “one tap share” + UI.
2. [scaffolded] **Declared value + micro-insurance/cover** — `0049` adds `declared_value_zmw`, `cover_opt_in/fee/status` (recorded/quoted). **Needed:** accept/store on booking flows, pricing rules, **commercial/legal underwriting/terms**, claims workflow, partner.
3. [scaffolded/server-partial] **No-show risk & smarter deposits** — strikes/auto-cancel/SMS warnings live; risk context used in hybrid rules. **Needed:** explicit booking risk score to tune deposits, in-app localized pre-cutoff warnings, ops clear/appeal.
4. [server-done/app-planned] **Density/slot optimization** — `GET /slots/suggest` returns least-loaded open slot + nudge (heuristic). **Needed:** app nudges, geo-aware density, dynamic incentives.
5. [scaffolded] **COD digitization & trust** — COD/remit events exist. **Needed:** sender/recipient receipts, faster reconcile UI, mismatch flags/alerts.
6. [planned] **Seller analytics** — **Needed:** no-show rate, on-time %, best slots, cost/parcel, repeat recipients, peaks, SME export (extend analytics endpoints/UI).
7. [server-done/app-planned] **Saved recipients/address book** — `GET/POST/DELETE /recipients` (migration `0049` `saved_recipients`). **Needed:** app UI + quick rebook with slot prefill.
8. [scaffolded] **Returns/reverse logistics** — `0049` adds `job_kind`/`return_job_ref`. **Needed:** booking flow support, routing/pricing, same evidence chain in UI.
9. [planned/external] **WhatsApp/SMS booking & status (localized)** — requires WhatsApp Business API/provider setup and inbound webhooks + templates. **Needed:** integration, opt-in, localized templates.
10. [scaffolded] **Referrals, loyalty, SLA guarantees** — referrals table/logic exists; SLA is partner-fed. **Needed:** “my referral code/stats” UX polish, reward rules, loyalty, partner SLA fields/feeds and guarantees.
11. [scaffolded/app-planned] **Full in-app localization & accessibility** — `PATCH /me` stores `locale_pref` (en/ny/bem/toi/loz/lun/kqn/lue); **SMS remain English-only until locale is used**. **Needed:** Flutter ARB/l10n for all screens, localized in-app warnings (skip/hold/cutoff), accessibility/voice notes.

## Anti-false-parcel / anti-ghost kit (done)
- [done] Seller parcel photo at booking; hybrid parcel-check compare/flag; depot `partner_confirmed` (POS webhook, `docs/POS_WEBHOOKS.md`).
- [done] Paygo first-time booking deposit (subscribers exempt) → wallet credit + dispatch; auto-cancel + strikes (3/14d → `booking_on_hold`); no untimed slots.
- [done] Tracking SMS-OTP verification; recipient handover OTP (door) + POD; OTP abuse strike. SMS **English-only** until user language pref is applied.

## Pay & ops
- [done] Rider pay K3,200/mo incl. K300/wk fuel (pace-gated). Versioned release script; Play docs. Fresh `dist/` APK/AAB (0.5.1+12).
- [blocked-external] Play Console upload; Lipila payout whitelist `260976847775`; physical-device verification.

## Training on “our own data” (Cloudflare)
- Collect: `parcel_check` signals + `parcel_check_feedback` (and export D1→R2). Optionally log via **AI Gateway**.
- Improve: **embeddings + Vectorize** for similarity/retrieval; evaluate against labeled feedback. True model fine-tuning on CF is limited to supported Workers AI models/workflows (evolving) — for custom vision (parcel re-ID) you’ll typically train externally and serve/compare via API, keeping data in R2. Not a general “train any model on a Worker”.