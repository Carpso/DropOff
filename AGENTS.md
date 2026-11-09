# AGENTS.md — DropOff repo guide for coding agents

## Play Store versioning (mandatory)

Every upload to Google Play **must** use a **strictly higher `versionCode`** than every previously uploaded build — Play Console rejects duplicates (`Version code N has already been used`).

- Version lives in `app/pubspec.yaml` as `version: <semver>+<versionCode>` (e.g. `0.5.2+13`).
- **For every Play Store submission, increment BOTH**:
  - `versionCode` (`+N` → `+N+1`) — required at minimum for each new upload, even for hotfixes;
  - `version` (`x.y.z`) — bump by convention (patch/minor/major).
- Before building a Play artifact:
  1. Open `app/pubspec.yaml`, read the current `versionCode`.
  2. Increase it by 1.
  3. Rebuild via `tools/build_release.ps1` (always `flutter clean` first; script handles `flutter pub get`, versioned artifact copy from pubspec).
  4. Commit with a message like `Release 0.5.2+13` (or `Bump versionCode to 13`).
- Never reuse a `versionCode`, even locally or on internal/track builds. Released Play version codes are immutable in effect.
- `dist/DropOff-<version>-release.apk|.aab` names come from this script; don’t hand-rename.
- `dist/` artifacts are the upload source of truth; do not upload stale builds.
- **Release artifacts only**: `dist/` never carries debug or profile builds. Every artifact copied there must come from a release build path (`tools/build_release.ps1`).
- **Clean `dist/` on each build**: after copying a new release pair into `dist/`, delete the previous versioned `DropOff-<version>-release.apk|.aab` so `dist/` only ever holds the current release plus `DropOff-release.apk|.aab` (unversioned alias of the latest). Never leave superseded version pairs for upload or inspection.

## Repo conventions

- Always `flutter clean` before a release build (build_release.ps1 does).
- No invented courier/depot fares; rates are shown only when publicly verified, otherwise “quoted at counter”.
- Courier/rider partner money is never collected by DropOff; the depot fare is paid at the counter.
- Cover is **quoted protection, not insurance**, until legal/commercial sign-off; never market as insured.
- SMS stays English-only until user locale is applied; TOI = Tonga (Zambia) / Chitonga.
- Ops/admin endpoints are gated (`isAdmin` = admin key | role=admin | owner phone). Never ship `DROPOFF_API_KEY`/`ADMIN_AUTH_KEY` in store builds.
