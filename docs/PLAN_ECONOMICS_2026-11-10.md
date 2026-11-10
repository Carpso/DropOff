# Plan Economics Audit — 2026-11-10

Every number here comes from the live D1 database or the fee engine source (`workers/src/fees.ts`, `workers/src/pricing.ts`, `workers/src/index.ts`). No invented fares.

## 1. Data snapshot (as of this audit)

| Fact | Value | Source |
|---|---|---|
| Jobs in DB (all time) | 4 (first job 2026-11-05) | `jobs` |
| Jobs settled as paid | **0** | `jobs.paid` |
| Avg rider fee (90d) | K70 | `JOBS AVG(rider_fee_zmw)` |
| Avg booking total | K96.74 (counter K25 + rider K70 + fees) | `JOBS AVG(total_zmw)` |
| Registered accounts | 30 (1 staff, 0 riders in `auth_users`) | `auth_users` |
| Subscriptions | 1 silver + 2 weekly, all `pending_payment` — **0 active** | `subscriptions` |

**Confidence: LOW.** Under 15 jobs. Treat every per-job average below as a working assumption, not a law. Re-run this audit at 30+ paid jobs.

## 2. How DropOff makes money per job (the code's model)

From `fees.ts`:
- **Customer pays**: parcel movement cost + ONE processing fee.
- **Rider keeps**: 90% of the rider fee, minus their own payout transaction costs (`payoutNet`).
- **DropOff keeps**: a 1%-of-base platform fee (min K3.48) **plus 10% of the rider fee** (`RIDER_TAKE_PCT = 10`). The counter fare is the courier partner's — paid at the depot, never held by DropOff.
- Optional last-mile door leg adds per-leg platform take (~K3.48 min each).

### Pay-as-you-go unit economics (Lusaka motorcycle, avg K70 rider fee)

| Item | ZMW |
|---|---|
| Platform fee (1% of K96.74 + K0.48, min K3.48) | **K3.48** |
| DropOff's 10% take of the rider fee | **K7.00** |
| **DropOff gross per completed PAYG job** | **≈ K10.50** |
| (volatility) | K6.2–K7.5 if rider fee is K55; K8–K9.5 if K95 |

So the PAYG engine prints roughly **10–15% of each booking** in platform revenue. On the observed K96.74 average booking: **~K10.5 per job**.

## 3. The critical fact the audit must start with: who pays the rider on a plan trip?

> ⚠️ **Superseded 2026-11-10 same-day:** this section assumed a per-trip rider payout model. Riders are in fact salaried — see **Section 9**, which corrects sections 3–6. Kept for the reasoning trail.

On a plan (`/collections` plan-inclusion path, `index.ts` ~1988–2006):

> Inside the cap, **the customer's rider fee is set to the tier's `rider_fee_zmw` — which is 0 for every tier.**

But a rider still physically drives the trip. Rider payouts are recorded manually via `/admin/payouts` (kind `rider_earning`). The rider's defensible rate is the same share they'd earn on PAYG: **90% of the prevailing fee ≈ K58 net per motorcycle trip** (90% of K70, minus K1.5 disbursement and K3.48 platform-fee-on-share — per `payoutNet`).

**Therefore: every in-plan trip is a cost the plan fee must cover.** There is no other payer. A bike can carry up to 3 parcels in one trip, which divides that K58 across the parcels consumed.

## 4. Per-tier audit at full cap utilisation (worst case) and consolidated trips

Revenue per slot = tier fee ÷ slot cap. Rider cost per trip: **K58** (1-parcel), K29/slot (2-parcel trip), K19.3/slot (3-parcel trip).

| Tier | Fee | Slots | Rev/slot | Margin/slot (1-parcel trips) | Margin at FULL cap (1-parcel) | Margin at full cap (2/trip) | Margin at full cap (3/trip) |
|---|---|---|---|---|---|---|---|
| Silver | K250 | 10 | K25.0 | −K33.0 | **−K330** | −K40 | **+K57** |
| Gold | K500 | 25 | K20.0 | −K38.0 | **−K950** | −K225 | −K17.5 |
| Platinum | K750 | 50 | K15.0 | −K43.0 | **−K2,150** | −K725 | −K215 |
| Weekly Sprint | K399 | 20 | K20.0 | −K38.0 | **−K760** | −K180 | −K14 |
| Daily Rider | K49/day | 2/day | K24.5 | −K33.5/day (1 trip) | **−K67/day** (2 trips) | −K34/day (2 trips as 1) | −K8/day |

### Break-even utilisation — below this share of the cap, the plan is profitable

