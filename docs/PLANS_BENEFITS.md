# DropOff Plans — What Sellers and Riders Actually Gain

> Plain-language reference for sellers, riders and staff. Numbers live in the
> `tiers` table (editable at `/admin/tiers`); this doc explains the VALUE, not
> the price card. Prices below are the current production config.

---

## 1. What every plan is

A plan **pre-buys your DropOff legs** — the rider runs from your door to the
courier depot. Every parcel consumes one plan slot: a booking with 3 parcels
uses 3 slots. A trip only rides the plan when ALL of its parcels still fit
under your remaining cap — otherwise the whole trip is billed at your tier
overage discount. The courier's **counter fare is never part of a plan** —
depot money stays at the depot, as always.

| Plan | Price | Covers | Cycle | If you go over |
|---|---|---|---|---|
| Daily Rider | K49/day | 1 parcel | 24 hours | Full PAYG fee per extra trip (no discount) |
| Weekly Sprint | K399 | 20 parcels | 7 days | 10% off PAYG |
| Silver | K250 | 10 parcels | 30 days | 15% off PAYG |
| Gold | K500 | 25 parcels | 30 days | 25% off PAYG |
| Platinum | K750 | 50 parcels | 30 days | 35% off PAYG |

Unused parcels **expire** with the cycle (no rollover) — the plans are priced so
that finishing the cap beats PAYG; buying more than you ship is on you.

---

## 2. What sellers gain on ANY plan (vs pay-as-you-go)

1. **K0 rider fee on covered trips.** The momo prompt at booking disappears —
   the booking screen shows "Covered by plan", the trip books, the rider is
   dispatched. No per-trip payment friction.
2. **No per-parcel processing fees on covered trips.** PAYG bookings carry
   platform + momo legs on the prompt; plan parcels don't — the plan renewal
   prompt already carried the fees once, at purchase.
3. **Prepay without paying every time.** The whole booking system is prepay
   (bogus bookings can't happen). A plan is prepay **in advance, in bulk** —
   one prompt per cycle instead of one per parcel.
4. **Cap-overage is discounted, not punitive.** exceed your cap and your extra
   trips still bill at your tier discount (Daily Rider excepted: full PAYG).
5. **Discounted legs only, never partner money.** Promos and plan discounts
   apply to the DropOff leg only — the courier counter fare is untouched.
6. **Priority economics, not priority queueing.** Covered trips auto-dispatch
   the moment they're booked (no payment wait), which is the real speed gain —
   dispatch waits for money, and your money already landed.
7. **Business dashboard fit.** Recurring plans, Book-the-return, the weekly
   forecast ("Gold pays for itself at ~N parcels"), and one-tap renewal all
   key off an active plan.

### Which plan wins for whom
- **Ship most days?** Daily Rider K49 < one Lusaka PAYG trip (K55) — activate
  the days you ship.
- **4–6 trips/week?** Weekly Sprint (20 for K399 ≈ K20/trip).
- **Steady monthly volume?** Silver/Gold/Platinum by cap: K25, K20, K15 per
  parcel respectively — Platinum is cheapest per trip if you'll actually use
  all 50.
- The Business screen computes this for you from your real history
  ("Best fit" recommendation) — a plan that costs more than PAYG is never
  recommended.

---

## 3. What RIDERS gain

Riders are **salaried team members** — plans are a seller product, but they
shape the rider's work life:

1. **Salary, not piece-work gamble.** Payroll lands on the cycle (weekly/monthly
   balance); the rider never depends on a given day's order count for rent.
2. **No cash from senders, ever.** Customers prepay by momo; the rider's phone
   is never a collection point. Depot runs: the rider may front the depot's
   counter fare from their own pocket and photographs the depot receipt —
   DropOff reimburses the exact amount **fee-free** as soon as the sender
   repays it through the app (the sender's processing fee covers DropOff's
   costs, so no payout fee touches the reimbursement).
3. **Clean work slots.** Riders work their assigned **sweep slots**
   (06:00 / 10:00 / 14:00 early/mid/afternoon sweeps) — booked work windows
   with route batching, not an all-day scramble. Outside their slot the phone
   is theirs for **other jobs**.
4. **Plan-covered senders = dense, frictionless runs.** Covered bookings
   auto-dispatch instantly with no payment wait, so a sweep packs more stops
   with fewer dead minutes waiting on "the customer is still paying".
5. **Tools do the heavy lifting.** Smart route ordering, live maps, batch
   pickup, parcel photo checks, wait-fee billing, and the Team tab with their
   live stats (jobs, ratings, queue).
6. **Fraud protection flows both ways.** Sender identity is verified, parcels
   are photographed at booking and compared at drop-off, and the handover OTP
   means the rider never delivers into a dispute about who received what.
7. **The 10% take.** Rider earnings carry a DropOff take from the leg fee;
   plan members' K0-leg trips are already paid for by the plan — the rider's
   payout for a covered trip comes from the plan economics, not from chasing
   the sender.

---

## 4. Ground rules that never change (either side)

- **No quoting, ever.** Depot/counter fares are heard at the counter and
  recorded there — DropOff never prices another company's leg.
- **DropOff never collects partner money.** The depot fare is the depot's.
- **Cash is never accepted.** Momo prepay only; unspent prepayment returns to
  the sender's momo if the delivery is cancelled before pickup.
- **Protection (Cover) is quoted protection, not insurance** until legal
  sign-off says otherwise.
