-- DropOff 0002: timed pickup windows + seller subscription packs (Daily/Pro)

ALTER TABLE jobs ADD COLUMN pickup_window TEXT NOT NULL DEFAULT 'now';
-- 'now' = on-demand, or a scheduled sweep window: '06:00' / '10:00' / '14:00'

CREATE TABLE IF NOT EXISTS subscriptions (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  phone TEXT NOT NULL UNIQUE,        -- sender phone, 260XXXXXXXXX
  sender_name TEXT,
  tier TEXT NOT NULL,                -- 'silver' (K350/mo) | 'gold' (K700/mo) | 'platinum' (K1500/mo)
  city TEXT NOT NULL,                -- pickup city, e.g. Lusaka
  pickup_window TEXT NOT NULL,       -- default sweep slot: 06:00 / 10:00 / 14:00
  status TEXT NOT NULL DEFAULT 'active',  -- active / cancelled / expired
  started_at TEXT NOT NULL DEFAULT (datetime('now')),
  expires_at TEXT,                   -- renews via Lipila monthly bill in phase 2
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_subscriptions_phone ON subscriptions(phone, status);
