# DropOff Fast Lane Desk — partner pilot brief (one page)

**Audience:** courier depot managers in Lusaka (owner-level decision maker).
**Use:** hand this as the one-page brief when asking for a desk; leave the
laminate with the counter. Pilot = 2 weeks, one desk, three sweeps, Friday review.

---

## The ask

A small marked **DropOff Fast Lane Desk** in your depot — a table, corner or one
staff member — where DropOff riders drop parcels and collect counter receipts
separately from your walk-in customers.

**Pickup windows (CAT):** 05:30–07:30 (06:00) · 10:00–11:30 · 14:00–15:30.
Riders collect only in these windows; between them they do other ride jobs.

## What your depot gets

- **Prepaid, batched arrivals** at three fixed windows — no surprise rushes and
  no cash chasing. Every DropOff leg is paid by mobile money before dispatch.
- **Clean receipts.** The rider photographs the depot receipt, types the EXACT
  amount written on it, and every photo is stamped with DropOff branding and the
  capture time. Fewer disputes, a real audit trail.
- **Your counter fare stays yours.** We never publish or undercut it — it is
  always quoted at the counter. The rider fronts it and the sender repays through
  DropOff; you are paid at the counter as normal.
- **Free demand.** Your depot appears in the DropOff app's pickup-point list, in
  front of our growing sender base.
- **Your own partner console** (see below) — no new software to buy.

## Your partner console — what it actually does

A partner is a normal DropOff account given the `partner` role and pinned to
ONE courier depot. It logs in at `dropoff.carpsosolutions.store` like any user,
then gets three surfaces:

1. **Manage quotes — `GET/POST /partner/quotes`**
   Record the counter price for a route (from city → to city, weight class,
   service, amount in Kwacha). Posting a price sets your depot's `price_status`
   to `confirmed_by_partner`. Stale quotes (older than 90 days) are ignored by
   the booking engine, so an old price is never shown to a sender. A partner can
   only ever edit **their own** depot's quotes.

2. **See rides — `GET /partner/rides`**
   The last 50 parcels handed to your depot, with reference, recipient,
   destination, weight, counter price, status and last event. This is your
   inbound manifest — you can see what is coming and prepare the desk.

3. **Confirm rides — `POST /partner/rides/:ref/confirm`** *(the key feature)*
   When the parcel physically arrives at your counter, the depot acknowledges
   the hand-off with one tap (and can optionally add the courier waybill number
   and a note). That writes a `partner_confirmed` event to the parcel's timeline,
   which the sender can see live in Bookings. It is a **receiving acknowledgement,
   not a payment action and not final delivery** — it closes the loop between
   "our rider left the sender" and "your depot actually has the parcel". A
   partner can only confirm jobs belonging to its own depot (`not_your_courier_job`
   otherwise). If the counter has no smartphone, the same loop is closed by the
   stamp-and-send or POS-webhook flows in `docs/PARTNER_CONFIRMATION.md`.

## The 2-week pilot

- **Week 1:** one desk, all three pickup windows, 2–4 real drops per window. Both sides
  log queue times and any receipt disputes.
- **Week 2:** increase volume as subscriber numbers grow; test one Friday
  review with actual numbers.
- **Friday review:** parcels handled, average counter wait, receipts matched,
  issues. Continue, adjust or stop — no lock-in.

## Why now

We are onboarding 100 business subscribers this week. The desk is specifically
to keep that new volume **away from your ordinary counter queue**. We would
rather pilot it small now than arrive unannounced at peak.

**Contact:** [owner name] · [phone] · [email]

---

## Internal: how to run the partnership conversation

**When to approach:** now, while the subscriber drive is starting. Depot managers
are reachable **after 16:30 or 09:00–10:00** — never during a sweep or when their
counter is already busy. Give 2 weeks' lead time before volume lands.

**Opening line:** "We are onboarding 100 businesses this week. We want to avoid
the queue at your counter — can we agree a small DropOff desk and pilot it for
two weeks?"

**Objection handling:**
- *"We don't have space"* — a marked table or one corner is enough; the point is
  separating our batches from your walk-in queue, not a new building.
- *"We don't have time"* — three fixed pickup windows (each 1h30), prepaid, waybills pre-made;
  the desk usually **reduces** total counter time.
- *"We don't want your system"* — they don't need to install anything; the
  console is a web page, and stamp-and-send works with a phone and paper.
- *"Will you publish our prices?"* — no. Counter fares are never shown in-app.

**Success test after 2 weeks:** counter wait down or flat, receipts matched 100%,
depot happy to keep the desk. Then sign 3–5 depots before scaling subscribers.
