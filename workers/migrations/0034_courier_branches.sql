-- 0034: courier branches (admin-managed, Lusaka-first) + which depot branch a
-- seller's rider delivers to; jobs carry the branch name.
CREATE TABLE IF NOT EXISTS courier_branches (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  courier_id INTEGER NOT NULL REFERENCES couriers(id),
  name TEXT NOT NULL,                -- e.g. 'Longacres branch'
  city TEXT NOT NULL DEFAULT 'Lusaka',
  address TEXT,
  lat REAL,
  lng REAL,
  phone TEXT,
  active INTEGER NOT NULL DEFAULT 1,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_courier_branches_courier ON courier_branches(courier_id, active);

-- One-shot: SQLite has no ADD COLUMN IF NOT EXISTS. Already applied on prod
-- (jobs.branch present); skip on re-run against a live database.
ALTER TABLE jobs ADD COLUMN branch TEXT;
