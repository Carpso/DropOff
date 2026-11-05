# 🇿🇲 DropOff — "We carry it to the courier"

> **The gap:** In Zambia, sending a parcel means the sender travels to the courier depot
> (Platinum, Mercury, Rivert, One World, Icypeed, DHL…). If you don't have a car,
> the depot run is the painful last 5 km **before** the courier's intercity leg.
> **DropOff is the Uber-of-the-first-mile**: a rider collects from the sender's home/shop
> and drops it at the depot, with live tracking, digital proof of drop-off, and a
> mobile-money receipt — delivered to the recipient's door on the receiving end too.

---

## 1. The App Model (two-sided marketplace + depot runners)

### Actors
| Actor | What they do |
|---|---|
| **Sender** (biz or individual) | Opens app → picks courier + service level → rider collects from home → parcel lands at depot → tracked to recipient's city |
| **Rider / Runner** (bike, trimoto, car) | Fills a job — collects parcels in the area, delivers to the right depots (and replies to pick up released parcels) |
| **Depot** (Platinum, Mercury…) | Receives the parcel, takes over the intercity leg, and hands it back to a runner on the far side |
| **Recipient** | Gets a door delivery in their city (optional add-on), or maps to the depot to collect |
| **DropOff Ops** | Riders, dispute support, cash-float handling, and courier partnership management |

### Core flow (booking → handover)
1. **Quote screen** — sender enters pickup & destination city + package weight/options.
2. **Rider request** — the closest available rider is assigned and heads to the sender.
3. **Package capture** — after pickup, the rider/ops agent weighs the package and captures the courier counter price (the "chargebook") into the app.
4. **Rider takes it to the depot** — the destination depot and (optional) receiver are set on the waybill.
5. **Receipt sync** — counter charge + delivery fee are reconciled against the money received; services are auto-billed weekly. The sender sees the courier charges + DropOff fee, and everything pays out of one wallet balance.
6. **Tracking** — status moves `pickup → at_depot → departed → arrived → delivered/ready_for_collection`.
7. **Payment** — pick the Lipila payment channel (D20 merchant, or an Airtel/MTN/Zamtel Money collect request); the client then polls payment status in the background until it flips to `success`. One day the **sender** pays the courier fare and the rider; the receiver can pay the leg-2 door-delivery fee and any COD and settle it online.

### What makes it catchy 🚀
- **Name** — "DropOff" says *we drop it off for you*. Short, delivery-native, easy to say in any language. ("DropOfff — one tap to the depot.")
- **The number-1 hook** — *“We meet you anywhere; your package leaves your hands in 30 minutes.”*
- **Price-anchoring mechanic** — the sender selects their courier (Platinum, Mercury, etc.), and DropOff quotes the *counter price PLUS* the rider fee. That's honest and kills the driver guessing game.
- **City-per-option booking flow** — in Lusaka, a "daily runner" pack for a seller doing 20 Platinum drops/week: fixed small rates, weekly automatic settlement (perfected by the driver!). WhatsApp/Group promos can push this.
- **Emergency/surge mechanic** — the sender can add a "tinder-style" urgent button that previews their distance-radius on a map and the extra surcharge for getting a rider within the hour.
- **Raise trust** — all riders are outfitted in chitenge-yellow/green DropOff gear; every pickup/drop-off needs a picture + a signature; parcels are only released against the recipient's courier waybill.
- **WhatsApp fallback** — a WhatsApp Business version of the same booking flow (important in Zambia).

---

## 2. Pricing intelligence (what each courier actually charges)

> Rates are only shown when a public or supplied source was verified. Missing tariffs are intentionally marked “quote at depot”; no courier fare is invented.

### Platinum Courier Services — public 2026 board from Lusaka

