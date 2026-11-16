# DropOff — production ops runbook
**2026-11-16 · owner-facing**

Everything here is written so an on-call human can do it with the phone and a laptop, no special access needed from the DropOff team.

---

## Where things run
- **Worker** (API, crons): `https://dropoff-api.godfreymoseskalambo.workers.dev` — Cloudflare Workers, D1 (SQLite), R2 buckets `dropoff-backups` + R2 for photos.
- **App**: Flutter Android (Play Store, `zm.dropoff.dropoff`), web build in `dist/web/`.
- **Payments**: Lipila (`blz.lipila.io`), callback URL wired: `/webhooks/lipila`.
- **SMS**: Africa's Talking, username `ChurchOnApp`, sender `Carpso`. **Sender ID registration with AT is unverified** — if SMS stop landing, check AT dashboard first.

## Monitors (all free)
1. UptimeRobot (free): new HTTP(s) monitor → `https://dropoff-api.godfreymoseskalambo.workers.dev/health` → 5-minute interval → email + WhatsApp alerts (own account).
2. Cloudflare Workers Logs: `Workers → dropoff-api → Logs` — real-time tail; retention is short (hours on this plan); forward to Logpush only if on the paid tier.
3. `/admin/client-crashes` (admin console → "Client crashes" card) — app crashes for the last 24h, deduped. Any row that recurs on the same build = halt rollout.
4. `error_events` (D1) — every unhandled server error, counted. The evening cron (19:00 UTC) pages the admin SMS when > 15 in 24h (once per day).

## Daily check — 60 seconds
1. `/health` 200?
2. Console → "Client crashes" — zero unexpected rows?
3. Console → alerts — nothing open?
4. Console → Payroll — yesterday's rider disbursement confirmed?

## Weekly check — 10 minutes
1. Deliveries this week vs. subscriptions active (admin stats card).
2. `quotes` learning rate — new counter fares learned?
3. One real test booking on your own phone (book → courier delivers a test parcel → confirm delivered + OTP works) or watch any live job to completion.
4. `wrangler d1 execute dropoff-db --remote --command="SELECT COUNT(*) FROM job_events WHERE created_at > datetime('now','-7 days')"` — sanity on volume.

## Crash triage (app)
1. Open admin console → "Client crashes" → find the message/stack.
2. Map version (`v0.5.29+40`) → the matching commit → fix → rebuild → **new versionCode** → upload → monitor the next 24h row count on each build.
3. No stack? The message alone + app_version is usually enough (null-check NPEs etc.).

## 5xx / silent failure
1. Console → nothing visible? Check `error_events` via:
   `wrangler d1 execute dropoff-db --remote --command="SELECT path, status, message, created_at FROM error_events ORDER BY id DESC LIMIT 10"`
2. "Dead pipeline" SMS means: active packs exist but zero deliveries in 48h — check dispatch (`/admin/jobs/:ref` queue health), Lipila webhooks, and the rider queue door (a rider account disabled?).
3. Recovery: fix → `wrangler deploy` → watch the next 19:00 cron's silence as confirmation.

## Backup & restore (tested 2026-11-16)
**Backups:** daily 02:00 UTC cron writes gzipped JSONL of 12 tables (`auth_users`, `jobs`, `payments`, `wallets`, `wallet_ledger`, `subscriptions`, `recurring_plans`, `referrals`, `riders`, `couriers`, `quotes`, `job_events`) to R2 `dropoff-backups`, under `backups/<YYYY-MM-DD CAT>/`. Manifest: `backups/<date>/manifest.json` listing what succeeded.

**Restore drill** (do this yearly or before any risky migration):
```bash
# download latest backup set
npx wrangler r2 object get dropoff-backups/backups/<DATE>/manifest.json --remote --file=manifest.json
# create a scratch DB
npx wrangler d1 create dropoff-restore-test
# replay all migrations (see .scale_tmp/replay_migrations3.ps1 for the loop)
# generate INSERTs from JSONL (same row order/escaping), e.g. .scale_tmp/restore_gen.mjs
# restore each table, count rows vs the JSONL line counts, drop the scratch DB
npx wrangler d1 delete dropoff-restore-test
```
**2026-11-16 drill result:** manifest intact (12/12 tables, 0 skipped; 328 rows backed up). Scratch restore verified by row counts (auth_users 32, jobs 11, payments 7, job_events 48, riders 6, couriers 39, quotes 150). Scratch DB deleted. Backup is **restorable as documented**.

Caveats: backup = business entities only. Not backed up: R2 photo payloads (`dropoff-*` prefix buckets), chat DOs, migrations metadata. If you lose the DB, photos still exist but jobs/payments return from JSONL. Add `delivery-dod` snapshots (media) when budget allows.

## Deploys
`cd workers && npx wrangler deploy` — uploads the Worker + re-checks crons.
`tools/build_release.ps1` — flutter clean → pub get → analyze → test → APK + AAB + web into `dist/`.
**Never** edit code while a build runs. Commit → build → dist swap → verify → push.

## Secrets
`wrangler secret put <NAME>` — set from the machine, never committed. Current secret set: see `wrangler.toml` comment block + `wrangler secret list`.

Notable: `ORS_API_KEY` **unset** (routing proxy 503s by design until you host the router — `infra/router/README.md`); `MESSAGING` SMS key is `AT_API_KEY`. Audit any `wrangler secret list` difference against last-known-good once a month.

## Known weak points (do not forget)
- Africa's Talking sender ID registration (Carpso) — unverified in production.
- Lipila production webhook = real money. Test first with K1.
- Reviewers test on real phones: rider GPS + camera capture + FCM — the three flows that only fail on device.
- Keystore: if you build from a new machine, you need `upload-keystore.jks` + `key.properties` (gitignored; keep both offline). Losing the upload key = the listing can never update — treat as password-of-passwords.
- When in doubt: revert = one `git revert` + rebuild + upload; keep the previous AAB to halt rollouts.
