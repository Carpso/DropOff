-- 0038: bulk pack codes (sold offline / by agents) + recipient door address.
-- NOTE: plain ALTERs (D1 has no ADD COLUMN IF NOT EXISTS); duplicate-column
-- errors are safe to ignore when re-applied.
CREATE TABLE IF NOT EXISTS pack_codes (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  code TEXT NOT NULL UNIQUE,
  tier TEXT NOT NULL,
  cycle_days INTEGER NOT NULL DEFAULT 30,
  note TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  used_by TEXT,
  used_at TEXT
);
CREATE INDEX IF NOT EXISTS idx_pack_codes_used ON pack_codes (used_by);
ALTER TABLE jobs ADD COLUMN dest_address TEXT;