| Province / route group | Small | Medium | Large |
|---|---:|---:|---|
| Copperbelt: Ndola, Kitwe, Luanshya, Kalulushi, Mufulira, Chambishi, Chingola, Chililabombwe | K50 | K60 | K80 & above |
| Kasumbalesa | K50 | K70 | K100 & above |
| Mpongwe | K70 | K100 | K120 & above |
| Central: Kabwe, Kapiri Mposhi | K50 | K60 | K80 & above |
| Mumbwa | K50 | K70 | K100 & above |
| Mkushi, Serenje, Mukando | K70 | K100 | K120 & above |
| Southern: Kafue | K40 | K50 | K70 & above |
| Southern: Mazabuka, Monze, Pemba, Choma, Kalomo, Zimba, Livingstone, Kazungula | K50 | K70 | K100 & above |
| Western: T.B.Z | K50 | K70 | K100 & above |
| Western: Kaoma, Mongu, Senanga, Mwandi, Katima Mulilo, Sesheke | K100 | K130 | K150 & above |
| North-Western: Solwezi, Kalumbila, Kisasa, Manyama | K100 | K130 | K150 & above |
| Luapula: Chembe, Mansa, Samfya | K100 | K130 | K150 & above |
| Eastern: Nyimba, Katete, Petauke, Sinda, Chipata | K70 | K100 | K130 & above |
| Northern: Kasama | K100 | K130 | K150 & above |
| Northern: Mbala | K130 | K150 | K180 & above |
| Muchinga: Mpika, Isoka, Chinsali, Nakonde | K100 | K130 | K150 & above |

Notes: prices are from Lusaka only; large parcels start at the shown amount; handle-with-care parcels are charged at the office. Source: supplied depot price board, effective 1 July 2026 and photographed 2 September 2026.

### Other courier options

| Courier | Status in the app | Verified evidence |
|---|---|---|
| Mercury Express Logistics | Quote at depot | Official website + supplied Lusaka–Ndola waybill dated 26 August 2026: 40×20×20 cm, 3.20 kg chargeable weight, service K95.23 + fuel K8.00 + VAT K13.65 = K116.88. This is one transaction, not a general tariff. |
| DHL Zambia | Shipment-specific quote | No reliable public Zambia domestic price card verified. |
| Rivert | Depot confirmation required | Public tariff not verified. |
| One World | Official rate calculator | `oneworld.co.zm/rate-calculator`; no fixed fare copied. |
| Icypeed Logistics | Local quote needed | Public rate cards mainly cover UK/South Africa to Zambia, not Lusaka–Ndola domestic routes. |

### Supplied receipt / waybill samples

- `app/assets/images/platinum_receipt_1.jpeg`
- `app/assets/images/platinum_receipt_2.jpeg`
- `app/assets/images/platinum_receipt_3.jpeg`
- `app/assets/images/platinum_price_2026.jpeg`
- `app/assets/images/platinum_offices.jpeg`
- `app/assets/images/mercury_waybill.jpeg`

### DropOff rider fee guidance (production)

- Standard city pickup: **K45** pay-as-you-go (Lusaka distance bands K35/`<=5 km` → K50/`<=12 km` → K75 beyond).
  Always stays under every courier's own counter fare (Platinum small-parcel minimum is K50, Kafue K40 is
  the only tight case — locally the rider only does the depot trip, not the intercity leg).
- Optional destination door delivery: **K30**.
- Platform take-rate on pay-as-you-go: **10%** of the rider fee — the *thin while paygo* slice; pack
  subscriptions are where platform margin lives (see §3.1 split table).
- Courier fare is always separate and shown as "quote needed" until a verified rate exists.

---

## 3. Money: how DropOff makes money 💰
2. **Rider fee (the DropOff leg) — collected first, in full by DropOff** — paygo K45: rider keeps K40.50 (90%), DropOff K4.50, plus Lipila's K2.50 momo prompt fee (added to the customer, never taken from the rider). The courier **counter fare is never collected by DropOff** — the customer pays it directly at the depot counter. Partner collection in-app is a future, opt-in feature ("coming soon" in the app).
3. **Leg-2 door delivery in the destination city** — customer pays K30 + a K3.48 platform processing on it (`LEG2_PROCESSING_FEE_ZMW`), collected by DropOff; the recipient signs at the door. Riders running leg-2 are paid out by DropOff from the leg money.
4. **COD collection (live)** — riders hand parcels to door customers and log the cash: `POST /jobs/:ref/events {cod_collected_zmw}` records the float **with the rider/driver**; the sender's wallet is credited net of a 2% COD fee **only after remittance** (`POST /admin/payouts {kind:'cod_remit', job_ref}`). Cash stays client-side until traced; DropOff's 2% is its only cut.
5. **Courier commissions / partner marketing (future)** — refer heavy Platinum/Mercury/Icypeed shippers for a per-parcel share, once partner collection exists.
6. **Business packs (Silver K350 / Gold K700 / Platinum K1,500 per month)** — see §3.1; auto-renewed via Lipila by the daily cron (renewal prompts also carry the +K2.50 customer-side fee).
7. **Surge / VIP** — express <30-min pickups, after-hours, weekend.
8. **Waiting / queue time** — rider logs minutes (sender not ready, depot counter queue): first 10 min free, K2/min, K50 cap, appended to the server-computed total.
9. **Wallet float (fee-amortiser)** — senders pre-load wallets via Lipila (`kind='topup'`, K10–K5,000): the K2.50 prompt fee is paid **once per deposit**, not per parcel. Wallet-method jobs charge the **DropOff leg only** (+ its platform fee) on pickup; every kwacha moves through `wallet_ledger` (single audit trail).

