-- Community POI layer (owner 2026-11-24, "growing location").
-- Every completed job's pickup/depot coords become a shared, named pin.
-- Riders name them on filing; all riders in that city see them (Waze model).
CREATE TABLE IF NOT EXISTS community_pois (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  city TEXT NOT NULL,
  name TEXT NOT NULL,
  lat REAL NOT NULL,
  lng REAL NOT NULL,
  source TEXT NOT NULL DEFAULT 'rider',
  created_by TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  upvotes INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS idx_community_pois_city ON community_pois(city);
CREATE INDEX IF NOT EXISTS idx_community_pois_name ON community_pois(name);