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
| **Recipient** | Gets the parcel where it's going. Creates a DropOff account with the phone the parcel was addressed to — every parcel sent to that number shows up automatically under **Bookings → "Parcels for you"**, tagged "addressed to you" |
| **Rider / Runner** (bike, trimoto, car) | Fills a job — collects parcels in the area, delivers to the right depots (and replies to pick up released parcels) |
| **Depot** (Platinum, Mercury…) | Receives the parcel, takes over the intercity leg, and hands it back to a runner on the far side |
| **Courier partner** | The shop/depot counter account (`role=partner`) — confirms counter prices and hand-offs in the depot console |
| **DropOff Ops** | Riders, dispute support, cash-float handling, and courier partnership management |

### Core flow (booking → handover)
1. **Quote screen** — sender enters pickup & destination city + package weight/options.
2. **Book a slot** — every parcel is booked onto a Sweep slot (`now`, `06:00`, `10:00`, `14:00`, or `tomorrow:06:00`). No untimed parcels.
3. **Rider request** — the closest available rider is assigned and heads to the sender (pay-as-you-go first-time senders may need to approve a small booking deposit before dispatch; subscribers are exempt).
4. **Package capture** — sender may attach a parcel photo at booking; after pickup, rider/ops captures details and the courier counter price (the "chargebook"). At the depot drop, the rider's photo can be AI-checked against the booking photo.
5. **Rider takes it to the depot** — the destination depot and (optional) receiver are set on the waybill. Depot partners can confirm receipt via the POS webhook.
6. **Receipt sync** — counter charge + delivery fee are reconciled against the money received; services are auto-billed weekly. The sender sees the courier charges + DropOff fee, and everything pays out of one wallet balance.
7. **Tracking** — status moves `pickup → at_depot → departed → arrived → delivered/ready_for_collection`. Shared tracking links require sign-in or SMS-verified access (sender/recipient phone).
8. **Payment** — pick the Lipila payment channel (D20 merchant, or an Airtel/MTN/Zamtel Money collect request); the client then polls payment status in the background until it flips to `success`. The **sender** pays the courier fare and the rider; the receiver can pay the leg-2 door-delivery fee and any COD and settle it online.

### Security & anti-fraud (live)
- **No untimed parcels:** every booking declares a Sweep slot.
- **Seller parcel photo + AI check:** sender can attach a parcel photo at booking; the rider's depot drop-off photo is compared (AI-assisted, conservative) and mismatches can be flagged for review.
- **Recipient handover OTP (door deliveries):** a 4-digit code is SMSed to the recipient; the rider must enter it to complete a door handover (depot drops rely on photo + depot confirmation).
- **Ghost-booking controls:** pay-as-you-go first-time senders approve a small booking deposit before dispatch (subscribers exempt); missed pickups auto-cancel and earn strikes (3 in 14 days → booking hold). OTP abuse is strike-worthy.
- **Depot counter confirmation:** depot/POS partners confirm receipt via webhook (`partner_confirmed`). See [`docs/POS_WEBHOOKS.md`](docs/POS_WEBHOOKS.md).
- **Tracking privacy:** shared tracking links never expose parcel data without sign-in or an SMS-verified grant to the sender/recipient phone.

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

### 3.1 Seller subscription plans, rider split & timed daily windows (implemented)

Batching is the whole margin story: a rider who sweeps one neighbourhood is cheaper per parcel
than a rider doing one run per booking. Timed windows (6am / 10am / 2pm) also respect depot
cut-offs (e.g. Platinum closes ~16:30, so an afternoon sweep still lands same-day).

| Plan | Price | Parcels | Seller cost per parcel | Break-even |
|---|---|---:|---|---|
| Pay-as-you-go | K45/pickup | ∞ (on demand) | K45 | — |
| **Daily Rider** | **K49/day** | 2 / day | **K24.50** at full use | first parcel pays for the day |
| **Weekly Sprint** | **K399/wk** | 20 / wk | **K19.95** | 9 parcels/wk |
| **Silver** | **K250/mo** | 10 / mo | **K25.00** | 10 parcels/mo |
| **Gold** | **K500/mo** | 25 / mo | **K20.00** | 20 parcels/mo |
| **Platinum** | **K750/mo** | 50 / mo | **K15.00** | ~38 parcels/mo |

