# Senders with many parcels — policy (owner directive 2026-11-12)

How DropOff handles a sender who moves more than one parcel at a time,
without breaking the no-quoting rule or the counter-receipt flow.

## The rule: exact receipts only — one photo, one amount, never a rider sum

- A sender books **one trip** carrying up to the vehicle's parcel limit:
  motorcycle **3**, car **6**, van **10**, truck **15** (`_maxParcelsByVehicle`
  in `booking_screen.dart`, clamped server-side by `VEHICLE_MAX_PARCELS`).
- The rider photographs **every parcel** in the batch (multiple parcel photos
  are supported) and files **every depot receipt** the depot wrote — each
  receipt photographed with the EXACT amount written on it
  (`_depotDropWithReceipt` supports multiple receipts for batches the depot
  splits across documents).
- A submitted receipt is always a **single, exact, photographed document** —
  the rider NEVER adds amounts up themselves. The **server** totals the
  photographed receipts (`counter_receipt_zmw` = sum), and the sender repays
  that total (+ processing — waived for plan-active senders). The rider is
  reimbursed fee-free.
- If the depot splits the batch, the rider files each receipt in the same
  drop (no re-booking needed); each document remains individually exact and
  photographed, and every photo is revealed to the sender after payment.

## Plan maths (already implemented server-side)

- Every parcel counts as **one** plan slot, even in the same trip
  (`planUsed + parcels <= planCap` in `/bookings`).
- Daily Rider (1 parcel/day): a 2-parcel trip exceeds the day cap → the trip
  prices as PAYG overage at the plan's discount instead of K0.
- Weekly/monthly plans: overage parcels keep the plan discount
  (10/15/25/35% off the rider fee).
- The booking screen's `_PlanBanner` shows exactly how many slots the trip
  deducts BEFORE paying, so multi-parcel senders are never surprised.

## Smart reminder for repeat senders

The booking screen shows a **Smart reminder** card (`_CounterReminder`) when
the sender has PAID depot receipts to the same destination before:
*"Last time to Ndola you paid K120.00 at the Mercury counter (3/11/2026)…"*
It is drawn only from real paid receipts — it never quotes a fare for the
next trip; the depot counter still decides, and the receipt photo is still
the source of truth.

## Why not let the rider type one summed total?

A rider-typed sum is a rider-computed number — exactly what the no-quoting /
exact-evidence rules forbid. Instead the rider files each photographed
receipt with its own exact amount (multi-receipt drops are supported), and
the server sums the documents. One trip still means one momo prompt for the
sender and one fee-free reimbursement for the rider — cheaper, simpler, and
the depot's own paperwork stays the single source of truth.
