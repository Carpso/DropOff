-- DropOff D1 schema (SQLite)

CREATE TABLE IF NOT EXISTS couriers (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,                -- Platinum, Mercury, Rivert, One World, Icypeed, DHL
  city TEXT NOT NULL,                -- depot city, e.g. Lusaka
  depot_name TEXT NOT NULL,          -- e.g. "Platinum Chibolya"
  lat REAL,
  lng REAL,
  active INTEGER NOT NULL DEFAULT 1
);

CREATE TABLE IF NOT EXISTS quotes (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  courier_id INTEGER NOT NULL REFERENCES couriers(id),
  from_city TEXT NOT NULL,
  to_city TEXT NOT NULL,
  weight_class TEXT NOT NULL,        -- e.g. "0-5kg", "5-15kg", "15kg+"
  counter_price_zmw REAL NOT NULL,   -- what the depot charges (from the chargebook)
  service TEXT NOT NULL,             -- standard / overnight / same_day
  updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS riders (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  phone TEXT NOT NULL UNIQUE,        -- 260XXXXXXXXX
  full_name TEXT NOT NULL,
  vehicle TEXT NOT NULL,             -- bike / trimoto / car
  active INTEGER NOT NULL DEFAULT 1,
  last_lat REAL,
  last_lng REAL,
  last_seen_at TEXT
);

CREATE TABLE IF NOT EXISTS jobs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  ref TEXT NOT NULL UNIQUE,          -- e.g. DRO-2026-000123
  sender_phone TEXT NOT NULL,        -- 260XXXXXXXXX
  sender_name TEXT NOT NULL,
  pickup_address TEXT NOT NULL,
  pickup_lat REAL, pickup_lng REAL,
  courier_id INTEGER NOT NULL REFERENCES couriers(id),
  recipient_name TEXT NOT NULL,
  recipient_phone TEXT NOT NULL,     -- 260XXXXXXXXX
  dest_city TEXT NOT NULL,
  dest_city_to_depot INTEGER NOT NULL DEFAULT 0,  -- "leg-2" door delivery in recipient city?
  description TEXT NOT NULL,
  weight_class TEXT NOT NULL,
  counter_price_zmw REAL NOT NULL,   -- collected package price recorded by the driver
  rider_fee_zmw REAL NOT NULL,
  leg2_fee_zmw REAL NOT NULL DEFAULT 0,
  total_zmw REAL NOT NULL,           -- (counter + rider + leg2)
  pickup_time TEXT,                  -- now / express / scheduled time
  status TEXT NOT NULL DEFAULT 'created',
    -- created -> rider_assigned -> picked_up -> at_depot -> departed
    -- -> arrived -> (delivered | ready_for_collection)
  rider_id INTEGER REFERENCES riders(id),
  courier_waybill TEXT,              -- entered after paying at the courier counter
  dropoff_photo_url TEXT,            -- proof of drop-off
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS job_events (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  job_id INTEGER NOT NULL REFERENCES jobs(id),
  status TEXT NOT NULL,
  note TEXT,
  lat REAL, lng REAL,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS payments (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  job_id INTEGER NOT NULL REFERENCES jobs(id),
  phone TEXT NOT NULL,               -- 260XXXXXXXXX
  provider TEXT NOT NULL,            -- airtel / mtn / zamtel
  amount_zmw REAL NOT NULL,
  lipila_reference TEXT,             -- reference from the Lipila response
  status TEXT NOT NULL DEFAULT 'pending',   -- pending / success / failed
  channel TEXT NOT NULL DEFAULT 'merchant', -- merchant (Push-to-pay) / collect
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  paid_at TEXT
);

CREATE TABLE IF NOT EXISTS wallets (
  phone TEXT PRIMARY KEY,            -- 260XXXXXXXXX
  balance_zmw REAL NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS wallet_ledger (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  phone TEXT NOT NULL REFERENCES wallets(phone),
  amount_zmw REAL NOT NULL,          -- + top-up / job payout, - spend
  kind TEXT NOT NULL,                -- topup / job_payment / rider_payout / refund
  job_id INTEGER REFERENCES jobs(id),
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_jobs_sender   ON jobs(sender_phone, status);
CREATE INDEX IF NOT EXISTS idx_jobs_status   ON jobs(status, dest_city);
CREATE INDEX IF NOT EXISTS idx_payments_ref  ON payments(lipila_reference);
CREATE INDEX IF NOT EXISTS idx_quotes_route  ON quotes(from_city, to_city, service);

-- Seed depots (counter prices are daily-captured by ops / riders)
INSERT INTO couriers (name, city, depot_name, lat, lng) VALUES
  ('Platinum', 'Lusaka', 'Platinum Chibolya (Ben Bella Rd)', -15.4255, 28.2805),
  ('Platinum', 'Kitwe',  'Platinum Kitwe (Kabengele Ave)',   -12.8100, 28.2100),
  ('Mercury Express Logistics', 'Lusaka', 'Mercury Longacres', -15.4140, 28.3230),
  ('Icypeed Logistics', 'Lusaka', 'Icypeed Libala (Kalundu)', -15.4380, 28.2500),
  ('Icypeed Logistics', 'Kitwe',  'Icypeed Parklands',        -12.8009, 28.2104),
  ('One World', 'Lusaka', 'One World Rhodes Park',           -15.4060, 28.3170);
