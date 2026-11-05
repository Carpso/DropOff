# DropOff — Partner Integration Guide (POS / payment / dispatch systems)

Audience: IT person at a courier shop, or DropOff ops onboarding them.
Goal: any depot or counter system can push parcel status into DropOff with ONE HTTPS call, and sellers can pay the courier directly using the courier's own payment rails — never through DropOff.

## 1. Partner webhook (status feed)

**Endpoint:** `POST https://dropoff-api.godfreymoseskalambo.workers.dev/webhooks/partner-status`

**Headers:** `X-Partner-Key: <per-courier key — ask DropOff ops (superadmin console → Partner keys)>`
`Content-Type: application/json`

**Body:**
```json
{
  "waybill": "PDN-2026-045512",   // courier's own waybill or DropOff job ref
  "ref": "DRO-0997310-74",        // alternative if no waybill exists yet
  "status": "departed",           // one of the 5 below
  "note": "LH802 departed Lusaka 18:30",  // optional, shown in the timeline
  "at": "2026-11-04T18:32:00+02:00"       // optional, ISO timestamp
}
```

**Statuses (1:1 with the sender's timeline):**
| Partner sends | Sender sees |
|---------------|-------------|
| `at_depot` | Arrived at depot |
| `departed` | Departed (intercity) |
| `arrived` | Arrived (destination city) |
| `ready_for_collection` | Ready for collection |
| `delivered` | Delivered |

**Idempotency:** same waybill+status within 5 minutes is deduped (returns `{"ok":true,"deduped":true}`). Retry safely.

**Verify:** `curl -X POST … -H "X-Partner-Key: $KEY" -d '{"waybill":"PDN-TEST-1","status":"at_depot","note":"smoke test"}'` → expect `{"ok":true,"ref":"DRO-..."}`. If the waybill isn't known, you get `{"error":"unknown_waybill"}` — check the DropOff job ref first.

**Integration recipes:**
- **Free POS (Africa's processes):** shop counter system just calls this from its "dispatch" landmark button or a cron.
- **Shopier/Mollies/e-comm plug:** use the "order status updated → delivered/ready_for_collection" webhook output to call ours.
- **Router/dispatch team has exports:** dump CSV → call in a loop (status moves monotonically; ours handles duplicates).
- **No system at all:** the partner portal (`GET /partner/console`) works from an Android phone; tap "departed" per waybill — same webhook under the hood.

## 2. Seller pays courier directly — "partner collection rail"

DropOff NEVER holds courier money today. Instead we show the seller *how to pay the partner* at the counter — merchant till number, bank account, WhatsApp order link, or a POS terminal instruction. This is set per courier via:

- `POST /admin/pos` (DropOff ops, X-Admin-Key): `{courier_id, rail, merchant_id, instructions}` — e.g. rail `momo`, merchant `0960000000`, instructions `Send K110 to merchant 0960… with waybill number as reference`.
- or self-serve by the partner: `POST /partner/pos` (partner JWT role) — the partner logs in like any account.

`GET /couriers` then returns each courier's `payment_rail`, `payment_merchant`, `payment_instructions`; the app shows it under the depot line ("Pay the shop direct: momo • 0960…, ref=waybill"). Sellers pay the courier; DropOff is never in that flow; no clearing risk, no regulatory drag. **In-app partner collection (Lipila/MoMo direct charges into the courier's merchant account) = phase 2, opt-in per partner — tagged "coming soon" everywhere today.**

## 3. API quick keys (env/headers cheat-sheet)
| Who | Header | What for |
|-----|--------|----------|
| Seller | `Authorization: Bearer <login JWT>` | book, pay, track, live location |
| Ops/rider device | `X-Api-Key: <API_AUTH_KEY>` | ops tooling, route pickup, confirm drop-off |
| Owner/admin | `X-Admin-Key: <ADMIN_AUTH_KEY>` | tiers, promos, partner keys, POS config, pricebook |
| Partner | JWT with `role=partner` | portal + own POS config |
| Partner system | `X-Partner-Key: <per-courier key>` | webhook ingestion |

## 4. Smoke-test checklist (5 minutes, end to end)
1. `POST /admin/partner-keys {"courier_id": 5}` → save `api_key`.
2. `POST /webhooks/partner-status {"waybill":"TEST-1","status":"at_depot"}` → expect `{ok:true}` (once the job waybill is known; book a test job first and paste its ref into `ref` instead of waybill).
3. `GET /couriers` — confirm your POS block shows for the partner id.
4. `POST /admin/promos {"code":"TEST10","discount_pct":10}` → `POST /promo/check?code=TEST10` → expect `{"ok":true,...}`.
5. Archive the test job row like ops always does (`DELETE /jobs` via console → or leave as demo evidence for the partner).
