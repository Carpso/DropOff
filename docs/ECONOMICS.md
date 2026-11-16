# DropOff economics — per parcel, per subscription plan

All figures in Zambian Kwacha (ZMW ≈ K). Rider = person doing the pickup run. Subscription plan = repeat-delivery allowance for a cycle (day/week/month). DropOff = platform revenue share. (The internal codename "pack" survives in older code/UI strings — it is the same product.)

## 1. Pay-as-you-go (paygo)

| Item | Amount | Who keeps |
|------|--------|-----------|
| Rider fee (customer) | K45 | rider: **K40.50** (90%), DropOff: **K4.50** (10%) |
| Platform processing fee on the DropOff leg (customer) | max(1% × leg, K3.00) + K0.48 → **min K3.48** | DropOff (on leg ≈ K45 → K3.48 wins) |
| Lipila mobile-money leg (customer) | K2.50 | Lipila (zero margin pass-through) |
| COD processing — REMOVED 2026-11-10 (owner directive: riders never carry recipient cash) | — | — |
| Waiting bill, K2/min after 10 min free, K50 cap | K0–K50 | Driver (full) |
| Depot door delivery (placement city) | Pay-as-you-go by recipient-city distance bands × vehicle multiplier (from K45) + processing | DropOff (rider works door for the same job; no second split) |
| Ride float top-up (riders only) | 1% + K0.48, min K3.48 + K2.50 | DropOff collects on float |

**Not shared today:** no per-parcel commission to DropOff from the courier fare — the counter fare is the partner's (seller pays at depot), and DropOff doesn't touch partner money.

## 2. Plans (the subscriber float pays for everything)

| Plan | Cycle | Parcels included | Windows (arrival range) | Rollover | After-cap overage |
|------|-------|------------------|-------------------------------|----------|-------------------|
| Weekly Sprint | 7 days | 20 | 06:00 / 10:00 / 14:00 | None | 10% off PAYG |
| Silver | 30 days | 10 | same windows | None — unused parcels expire | 15% off PAYG |
| Gold | 30 days | 25 | same windows | None | 25% off PAYG |
| Platinum | 30 days | 50 | same windows | None | 35% off PAYG |

Seed prices (2026-11 live): **Weekly Sprint K399, Silver K250, Gold K500, Platinum K750** — **the live chargebook in the `tiers` D1 table is the source of truth** (editable via `POST /admin/tiers` without a deploy; All four live packs edit this way too. Daily Dash (K69) and Daily Rider (K49) are retired — removed from `/plans` output; stale rows in `tiers` are never surfaced.

Cycle length is the plan's `cycle_days` (1 / 7 / 30) — `period_end` is always `period_start + cycle_days`, never a hardcoded +30. Every parcel counts as one slot per **parcel** (3 parcels in one trip = 3 slots). Cutoffs: book by 05:30 / 09:30 / 13:30 CAT; late bookings auto-roll to the next open window. Plan members pay NO rider fee and NO per-parcel processing inside the cap.

**One allowance, every normal delivery (2026-11-05+).** A plan's parcels are spendable on *any* in-app delivery the seller books — door pickup → courier depot, courier-depot collection → door, and the optional last-mile leg — not just pickups. Collections now apply the same inclusion logic and consume the same slots (`plan_inclusion` / `plan_used` / `plan_cap` are returned for both flows). Day-cycle plans (`parcels_per_day > 0`, e.g. Silver 1/day, Gold 3/day, Platinum 10/day) meter the cap per day instead of per month; the cycle window is `period_start..period_end` in both cases.

**Usage outlives the drop.** Unused parcels still expire with the cycle (no rollover), but the endpoints (`/jobs`, `/collections`, `/subscriptions`) all agree on `plan_used`/`plan_cap`, so what the app shows as "used" matches what the server enforces at booking time.

## 3. Sweep rider economics (salaried, performance-gated)

- **Rider pay: K3,200/month inclusive of a K300/week fuel allowance** (4 weeks = K1,200 fuel; base K2,000). Daily expectation: **30 parcels/day** per rider (ops monitoring target). Weekly fuel/pay is pace-gated to the sweep target (see `/rider/targets` `pay.adjusted` shortfall); consecutive off-pace weeks trigger an ops performance review.
- Break-even per rider (illustrative): 30 parcels/day × 30 days = ~900 parcels/month served.
  - At an average plan yield of K20/parcel (blended Silver K25 / Gold K20 / Platinum K15): ~K18,000 plan revenue vs K3,200 inclusive pay (fuel covered in allowance) → strong gross margin per rider/month when routes are dense.
- Paygo parcels on the same runs still pay riders their normal 90% share of the rider fee — the salary covers the committed sweep workload only.

## 4. Batch pickup — scattered points, one run

`GET /batch/pickup` applies a **snake latband sweep**: stops bucketed into ~1.3 km north–south bands, walked alternately east→west and west→east. Caps 25 stops/rider. Output:

- ordered stops per route, km from previous leg, cumulative km, ETA at 22 km/h + 4 min/stop
- expected ~12–18 km per 30-stop Lusaka ‑Kanyama pickup run (vs ~28–40 km zig-zagging)

Example: 32 stops across Kabulonga/Northmead/Kanyama/Chilenje → 2 routes: 22 stops ≈ 14 km ≈ 82 min, 10 stops ≈ 9 km ≈ 40 min.

## 5. Payout path (when there are riders other than the founder)

- Fixed part: K5/parcel (plan) or 90% (paygo)
- Float handling: COD is REMOVED — DropOff never handles recipient cash; parcels are prepaid at booking.
- Rider payouts: `/admin/payouts kind=rider_payout` (momo) or batch remit Fridays, ≤ K5,000/day cap

## 5b. Packs — retired (2026-11)

**Daily Rider (K49/day, 1 parcel) and Daily Dash (K69/day, 6 parcels, 24h) are no longer sold.** The live catalogue is pay-as-you-go plus four packs: Weekly Sprint K399 (20 parcels / 7 days), Silver K250 (10 / 30d), Gold K500 (25 / 30d), Platinum K750 (50 / 30d). Existing `rider_daily`/`daily` rows in `tiers` are excluded from `/plans` at the handler level, not by deleting rows. Server flags `overage_discount_enabled` / `door_to_door_enabled` stay OFF by default; extra parcels past a pack bill at full PAYG — nothing hidden, everything visible at confirm time.

## 6. The honest bottom line

- Customers pay: rider fee + DropOff processing + Lipila momo + plan price
- Couriers keep 100% of counter fares
- Riders keep 90% paygo / K5 plan parcel
- DropOff keeps: rider-fee legs + processing fees + waiting fees − payroll (salaried riders) − momo legs − rider disbursement fees
