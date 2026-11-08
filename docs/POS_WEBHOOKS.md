# POS / Partner Webhooks — Push Parcels into DropOff

DropOff accepts **partner status updates** from courier depots, storefronts, and POS systems so a counter can confirm receipt, mark departures, and close the loop without the app.

## Endpoint

- **URL:** `POST https://dropoff-api.godfreymoseskalambo.workers.dev/webhooks/partner-status`
- **Auth:** `X-Partner-Key: <api_key>` (issued per courier/partner; stored in `partner_keys`)
- **Content-Type:** `application/json`

## Request

```json
{
  "ref": "DRO-261108-ABCDE",
  "waybill": "WB-12345",
  "status": "received",
  "note": "Parcel received at Ndola counter",
  "at": "2026-11-08T10:15:00+02:00"
}
```

- `ref` **or** `waybill` is required (used to locate the job; `waybill` checked first).
- `status` is required and must be one of the mapped partner statuses below.
- `note` and `at` are optional (appended to the job event).

## Status mapping (partner → DropOff)

| Partner status | DropOff event/status | Meaning |
|---|---|---|
| `received` / `at_depot` | `at_depot` | Depot/counter has the parcel (**sets `partner_confirmed=1`**) |
| `departed` / `in_transit` | `departed` | Left the origin depot / in transit |
| `arrived` / `arrived_destination` | `arrived` | Reached destination city/depot |
| `ready` / `ready_for_collection` | `ready_for_collection` | Ready for recipient pickup |
| `collected` / `delivered` | `delivered` | Handed over / collected |

Unknown statuses return `400` with the allowed list.

## Response

- **200** `{ "ok": true, "ref": "DRO-...", "partner_confirmed": true }` (on mapped status)
- **403** `{ "error": "bad_partner_key" }`
- **404** `{ "error": "unknown_waybill" }`
- **409** duplicate within 5 minutes (idempotent guard) — safe to retry

## Depot counter confirmation & parcel security

A `received`/`at_depot` webhook from the depot POS is the **depot counter confirmation**: it sets `jobs.partner_confirmed=1` and records a `[partner]` event. Combined with:
- the **seller's booking-time parcel photo** (`parcel_photo_url`), and
- the **rider's depot drop-off photo** + `POST /jobs/:ref/parcel-check` (AI photo comparison),

this forms the anti-false-parcel evidence chain (booking photo → rider drop photo/AI check → depot confirmation).

## Integration notes for storefronts/POS

1. Store the DropOff `ref` (and/or the courier `waybill`) on the counter ticket at intake.
2. On intake, call the webhook with `status: "received"`. On linehaul departure/arrival/collection, post the corresponding status.
3. Retries are safe (5-minute dedup). Use HTTPS only; keep the partner key secret (server-to-server).
4. Partner keys are provisioned by DropOff ops/admin (superadmin manages `partner_keys` per courier). Contact DropOff to obtain a key for your courier/location.

## Security

- Keyed per courier (`X-Partner-Key`). Never embed the key in client-side code.
- The endpoint only advances status for jobs tied to the key's courier context as configured; mismatches/unknown refs return 404.
- All partner events are attributed `[partner]` in the job timeline for audit.