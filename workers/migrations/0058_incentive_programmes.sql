-- 0058: Rider incentive programmes — admin/superadmin runs them as promos
-- with a title ("Christmas Bonus", "Weekend sprint") that can toggle on/off
-- without a deploy and without touching the salaried model.
CREATE TABLE IF NOT EXISTS incentive_programmes (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  title TEXT NOT NULL,                -- "Christmas Bonus", "Year-End Sprint"…
  starts_on TEXT,                     -- ISO date or NULL = always-on while enabled
  ends_on TEXT,                       -- ISO date or NULL
  completion_bonus_zmw REAL NOT NULL DEFAULT 200,
  per_extra_parcel_zmw REAL NOT NULL DEFAULT 5,
  per_extra_cap INTEGER NOT NULL DEFAULT 135,
  stretch_ratio REAL NOT NULL DEFAULT 1.25,
  stretch_bonus_zmw REAL NOT NULL DEFAULT 150,
  active INTEGER NOT NULL DEFAULT 1,
  note TEXT,
  created_by TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_incentive_active ON incentive_programmes(active);
