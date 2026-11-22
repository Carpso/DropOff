-- 0078 — additive sweep-run manifest for rider sequencing/audit.
-- Jobs remain the source of truth for proof, payment, status and custody.
-- This layer records the planned run order per rider/slot/date so dispatch
-- and mid-run insertion decisions are explicit and auditable.

CREATE TABLE IF NOT EXISTS sweep_runs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  rider_id INTEGER NOT NULL,
  rider_phone TEXT NOT NULL,
  run_date TEXT NOT NULL,
  slot TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'active',
  vehicle_class TEXT,
  capacity INTEGER,
  stop_count INTEGER NOT NULL DEFAULT 0,
  parcel_count INTEGER NOT NULL DEFAULT 0,
  minutes_on_road INTEGER NOT NULL DEFAULT 0,
  generated_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_sweep_runs_rider_slot_date ON sweep_runs(rider_id, run_date, slot);
CREATE INDEX IF NOT EXISTS idx_sweep_runs_phone_date ON sweep_runs(rider_phone, run_date, status);

CREATE TABLE IF NOT EXISTS sweep_run_stops (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  run_id INTEGER NOT NULL,
  seq INTEGER NOT NULL,
  kind TEXT NOT NULL,
  label TEXT,
  lat REAL,
  lng REAL,
  depot_name TEXT,
  courier_name TEXT,
  eta_min INTEGER,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  FOREIGN KEY(run_id) REFERENCES sweep_runs(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_sweep_run_stops_run ON sweep_run_stops(run_id, seq);

CREATE TABLE IF NOT EXISTS sweep_run_items (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  run_id INTEGER NOT NULL,
  stop_id INTEGER NOT NULL,
  job_id INTEGER,
  job_ref TEXT NOT NULL,
  action TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending',
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  FOREIGN KEY(run_id) REFERENCES sweep_runs(id) ON DELETE CASCADE,
  FOREIGN KEY(stop_id) REFERENCES sweep_run_stops(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_sweep_run_items_run ON sweep_run_items(run_id);
CREATE INDEX IF NOT EXISTS idx_sweep_run_items_ref ON sweep_run_items(job_ref);

CREATE TABLE IF NOT EXISTS sweep_run_decisions (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  run_id INTEGER,
  rider_id INTEGER,
  job_ref TEXT,
  decision TEXT NOT NULL, -- inserted|deferred|rolled_next_run|reoptimized
  reason TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_sweep_run_decisions_run ON sweep_run_decisions(run_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_sweep_run_decisions_ref ON sweep_run_decisions(job_ref, created_at DESC);
