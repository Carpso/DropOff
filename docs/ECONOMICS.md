# DropOff economics — per parcel, per subscription plan

All figures in Zambian Kwacha (ZMW ≈ K). Rider = person doing the pickup run. Subscription plan = repeat-delivery allowance for a cycle (day/week/month). DropOff = platform revenue share. (The internal codename "pack" survives in older code/UI strings — it is the same product.)

## 1. Pay-as-you-go (paygo)

| Item | Amount | Who keeps |
|------|--------|-----------|
| Rider fee (customer) | K45 | rider: **K40.50** (90%), DropOff: **K4.50** (10%) |
| Platform processing fee on the DropOff leg (customer) | max(1% × leg, K3.00) + K0.48 → **min K3.48** | DropOff (on leg ≈ K45 → K3.48 wins) |
| Lipila mobile-money leg (customer) | K2.50 | Lipila (zero margin pass-through) |
| COD processing (cash at door) — platform cut | 2% of collected amount | DropOff |
| Waiting bill, K2/min after 10 min free, K50 cap | K0–K50 | Driver (full) |
| Depot door delivery (placement city) | Pay-as-you-go by recipient-city distance bands × vehicle multiplier (from K45) + processing | DropOff (rider works door for the same job; no second split) |
| Wallet top-up (riders only) | 1% + K0.48, min K3.48 + K2.50 | DropOff collects on float |

**Not shared today:** no per-parcel commission to DropOff from the courier fare — the counter fare is the partner's (seller pays at depot), and DropOff doesn't touch partner money.

## 2. Plans (the subscriber float pays for everything)

| Plan | Cycle | Parcels included | Windows (arrival range) | Rollover | After-cap overage |
|------|-------|------------------|-------------------------------|----------|-------------------|
| Daily Rider | 1 day — TODAY only | 2 / day | on-demand ('now' + 06:00/10:00/14:00) | None — expires tonight | 45% off PAYG |
| Weekly Sprint | 7 days | 20 | 06:00 / 10:00 / 14:00 | None | 10% off PAYG |
| Silver | 30 days | 10 | same windows | None — unused parcels expire | 15% off PAYG |
| Gold | 30 days | 25 | same windows | None | 25% off PAYG |
| Platinum | 30 days | 50 | same windows | None | 35% off PAYG |

Seed prices: **Daily Rider K49, Weekly Sprint K399, Silver K250, Gold K500, Platinum K750** — **the live chargebook in the `tiers` D1 table is the source of truth** (editable via `POST /admin/tiers` without a deploy; Daily Rider itself can be re-priced the same way). The old "Daily Dash" product (K69) was discontinued and is deliberately never surfaced even if a stale row lingers; "rider_daily" is its leaner replacement.

Cycle length is the plan's `cycle_days` (1 / 7 / 30) — `period_end` is always `period_start + cycle_days`, never a hardcoded +30. Every parcel counts as one slot per **parcel** (3 parcels in one trip = 3 slots). Cutoffs: book by 05:30 / 09:30 / 13:30 CAT; late bookings auto-roll to the next open window. Plan members pay NO rider fee and NO per-parcel processing inside the cap.

**One allowance, every normal delivery (2026-11-05+).** A plan's parcels are spendable on *any* in-app delivery the seller books — door pickup → courier depot, courier-depot collection → door, and the optional last-mile leg — not just pickups. Collections now apply the same inclusion logic and consume the same slots (`plan_inclusion` / `plan_used` / `plan_cap` are returned for both flows). Daily-cap plans (`parcels_per_day > 0`, i.e. Daily Rider) meter the cap per day instead of per month; the cycle window is `period_start..period_end` in both cases.

**Usage outlives the drop.** Unused parcels still expire with the cycle (no rollover), but the endpoints (`/jobs`, `/collections`, `/subscriptions`) all agree on `plan_used`/`plan_cap`, so what the app shows as "used" matches what the server enforces at booking time.

## 3. Sweep driver economics (salaried, not per-parcel)

- **Driver pay: K3,000/month flat, per driver.** Daily expectation: **30 parcels/day** per driver (ops monitoring target, not a wage unit).
- Break-even per driver: 30 parcels/day × 30 days = ~900 parcels/month served.
  - At an average plan yield of K20/parcel (blended Silver K25 / Gold K20 / Platinum K15): ~K18,000 plan revenue vs K3,000 wage + ~K1,500 route cost (fuel/time per sweep) → **~K13,500 gross margin per driver/month**.
- Paygo parcels on the same runs still pay riders their normal 90% share of the rider fee — the salary covers the committed sweep workload only.

## 4. Batch pickup — scattered points, one run

`GET /batch/pickup` applies a **snake latband sweep**: stops bucketed into ~1.3 km north–south bands, walked alternately east→west and west→east. Caps 25 stops/rider. Output:

- ordered stops per route, km from previous leg, cumulative km, ETA at 22 km/h + 4 min/stop
- expected ~12–18 km per 30-stop Lusaka ‑Kanyama pickup run (vs ~28–40 km zig-zagging)

Example: 32 stops across Kabulonga/Northmead/Kanyama/Chilenje → 2 routes: 22 stops ≈ 14 km ≈ 82 min, 10 stops ≈ 9 km ≈ 40 min.

## 5. Payout path (when there are riders other than the founder)

- Fixed part: K5/parcel (plan) or 90% (paygo)
- Float handling: COD collected is re-issued to the sender by **Lipila disbursement** minus our 2% — DropOff never holds seller money at rest
- Rider payouts: `/admin/payouts kind=rider_payout` (momo) or batch remit Fridays, ≤ K5,000/day cap

## 5b. Daily Rider (K49/day, 2 parcels)

On-demand "Yango-style" usage, priced for impulse buys, not subscriptions:

- **Price K49/day**, activates on payment (no approval window), 24h validity.
- **2 parcels/day** included; rider fee and processing K0 inside the allowance (same guarantee as monthly plans).
- **Overage 45% off PAYG** — a K45 trip costs K24.75 once the day's 2 slots are gone.
- **Economics:** at 1 parcel/day average usage, effective cost ≈ K24.50/parcel — still above the Platinum K15/parcel, deliberately: the ladder's job is to push regular shippers *up* (Daily → Weekly at 4+ parcels/week → Silver+ at 10+/mo), and Daily's job is to convert pure-PAYG occasionals into plan-payers. Days used < 2 parcels are pure margin; the risk of abuse is capped by the 2-parcel/day meter.
- **Placement in the app:** Account → Subscribe; shown next to the plan ladder; never replaces Weekly Sprint as the default upsell. `POST /admin/tiers` can re-price/re-cap it live without a deploy.
- **Frontend nudge:** Business → DropOff Predict surfaces it as `daily_option` when a seller ships in bursts (`forecast/2` days needed ≤ 30).

## 6. The honest bottom line

- Customers pay: rider fee + DropOff processing + Lipila momo + plan price
- Couriers keep 100% of counter fares
- Riders keep 90% paygo / K5 plan parcel
- DropOff keeps: 10% of rider fees + processing fees + COD 2% + waiting/wail fees − rider wages on plans − momo legs − rider disbursement fees (absorbed in 10%)
