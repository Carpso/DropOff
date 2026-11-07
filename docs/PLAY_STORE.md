# Play Store release checklist

App id: `zm.dropoff.dropoff` - current version `0.4.0+7` (`pubspec.yaml`).

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
cd DropOff\app
flutter clean; flutter pub get
flutter build appbundle --release `
  --dart-define=DROPOFF_API_URL=https://dropoff-api.godfreymoseskalambo.workers.dev
```

Output: `build/app/outputs/bundle/release/app-release.aab`.

Do **not** pass `DROPOFF_API_KEY` in a store build — the ops key must never ship
to customers. Only `DROPOFF_API_URL` belongs in the Play build.

## 3. Play Console setup

1. Create the app (name **DropOff**, default language English, app/game: App,
   free).
2. **App content**:
   - Privacy policy URL (host `assets/legal/privacy.md` on a public page).
   - Data safety: collect phone number, name, approximate location (rider
     devices), delivery addresses; data is used for app functionality; no
     selling; deletion request contact.
   - Ads: no. Content rating questionnaire: utility/transport.
   - Target audience 18+ (payments and addresses).
3. **Permissions declaration**: location is only requested on rider/ops flows;
   explain "live rider tracking during an active delivery". Background location
   is not used.
4. **Store listing**: use `marketing/` assets; screenshot the booking flow,
   tracking page, and ratings.
5. Upload the AAB to **Internal testing** first.

## 4. Verify before promoting

- Fresh install from the testing track, not a local build.
- Register → OTP arrives → book a cash job → recipient receives the tracking SMS.
- Rating flow only appears on completed, server-dispatched bookings.
- Push: requires `FIREBASE_SERVICE_ACCOUNT` on the Worker; verify a real device
  receives "Rider assigned".
- Payments: run one real 1 ZMW Lipila collect against the production Worker and
  confirm the receipt endpoint and webhook state.
- Check `X-Request-Id` on a failing request and find it in Workers Logs.

## 5. Rollout

- Internal → Closed (10–20 riders and depots) → Production staged rollout 10% →
  50% → 100%, watching crash-free sessions and payment failures.
- Keep the previous AAB so you can halt and roll back.
- Bump `version` in `pubspec.yaml` for every upload (`build` number must increase).

## 6. Known release blockers

- Play rejects debug-signed bundles — section 1 is mandatory.
- FCM push stays disabled until the Worker secret is set.
- `flutter build appbundle` uses the machine's Java 17; install Temurin 17 if the
  Gradle step fails.

## 7. What's new in 0.4.0+7 (2026-11-07)

- **You can now track parcels sent to you** — sign up with the phone your parcel was
  addressed to and every incoming parcel appears automatically ("Parcels for you").
  Tracking links now require proof that you own that number; strangers with the link see nothing.
- **DropOff Predict** — the app learns each courier's real speed and shows a predicted
  arrival on the tracking page, and the Business tab forecasts your next 30 days
  (with the plan that fits best).
- **Plans, not packs** — introduce the Daily Rider (K49/day) next to Weekly Sprint and
  monthly plans; subscription plan benefits now cover every delivery you book.
- Reliability fixes: chat/support tickets now reliably reachable, and the AI depot
  proof-of-delivery check is back.

Data safety reminder: the app requests no background location; rider location is
collected only during active deliveries shown on the map.
