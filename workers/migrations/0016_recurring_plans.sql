-- 0016: recurring/standing parcel plans — weekly/biweekly/monthly sweeps at an owner's depot door.
CREATE TABLE IF NOT EXISTS recurring_plans (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  phone TEXT NOT NULL,
  dest_city TEXT NOT NULL,
  weight_class TEXT NOT NULL DEFAULT '0-5kg',
  recipient_name TEXT,
  recipient_phone TEXT,
  description TEXT,
  pickup_address TEXT,
  frequency TEXT NOT NULL DEFAULT 'weekly',    -- weekly | biweekly | monthly
  weekday INTEGER,                             -- 1=Mon … 7=Sun (NULL = any/daily for premium)
  active INTEGER NOT NULL DEFAULT 1,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS recurring_plans_phone ON recurring_plans(phone, active);