(Live prices live in the `tiers` D1 table — Silver/Gold/Platinum were re-based in 0039; `/admin/tiers` edits them without a deploy.)

**Rider/driver earnings per parcel (the split):**

| Job type | Rider earns | DropOff keeps | Notes |
|---|---|---|---|
| Pay-as-you-go K45 | **K40.50** | K4.50 (10%) | + the **customer** pays the K2.50 Lipila prompt fee — the rider split is untouched |
| Plan parcel (swept) | **K5.00 flat** | plan fee − K5 | sweep riders carry 20–80 parcels/window, so a sweep of 60 = K300/day wage on top of paygo catch |
| Waiting >10 min | bill passed through | K2/min → sender | logged as evidence per event |

Plan margin is honest: at full Platinum usage the plan fee ≈ rider cost (~K5×300 parcels/month).
Real profitability comes from three lifts: (1) Platinum sellers rarely max the 50/month cap,
(2) over-cap parcels fall back to pay-as-you-go at the tier overage discount, never blocked, (3) density — one rider sweep amortises across *all*
sellers in the neighbourhood. Guardrail: run a fleet-margin report (`GET /admin/stats`) weekly and
re-price `rider_daily` / `weekly` in `/admin/tiers` if sweeps out-earn revenue.

**One allowance for every normal delivery (2026-11-06):** a plan's parcels pay for *any* in-app
delivery — door pickup, courier-depot collection → door, and the optional last mile — not just
bookings. Collections consume the same slots as pickups. Daily Rider meters 2/day; the monthly
plans meter 10/25/50 per cycle; the day/week cycles start at payment, not at a calendar boundary.

Upsell order: pay-as-you-go → (week 2: 3+ pickups seen = "regular") → Daily Rider for burst days →
Weekly Sprint at 3+/week → Silver→Gold→Platinum for depot-class shippers. **Targets: 100 paying plan sellers/month
+ 50 active paygo customers, of which aim ≥20 regular paygo sellers (3+ parcels/mo) converting up.** Growth funnel is instrumented at `GET /admin/stats` (regulars counter included). APIs:
`GET /plans`, `POST /subscriptions` (Day/Week/Month by `cycle_days`); over-cap jobs fall back to pay-as-you-go — never block a paid drop.

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
- Auto-renewal: daily **cron** (02:00 UTC) collects expiring plans 3 days early via Lipila;
  grace of 7 days before a plan lapses to `expired`.
- Plans are **one allowance for every normal delivery**: pickups, courier-depot collections → door, and the optional last-mile leg all consume the same slots (`plan_inclusion` returned by both `/jobs` and `/collections`); daily caps meter per day, monthly per cycle (`period_start..period_end`).

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
- `GET /admin/stats` — growth cockpit: active plan sellers by tier, paygo regulars (3+ parcels/30d),
  parcels, revenues, wallet float, COD volumes → track the 100 plan + 50 paygo target here.

### 3.4 Growth targets (100 plan sellers / month)

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

## 6. Deployed (2026-11-08, v0.5.0+11)

- **API:** https://dropoff-api.godfreymoseskalambo.workers.dev — health `GET /health` → `{"ok":true}`
- **Auth:** email + password accounts (`POST /auth/register`, `POST /auth/login`, PBKDF2-210k, migration `0007_email_auth.sql`) — the JWT still carries the momo **phone** as identity; phone-OTP stays for the ops/rider device-link. Login UI: `AccountScreen` from the Home avatar. PBKDF2 verify is iteration-aware (hashes minted at older iteration counts self-upgrade transparently on next login); OTP sessions carry the account `token_version` so a password reset revokes them too.
- **D1:** `dropoff-db` (`1100c702-d4c2-4114-8926-7e113350ad17`, region WEUR); migrations 0001–**0043** (0043 = `rider_daily`, the K49 Daily Rider subscription plan)
- **Secrets set:** `JWT_SECRET`, `API_AUTH_KEY`, `ADMIN_AUTH_KEY`, `LIPILA_API_KEY` (values in `workers/.prod-secrets.txt`, gitignored)
- **Artifacts:** signed APK + AAB (`--release`, upload keystore in `app/android/app/upload-keystore.jks` + gitignored `app/android/key.properties`; store password in `workers/.prod-secrets.txt`). Built with
  `--dart-define=DROPOFF_API_URL=…` — **customer/store builds carry no API or admin key** (JWT-only
  auth); rider/ops builds additionally get `--dart-define=DROPOFF_API_KEY=…`, the owner's console
  build `DROPOFF_ADMIN_KEY=…`. Keys are injected on-device only, never committed or defaulted.