> **Never compete on the courier ticket itself.** DropOff is a *value-add* to Platinum / Mercury / One World —
> that positioning makes depot partnerships win-wins instead of defensive.

### 3.1 Seller packs, rider split & timed daily windows (implemented, Worker v5)

Batching is the whole margin story: a rider who sweeps one neighbourhood is cheaper per parcel
than a rider doing one run per booking. Timed windows (6am / 10am / 2pm) also respect depot
cut-offs (e.g. Platinum closes ~16:30, so an afternoon sweep still lands same-day).

| Tier | Price | Parcels/day | Seller cost per parcel | Break-even |
|---|---|---:|---|---|
| Pay-as-you-go | K45/pickup | ∞ (on demand) | K45 | — |
| **Silver** | **K350/mo** | 1 | **K11.70** | 10 parcels/mo |
| **Gold** | **K700/mo** | 3 | **K7.80** | 20 parcels/mo |
| **Platinum** | **K1,500/mo** | 10 | **K5.00** | ~43 parcels/mo |

**Rider/driver earnings per parcel (the split):**

| Job type | Rider earns | DropOff keeps | Notes |
|---|---|---|---|
| Pay-as-you-go K45 | **K40.50** | K4.50 (10%) | + the **customer** pays the K2.50 Lipila prompt fee — the rider split is untouched |
| Pack parcel (swept) | **K5.00 flat** | pack fee − K5 | `PACK_RIDER_PAY_ZMW`; sweep riders carry 20–80 parcels/window, so a sweep of 60 = K300/day wage on top of paygo catch |
| Waiting >10 min | bill passed through | K2/min → sender | logged as evidence per event |

Pack margin is honest: at full Platinum usage the pack fee ≈ rider cost (~K5×300 parcels/month).
Real profitability comes from three lifts: (1) Platinum sellers rarely max the 10/day cap,
(2) over-cap parcels fall back to K45 paygo, (3) density — one rider sweep amortises across *all*
sellers in the neighbourhood. Guardrail: run a fleet-margin report (`GET /admin/stats`) weekly and
move `PACK_RIDER_PAY_ZMW` if rider sweeps out-earn the pack revenue.

Upsell order: pay-as-you-go → (week 2: 3+ pickups seen = "regular") → Silver offer on WhatsApp →
Gold at 3/day cadence → Platinum for depot-class shippers. **Targets: 100 paying pack sellers/month
+ 50 active paygo customers, of which aim ≥20 regular paygo sellers (3+ parcels/mo) converting to
Silver.** Growth funnel is instrumented at `GET /admin/stats` (regulars counter included). APIs:
`GET /plans`, `POST /subscriptions`; over-cap jobs fall back to pay-as-you-go — never block a paid drop.

### 3.2 Client ↔ Worker wiring (implemented)

