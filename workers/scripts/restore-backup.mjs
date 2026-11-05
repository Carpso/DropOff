#!/usr/bin/env node
// Restore a nightly/manual backup from R2 into a D1 database. Builds portable
// INSERT statements from the JSONL dumps (no sqlite3 binary needed) and can
// apply them straight to a scratch D1 for a restore drill.
//
//   # generate SQL only (inspect before applying)
//   node scripts/restore-backup.mjs --date 2026-11-05 --target dropoff-restore-drill --out ./restore.sql
//
//   # restore drill: wipe + reload a scratch DB and print row counts
//   node scripts/restore-backup.mjs --date 2026-11-05 --target dropoff-restore-drill --apply --clean
//
// NOTE: never point --apply at the production DB unless you mean it.
import { execFileSync } from 'node:child_process';
import { gunzipSync } from 'node:zlib';
import { writeFileSync, readFileSync, mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const args = Object.fromEntries(
  process.argv.slice(2).reduce((acc, cur, i, arr) => {
    if (cur.startsWith('--')) acc.push([cur.slice(2), arr[i + 1] && !arr[i + 1].startsWith('--') ? arr[i + 1] : true]);
    return acc;
  }, []),
);
const date = args.date ? String(args.date) : '';
if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) {
  console.error('usage: node scripts/restore-backup.mjs --date YYYY-MM-DD [--target DB] [--bucket B] [--out file.sql] [--apply] [--clean] [--local]');
  process.exit(1);
}
const bucket = String(args.bucket ?? 'dropoff-backups');
const target = String(args.target ?? 'dropoff-restore-drill');
const remote = args.local ? [] : ['--remote'];
const cfg = args.config ? ['--config', String(args.config)] : [];
const tables = ['auth_users', 'jobs', 'payments', 'wallets', 'wallet_ledger', 'subscriptions',
  'recurring_plans', 'referrals', 'riders', 'couriers', 'quotes', 'job_events'];
// Parents before children so INSERT OR REPLACE satisfies foreign keys.
const insertOrder = ['auth_users', 'wallets', 'riders', 'couriers', 'quotes', 'subscriptions',
  'recurring_plans', 'referrals', 'jobs', 'payments', 'wallet_ledger', 'job_events'];
const deleteOrder = [...insertOrder].reverse();

const npx = process.platform === 'win32' ? 'npx.cmd' : 'npx';
const quote = (a) => {
  const s = String(a);
  return /[\s&|<>^()]/.test(s) ? `"${s}"` : s;
};
const wrangler = (argv) => execFileSync([npx, 'wrangler', ...argv, ...cfg].map(quote).join(' '), {
  encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'], maxBuffer: 256 * 1024 * 1024,
  shell: true,
});

function literal(value) {
  if (value === null || value === undefined) return 'NULL';
  if (typeof value === 'number') return Number.isFinite(value) ? String(value) : 'NULL';
  if (typeof value === 'boolean') return value ? '1' : '0';
  if (typeof value === 'object') value = JSON.stringify(value);
  return `'${String(value).replace(/'/g, "''")}'`;
}

function statementsFor(table, rows) {
  if (!rows.length) return '';
  const cols = [...new Set(rows.flatMap((r) => Object.keys(r)))].filter((c) => /^[A-Za-z_][A-Za-z0-9_]*$/.test(c));
  const colList = cols.map((c) => `"${c}"`).join(', ');
  return rows.map((row) => `INSERT OR REPLACE INTO "${table}" (${colList}) VALUES (${cols.map((c) => literal(row[c])).join(', ')});`).join('\n');
}

const dir = mkdtempSync(join(tmpdir(), 'dropoff-restore-'));
const sections = [];
if (args.clean) for (const t of deleteOrder) sections.push(`DELETE FROM "${t}";`);
const counts = {};
try {
  for (const table of tables) {
    const file = join(dir, `${table}.jsonl.gz`);
    try {
      wrangler(['r2', 'object', 'get', `${bucket}/backups/${date}/${table}.jsonl.gz`, `--file=${file}`]);
      const text = gunzipSync(readFileSync(file)).toString('utf8');
      const rows = text.split('\n').filter(Boolean).map((line) => JSON.parse(line));
      const sql = statementsFor(table, rows);
      if (sql) sections.push(sql);
      counts[table] = rows.length;
      console.log(`read ${table}: ${rows.length} rows`);
    } catch (e) {
      counts[table] = 'missing';
      console.log(`skip ${table}: no object for ${date} (${String(e.stderr ?? e.message).trim().slice(0, 120)})`);
    }
  }
  const sql = sections.join('\n') + '\n';
  if (args.out) { writeFileSync(String(args.out), sql); console.log(`wrote ${args.out}`); }

  if (args.apply) {
    const file = join(dir, 'restore.sql');
    writeFileSync(file, sql);
    console.log(`applying to ${target}${args.local ? ' (local)' : ' (remote)'}…`);
    wrangler(['d1', 'execute', target, ...remote, '--yes', '--file=' + file]);
  for (const table of insertOrder) {
      const raw = wrangler(['d1', 'execute', target, ...remote, '--json', '--command', `SELECT COUNT(*) AS n FROM ${table}`]);
      const n = JSON.parse(raw)?.[0]?.results?.[0]?.n ?? 0;
      console.log(`verify ${table}: ${n} rows (backup ${counts[table]})`);
    }
  }
} finally {
  rmSync(dir, { recursive: true, force: true });
}