- **D1 = the only store:** zero data lives on-device for server truth; the app persists only local
  prefs (JWT, bookings cache) and falls back to REST.
- **Release v0.4.0+7 (2026-11-07):** recipient accounts with auto-claimed parcels ("Parcels for you"),
  DropOff Predict (seller forecast, predictive ETA on the tracking page, ops 7-day demand heatmap),
  subscription-plan usage for *all* in-app deliveries (pickup + depot collection + last mile) and the
  Daily Rider plan, AI draft replies in the support inbox, hardened tracking links (per-token throttles,
  180-day token expiry), and the return of the AI depot POD check (`/ai/receipt/:ref`) which had been
  swallowed inside another handler and never registered. See `docs/GROWTH.md` for the moat strategy.

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

**Who is what.** The owner (the `OWNER_PHONE` secret) is **both superadmin and admin**:
- `admin` — sees and uses every admin surface (`/admin/*`, support inbox, stats, tiers, fraud, security alerts, depot branches, SMS broadcasts).
- `superadmin` — everything `admin` can do, **plus** the owner-only powers: mint/demote `admin` accounts (`POST /admin/users/role`), mint plan codes (`POST /admin/pack-codes`), and manage the depot branches.

**Granting an assistant (e.g. a spouse) admin.** Sign in as the owner → Account → Admin console → *Accounts & roles* → set that email to `admin`. Backend: `POST /admin/users/role {"email":"…","role":"admin"}` — superadmin only; the owner's own row can never be demoted, and plain admins **cannot** mint more admins. Admins can reply into support tickets and see stats; only the owner (superadmin) can manage roles and plan codes.

**In-app console (owner & admins).** Account tab → *Admin console* (visible when `GET /me` says `role: "admin"` or `"ops"`). Shows: last-30-day KPI chips, usage analytics KPI (DAU/funnel), **DropOff Predict — next 7 days** heatmap (branch × pickup window), security alerts, fraud queue, **support inbox** (every ticket with unread count, tap to open the thread), branch manager, SMS broadcast, and (owner-only) Users & roles + plan-code generator.

