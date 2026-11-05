-- Round-trip bookings, scheduled/timed pickups and explicit last-mile legs.
-- All additive: existing pay-as-you-go jobs keep working unchanged.
ALTER TABLE jobs ADD COLUMN round_trip INTEGER NOT NULL DEFAULT 0;
ALTER TABLE jobs ADD COLUMN return_city TEXT;
ALTER TABLE jobs ADD COLUMN return_address TEXT;
ALTER TABLE jobs ADD COLUMN return_leg_fee_zmw REAL NOT NULL DEFAULT 0;
ALTER TABLE jobs ADD COLUMN pickup_at TEXT;        -- ISO-8601 scheduled pickup (CAT)
ALTER TABLE jobs ADD COLUMN last_mile INTEGER NOT NULL DEFAULT 0; -- mirror of dest_leg2 for UI clarity

CREATE TABLE IF NOT EXISTS scheduled_pickups (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  job_ref     TEXT NOT NULL,
  phone       TEXT NOT NULL,
  rider_phone TEXT,
  pickup_at   TEXT NOT NULL,
  status      TEXT NOT NULL DEFAULT 'pending',   -- pending | notified | assigned | missed | completed
  notified_at TEXT,
  created_at  TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_scheduled_pickups_at ON scheduled_pickups(pickup_at, status);
CREATE INDEX IF NOT EXISTS idx_jobs_pickup_at ON jobs(pickup_at);
CREATE INDEX IF NOT EXISTS idx_jobs_round_trip ON jobs(round_trip);
