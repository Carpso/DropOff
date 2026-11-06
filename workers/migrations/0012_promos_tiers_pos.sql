-- 0012: editable tiers with promo tags + promo codes + partner POS rails + live rider location.
CREATE TABLE IF NOT EXISTS tiers (
  tier TEXT PRIMARY KEY,
  fee_zmw REAL NOT NULL,
  parcels_per_day INTEGER NOT NULL,
  rider_fee_zmw REAL NOT NULL DEFAULT 0,
  tag TEXT,                          -- e.g. 'Most popular', 'PROMO 20% OFF' — shown on the packs
  active INTEGER NOT NULL DEFAULT 1
);
INSERT OR IGNORE INTO tiers (tier, fee_zmw, parcels_per_day, rider_fee_zmw, tag) VALUES
  ('silver', 250, 1, 0, NULL),
  ('gold', 500, 3, 0, 'Most popular'),
  ('platinum', 750, 10, 0, NULL);

CREATE TABLE IF NOT EXISTS promo_codes (
  code TEXT PRIMARY KEY,
  discount_pct REAL NOT NULL DEFAULT 0,   -- whole percent off the DropOff leg
  note TEXT,
  applies_tier TEXT,                       -- NULL = any; e.g. 'silver' restricts to pack
  uses_left INTEGER,                       -- NULL = unlimited
  expires_at TEXT,
  active INTEGER NOT NULL DEFAULT 1,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE TABLE IF NOT EXISTS promo_uses (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  code TEXT NOT NULL,
  phone TEXT NOT NULL,
  job_id INTEGER,
  used_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Partner self-declared collection rails (their own POS / momo / WhatsApp business).
-- DropOff NEVER custodies partner funds; sellers pay partners directly at the depot/POS.
CREATE TABLE IF NOT EXISTS partner_pos (
  courier_id INTEGER PRIMARY KEY REFERENCES couriers(id),
  rail TEXT NOT NULL,                 -- momo | bank | pos_terminal | whatsapp | cash
  merchant_id TEXT,                   -- till/merchant/momo number
  instructions TEXT,                  -- e.g. "Send K110 to 0960000000, ref = waybill"
  active INTEGER NOT NULL DEFAULT 1,
  updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Per-partner webhook keys: ANY POS/e-commerce/dispatch system can push parcel
-- status into our attempt timeline with one POST + this key.
CREATE TABLE IF NOT EXISTS partner_keys (
  courier_id INTEGER PRIMARY KEY REFERENCES couriers(id),
  api_key TEXT NOT NULL UNIQUE,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- (riders.last_lat / last_lng / last_seen_at already exist on the live schema)
