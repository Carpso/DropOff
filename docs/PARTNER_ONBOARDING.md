# DropOff — Courier Partner Onboarding & Login

> Who this is for: courier companies whose depots receive DropOff parcels
> (e.g. Platinum, Icypeed, Mercury). Their depot counter interacts with
> DropOff through a partner console — **never by holding customer money**
> (the depot fare is paid at the counter; DropOff never collects partner money).

---

## 1. The one-time onboarding (done by the DropOff owner)

Partners are normal DropOff accounts with a `partner` role bound to one
courier row. Onboarding is three steps:

1. **The courier registers in the app** like any user — email + phone +
   password (they can do this themselves on any phone).
2. **The DropOff owner promotes them**: `POST /admin/partners`
   `{ "email": "<their email>", "courier_id": <id> }` with the admin key.
   This sets `role = 'partner'` and binds the account to the courier
   (`courier_id` — the row in the `couriers` table, e.g. Platinum).
   The admin console (`/console`) has a "make partner" helper for this.
   *Guard:* the endpoint requires an admin identity — accounts can never
   self-promote to partner.
3. **The partner logs in** and their console unlocks (below).

If the courier is not yet a row in the `couriers` table, add the courier
first (name, city, depot) — that's also what the sender's booking screen
lists as the depot they choose.

## 2. How a partner logs in

Two supported surfaces, same identity:

- **Web console — `https://dropoff-api.godfreymoseskalambo.workers.dev/partner/console`**
  The partner signs in on the app (or is issued a login token), pastes the
  **login token** into the console (or opens the link with `?t=<token>`).
  The token is kept in the browser's local storage only — never server-side,
  and it is scrubbed from the URL/history immediately.
- **API — `GET /partner/*`** with the same `Authorization: Bearer <token>`.

What the partner sees and does:

| Feature | Endpoint | What it is |
|---|---|---|
| My depot | `GET /partner/me` | Their courier row (name, city, depot) |
| Parcels handed to us | `GET /partner/rides` | Every DropOff parcel sent to their depot, with status + prepay state |
| Confirm hand-off | `POST /partner/rides/:ref/confirm` | The depot acknowledges the parcel was lodged (their counter waybill ref) |
| Counter prices | `GET /partner/quotes` / `POST /partner/quotes` | **The partner publishes their own counter fares.** DropOff never quotes for them — the partner sets and updates their price grid (city → city, weight, service) |

## 3. POS / system integration (optional, for depots with a counter system)

For partners who prefer machine-to-machine instead of the console:

1. Owner mints a key: `POST /admin/partner-keys` `{ "name": "Platinum POS" }`.
2. The depot's system then calls DropOff with `X-Partner-Key: <key>`:
   - `POST /webhooks/partner-status` — status updates for parcels in their
     care (`at_depot`, `departed`, `arrived`, `delivered`,
     `ready_for_collection` + optional waybill/note).
   - `GET /partner/pos` / `POST /partner/pos` — the POS hand-off feed.

## 4. Ground rules for partners

- **They own their prices.** DropOff never publishes or changes a counter
  fare; the partner's quotes feed is the only source, updated by the
  partner (or confirmed at the counter — "quoted at counter" shows until
  then).
- **They never handle DropOff money.** The DropOff leg is prepaid by momo
  before the rider even dispatches; the depot fare is paid directly at
  their counter, by the sender, in the normal course of depot business.
- **They confirm receipt, not payment.** The confirm action acknowledges
  the parcel was handed over and lodged — nothing else.
- One courier row per partner account; multiple counter staff can share
  the account or each register and be bound to the same courier.
