# DropOff — How We Partner With Courier Companies

Internal document (DropOff ops & owner). Not shipped in the app.

## 1. What DropOff is today

DropOff is the **first-mile runner + booking/distribution layer**: we pick up a parcel at the sender's
home/shop and run it to the depot of a courier of the sender's choice. We are
**not** intercity carriers (yet) and we are deliberately positioned as a
*value-add* to courier companies, never a competitor to them.

## 2. What each side does (Phase 1 — current)

| Step | Who | How |
|------|-----|-----|
| Book pickup + pay DropOff leg | Customer | App: K45 rider fee + platform processing (customer covers momo prompt fee) |
| Receive parcel at depot | Courier partner | Customer walks in / rider drops off; **the customer pays the counter fare directly to the partner** |
| Money DropOff holds | **None — never partner money** | We collect our leg + COD float cut (2%) only |
| Tracking | DropOff | Ends at **"Dropped at depot"** — partner owns the intercity leg |
| COD float | DropOff rider/driver | Cash floats with the rider; remitted → sender wallet credited net of 2% (admin `cod_remit`) |

## 3. What the partner gets (without paying us a kwacha)

- Guaranteed parcel inflow on the routes we serve (Lusaka first-mile).
- Their rates live **in the app directory** with their logo + depot address (free — we show up on day 1).
- A queue of pre-sorted parcels at their counter; no sales/collection work on their side.
- A **Partner Portal** where shop staff confirm quoted counter prices and mark rides complete
  (`https://dropoff-api.godfreymoseskalambo.workers.dev/partner/console` — paste login token;
  accounts become `role=partner` via the owner).

## 4. What we ask of a partner (Phase 1)

1. **Real legs, not proxies.** You run the depoalg you advertise (or an express partner of your own,
   e.g. you are the receiving hub for an SA→ZM consigner — Rovert Logistics is exactly this kind).
2. **A fare you stand behind.** A published price list, or a firm per-route quote we record as
   `price_status='confirmed_by_partner'` in the chargebook before we quote it in-app.
   No invented prices — if you can't publish, we list you as `quote_on_request` with your counter phone.
3. **Counter honesty.** The customer asks for the confirmed fare; if it drifts more than 10%
   at the counter, tell us — the app disputes it against the recorded quote.
4. **Proof of drop.** The rider hands the waybill copy at your counter; you stamp/sign.
   That signature is the delivery closure for us and the handoff of liability to you.
5. **Dispatch discipline.** You send the parcel the same business day (or publish your departure
   windows on the quote). Repeat no-shows = removal from the directory.

## 5. What partnership unlocks in phase 2 (not now)

These stay **"coming soon"** in the app until every partner below signs the addendum:

- **Partner collection in-app** — DropOff collects the counter fare on their behalf via Lipila
  and settles weekly (needs: rates locked, waybill-format agreement, settlement account &
  14 days of clean test shipments in phase 1).
- **Live parcel status scanning** — riders/shop staff log `at_depot → departed → arrived → ready/delivered`
  on their own devices; tracking continues past depot drop-off *for that depot only*.
- **Parcel insurance & claims desk** routing through our support inbox.
- **Cash-on-delivery settlement agency** for e-commerce sellers partnering with the depot.

## 6. Onboarding a courier (week-by-week)

1. **Approach / intro** — ask for the station manager + the person who prices the counter
   (e.g. Platinum Chibolya, Mercury Lusaka, Zampost counters, Rovert Lusaka office).
2. **Send the one-pager** — this document trimmed to §2–§4.
3. **Rate capture visit** — photograph the price board or get the official tariff
   (we did this for Platinum — it anchors every estimate in the app).
4. **System entry** — owner (`X-Admin-Key`): `POST /admin/couriers` (add depot), then
   `POST /admin/quotes` (verified fares FROM Lusaka), or promote the shop to partner via
   `POST /admin/partners {email, courier_id}` so their own staff can confirm quotes in the portal.
5. **Week-1 test ride** — owner drives/rider runs one parcel, full loop: book → pickup → depot
   drop → signature. Any friction (no waybill, fare surprise, no stamp) = fix before listing.
6. **Quarterly rate review** — every 3 months re-verify their fares; stale prices in the app
   disqualify, not embarrass — the app would rather say "confirm at counter" than lie.

## 7. Recruiting (our weekly cadence — months 1–3)

DropOff is driver+rider ourselves for the first months, then we push one rider per week.

- **Who**: 700cc+ motorbike holders with own helmets & phone, 22–38, living along
  our Lusaka route (Kanyama / Chilenje / Kalingalinga / Kabwata / Chelstone / Libala).
- **Pay**: per-parcel split — rider keeps **90% of K45 = K40.50** (90/10), plus pack-included
  routes; average 25–40 parcels on busy days once the directory covers the route map.
  Never fixed salary until route density justifies it.
- **Kit**: branded reflector vest + courier bag + DropOff receipts book + depot drop stamp sheet.
- **Device**: rider app is the same Flutter app (role=ops JWT; assign rides from the console).
- **Rules**: no carrier rides without waybill; COD float remitted every Friday or the account
  freezes until reconciled; customer first, no heroics, report damage at counter.
- **Pipeline**: applicant → interview at the depot → one escorted trial sweep → solo access after
  50 clean parcels or 2 weeks. Recruited every Friday via the depot noticeboard + Facebook
  groups + posters at counter partners (they get first-look credit — weekly).

## 8. The number we watch

`parcels_last_30d` and `cod_last_30d` on the admin console KPIs, per partner depot + per rider.
A depot that drops 5+ parcels/week earns the "★ Verified partner" slot in the app.
