#!/usr/bin/env node
// Manual backup: dump every app table from D1 to JSONL, gzip it, and upload to
// the R2 BACKUPS bucket under backups/<CAT-date>/<table>.jsonl.gz — the same
// layout the nightly Worker cron writes. Useful before a risky migration and as
// the source for restore drills.
//
//   node scripts/backup-now.mjs [--db dropoff-db] [--bucket dropoff-backups] [--date YYYY-MM-DD] [--local]
import { execFileSync } from 'node:child_process';
import { gzipSync } from 'node:zlib';
import { writeFileSync, mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const args = Object.fromEntries(
  process.argv.slice(2).reduce((acc, cur, i, arr) => {
    if (cur.startsWith('--')) acc.push([cur.slice(2), arr[i + 1] && !arr[i + 1].startsWith('--') ? arr[i + 1] : true]);
    return acc;
  }, []),
);
const db = String(args.db ?? 'dropoff-db');
const bucket = String(args.bucket ?? 'dropoff-backups');
const remote = args.local ? [] : ['--remote'];
const cfg = args.config ? ['--config', String(args.config)] : [];
const date = String(args.date ?? new Date(Date.now() + 2 * 3600_000).toISOString().slice(0, 10));
const tables = ['auth_users', 'jobs', 'payments', 'wallets', 'wallet_ledger', 'subscriptions',
  'recurring_plans', 'referrals', 'riders', 'couriers', 'quotes', 'job_events'];

const npx = process.platform === 'win32' ? 'npx.cmd' : 'npx';
const quote = (a) => {
  const s = String(a);
  return /[\s&|<>^()]/.test(s) ? `"${s}"` : s;
};
const wrangler = (argv) => execFileSync([npx, 'wrangler', ...argv, ...cfg].map(quote).join(' '), {
  encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'], maxBuffer: 128 * 1024 * 1024,
  shell: true,
});

const dir = mkdtempSync(join(tmpdir(), 'dropoff-backup-'));
const manifest = { date, ok: [], skipped: [], generated_at: new Date().toISOString() };
try {
  for (const table of tables) {
    try {
      const raw = wrangler(['d1', 'execute', db, ...remote, '--json', '--command', `SELECT * FROM ${table}`]);
      const rows = JSON.parse(raw)?.[0]?.results ?? [];
      const jsonl = rows.map((r) => JSON.stringify(r)).join('\n') + (rows.length ? '\n' : '');
      const file = join(dir, `${table}.jsonl.gz`);
      writeFileSync(file, gzipSync(Buffer.from(jsonl, 'utf8')));
      const key = `backups/${date}/${table}.jsonl.gz`;
      wrangler(['r2', 'object', 'put', `${bucket}/${key}`, `--file=${file}`, '--content-type=application/gzip']);
      manifest.ok.push(key);
      console.log(`ok   ${table}: ${rows.length} rows -> ${key}`);
    } catch (e) {
      manifest.skipped.push(table);
      console.error(`skip ${table}: ${String(e.stderr ?? e.message).trim().slice(0, 200)}`);
    }
  }
  const mf = join(dir, 'manifest.json');
  writeFileSync(mf, JSON.stringify(manifest, null, 2));
  try { wrangler(['r2', 'object', 'put', `${bucket}/backups/${date}/manifest.json`, `--file=${mf}`, '--content-type=application/json']); } catch {}
  console.log(`done: ${manifest.ok.length} tables backed up, ${manifest.skipped.length} skipped (date ${date})`);
} finally {
  rmSync(dir, { recursive: true, force: true });
}
