-- Refund / settlement payout engine (owner 2026-11-20). Adapted from the
-- Chisomo (Kingdom Sponsor) guarded auto-disburse pattern: a durable payout
-- ledger with idempotent references, atomic claims, bounded retries with a
-- 30-minute backoff, and webhook/status reconciliation. No per-parcel rider
-- payout — riders remain salaried. Money is ZMW kwacha, 2 decimals.
CREATE TABLE IF NOT EXISTS payouts (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  kind TEXT NOT NULL DEFAULT 'refund',        -- refund | settlement | fee_sweep
  payment_id INTEGER,                        -- source payment for a refund
  job_id INTEGER,
  phone TEXT NOT NULL,
  amount_zmw REAL NOT NULL,
  reference TEXT NOT NULL UNIQUE,            -- idempotency key (random suffix)
  lipila_identifier TEXT,
  status TEXT NOT NULL DEFAULT 'queued',     -- queued | processing | pending | success | failed
  attempts INTEGER NOT NULL DEFAULT 0,
  max_attempts INTEGER NOT NULL DEFAULT 8,
  next_attempt_at TEXT NOT NULL DEFAULT (datetime('now')),
  last_error TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now')),
  settled_at TEXT
);
CREATE INDEX IF NOT EXISTS idx_payouts_due ON payouts(status, next_attempt_at);
CREATE INDEX IF NOT EXISTS idx_payouts_source ON payouts(payment_id, kind);

-- Gateway audit log: every outbound collection/disbursement attempt and the
-- normalized status that came back. Mirrors Chisomo's lipila_logs.
CREATE TABLE IF NOT EXISTS lipila_logs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  kind TEXT NOT NULL,                        -- collection | disbursement
  reference TEXT NOT NULL,
  phone TEXT,
  amount_zmw REAL NOT NULL,
  status TEXT NOT NULL,                      -- pending | success | failed
  message TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_lipila_logs_reference ON lipila_logs(reference);
