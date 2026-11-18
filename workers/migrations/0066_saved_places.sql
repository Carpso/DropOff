-- Server-owned address book (owner 2026-11-18): places that were searched,
-- pinned or used for a booking are stored against the signed-in phone so the
-- collection grows across devices and can populate the in-app map. Local
-- storage in the app stays as the offline mirror.
CREATE TABLE IF NOT EXISTS saved_places (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  phone TEXT NOT NULL,
  label TEXT NOT NULL,
  lat REAL,
  lng REAL,
  source TEXT NOT NULL DEFAULT 'app',
  used_at TEXT NOT NULL DEFAULT (datetime('now')),
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  UNIQUE(phone, label)
);
CREATE INDEX IF NOT EXISTS idx_saved_places_phone ON saved_places(phone);
