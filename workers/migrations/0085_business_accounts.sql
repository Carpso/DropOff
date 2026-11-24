-- Step 6: Business accounts v1
CREATE TABLE IF NOT EXISTS business_accounts (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  owner_phone TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'active',
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_business_owner ON business_accounts(owner_phone);

CREATE TABLE IF NOT EXISTS business_members (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  business_id INTEGER NOT NULL,
  phone TEXT NOT NULL,
  role TEXT NOT NULL DEFAULT 'member', -- owner|admin|member|bookkeeper
  spend_limit_zmw REAL,
  status TEXT NOT NULL DEFAULT 'active', -- active|invited|removed
  invited_by TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  UNIQUE(business_id, phone)
);
CREATE INDEX IF NOT EXISTS idx_business_members_phone ON business_members(phone, status);
CREATE INDEX IF NOT EXISTS idx_business_members_biz ON business_members(business_id, status);

CREATE TABLE IF NOT EXISTS business_addresses (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  business_id INTEGER NOT NULL,
  label TEXT NOT NULL,
  lat REAL,
  lng REAL,
  address TEXT,
  created_by TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_business_addresses_biz ON business_addresses(business_id);

CREATE TABLE IF NOT EXISTS business_audit_log (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  business_id INTEGER NOT NULL,
  actor_phone TEXT,
  action TEXT NOT NULL,
  target_type TEXT,
  target_id TEXT,
  meta_json TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_business_audit_biz ON business_audit_log(business_id, id DESC);

ALTER TABLE jobs ADD COLUMN business_id INTEGER;
ALTER TABLE payments ADD COLUMN business_id INTEGER;
CREATE INDEX IF NOT EXISTS idx_jobs_business ON jobs(business_id, id DESC);
CREATE INDEX IF NOT EXISTS idx_payments_business ON payments(business_id, id DESC);