# DropOff — Exit-readiness audit (internal draft)

> Draft prepared from the codebase and product docs. Not legal, financial or investment advice. Review with counsel and an accountant before any sale, fundraising or partner term sheet.

## What “exit-ready” means here
A buyer (courier partner, investor or acquirer) will ask for:
- Product that works without the founder
- Clean books
- Retained sellers/couriers
- Legal posture that can survive due diligence
- A repeatable partner confirmation path

## Product / depot workflow
**Goal:** rider pickup → depot counter → stamp → confirmation, without requiring the courier to run your app.
- **Proof for the counter:** the waybill screen in the app (`WaybillScreen`) shows ref, route, recipient, parcel size, declared value, fee split and tracking token. It can be shared as an image and printed/shown at the counter.
- **Partner-confirm parity:** `POST /webhooks/partner-status` accepts `X-Partner-Key`, `ref` or `waybill`, sets `partner_confirmed=1`, and closes the job. Use this even if the depot has no POS. If they need to confirm without the app, use the partner smart console at `/partner/console` (token-gated, web only).
- **Low-tech counters:** if a depot cannot use a smartphone or POS, accept a photo of the stamped waybill as POD evidence (`POST /jobs/:ref/pod-photo`); rely on admin review at first.

## Activation & retention (what buyers will test)
- **Activation claim:** `bookings created → delivered`. Track via `analytics_events` (`feature=booking/delivered jobs`) and admin KPI (`top_screens`, `funnel`, `DAU`).
- **Retention claim:** users who complete ≥3 deliveries in 60 days. Track cohorts by `sender_phone` and `delivered` jobs.
- **Referral claim rate:** `referrals.status` pending → rewarded. Reward unlocks only after a referred first delivery.

## Books (revenue split DropOff vs partner)
- DropOff leg revenue = rider fee + last-mile processing fee only (`platform_fee_zmw`, `lipila_fee_zmw`, `amount_zmw`).
- Partner leg revenue = counter fare, paid at depot (`counter_price_zmw`), never collected by DropOff.
- Deposits (`booking_deposit`), disbursements (`platform_disbursements`), payouts and settlement must reconcile to the phone number/merchant.
- `payment_refunds` noted in code; export monthly statement.

## Legal / cover posture
- **Quoted protection only — NOT insurance**. Cover exists as a quoted product; no paying claims unless insurance is contracted.
- Referral/coupon T&Cs must be written clearly (unique use, expiry, earliest expiry wins).
- Privacy/terms updated (`/legal/privacy`, `assets/legal/terms.md`, `assets/legal/privacy.md`).
- Do not market the app as “insured”, “verified”, “guaranteed” or “partner-approved” until signed by each courier.

## Checklist before first call with courier / investor
- [ ] 3-month retention by cohort (≥30% of first-time PAYG bookers deliver again within 60 days)
- [ ] 30-day GMV and take-rate (DropOff vs partner)
- [ ] Partner-confirmed ratio (jobs with `partner_confirmed=1` / total delivered)
- [ ] Deposits vs lost deposits; unpaid balances
- [ ] 1 courier MoU (even weak) — confirms, settlement, dispute resolution
- [ ] Cover legal opinion (not-insurance disclaimers)
- [ ] Clean rights to the brand (trademark search, ASIC domain, app store)
