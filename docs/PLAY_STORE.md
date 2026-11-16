# Play Store release checklist

App id: `zm.dropoff.dropoff` - current version `0.5.29+40` (`pubspec.yaml`).

## 1. Upload keystore (one-time)

Never commit the keystore or `key.properties`.

```powershell
cd DropOff\app\android
keytool -genkey -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 `
  -validity 10000 -alias upload
```

Create `android/key.properties`:

```properties
storePassword=...
keyPassword=...
keyAlias=upload
storeFile=upload-keystore.jks
```

`build.gradle.kts` uses this automatically for release builds; without it the
build falls back to the debug key and **Play will reject the upload**.

Store the keystore + passwords in a password manager and a sealed offline copy.
Losing it means you can never update the app under the same listing.

## 2. Build the bundle

```powershell
powershell -File tools\build_release.ps1
```

(cleans first, runs analyze/test, builds APK + AAB, copies to `dist/`)

Output: `dist/DropOff-<version>-release.aab` (matches `pubspec.yaml`).

Do **not** pass `DROPOFF_API_KEY` in a store build — the ops key must never ship
to customers. Only `DROPOFF_API_URL` belongs in the Play build.

## 3. Privacy policy (live URL)

Play requires a working HTTPS privacy policy URL for every account type that
can be created without a URL. It is served by the Worker:

> **https://dropoff-api.godfreymoseskalambo.workers.dev/legal/privacy**

(`workers/src/legal.ts` — edit there if the policy changes; `app/assets/legal/privacy.md`
mirrors its in-app copy.)

## 4. Play Console — production channel, step by step

1. **Create the app**: name **DropOff**, default language English (United
   Kingdom), *App*, *Free*. Zambian package name `zm.dropoff.dropoff`.
2. **App content -> Privacy policy**: paste the URL above.
   - **Ads**: none. **Data safety**: fill as below.
   - **Content rating questionnaire**: *Utility / Tools* (parcel logistics —
     no violence, no gambling, no user-generated content that is public-facing
     except courier reviews, which are moderated).
   - **Target audience**: 18+ (addresses, payments, KYC).
   - **App access**: all functionality works from the front screen; the admin
     console is internal — use the "restricted access" declaration and provide
     an ops demo login + office phone.
   - **Government apps**: no. **Financial features**: none beyond payments —
     DropOff charges for delivery, it is not a lending/wallet product.
3. **Data safety** answers (matching the live policy):
   - Collected: *name, email, phone number, precise location (rider devices,
     shared live during an active job), physical address (pickup/drop),
     photos (rider selfie / KYC / delivery proof), device or other IDs (device
     session + FCM token).* Payment info: transaction references only — play
     does not process it.
   - Purpose: app functionality, fraud prevention/handover verification,
     support. Data is encrypted in transit. Data deletion: sign-out/unlink
     removes device data; email support@carpsosolutions.store for account
     deletion.
   - Not sold, not shared with third parties beyond the courier chosen and
     Lipila.
4. **Store listing -> Production** (copy section below).
5. **Countries**: Zambia (plus any market the pricebook covers).
6. **Release production**:
   - *Promote track -> Production, countries -> Zambia, release name
     "0.5.29 (40) — Held bookings unmissable + fully in-app map"*.
   - Upload `dist/DropOff-0.5.29-release.aab` into a NEW production release.
   - Choose **staged rollout 10%** first (small user base: 10% of <100 is
     statistically silent — either pick 10% for caution or 100% given testers
     already validated 0.5.0; for a first production release, 100% in Zambia
     is acceptable).
   - Add release notes (below), publish.
7. **App signing**: first upload enrols you in Play App Signing automatically —
   the upload key above signs, Play holds the signing key. Export it via
   *Setup -> App signing* and keep the account email/phone verified
   (`godfreymoseskalambo@gmail.com`).

## 5. Store listing copy

### Title (30 chars max)
```
DropOff: Parcel Pickup Zambia
```

### Short description (80 chars max)
```
Book trusted local riders, drop at your courier depot, track every parcel live.
```

### Full description (<= 4000 chars)
```
DropOff is Zambia's first-mile parcel marketplace: a rider you can see and
trust collects your parcel at your door and drops it at YOUR nominated courier
depot branch, with live tracking, photo proof, chat, and a handover code that
makes false-parcel claims impossible.

WHY SELLERS USE DROPOFF
* Door pickup in Zambian cities — Lusaka's 6:00/10:00/14:00 sweeps or an
  instant ride, tomorrow slots included.
* One place for every courier — Platinum, Mercury, DHL, One World, Icypeed,
  Rovert, Falcon and more. Counter fares are heard at the depot — we never
  publish them or quote them; you pay exactly what the receipt says.
* Handover protection: your parcel recipient gets a 4-digit DropOff code by
  SMS; the delivery only completes when that code is entered. Photos are
  filed at pickup and at handover.
* Live tracking: follow your rider on the map, or share a no-account tracking
  link with your customer by SMS/WhatsApp.
* Direct chat with your rider and support inside every job.
* City-to-city legs run entirely by your chosen courier — DropOff gets your
  parcel to their counter and confirms it was handed in with photographic
  evidence.

SIMPLE, TRANSPARENT PAYMENTS
* Every parcel is prepaid by mobile money at booking — a prepayment for your
  parcel delivery (trip price + processing fee), never more. No cash, ever:
  your rider never handles your money. Cancel before pickup and the unspent
  prepayment returns to your momo automatically.
* In-app receipts, plus a full booking history per parcel.

