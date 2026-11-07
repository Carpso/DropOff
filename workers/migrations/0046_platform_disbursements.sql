-- Platform revenue sweep ledger.
-- Every successful payment contributes platform_fee_zmw + lipila_fee_zmw to
-- the Lipila wallet (the money sits there as DropOff's income). This table
-- records each sweep disbursement of that accumulated income to the business
-- momo (BUSINESS_PHONE). A sweep is idempotent-safe: SUM(fees) - SUM(this
-- table's success rows) is always the undistributed balance.
CREATE TABLE IF NOT EXISTS platform_disbursements (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  amount_zmw REAL NOT NULL,             -- exact amount swept to BUSINESS_PHONE
  business_phone TEXT NOT NULL,         -- 260XXXXXXXXX destination
  lipila_reference TEXT,                 -- Lipila ref when the disbursement went out
  status TEXT NOT NULL DEFAULT 'pending',  -- pending / success / failed
  note TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  paid_at TEXT
);
CREATE INDEX IF NOT EXISTS idx_platform_disbursements_status
  ON platform_disbursements (status, created_at);
