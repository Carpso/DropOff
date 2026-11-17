-- 0063: payments.job_id must be nullable. Wallet top-ups, plan subscriptions,
-- counter fares and K1 payment-rails test rows have no booking behind them;
-- the NOT NULL inherited from 0001 made every such INSERT fail (including
-- POST /admin/test-collect, which inserts job_id = NULL by design).
CREATE TABLE payments_new (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  job_id INTEGER REFERENCES jobs(id),
  phone TEXT NOT NULL,               -- 260XXXXXXXXX
  provider TEXT NOT NULL,            -- airtel / mtn / zamtel
  amount_zmw REAL NOT NULL,
  lipila_reference TEXT,             -- reference from the Lipila response
  status TEXT NOT NULL DEFAULT 'pending',   -- pending / success / failed
  channel TEXT NOT NULL DEFAULT 'merchant', -- merchant (Push-to-pay) / collect
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  paid_at TEXT,
  subscription_id INTEGER,
  settled INTEGER NOT NULL DEFAULT 0,
  kind TEXT NOT NULL DEFAULT 'job',
  credit_zmw REAL NOT NULL DEFAULT 0,
  platform_fee_zmw REAL NOT NULL DEFAULT 0,
  lipila_fee_zmw REAL NOT NULL DEFAULT 0,
  refund_of_payment_id INTEGER,
  refunded_at TEXT,
  meta TEXT,
  paused_at TEXT
);
INSERT INTO payments_new (id, job_id, phone, provider, amount_zmw, lipila_reference, status, channel, created_at, paid_at, subscription_id, settled, kind, credit_zmw, platform_fee_zmw, lipila_fee_zmw, refund_of_payment_id, refunded_at, meta, paused_at)
  SELECT id, job_id, phone, provider, amount_zmw, lipila_reference, status, channel, created_at, paid_at, subscription_id, settled, kind, credit_zmw, platform_fee_zmw, lipila_fee_zmw, refund_of_payment_id, refunded_at, meta, paused_at FROM payments;
DROP TABLE payments;
ALTER TABLE payments_new RENAME TO payments;
CREATE INDEX IF NOT EXISTS idx_payments_ref ON payments(lipila_reference);
CREATE INDEX IF NOT EXISTS idx_payments_refund_of ON payments(refund_of_payment_id);
CREATE INDEX IF NOT EXISTS idx_payments_status_created ON payments(status, created_at);