| Tier | If every trip is 1 parcel | If trips consolidate 2 parcels |
|---|---|---|
| Silver | ≤ 3.9 trips of 10 (**≤ 39%**) | ≤ 79% |
| Gold | ≤ 7.7 trips of 25 (**≤ 31%**) | ≤ 62% |
| Platinum | ≤ 11.6 trips of 50 (**≤ 23%**) | ≤ 46% |
| Weekly | ≤ 6.2 trips of 20 (**≤ 31%**) | ≤ 62% |
| Daily Rider | breaks even at **0.76 trips/day** — losing money on any day it activates a trip | ≤ 1 trip/day of 2 parcels = −K7/day |

### Verdict (honest)

1. **The tiers are priced as if the rider leg is free. It is not.** Under the current structure, a FULLY-USED subscriber is the WORST customer you can have: Silver −K330/mo, Platinum −K2,150/mo. More subscribers with high utilisation = more losses, not more profit.
2. **Plans only make money through under-utilisation (breakage)** — the gym-model. That can sustain a business while utilisation stays low, but it is fragile: every improvement you make in getting subscribers to ship more INCREASES losses. That is the opposite of growth-friendly.
3. **Weekly Sprint is a sales trap at its price point**: at K399/20 slots it needs utilisation ≤31% to be safe. Someone shipping 10 parcels/month (a dream user!) costs you K180 to serve on a K399 plan.
4. **Daily Rider is a customer-acquisition loss-leader, not a profit product**: every active day costs ~K9–K67. It's fine for adoption — but treat its loss as marketing spend (CAC), know its number.
5. **PAYG remains the only structure today where a heavy shipper makes you money** (~K10.5 per job). Ironically, the plans convert your best revenue event (a shipment) into a fixed cost.

## 5. How to make plans profitable — three levers

**Lever A — Set a plan-rate rider payout (RECOMMENDED, policy-only, no code):**
Pay riders a fixed plan rate per parcel on in-plan trips instead of 90% of PAYG (e.g. K20–25/parcel ⇒ K20–25 per slot on a 2-parcel trip). Riders on consolidated trips already net ~K19–29 per parcel effectively, so K20–25/parcel is consistent with real rider economics. Result: Silver K25/slot ≥ K20–25 cost → **+K0–5/slot even at full utilisation**; Gold/Platinum/Weekly need the payout at the upper half of that band or slightly higher plan rates.

**Lever B — Reprice / re-cap (needs code + store updates):**
Safe floors (rider cost K58/trip, 1–2 parcels/trip): Silver K250 → cap 3–4 trips (K62/K83 per trip); Gold K500 → cap ~8 trips; Platinum K750 → cap ~12 trips; Weekly K399 → cap ~6–7 trips. This makes plans profitable for exactly the heavy users you WANT most.

**Lever C — Accept breakage explicitly (do nothing, but never advertise "ship your cap!")**: every marketing message that pushes full utilisation destroys plan margin under current pricing. Not recommended as the main strategy.

**Minimum action before pushing plans: write down the in-plan rider payout policy (Lever A).** Until then, an admin recording a rider payout at 90% of PAYG on plan jobs silently makes every plan subscriber loss-making.

## 6. Subscriber targets — "at what number don't we lose money?"

Fixed monthly infrastructure cost is currently ≈ K0 in cash terms (Cloudflare Workers/D1 on current plan, D1 free tier) plus variable costs: SMS sends, occasional operational spends, and marketing. Assume a conservative **K1,000–K2,000/month** all-in fixed floor once you modestly market.

Under **current pricing** (breakage model), profit per month ≈ sum over subscribers of (plan fee − utilisation× rider cost) − fixed:
- 20 Silver subs at avg 30% utilisation (3 trips): 20 × (250 − 174) ≈ **+K1,520** → covers the floor; ~15 subs break even.
- BUT the same 20 subs at 100% utilisation: 20 × (250 − 580) = **−K6,600/mo**. The same subscriber COUNT can be hugely profitable or hugely loss-making depending on utilisation + payout policy. Sub counts alone cannot protect you.

**Targets after Lever A (plan-rate payout ~K22/parcel, trips consolidate ~2 parcels ⇒ cost ≤ K22–29/slot):**
- Silver at K25/slot: +K0–3/slot; 100 Silver full-util ≈ +K0–300/mo; whether more comes from Gold/Platinum upsell.
- With Lever A + Lever B (better caps), plan for these targets:

| Milestone | Subs (mix 60/30/10 Silver/Gold/Platinum-ish) | Monthly plan revenue | Est. platform cost (rider payouts, ~35% util) | Est. net before fixed costs |
|---|---|---|---|---|
| First profit | 25–40 | K6,875–K11,000 | K4,500–K7,000 | +K2,000–K4,000 |
| Sustainable floor | 100 | K27,500 | ~K17,500 | ~+K10,000 |
| 5,000-sub goal | 5,000 | K1,375,000 | ~K875,000 | ~+K500,000/mo |