FOR RIDERS
* Slot-batched task queues, a nearest-neighbour route, targets and daily
  stats, salaried pay (never collecting customer cash), and pay-outs
  to your mobile money.
* Fast KYC: selfie + NRC + plate photos, AI-checked, you ride while review
  completes.

FOR BUSINESSES AND COURIERS
* Subscription packs: bundle parcels on Weekly or Monthly plans.
* Team accounts, admin consoles, POS/partner webhooks so any storefront can
  push parcels into the DropOff network.

BUILT FOR ZAMBIA
* Works on 3G, sized for every Android phone, English/isiNyanja-friendly
  copy, payments in Kwacha and no foreign dependencies.

Download DropOff and get your parcel moving today.
Questions? support@carpsosolutions.store
```

### Screenshots to capture (phone, 1080x1920 minimum)
1. Home screen with the slot chips (06:00 / 10:00 / 14:00 / Tomorrow).
2. Booking form with a parcel + total row.
3. Rider tracking map with the rider photo card ("Verified rider").
4. Ratings + plan card from the Business tab.
5. Recipient tracking page (SMS link) showing handover code hint.
6. Task queue (rider) with proof-of-delivery dialog.

### Release notes (0.5.32+42)
```
* Signed-in errors simply report in. Unhandled app errors now report
  themselves to DropOff (anonymous, deduped) so crashes get fixed fast —
  no action needed from you.
* Admins can edit a user's details — set or fix a customer's email so they
  can sign in with password, or update their name. Admin-only and audited.
* Zambian phone numbers fixed (ZICTA's 2024 plan: 057 Airtel, 056 MTN,
  055 Zamtel, Beeline 058/078/098 all accepted).
* Bookings held for prepayment show "Booking held — payment pending"
  one tap away on My Bookings. No rider until it clears.
* DropOff runs its own map — live rider tracking, recipient tracking and
  rider navigation, all in-app. No Waze or Google Maps links.
* Simplified release — English only; the phone settings now cover
  everything. Stability and polish throughout.
```

## 6. Verify before promoting

- Fresh install from the testing track, not a local build.
- Register → OTP arrives → book a prepaid (momo) job → prompt approved →
  rider dispatched → recipient receives the tracking SMS
  WITH the 4-digit handover code.
- Mark a delivery as the assigned rider **without** the code → server rejects
  (`otp_required`); with the code → delivered.
- Rating flow only appears on completed, server-dispatched bookings.
- Push: requires `FIREBASE_SERVICE_ACCOUNT` on the Worker; verify a real device
  receives "Rider assigned".
- Payments: run one real small Lipila collect against the production Worker and
  confirm the receipt endpoint and webhook state.
- Check `X-Request-Id` on a failing request and find it in Workers Logs.

## 7. Rollout

- Internal → Closed (10–20 riders and depots) → Production staged rollout 10% →
  50% → 100%, watching crash-free sessions and payment failures.
- Keep the previous AAB so you can halt and roll back.
- Bump `version` in `pubspec.yaml` for every upload (`build` number must increase).

## 8. Known release blockers

- Play rejects debug-signed bundles — section 1 is mandatory.
- FCM push stays disabled until the Worker secret is set.
- `flutter build appbundle` uses the machine's Java 17; install Temurin 17 if the
  Gradle step fails.

## 9. What is new in 0.5.32+42

- **DropOff is now English-only** — the ny/bem/toi/loz catalogue (ARB files,
  generated l10n classes, `l10n.yaml`, `flutter_localizations`/`intl`, the
  in-app language picker, `locale_pref` sync) is fully removed. Fewer
  ambiguous machine-translation surfaces; single canonical copy.
- **Admin edit user details** — Accounts & roles → pencil on a
  non-admin row → full name + email. Emails set by an admin are marked
  verified (admin attestation), so the number can sign in with password
  immediately; server refuses edits to the master admin account and to other
  admin rows, and checks uniqueness before saving.
- **Client crash reporting, in-house** — unhandled app errors post to
  `/client/error` (rate-limited, deduped per device+stack) — visible in
  admin console "Client crashes".

Engineering notes carried over from the previous waves: ZICTA 2024 numbering,
one admin role, audit-restore drill completed, 5xx D1 ledger + admin SMS on
storms, Africa's Talking STOP honoured, terms live, `/legal/terms`.

- **Deletes are staff-only** — customers cannot delete a booking; a
  "Request deletion" one-tap opens support chat with the ref prefilled.
  Admins delete bookings in the console (soft delete; payments and audit
  kept); deleting an account is admin-only and removes sessions, push
  tokens and the auth row (history kept). The admin account is refused.
- **Truth in UI** — waybill/depot receipt appears only after payment;
  Delivery IQ shows measured p50/p90 with n≥5 only (advertised fallback
  hidden); counter-fare wording matches the depot.
- **Soft-delete for jobs** — every user-facing listing (sender timeline,
  recipient incoming, tracking token resolve) filters out `status='deleted'`.
- Typo scale (AppType) across the app; EmptyState redesigned; help copy
  moved behind "?" in help sheets.

Historical (0.5.1+12, 0.5.26+37 and earlier) highlights: handover codes +
proof of delivery, Tidy address pinning, algorithmic rider dispatch,
plan caps for day-cycles, Live Lipila collect with pending-prompt display,
tracking lock for unpaid bookings, payment reminders pause/resume,
admin bearer-key gates on every /admin route, `/admin/jobs/:ref/delete`
and `/admin/users/:phone` endpoints.