`app/lib/data/dropoff_api.dart` is a REST client for the Worker:
- Config via `--dart-define=DROPOFF_API_URL=... DROPOFF_API_KEY=... DROPOFF_ADMIN_KEY=...`
  (no API key → demo mode; the ADMIN key is for the owner's web console build only — never ship it in the store app).
- Identity: phone-OTP login (`POST /auth/request` → SMS code → `POST /auth/verify` → JWT, 30 days).
  A customer JWT always books/pays/subscribes as **its own phone** — the client cannot spoof a sender.
  The `X-Api-Key` ops key is for the rider-device service account; `X-Admin-Key` guards the pricebook.
- Signature: SMS delivery of OTP codes still needs an SMS gateway (e.g. Africa's Talking); until then
  `AUTH_DEV_MODE="1"` returns the code in the response for testing.
- Booking posts `POST /jobs` with **no prices** — the server computes counter + rider + leg-2
  from the `quotes` chargebook (missing route → `422 quote_needed`, never an invented fare).
- Payment: `POST /payments` (`kind: job | topup`) → Lipila collect → poll `GET /payments/:id/status`
  every ~2s up to ~40s. Settlement is **idempotent** (`settled` flag) — webhook + poll can race safely.
- Wallet: `POST /payments {kind:'topup'}` → float; `GET /wallet` balance + ledger.
  Wallet-method jobs auto-charge at pickup (atomic `balance >= total` guard).
- COD: rider logs `cod_collected_zmw` on delivery → seller wallet credited net of 2%.
- Timed pickups: `pickup_window` ∈ `now / 06:00 / 10:00 / 14:00`.
- Waiting time: `wait_minutes` in `POST /jobs/:ref/events`.
- Auto-renewal: daily **cron** (02:00 UTC) collects expiring packs 3 days early via Lipila;
  grace of 7 days before a pack lapses to `expired`.

### 3.3 Partnership management & price capture (superadmin)

Courier partners keep **live profiles in the app** (`GET /couriers/:id/profile` — name, depot,
website, price status, verified rates straight from the chargebook). The superadmin (the owner)
maintains everything with `X-Admin-Key`:
- `POST /admin/couriers` — create/update a partner profile (website, price_status, notes).
- `POST /admin/quotes` — capture/upsert any depot tariff (route / weight / service / K price);
  this chargebook is the single source of pricing for the whole app.
- `POST /admin/riders` — rider roster (their phone becomes their login identity).
- `POST /admin/jobs/:ref/assign` — dispatch a rider onto a job (rider events then authenticate as that phone).
- `POST /admin/payouts` — rider earnings & cash-outs in the ledger.
- `GET /admin/stats` — growth cockpit: active pack sellers by tier, paygo regulars (3+ parcels/30d),
  parcels, revenues, wallet float, COD volumes → track the 100 pack + 50 paygo target here.

### 3.4 Growth targets (100 pack sellers / month)

| Funnel stage | Signal | Goal |
|---|---|---|
| Paygo customer books | new senders in `/jobs` | 50/mo |
| Regular paygo (3+ parcels/mo) | `/admin/stats.paygo_regulars` | ≥20/mo |
| Silver/Gold/Platinum conversion | `POST /subscriptions` | 100/mo (mix ≈ 70/25/5) |
| Revenue at target | 70×350 + 25×700 + 5×1500 ≈ **K47,000/mo** | ~1 rider node = 6–10 sweeps/day |

---


## 4. Tech stack (as per Carpso/AGENTS conventions)

- **Client:** Flutter (customer + rider in one app, role-switched; web admin on Flutter Web).
- **Maps:** `flutter_map` + R2-hosted PMTiles (`https://maps.churchonapp.com/{country}.pmtiles`, consolidating to `https://media.churchonapp.com/maps/{country}.pmtiles`). **No MapTiler/Mapbox/Google Maps.**
- **Backend:** Cloudflare **Workers + Hono** REST API, **D1** (SQLite) for all relational data. No Supabase for new projects (Supabase is only kept for legacy Lipila edge functions).
- **Payments:** **Lipila** — Supabase Edge Function pattern is only a reference; here we run it server-side in the Worker (`supabase.functions.invoke('lipila-collect')` equivalent → `POST /v1/payments/init` + client polling). Zambian phone numbers are normalized to `260XXXXXXXXX` (Airtel 097/077, MTN 096/076, Zamtel 095/075).
- **Push:** FCM (`firebase_messaging` + `flutter_local_notifications`), initialized lazily — the app must run without it.
- **Realtime tracking:** Worker → WebSocket with Durable Object (chunk 2028) or simple D1 polling in the MVP.

### Repo layout in this folder
```
DropOff/
├── README.md                    ← this strategy doc
├── workers/                     ← Cloudflare Worker + Hono API + D1
│   ├── wrangler.toml
│   ├── package.json
│   ├── src/index.ts             ← routes
│   ├── src/lipila.ts            ← Lipila collect / status / webhook
│   └── migrations/0001_schema.sql
└── app/                         ← Flutter client (draft)
    ├── pubspec.yaml
    └── lib/
        ├── main.dart
        ├── data/dropoff_api.dart    ← REST client for the Worker
        ├── models/models.dart
        └── screens/
            ├── quote_screen.dart        ← courier + weight → price
            ├── create_job_screen.dart   ← address + confirm + pay
            └── track_screen.dart        ← status timeline
```

---

## 5. Launch plan (Lusaka pilot)

| Week | Milestone |
|---|---|
| 1–2 | Sign 3 couriers (Platinum Chibolya, Mercury Longacres, Icypeed Libala) → agree merchant rates + a "DropOff fast-lane" counter desk. Recruit 8 motorbike riders |
| 3 | Launch MVP: Flutter customer app (quote → book → pay → track) + 1 rider app build; WhatsApp Business booking as backup channel |
| 4 | Pilot with 25 sellers who ship regularly to Kitwe/Ndola/Livingstone; capture real counter prices weekly so the app's costbook stays accurate |
| 6 | Add "leg-2" door delivery at destination; corporate tier for platinum-class sellers making 20+ drops/week |
| 8 | Promo + referral: *send 4 parcels, the 1st of next week is free* |

### Why this wins
- **No chicken-and-egg on the courier side** — depots handle walk-ins already; DropOff just arrives with more parcels per hour. We're a customer at first, a partner at second.
- **We don't compete on the courier's rates** — the intercity leg stays with Platinum/Mercury/Icypeed; we own the first-mile (home→depot) and later the last-mile (depot→door), which nobody currently serves with a phone tap.
- **The pain is physical, not technical** — people without cars (or without time) still walk or take a taxi to a depot. K25–45 to avoid that trip is an easy sell.
- **Low-tech adjacent market** — even today, heavy shippers phone a "runner" ad-hoc. A branded, tracked, photo-proven rider service is a step change, and mobile money (Lipila) makes the payment side trivial.

---

## 6. Deployed (2026-11-04)

- **API:** https://dropoff-api.godfreymoseskalambo.workers.dev — health `GET /health` → `{"ok":true}`
- **Auth:** email + password accounts (`POST /auth/register`, `POST /auth/login`, PBKDF2-100k, migration `0007_email_auth.sql`) — verified live 201/200/401/409. The JWT still carries the momo **phone** as identity, so jobs/payments/wallets are unchanged; phone-OTP stays for the ops/rider device-link (needs an SMS gateway). Login UI: `AccountScreen` from the Home avatar.
- **D1:** `dropoff-db` (`1100c702-d4c2-4114-8926-7e113350ad17`, region WEUR); migrations 0001–0017 applied remotely
- **Secrets set:** `JWT_SECRET`, `API_AUTH_KEY`, `ADMIN_AUTH_KEY`, `LIPILA_API_KEY` (values in `workers/.prod-secrets.txt`, gitignored)
- **Artifacts:** signed APK + AAB (`--release`, upload keystore in `app/android/app/upload-keystore.jks` + gitignored `app/android/key.properties`; store password in `workers/.prod-secrets.txt` / `C:\Users\User\AppData\Local\Temp\prodkeys.txt`). Built with
  `--dart-define=DROPOFF_API_URL=…` — **customer/store builds carry no API or admin key** (JWT-only
  auth); rider/ops builds additionally get `--dart-define=DROPOFF_API_KEY=…`, the owner's console
  build `DROPOFF_ADMIN_KEY=…`. Keys are injected on-device only, never committed or defaulted.
- **D1 = the only store:** zero data lives on-device for server truth; the app persists only local
  prefs (JWT, bookings cache) and falls back to REST. Migrations 0001–0017 applied remotely.

## 7. Offline capability & storage truth

- **Reads (couriers, cities, quotes, plans):** successful `GET`s are cached in-memory via
  `shared_preferences` (`dropoff_api.dart` — `_cacheKey`); when the network is down the app serves the
  last good response, otherwise falls back to the built-in catalog/cities.
- **Bookings:** always created locally first; dispatched to the Worker when reachable
  (pricing is authoritative server-side).
- **No local DB/sync engine:** the backend of record is D1; the client never persists wallet
  balances, jobs or payment state locally. Offline = read-only + queued-looking local bookings;
  payment prompts require connectivity by design (Lipila mobile money).
- **fresh build = fresh cache** — stale caches survive only until the user reinstalls.

## 8. Admin / Superadmin access

**Account:** the owner's `auth_users` row with `role='admin'` (seeded in migration `0007`; the phone
is the momo identity). The password is **not** recorded here — it was seeded once and must be
rotated via app → Account → Forgot password (a reset also revokes all prior JWT sessions via
`token_version`). JWT sessions for that phone carry admin rights for `/admin/*` (DB-role based, no key needed).

**Superadmin console (owner):**
1. Open `https://dropoff-api.godfreymoseskalambo.workers.dev/console?key=<ADMIN_AUTH_KEY>` — KPIs
   (active paying senders, parcels 30d, platform/Lipila fees, COD float, referrals funnel) + tier/promo/POS editors + partner promotion.
2. The same admin key authorizes the management API: `X-Admin-Key: <ADMIN_AUTH_KEY>`:
   - `POST /admin/couriers` — add/verify depots (`{name, depot_name, city, website, logo_url, ...}`)
   - `POST /admin/partners` — promote an email to partner shop (`{email, courier_id}`)
   - `POST /admin/quotes` — insert a chargebook rate
   - `POST /admin/payouts` — rider earnings (`{phone, amount_zmw, kind: rider_earning|rider_payout}`)
     or settle door-collected COD (`{kind: 'cod_remit', job_ref}`) — Lipila disbursement to the seller's momo, net of the 2% cut.
   - `POST /admin/partner-keys` — mint a webhook key for a courier.
   - `POST /admin/pos` — set a courier's collection rail (momo/bank/POS terminal/WhatsApp/cash).
   - `GET /admin/referrals` — full referral funnel.
   - `GET /admin/tiers` / `POST /admin/tiers` — edit pack prices/tags live.
   - `GET /admin/promos` / `POST /admin/promos` — create seller promo codes.
3. **Partner (courier shop) console:** `GET /partner/console`, paste a login token; they confirm
   quote prices and rides at `/partner/quotes` / `/partner/rides` (`role=partner` JWT).

**API keys:** `API_AUTH_KEY` = ops/rider devices (`X-Api-Key`), `ADMIN_AUTH_KEY` = owner console
(`X-Admin-Key`). Never ship these keys inside anything distributed publicly; they are compile-time
`--dart-define`s and the app uses them only when calling the admin API.

### Still yours to do
1. **Password:** change the seeded admin password immediately.
2. **Email sending:** wrangler v4 → `wrangler email sending enable churchonapp.com`; until then reset/verify links return `mail_error` (dev links with `AUTH_DEV_MODE=1`).
3. **SMS OTP:** set `SMS_USERNAME` / `SMS_API_KEY` / `SMS_SENDER_ID` via `wrangler secret put`.
4. **Lipila live:** `LIPILA_BASE_URL=https://blz.lipila.io` + live key; disbursements need IP whitelisting.
5. **Keystore backup:** `app/android/app/upload-keystore.jks` + password backup — losing it = new app signing on Play.

## 9. Marketing kit (this repo)

`marketing/` — seller & courier email/DM sequences, A5 flyers (HTML → print-to-PDF), WhatsApp broadcast scripts, Facebook ad brief, 4-week launch calendar, promo codes (`FIRSTM10`, `SELLER20`, `LOYAL5`) wired to the live campaign. See `marketing/README.md` for the full index.

## 10. Google Maps are NOT used anywhere

Rider map (`lib/widgets/rider_map.dart`) renders our Church On App R2 PMTiles Zambia basemap (`https://maps.churchonapp.com/zambia.pmtiles`) via `flutter_map` + `vector_map_tiles_pmtiles` — the same source as churchonapp's web maps. Routing/stops are latitude-banded (`/batch/pickup`), not Google Directions. Ops console links to Waze only for navigation (public deep links, no data leaves the device).

## 11. Referral funnel

Sellers get a permanent code (`/refer/code`); a seller who signs up via the code and books becomes **rewarded** — the inviter receives a single-use 20 % promo (`FRIENDxxxxx`). Funnel visible at `/admin/referrals` (superadmin) and KPI tiles on `/console`.

## 12. Where the numbers live

`docs/ECONOMICS.md` — paygo/packs/batch math, rider splits, COD remittance flow, per-sweep economics. `docs/PARTNERSHIP.md` — the partner program. `docs/PARTNER_INTEGRATION.md` — POS/system webhook for partner shops.

## 13. Security notes (post-audit 2026-11-05)

- **Rotate the leaked keys now.** The first app build shipped `API_AUTH_KEY` compiled-in; treat
  that key as burned: `npx wrangler secret put API_AUTH_KEY` (and rebuild rider devices with the
  new `--dart-define=DROPOFF_API_KEY=…`). The store/custumer build ships **no** key — it authenticates with the JWT only.
- The admin password that was once written here is also burned — reset it via Forgot password.
- Lipila webhooks are **never trusted**: `POST /webhooks/lipila` re-verifies every reported status
  against Lipila's own check-status API before any settlement.
- Password resets bump `token_version` — all older sessions die instantly.
- OTP codes are crypto-random, burn after 5 wrong attempts, and the verify endpoint is IP-throttled.
- Customer app caches are keyed per-account; no cross-user cache leakage on logout.
