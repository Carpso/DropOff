-- Fraud controls: jobs can be flagged for ops review without blocking the
-- customer outright (false positives are cheap to clear, chargebacks are not).
ALTER TABLE jobs ADD COLUMN review_required INTEGER NOT NULL DEFAULT 0;
ALTER TABLE jobs ADD COLUMN fraud_score INTEGER NOT NULL DEFAULT 0;

CREATE TABLE IF NOT EXISTS fraud_flags (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  job_id INTEGER NOT NULL REFERENCES jobs(id),
  job_ref TEXT NOT NULL,
  phone TEXT,
  score INTEGER NOT NULL,
  reasons TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'open',   -- open | cleared | confirmed
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  reviewed_at TEXT,
  reviewer TEXT
);

CREATE INDEX IF NOT EXISTS idx_fraud_flags_status ON fraud_flags(status);
CREATE INDEX IF NOT EXISTS idx_fraud_flags_phone ON fraud_flags(phone);
