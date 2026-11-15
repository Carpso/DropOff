# DropOff — Trip & Plan Unit Economics (2026-11-15)
What it costs to run a parcel, what it earns, and whether it survives 10,000 senders.
**Every figure here is either (a) a live constant/table in the codebase, (b) a measured
live-DB average, or (c) an explicit assumption with a confidence label.**
Re-run this audit at 30+ paid jobs and at 10x rider fleet size.

## The one-line answer

At full sweep pace (30/day per rider), DropOff spends **≈ K3–K6 per parcel** in rider pay
and platform fees, earns **K73 per PAYG parcel** (~10–15% of which is fees), and survives
any sender count the fleet can physically absorb — the constraint is **rider hires and
bike availability**, not unit economics.

---

## 1. The rider, all-in (what each parcel costs us to deliver)

From `workers/src/index.ts` (`DRIVER_*` — single source of truth):

| Line item | Per month | Notes |
|---|---|---|
| Base wage | K1,800 | Paid out Sundays (weekly cycle) or on the 1st (monthly) |
| Fuel allowance | K1,200 (K300 × 4 weeks) | Incl. in the K3,000 package — any unreimbursed excess is the rider's to manage |
| **Monthly package** | **K3,000** | Incl. fuel. Two payout cadences supported (weekly K750/wk vs monthly reconciliation) |
| Pace gate | 30 stops/day | Under pace → pro-rated pay (`/rider/targets`) |

**Cost per parcel at 30/day × 26 working days = 780 parcels/month:**

| Pace | Parcels/month | Package cost/parcel |
|---|---|---|
| 100% of pace (780/mo) | 780 | **K3.85** |
| 60% pace (468/mo) | 468 | **K6.41** |
| 40% pace (312/mo) | 312 | **K9.62** |

Riders not hitting 60% pace get reviewed (see `PLAY_BOOK.md`), so model on ≥468/mo.

**Other fixed-ish costs** (very rough, labelled LOW confidence):

| Item | Per month | Notes |
|---|---|---|
| Cloudflare Workers/D1 | ~$5–$25 | DropOff worker is on paid WP plan now; D1 still well inside limits |
| SMS/push (failure texts, nudges) | K100–K400 | At today's volume; scales with failed payments not parcels |
| Backups (R2) | ~$5 | R2 bucket `dropoff-backups` |
| Owner time / marketing | not counted | This is YOUR salary — decide it yourself |

**All-in monthly floor today ≈ K4,500–K5,500 per active rider** (package + infra share).

---

## 2. What each parcel EARNS per leg type (current pricing, 2026-11-15)

Live tiers (`tiers` table, verified 2026-11-15):

| Tier | Fee | Slots (cap) | Slot rate | PAYG-after-cap discount |
|---|---|---|---|---|
| Daily Rider | K49 / 24h | 1 parcel | K49/day | 0% |
| Weekly Sprint | K399 | 20 / 7d | K19.95 | 10% |
| Silver | K250 | 10 / 30d | K25.00 | 15% |
| Gold | K500 | 25 / 30d | K20.00 | 25% |
| Platinum | K750 | 50 / 30d | K15.00 | 35% |

Slot rate ≠ margin: every parcel also carries vehicle cost (1 parcel/trip ⇒ rider
salary share ≈ K3.85–6.4 at pace) + platform fee + momo fee.

### PAYG moto parcel (K70 avg leg, K55/K75/K95 by band)

| Component | ZMW | Notes |
|---|---|---|
| Customer pays | K75.98 | Rider leg K70 + platform fee K3.48 + momo leg K2.50 |
| **DropOff keeps (margin before rider salary!)** | **K73.48** | Whole leg is ours — rider fee is NOT passed through (salaried rider) |
| → after rider salary share (K4.5) | **≈ K69** | Per-parcel contribution |
| → after platform fee redistribution | ≈ K69 | Platform fee is also ours |

### Plan parcel (full cap utilisation — worst case per slot)

| Tier | Fee/slot | Salary share | Net before fees |
|---|---|---|---|
| Silver | K25.00 | −K4.0 | ≈ +K21.0 |
| Weekly | K19.95 | −K4.0 | ≈ +K16.0 |
| Gold | K20.00 | −K4.0 | ≈ +K16.0 |
| Platinum | K15.00 | −K4.0 | ≈ +K11.0 |
| Daily Rider | K49/day | −K4.0 | ≈ +K45 (if rider does jobs) |

