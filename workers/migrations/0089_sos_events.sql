-- SOS alerts (owner 2026-11-24): a rider in trouble pings every other rider.
CREATE TABLE IF NOT EXISTS sos_events (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  rider_phone TEXT NOT NULL,
  rider_name TEXT,
  lat REAL,
  lng REAL,
  city TEXT,
  note TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  resolved_at TEXT
);
CREATE INDEX IF NOT EXISTS idx_sos_events_created ON sos_events(created_at);