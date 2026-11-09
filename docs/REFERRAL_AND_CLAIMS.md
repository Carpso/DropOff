# Referral & claim flow — how it works (internal)

> Draft. Not legal advice.

## Models
- **Referral codes** (`auth_users.referral_code`, e.g. `DRP-XXXXX`) — every signed-up user gets a code.
- **Referral records** (`referrals` table) — unique (`referred_phone`), track lifecycle from `pending` → `rewarded`.
- **Claim** (`POST /refer/claim`) — referee can claim a referral; coupon applied at first eligible booking.
- **Reward unlock** — only after the referred seller delivers their first DropOff job.
- **Deposit waive** — referred first-time pay-as-you-go bookers skip the `booking_deposit` ghost-booking gate.

## Limits
- One referral per referred phone; no self-refer.
- Reward discounts apply only to the DropOff leg (`riderFee + last-mile processing`).
- Pack-code freebies are one-time use; referral rewards are single-use.
- Inactive referrers get nothing; referred link token expires 180 days.

## What can break / score wrong
- `referrals.status` `pending` on a referred user means the referral was never confirmed — no reward, no deposit waive flag checked by server at booking time.
- If the referral is for a *payg* booking but redeems with a pack code, the code consumes as `pack`; referral can still be pending at that point.
- Referral code is accepted at account creation, not at booking time. It cannot be applied to an already-active booking.

## What must be written
- Terms section: “Refer a friend — one reward per unique recipient, max one per DropOff-day for your own use.”
- Clear expiry (e.g. 6 months).
- No cash out.

## Recommended next steps
- Finish the “claim” flow end-to-end: friend gets claim link → applies at first booking → watch referrals move to `rewarded`.
- Track claim rate in admin KPI (`action=claim_referral`) and reward rate.
- Consider removing the deposit waiver once claim rate is stable; keep it simple for PAYG.
