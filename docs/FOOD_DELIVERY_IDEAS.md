# DropOff — Food Delivery Exploration (IDEAS ONLY — no code committed)

> Owner directive: food service is a **separate product line from parcel sweeps**.
> Nothing here touches the parcel booking engine, sweep windows (06:00 / 10:00 / 14:00),
> or rider salary payroll until a separate decision is made. This document is a
> brainstorm for evaluation only.

---

## 1. Why food is NOT parcels

| | Parcels (existing) | Food (proposed) |
|---|---|---|
| Product | Sender → depot → destination (first mile) | Kitchen → eater's door (full journey) |
| Clock | Sweep windows, batched | Minutes, one order at a time |
| Money | Prepaid momo at booking; counter fare at depot | Prepaid at order (incl. food price) |
| Failure mode | Rebooking / return leg | Refund / waste — food is perishable |
| Partners | Courier depots | Restaurants / cookhouses |
| Rider role | Depot runs, salaried sweeps | On-demand restaurant runs |

Food cannot ride the parcel sweeps: a 10:00 sweep that collects 6 parcels across
Lusaka cannot deliver a hot plate of nshima in 30 minutes. It needs its own
dispatch brain, its own clock, and its own money flow.

---

## 2. Core concept options

### Option A — "DropOff Eats" as a separate order type (recommended start)
- New `orders` table (food), separate from `jobs`. Order = vendor + items + eater
  + address + prepaid amount.
- **Separate dispatch pool**: food-ready riders (bikes with carrier boxes) work
  on-demand food shifts, independent of parcel sweeps.
- **Separate app section**: a "Food" tab with its own vendor list — never mixed
  into the Booking flow.
- Pros: clean data, clean accounting, parcel KPIs stay pure.
- Cons: two dispatch systems to run.

### Option B — Vendor-managed (DropOff as the payment + rider layer)
- Restaurants keep their own WhatsApp/phone orders; DropOff only does
  **payment + delivery**: the vendor "requests a rider" for a prepaid order.
- Lightest build: no menu system, no cart, no vendor portal beyond a simple
  order hand-off screen.
- Pros: fast to pilot with 5–10 restaurants in Lusaka; DropOff never touches
  food quality or order errors (vendor owns them).
- Cons: weaker product feel; commission per delivery only.

### Option C — Full marketplace (later stage)
- Menus, cart, promos, ratings, vendor dashboards — the Bolt Food shape.
- Only worth it after A or B proves order density.

**Recommendation: pilot Option B (rider-on-request), graduate to A.**

---

## 3. Money flow (same compliance DNA as parcels)

1. **Everything prepaid** — eater pays momo at order: food price + DropOff
   delivery fee + processing fee. No cash to riders, ever (same rule as parcels).
2. **Vendor settlement**: DropOff holds the food-price portion and disburses to
   the vendor on a daily/weekly sweep (existing Lipila disbursement machinery),
   minus commission. The delivery fee portion stays with DropOff.
3. **Rider economics**: food riders are the same salaried team working a
   **separate food shift**, OR paid per successful food drop from a separate
   pool — never mixing parcel payroll with food payouts in one ledger.
4. Refunds: if the vendor can't fulfil, refund goes back to the eater's momo
   automatically (same unspent-prepayment return rule as parcel cancellations).

---

## 4. Dispatch design (separate from sweeps)

- **Food shift model**: riders opt into a "Food shift" (e.g. 10:30–13:30 lunch,
  16:30–20:00 dinner) in the Team tab. On-shift food riders appear on the food
  map; parcel sweeps never pull them unless they also hold a parcel slot.
- **Batching by zone, not by time**: assign the nearest on-shift rider; allow
  max 2 simultaneous orders per rider (hot food + short hops).
- **Vendor ready-check**: vendor marks the order "ready" → only then is the
  rider dispatched to collect (prevents riders idling at kitchens).
- **Timers with teeth**: SLA countdowns (vendor prep, rider to vendor, rider to
  eater); a breach triggers an ops alert, not a silent miss.

---

## 5. Vendor onboarding (Lusaka first)

- Start with **10 anchor vendors** near existing DropOff density: take-aways
  around Mass Media, Kabulonga, Longacres, town (Congo-Crossline area).
- Vendor needs: smartphone, momo number for settlement, a "ready" button.
  No POS integration for the pilot — orders arrive as notifications + SMS backup.
- Menu handling in pilot: vendor sends a photo/price list; eater orders via a
  simple item picker or a "Order this combo" link. Full menus only in Option C.
- Vendor agreement mirrors the depot counter model: **DropOff never quotes their
  food prices** — the vendor sets prices, DropOff only publishes them.

---

## 6. Trust, safety and food-specific risks

- **Sealed-bag policy**: vendor seals the order; rider photographs the sealed
  bag at collection (reuse the parcel photo-check idea) — protects against
  tampering claims.
- **Handover OTP**: reuse the existing recipient-code flow for the eater.
- **Allergen disclaimer**: vendor-provided descriptions only; DropOff never
  asserts ingredients (liability stays with the vendor).
- **Cold/late compensation rule**: defined upfront (e.g. delivery-fee refund on
  SLA breach) so support never improvises.

---

## 7. What DropOff already has that food reuses

- Lipila collect + disburse + webhook settlement (prepay + refunds).
- OTP/handover codes, photo evidence, job chat, tracking-with-account.
- Rider identity, verification, GPS broadcast, team roster.
- Analytics outbox + ops KPI pattern (add a `food_orders` layer later).
- Rate limiting, idempotency, fraud scoring.

New build needed: `orders` table + endpoints, Food tab UI, food dispatch pool,
vendor portal (pilot = a simple web page like the partner portal), settlement
sweep for vendors.

---

## 8. Suggested phasing

| Phase | Scope | Verdict gate |
|---|---|---|
| 0 (paper) | This doc; pick Option B pilot vendors | Owner sign-off |
| 1 (pilot) | Rider-on-request for 10 vendors, prepaid momo, manual dispatch by ops | 30 days: order count, SLA hit-rate, refund rate |
| 2 | Food shifts + auto-dispatch, vendor settlement sweep | Vendor retention + rider earnings per shift |
| 3 | Food tab with vendor list, order tracking | Repeat-order rate |
| 4 | Full marketplace (menus, cart, promos) | Density ≥ X orders/day/vendor |

---

## 9. Open questions for the owner

1. Commission model: % of food value, flat per-order delivery fee, or both?
2. Who owns late/failed food orders commercially — vendor, DropOff, or split?
3. Should food riders be the same salaried team on extra shifts, or a separate
   per-drop pool?
4. Alcohol / restricted items: in or out of scope from day one?
5. Pilot city boundaries: Lusaka only? Which zones?