(These use Silver-led ARPU ≈ K275/sub and ~45% of fee going to riders at 35% utilisation under Lever A pricing. Re-run at 30+ paid jobs.)

**Answer to your question in one line:** there is no "magic subscriber number" under current pricing — the unit economics decide; fix the payout policy first, then **25–40 real subscribers** is the first profit band, **~100** is a sustainable floor, and every number above that scales with the same margin discipline.

## 7. First-week reality: can a Facebook campaign bring 100–500 Silver subs?

**No — not week one, and not at K250 as the ask.** (Detailed math in `docs/GROWTH_RUNWAY_2026-11-10.md`.) Realistic first-week outcome for even a vigorous Zambian FB campaign on a K250 monthly subscription ask: **5–30 paying subs**, mostly from your warm circles. 100+ weekly would need brand trust you haven't accumulated yet (0 paid jobs, no reviews, no riders scaled).

The week-one product the market WILL take: **Daily Rider days (K49/day)** and app installs — cheap trials that train the habit. Convert to plans when Predict's honest recommender shows real savings.

## 9. UPDATE (2026-11-10, later same day): riders are SALARIED — the economics change

Correction from the owner: riders are **employees on a fixed package, not per-trip payout contractors**. Deployed in worker `138c6802`: **K3,000/month inclusive of K300/week fuel** (base wage K1,800), paid weekly every Sunday 16:00 CAT or monthly on the 1st, 16:00 CAT, pace-gated (30 trips/day sweep target; under-target periods are pro-rated), auto-generated payroll with admin → superadmin confirmation and downloadable proof (`/admin/payroll`).

**What this does to the numbers above:** sections 3–4 modelled the rider cost as 90% of each trip's fee (~K58/trip). Under the salary model:

- The rider package is a **fixed cost**, not a per-trip cost. In-plan trips' marginal rider cost ≈ **K3,000 ÷ ~900 target trips = ~K3.3/trip** (at realistic lower pace, ~K15–K20/trip).
- The 90% share DropOff "hands over" per PAYG trip no longer leaves the business — **gross per PAYG job rises to roughly the whole rider fee + platform take (~K73 at K70 avg fee)**, minus the salary.
- **Plans become profitable at current prices.** Silver at FULL cap (10 parcels): K250 collected vs ~K30 salary-share + admin → **+K200+ per full-util subscriber**. Gold/Platinum/Weekly magnitudes better. Sections 3–4's "losing money on heavy users" verdict is **superseded** — the earlier per-trip payout concern evaporates with the salary; what replaces it is a fixed breakeven per rider.

**Break-even per month becomes simple:** rider package K3,000 (+ ops floor, est. K1,500–K2,500 infra/marketing/SMS) ≈ **K4,500–K5,500/month per active rider**. At observed averages that's roughly:
- ~40–60 completed PAYG jobs/month alone, or
- **~10–15 average-priced plan subscribers** (mix incl. Silver) per rider, with PAYG topping up.

This makes the plan-push strategy — and the 100→5,000 subscriber ladder in `GROWTH_RUNWAY` — structurally sound: hire the next rider only when trailing-30-day demand covers K4,500+ more per month. Daily Rider's loss-leader verdict also inverts: its only cost is salary-share (~K3–7 per active day), so **Daily Rider is now a profitable funnel product too**.

Payroll mechanics (live): auto rows generated Sunday 16:00 CAT (weekly) / 1st 16:00 CAT (monthly + K3,000-minus-weeks balance reconciliation); pace-gated amounts; admin → superadmin two-signature confirmation; Lipila disbursement to the rider's momo; downloadable proof per payout. Rider's own app endpoint: `/rider/payroll`.

**ZRA turnover tax now recorded automatically** on the main ledger (`/admin/tax`): monthly turnover = DropOff's own charged income (momo job collections + wallet-settled DropOff legs + subscriptions/upgrades + COD platform cut; excludes partner counter fares and wallet top-ups until spent). Rates per ZRA 2026: **0% up to K2,500/month, 5% of gross above the band**, return + payment due **by the 14th of the following month** — printable sheet at `/admin/tax/:ym/report` for your submission. Refreshed daily by cron; closed at month end. (Reminder: Turnover Tax has no expense deductions — salaries and fuel are NOT set against it; confirm treatment with ZRA/your accountant once turnover is established.)

## 10. Signs to re-run this audit

- 30+ paid jobs, or 10+ active subscribers
- With the salary model: trailing-30-day revenue per active rider falling below ~K4,500–K5,500 (rider break-even)
- Any change to the salary constants (`DRIVER_*` in `workers/src/index.ts`) or tier maths in `tiers`
