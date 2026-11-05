# DropOff Operations Runbook

Everything below assumes:

```powershell
cd DropOff\workers
```

API: `https://dropoff-api.godfreymoseskalambo.workers.dev`
D1: `dropoff-db` (id `1100c702-d4c2-4114-8926-7e113350ad17`)
R2: `dropoff-backups`

## 1. Deploy

```powershell
npx tsc --noEmit
npx vitest run
npx wrangler d1 migrations apply dropoff-db --remote
npx wrangler deploy
```

Verify after every deploy:

```powershell
curl.exe https://dropoff-api.godfreymoseskalambo.workers.dev/health
```

## 2. Secrets

Set once per environment with `npx wrangler secret put <NAME>`:

| Secret | Purpose | If missing |
| --- | --- | --- |
| `FIREBASE_SERVICE_ACCOUNT` | FCM push notifications | Push is a safe no-op |
| `SENTRY_DSN` | Error forwarding to Sentry | Errors only in Workers Logs |
| `LIPILA_WEBHOOK_SECRET` | Reject unsigned payment webhooks | Header check skipped |
| `API_AUTH_KEY` | Ops/rider service key | Device calls fall back to JWT |

`FIREBASE_SERVICE_ACCOUNT` is the full JSON of a service-account key for
`dropoff-zambia-adminsdk@dropoff-zambia.iam.gserviceaccount.com`. Create it in
Google Cloud Console → IAM → Service Accounts → Keys → Add key → JSON, then:

```powershell
Get-Content .\dropoff-zambia-adminsdk.json -Raw | npx wrangler secret put FIREBASE_SERVICE_ACCOUNT
npx wrangler deploy
```

## 3. Edge rate limiting (Cloudflare WAF)

The Worker already enforces per-IP buckets in D1 (`rate_hits`). Add cheap edge
rules in **Cloudflare dashboard → Security → WAF → Rate limiting rules** so
abusive traffic never reaches D1:

| Rule | Expression | Rate | Action |
| --- | --- | --- | --- |
| OTP request | `http.request.method eq "POST" and http.request.uri.path eq "/auth/request"` | 10 / 1 min per IP | Block 10 min |
| Create job | `http.request.method eq "POST" and http.request.uri.path eq "/jobs"` | 60 / 1 hour per IP | Managed Challenge |
| Create payment | `http.request.method eq "POST" and http.request.uri.path eq "/payments"` | 30 / 1 hour per IP | Managed Challenge |
| Auth verify | `http.request.method eq "POST" and http.request.uri.path eq "/auth/verify"` | 20 / 10 min per IP | Block 10 min |

Turn off "Block" for rules that could hit shared NAT (offices, cyber cafés) if
you see false positives; Managed Challenge is the safer default.

## 4. Scale path

Current shape: one Worker + one D1 database + R2 for backups. It comfortably
handles low-thousands of bookings/day. Move up in this order as load grows:

1. **Offload side effects to Queues** (`dropoff-notify`): SMS, FCM, and receipt
   emails are already wrapped in `waitUntil`; move them into a queue consumer
   when send volume starts adding latency or hitting provider limits.
2. **Read caching at the edge**: `/couriers`, `/cities`, `/quotes`, `/plans`
   already send `s-maxage` + `stale-while-revalidate=0`; keep TTLs short and
   rely on Cache API rules for public GETs only. Never cache `/jobs/*`,
   `/payments/*`, or `/track/*` at the edge (they are `private, no-store`).
3. **D1 read replicas / Sessions API** when read latency dominates; route
   catalog reads with `withSession('first-primary')` and keep writes on primary.
4. **Durable Objects for rider location** if per-second location updates become
   the bottleneck: one DO per active city, batched writes back to D1.
5. **Shard by city** only after 4 — separate D1 databases per operating region,
   with the catalog duplicated per shard.
6. **Queue + Workflow for payouts** so Lipila disbursement retries are durable
   and never tied to a single request lifetime.

Load-test before each step with `tools/k6-smoke.js` (read-only) and a staging
key for write paths.

## 5. Observability

- Every response carries `X-Request-Id` (Cloudflare Ray ID when present) and
  emits a JSON access log line with `req_id`, `path`, `status`, `ms`, `ip`.
- Workers Logs query examples:
  - Errors: `level = "error"`
  - Slow requests: `ms > 1500`
  - One request: `req_id = "<id>"`
- Configure **Logpush** to R2 or your SIEM if you need retention beyond the
  dashboard window.
- Set `SENTRY_DSN` to forward 5xx exceptions; the Worker never fails a request
  because Sentry is down.
- Payment sweeper `reconcilePayments` runs on the 5-minute style cron path and
  closes stale `pending` rows; check for `payment_reconcile_failed` logs.

## 6. Backups and restore drill

Nightly cron writes JSONL gzip per table to R2 under
`backups/YYYY-MM-DD/<table>.jsonl.gz` plus `manifest.json`.

Manual backup:

```powershell
node scripts/backup-now.mjs
```

Restore into a scratch database (never straight into production):

```powershell
node scripts/restore-backup.mjs --date 2026-11-05 --config wrangler.drill.toml --apply --clean
```

Validate row counts against `manifest.json`, then swap traffic only after a
clean drill. Insert order is parent-first; delete order is reverse.

## 7. Incident playbook

**Payments stuck in pending**
1. `GET /payments/:id/receipt` with admin key to inspect state.
2. Let the reconciler run; if still stuck, call `POST /admin/payments/:id/refund`
   only after confirming the customer was actually charged.
3. Never mark `paid` by hand without a Lipila reference.

**Webhook spam / forged callbacks**
- Set `LIPILA_WEBHOOK_SECRET`; the handler checks `X-Lipila-Signature` or
  `X-Webhook-Secret` when configured, and always re-verifies with Lipila before
  crediting.

**Fraud flags piling up**
- `GET /admin/fraud?status=open`
- `POST /admin/fraud/:id/review` with `{"status":"cleared"}` or `"confirmed"`.
- Confirmed jobs keep `review_required = 1`; the job itself is not cancelled.

**Suspected data loss**
- Stop writes (`wrangler deploy` a maintenance flag or WAF block on POSTs),
  restore the latest backup into a scratch DB, diff, then backfill.

## 8. Known gaps

- No customer accounts for recipients by design: tracking is token/SMS only.
- Firebase push requires the service-account secret above.
- Cloudflare WAF rules in section 3 must be created in the dashboard; the API
  does not have zone access.