**Support tickets end-to-end (they do work — here's the whole path).**
1. Seller/anyone signed in in the app → Account → *Chat with DropOff support* → `POST /chat/support` opens/reuses `chat_threads(kind='support')` for their phone.
2. Owner/admin opens the Admin console → *Support inbox* → the ticket shows with unread badge → tap → full history + reply box. **AI draft reply** pre-writes a suggested answer (Workers AI) — edits fine, never auto-sends; you press send. `POST /chat/support/:id/reply` stores the reply as `sender_role='ops'` and pushes the seller a notification.
3. Seller sees the reply in *Inbox → Support thread* (`GET /chat/threads`), or via push.
Tickets live in `chat_threads`/`chat_messages` — inspect with `wrangler d1 execute dropoff-db --remote --command "SELECT kind, count(*) FROM chat_threads GROUP BY kind"`.

**Web console (legacy, still live):** `https://dropoff-api.godfreymoseskalambo.workers.dev/console?key=<ADMIN_AUTH_KEY>`.

**API keys:** `API_AUTH_KEY` = ops/rider devices (`X-Api-Key`), `ADMIN_AUTH_KEY` = owner console
(`X-Admin-Key`, implies superadmin). Never ship these keys inside anything distributed publicly; they are compile-time
`--dart-define`s and the app uses them only when calling the admin API.

The `partner` role (courier shop console) is minted only by `POST /admin/partners` (admin-guarded). Riders get no stored role — a phone registered in `riders` resolves as `role='rider'` automatically.

### Still yours to do
1. **Email sending:** wrangler v4 → `wrangler email sending enable churchonapp.com`; until then reset/verify links return `mail_error` (dev links with `AUTH_DEV_MODE=1`).
2. **SMS OTP:** confirm `SMS_*` secrets are set (`wrangler secret list`); until production SMS is live, rider device-link codes can be watched with `AUTH_DEV_MODE=1` only on a local/dev deployment — never in production.
3. **Lipila live:** `LIPILA_BASE_URL=https://blz.lipila.io` + live key; disbursements need IP whitelisting.
4. **Keystore backup:** `app/android/app/upload-keystore.jks` + password backup — losing it = new app signing on Play.

## 9. Marketing kit (this repo)

`marketing/` — seller & courier email/DM sequences, A5 flyers (HTML → print-to-PDF), WhatsApp broadcast scripts, Facebook ad brief, 4-week launch calendar, promo codes (`FIRSTM10`, `SELLER20`, `LOYAL5`) wired to the live campaign. See `marketing/README.md` for the full index.

## 10. Google Maps are NOT used anywhere

Rider map (`lib/widgets/rider_map.dart`) renders our Church On App R2 PMTiles Zambia basemap (`https://maps.churchonapp.com/zambia.pmtiles`) via `flutter_map` + `vector_map_tiles_pmtiles` — the same source as churchonapp's web maps. Routing/stops are latitude-banded (`/batch/pickup`), not Google Directions. Ops console links to Waze only for navigation (public deep links, no data leaves the device).

## 11. Referral funnel

Sellers get a permanent code (`/refer/code`); a seller who signs up via the code and books becomes **rewarded** — the inviter receives a single-use 20 % promo (`FRIENDxxxxx`). Funnel visible at `/admin/referrals` (superadmin) and KPI tiles on `/console`.

## 12. Where the numbers live

`docs/ECONOMICS.md` — paygo/plan/batch math, rider splits, COD remittance flow, Daily Rider economics. `docs/GROWTH.md` — what makes DropOff trendy, the moat strategy, and the seller-acquisition playbook. `docs/PARTNERSHIP.md` — the partner program. `docs/PARTNER_INTEGRATION.md` — POS/system webhook for partner shops. `docs/PLAY_STORE.md` — store listing copy & release notes. `docs/OPERATIONS.md` — ops runbooks (subscriptions, support inbox, offline re-issue).

## 13. Security notes (post-audit 2026-11-05, hardened 2026-11-07)

- **Rotate the leaked keys now.** The first app build shipped `API_AUTH_KEY` compiled-in; treat
  that key as burned: `npx wrangler secret put API_AUTH_KEY` (and rebuild rider devices with the
  new `--dart-define=DROPOFF_API_KEY=…`). The store/customer build ships **no** key — it authenticates with the JWT only.
- The admin password that was once written here is also burned — reset it via Forgot password.
- Lipila webhooks are **never trusted**: `POST /webhooks/lipila` re-verifies every reported status
  against Lipila's own check-status API before any settlement.
- Password resets bump `token_version` — all older sessions die instantly, OTP or password.
- **Sessions roll, they don't linger.** JWT TTL is 30 days; `POST /auth/refresh` re-issues a fresh 30-day
  JWT for live-or-recent sessions (30-day grace), subject to the same `token_version` revocation. Idle or
  revoked sessions are dead honestly — the app shows the sign-in door, never a broken shell.
- **The JWT mirror lives in SharedPreferences** (plaintext) by design and for reliability: Android keystore
  entries vanish on lock-screen/fingerprint changes. The hardware-backed layer was removed because it silently
  kicked users out every time they re-enrolled a fingerprint. If a hard requirement to encrypt the token at
  rest returns, gate it behind biometrics (the "Fingerprint / face unlock" toggle already does this).
- OTP codes are crypto-random, burn after 5 wrong attempts, and the verify endpoint is IP-throttled.
- Customer app caches are keyed per-account; no cross-user cache leakage on logout.
- **Tracking links are no longer bearer tokens.** `GET /track/:token` answers a phone-verification
  gate (`hint_phone` last-4 only) until the viewer proves a *participant* phone — sender's or
  recipient's — via `POST /track/:token/verify`, which mints an `X-Track-Grant`
  (SHA-256 of `JWT_SECRET:token:phone`). Signed-in participants pass automatically via JWT; staff pass via keys.
  Grants are per-token, checked on every `/track/*` read/chat. Verify + token-chat are throttled **per token**
  (10 and 20 per 10 min respectively) on top of the per-IP buckets, so one leaked grant cannot flood a thread or brute-force the phone hint.
  Newly minted tracking tokens expire after **180 days**; expired tokens 404 everywhere.
- **Media access is prefix-scoped** (2026-11-08): `uploads/selfie/*` serves any signed-in user (sellers see riders); `uploads/kyc/<phone>/*` serves staff or that phone only; everything else under `uploads/` is staff-only. KYC documents never render outside staff/seller-or-admin views; the seller tracking page exposes only the selfie.
- `POST /rider/photo` (rider-only) adds JUST a selfie without touching KYC docs; inline AI review, `fail` demotes a verified rider to `pending` (auto re-review queue), `pass`/`review` keep standing.

- **Recipient identity is enforced, not hinted:** `POST /track/:token/verify` returns `403 phone_does_not_match`
  for wrong numbers. The tracking payload reports `you_are: sender|recipient|staff` so the app can tag the parcel
  "Addressed to you — belongs to your number". Nobody else sees parcel data, rider location or events — never prices.
- `POST /admin/partners` previously required only *a* signed-in session — any customer could self-promote to a
  partner shop for any courier. It now requires `isAdmin` (owner/admin/admin-key).
- `/ai/receipt/:ref` and the rider/admin KYC routes existed in source but were registered inside a handler's
  `catch` block (an unterminated `catch` swallowed the following routes), so they never loaded at module init.
  Fixed 2026-11-07; a route-registration audit (depth>0 scan) now reports zero swallowed routes — re-run it after any large handler edit.
- `POST /track/:token/chat` is grant-gated and both per-IP and per-token throttled; `POST /chat/support` is per-IP throttled and profanity-filtered.

## 14. Who signs up how (and how each role sees its screen)

Everyone signs in through the same Account screen; what they see afterwards is driven by the server role (`GET /me`).

| Role | How they get it | What unlocks |
|---|---|---|
| **Customer / Sender** | App → Account → Create account (email + password + the momo phone). No approval needed. | Home, Bookings, Business tab (Seller dashboard), pay-as-you-go & subscription plans, support chat. |
| **Recipient** | Same flow. Use the **phone the parcel was addressed to** — parcels auto-claim by phone match. | Bookings shows **"Parcels for you"** with live tracking; tracking page tags the parcel "Addressed to you". |
| **Rider** | Ops creates the rider (`POST /admin/riders`) with their phone, OR the rider completes the in-app KYC card (NRC, licence, plate, vehicle details and a **selfie**) and an admin approves (`POST /admin/riders/:id/verify`). The selfie is AI-checked for "one real person's face" before/at review. **Grandfathered riders with no selfie** get a one-tap "Add photo" nudge on their Team tab; the AI reviews it inline and a clear fail demotes them to re-review. Sign-in: Account → phone OTP with that phone. | Team tab → personal rider view (jobs, route, COD, targets, verification status). |
| **Courier partner** | Ops promotes an email account to partner for a depot (`POST /admin/partners {email, courier_id}`, admin-guarded). | Team tab → partner console (counter prices, ride confirms) at `/partner/*`. |
| **Admin** | Owner promotes the email (`Account → Admin console → Users & roles`, or `POST /admin/users/role`). Owner is always admin+superadmin via `OWNER_PHONE`. | Everything above plus stats, security, fraud, support inbox, branches, SMS. |
| **Ops** | Devices/builds configured with `API_AUTH_KEY` (`X-Api-Key`). | Ops console APIs (device service account), not superadmin powers. |

**Tracking for recipients (the full path):**
1. Sender books → Worker mints a tracking token (180-day expiry) → SMS to the recipient: *"Your parcel is on the move — track: APP_URL/track/<token>"*.
2. Recipient taps the link. The page is gated: last-4 phone hint only. They either **sign in / create a DropOff account with the recipient phone**, or enter the number manually (no account; mints a short-lived `X-Track-Grant`).
3. Wrong number → `403 phone_does_not_match`. Right number → status, depot branch, courier, **rider (name, vehicle, selfie photo and a "Verified rider" badge — sellers see the person collecting their parcel)**, last location fix, public event timeline, and a **Predictive ETA** ("Predicted: around tomorrow 10:30 · high confidence", learned from that courier's measured pickup→depot / depot→door history).
4. Parcels also appear under **Bookings → "Parcels for you"** (`GET /track/incoming`) the moment they're booked — no link-pasting needed. Recipients sign up once with their number and every future parcel sent to it appears automatically, tagged "Addressed to you".
5. Recipients can chat about the parcel (grant-gated, per-token throttled) — the sender/rider/depot/ops see the same thread.

**How a seller sees the Seller dashboard:** sign in → bottom tab **Business** (only shown when `linked && !rider`):
plan usage meter, parcels-in-flight, referral link, and **DropOff Predict** (see below).
**How an owner sees Admin:** Account tab → Admin console → everything above; Users & roles is owner-only.
**How a rider sees their queue:** sign in with the rider phone → bottom tab **Team** → personal queue/route/targets.
**How a courier partner sees theirs:** sign in → Team tab → partner list of rides + quote confirms.

## 15. DropOff Predict — the intelligence layer

Explainable heuristics over real job data (no opaque ML, no fake certainty; every number ships with its basis + sample size):

| Surface | Endpoint | What it does |
|---|---|---|
| Predictive ETA (tracking page) | `GET /track/:token` → `predicted` | Where the parcel is vs this courier's measured p50 legs → `eta_minutes`, `arrival_by`, `confidence` (high ≥30 samples, medium ≥8, else low), 180-day lookback. Shown on every verified tracking view. |
| Seller forecast | `GET /predict/seller` | Next-30-day parcel count (least-squares over 6 CAT months blended 50/50 with trailing 3-month average), trend, peak window/weekday, and the cheapest subscription plan that covers the forecast (+ est. savings vs PAYG) and a Daily-Rider-vs-monthly comparison. Shown in Business → DropOff Predict with one-tap plan switch. |
| Delivery IQ (existing) | `GET /iq/eta` | p50/p90/avg minutes pickup→depot for a courier/window — feeds the booking screen card. |
| Ops demand heatmap | `GET /admin/demand-forecast` | Next 7 days per depot branch × pickup window (same weekday+window average of trailing 8 weeks, CAT) — staff planning for sweeps; shown in Admin console → DropOff Predict card. |

All four surfaces are gated exactly like their siblings: predictive ETA rides the tracking grant; `/predict/seller` requires any signed-in identity; `/admin/demand-forecast` requires admin/ops.
`predict` / `forecast` / `IQ` all appear in `workers/src` and docs — grep them to verify coverage.

## 16. Subscription plans & Daily Rider (not "packs")

The subscription product is **subscription plans** — Weekly Sprint K399 (20/7d), Silver K250, Gold K500, Platinum K750 (30-day cycles), and **Daily Rider K49** (1-day cycle, 2 parcels/day included, overage 45% off, on-demand windows including `now`). See `docs/ECONOMICS.md` §2/§5b for economics and `docs/GROWTH.md` for positioning.
Internal identifiers (`_packs`, `redeemPackCode`, `/admin/pack-codes`) keep the old codename; everything user-facing says **plan**.

## 17. 2026-11-08 release (v0.5.0+11) — what changed
- **Collecting parcels works again** (was 500): jobs always need a non-null `sender_name` (NOT NULL column) — both job paths now fall back to the caller's profile name instead of crashing. Hand-rolled API calls get a clear `400 missing_required_fields` instead of a 500.
- **"Remember me" actually works now.** The JWT was dying silently on keystore misses; the token now lives in a resilient SharedPreferences mirror (iOS keychain-equivalent fallback), plus a rolling **`POST /auth/refresh`** (renewable session while alive; 30-day JWT + 30-day grace). A revoked/idle-dead token shows the honest sign-in door instead of a broken shell. Trade-off (intentional): sessions are NOT hardware-encrypted at rest anymore (documented in §13); biometric lock is the sanctioned gate.
- **Biometric app unlock** (Account → Privacy & sign-in → Fingerprint / face unlock): cold start shows a fingerprint/face padlock screen; unlock restores the session instantly — no password re-typing. Biometric success uses the device credential (face / fingerprint / PIN) — `biometricOnly:false` so a failed sensor falls back to PIN, never locks you out. Also extends token TTL from 7 → 30 days.
- **AI KYC identity assist**: the admin AI check now compares the selfie against the ID portrait (licence, or NRC when it carries one) — `{same_person, confidence, note}` via two vision passes + a text-model compare. Header in the dialog: 'AI KYC identity check'. Advisory only — the admin still approves.
- **Web build ships**: `flutter build web` works (plugin graph no longer includes the wasm-breaking `flutter_secure_storage_web`); branded manifest/icons/theme, OG/Twitter share cards. Static host it anywhere (Workers Static Assets, R2/Pages, Cloudflare Pages).
- **iOS prep**: bundle id `zm.dropoff.dropoff` (already), `NSFaceIDUsageDescription`, and a standard CocoaPods Podfile — macOS + Xcode still required to compile; not built on this Windows host.
- **`tools/build_release.ps1`**: every release build starts with `flutter clean` — no more stale artifacts.
- **Devices signed in**: Account → Privacy & sign-in → **Devices signed in** shows every device tied to this account (last seen, IP best-effort) and lets you revoke any of them. Newly bound `device_id` survives app restarts; verified phones register it via `/me/devices`; the app sends `X-Device-Id` on every request so revoke takes effect immediately. Sign-out on other devices is one tap.

## 18. 2026-11-08 release (v0.4.3+10) — what changed
- **Universal profile photos**: every account (customer, sender, recipient, seller, rider, partner, admin)
  can upload one avatar — Account → tap the circle (or Add photo). It syncs from `auth_users.photo_url`
  (0044) via `GET /me` → shown on Account, in every chat bubble (signed in users), and on support tickets
  (assignees see the customer's face). Riders' avatars also land on `riders.photo_url` (that's the photo
  sellers see on tracking). Photos live in the `uploads/selfie/` namespace (any signed-in user), KYC
  documents stay `uploads/kyc/<phone>/` staff-or-owner only. `DELETE /me/photo` removes back to initials.
  Inline AI review — a clear "fail" demotes a *verified rider* to re-review; pass/review keeps standing.
- Rider "Add photo" nudge on Team tab when no selfie on file (0.4.1).
- Support: ticket list/detail shows customer avatar + AI draft reply (0.4.1 support).

## 19. 2026-11-07 release (v0.4.0+7) — what changed
- Recipient accounts + auto-claimed "Parcels for you" + tracking "Addressed to you" tag + Claim CTA.
- Tracking hardened: 180-day token expiry, per-token verify/chat throttles, JWT-participant grants, `/admin/partners` admin-guard.
- DropOff Predict: seller forecast, predictive ETA, ops demand heatmap, one-tap plan switch from Business.
- Plans: Daily Rider K49 launched; plan allowance now covers pickups, depot collections→door and last-mile legs (one slot per parcel, per-day meter for daily plans).
- Support: AI draft replies (never auto-send), ticket copy-phone, unread badges; confirmed end-to-end.
- Fixed: `/ai/receipt/:ref` (AI depot POD) and six co-swallowed routes registered again; `/rider/profile` KYC flow reachable.
- Home: tagline under the wordmark renders full-width (no more cut-off).
- "pack" → "subscription plan" across all user-facing copy (app, store listing, legal docs).

## 20. Growth, trendiness & the moat
See **`docs/GROWTH.md`** — seller-acquisition playbook, retention flywheel, what makes DropOff share-worthy, and the four moats (density, data, trust, plan lock-in) with the 90-day action list.
