# DropOff economics — per parcel, per pack, per batch

All figures in Zambian Kwacha (ZMW ≈ K). Rider = person doing the pickup run. Pack = monthly subscription for repeat drop-offs. DropOff = platform revenue share.

## 1. Pay-as-you-go (paygo)

| Item | Amount | Who keeps |
|------|--------|-----------|
| Rider fee (customer) | K45 | rider: **K40.50** (90%), DropOff: **K4.50** (10%) |
| Platform processing fee on the DropOff leg (customer) | max(1% × leg, K3.00) + K0.48 → **min K3.48** | DropOff (on leg ≈ K45 → K3.48 wins) |
| Lipila mobile-money leg (customer) | K2.50 | Lipila (zero margin pass-through) |
| COD processing (cash at door) — platform cut | 2% of collected amount | DropOff |
| Waiting bill, K2/min after 10 min free, K50 cap | K0–K50 | DropOff (full) |
| Depot door delivery (placement city) | K30 + K3.48 min processing | DropOff (rider works door for the same job; no second split) |
| Wallet top-up (riders only) | 1% + K0.48, min K3.48 + K2.50 | DropOff collects on float |

**Not shared today:** no per-parcel commission to DropOff from the courier fare — the counter fare is the partner's (seller pays at depot), and DropOff doesn't touch partner money.

## 2. Packs (win-back/retention engine — the subscriber float pays for everything)

| Pack | Price / mo | Parcels/day | Sweep window | Rider earns* | DropOff floor/mo |
|------|-----------|------------|--------------|--------------|------------------|
| Silver | K350 | 1 | 6am / 10am / 2pm | K5 per swept parcel | ~K235 if 30 sweeps (~66% margin) |
| Gold | K700 | 3 | 6am / 10am / 2pm | K5 per swept parcel | ~K550 if 90 sweeps |
| Platinum | K1,500 | 10 | 6am / 10am / 2pm | K5 per swept parcel | ~K1,150 if 300 sweeps |

*Rider wage = K5 per pack parcel (direct operator cost). Pack members pay NO rider fee and NO per-parcel processing.

## 3. One engine, three margins (the sweep math)

A Lusaka sweep of 30 parcels across Silver + Gold + Platinum:

- Pack revenue: e.g. 10 Silver + 10 Gold + 10 Platinum → K3,500 + K7,000 + K15,000 = **K25,500/mo**
- Rider wages: 300 parcels × K5 = K1,500
- Route cost: fuel/time for 1 sweep ≈ K120–K180
- **Gross per month from packs alone ≈ K23,800**

## 4. Batch pickup — scattered points, one run

`GET /batch/pickup` applies a **snake latband sweep**: stops bucketed into ~1.3 km north–south bands, walked alternately east→west and west→east. Caps 25 stops/rider. Output:

- ordered stops per route, km from previous leg, cumulative km, ETA at 22 km/h + 4 min/stop
- expected ~12–18 km per 30-stop Lusaka ‑Kanyama pickup run (vs ~28–40 km zig-zagging)

Example: 32 stops across Kabulonga/Northmead/Kanyama/Chilenje → 2 routes: 22 stops ≈ 14 km ≈ 82 min, 10 stops ≈ 9 km ≈ 40 min.

## 5. Payout path (when there are riders other than the founder)

- Fixed part: K5/parcel (pack) or 90% (paygo)
- Float handling: COD collected is re-issued to the sender by **Lipila disbursement** minus our 2% — DropOff never holds seller money at rest
- Rider payouts: `/admin/payouts kind=rider_payout` (momo) or batch remit Fridays, ≤ K5,000/day cap

## 6. The honest bottom line

- Customers pay: rider fee + DropOff processing + Lipila momo + pack price
- Couriers keep 100% of counter fares
- Riders keep 90% paygo / K5 pack parcel
- DropOff keeps: 10% of rider fees + processing fees + COD 2% + waiting/wail fees − rider wages on packs − momo legs − rider disbursement fees (absorbed in 10%)
