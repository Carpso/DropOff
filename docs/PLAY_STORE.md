# Play Store release checklist

App id: `zm.dropoff.dropoff` - current version `0.5.0+11` (`pubspec.yaml`).

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

## 7. What is new in 0.5.0+11

- **Sessions that actually stay signed in** - rolling refresh (JWT 30d + grace) and a resilient token
  mirror. No more random "sign in again every time I leave".
- **Biometric unlock** (Account -> Privacy & sign-in) - use your fingerprint/face to open the app.
- **Bug fix: booking a collection** no longer fails silently - it now books or shows a precise error.
- **iOS prep** (Podfile, Face ID permission) and a **web build** ready for hosting.


- **Every account can now have a photo** — riders, sellers, recipients, courier partners, admins.
  Your avatar shows on your account, in chat bubbles, and to support agents. Rider selfies now AI-
  checked (documents, screenshots and memes are rejected automatically).

## 7a. 0.4.2+9
- Riders can add one selfie from the Team tab without re-submitting KYC; AI reviews it inline.
- Media access is prefix-scoped: rider selfies visible to signed-in users, KYC docs staff-only.

## 7b. 0.4.1+8 (build 8)
- Rider selfies show to sellers on the tracking page (with a 'Verified rider' badge),
  and every upload is AI-reviewed for being one genuine person's face.
- Everything from 0.4.0: recipient auto-claimed parcels, DropOff Predict, Daily
  Rider plan, subscription-plan usage across all normal deliveries.