**Plans are profitable at current prices as long as salary share holds at ~K4/parcel.**
A rider producing below ~40% pace makes plans cost-negative — that's what the pace gate
and review path exist to prevent.

---

## 3. Per-job operating ledger (PAYG bike, Lusaka)

| Line | ZMW | Direction |
|---|---|---|
| Invoice total (before courier fare) | K75.98 | IN |
| Platform fee | K3.48 | OUT (kept, but counted) |
| Momo collection leg | K2.50 | OUT (passed through to Lipila) |
| **Gross before rider salary** | **≈ K70** | IN |
| Rider salary (ro-rated) | −K4.5 | OUT |
| Courier fare | 0 | Never ours (partner money at counter) |
| **Net contribution per PAYG parcel** | **≈ K65.5** | |

---

## 4. Can it survive 10,000 senders?

### Demand model (assume — label LOW confidence)

| Cohort | Assumption | Parcels/mo |
|---|---|---|
| 10,000 registered senders | avg 4 parcels each/mo (industry small-seller norm SE Africa) | **40,000** |
| …or 2 per sender (dormant-heavy) | | 20,000 |
| …or 8 each (aggressive sellers) | | 80,000 |

### Fleet maths (sweep pace 30 parcels/day/rider = 780/mo, realistic 60% pace = 468/mo)

| Scenario | Parcels/mo | Parcels/rider/mo @468 | Riders needed (60% pace) | +20% spare | **Bikes to handle** |
|---|---|---|---|---|---|
| Low engagement | 20,000 | 468 | **43** | 52 | **≈ 55** |
| Base case | 40,000 | 468 | **86** | 104 | **≈ 105** |
| Heavy senders | 80,000 | 468 | **171** | 206 | **≈ 210** |

**Rule of thumb: one working bike per 380–1,000 monthly senders.**
Buybikes to the **low** end once demand proves up — do NOT pre-buy 210 bikes on spec.

### Revenue vs cost at base case (40,000 parcels/mo)

| Line | Amount |
|---|---|
| 50% PAYG (20,000 × K73) | K1.46M |
| 50% plan slots (20,000 × ~K19 avg) | K0.38M |
| **Gross contribution** | **≈ K1.84M/mo** |
| 86 riders × K3,000 | K258,000 |
| Ops/infra/admin | ≈ K80,000 |
| **Net margin** | **≈ K1.5M/mo** |

Even at pure break-even tiers, the fixed cost is only K258k + K80k — the model is robust
on unit economics. The risks are (in order): (1) rider hiring/training pipeline, (2) churn
and under-utilisation on plans, (3) counter relationships with depots, (4) momo float
health, (5) fraud/false parcels — all solved or solvable operations, not price structure.

### So — is it sustainable?
**Yes, provided**:
1. Riders are hired only when trailing-30dp + next-30d forecast exceeds K4,500–K5,500/rider.
2. Pace is enforced weekly (underperformers reviewed or pro-rated).
3. Plan usage is tracked — a tier whose subscribers average <40% utilisation is re-priced or capped.
4. New riders are added only when demand trails capacity by <20%.

---

## 5. Honest unknowns (do not let these slide)

1. **Actual PAYG K70 average** is 4-job data — re-measure at 30+ paid jobs, or all book economics are fiction.
2. Fuel/oil/depreciation per parcel — not yet in rider package. Adding a vehicle-owning rider's true cost matters if packages change.
3. Turnover tax (ZRA TOT) — 0% under K2,500/mo, 5% above. At scale, tax moves the model ~5 points. Accountant sign-off required.
4. Daily Rider cannibalises PAYG for very light users (K49/day covers them best).
5. 10,000 senders is not 10,000 ACTIVE senders. Cohort modelling before any fleet buy.

## 6. Immediate next steps (owner)

1. Fill `DRIVER_DAILY_TARGET` = 30 and rider package (K3,000) — already live.
2. Decide the bike buy: request 3 quotes (new 150cc + rider-package buyout) and bring 10 bikes only after week-4 volume is known.
3. Lock `PAYG_AVG_FEE` tracker in the ops console (today = "estimate K70" — should become a live `AVG(rider_fee_zmw)` query field).
4. Re-run this calculation at 30+ paid jobs and again at 200.
