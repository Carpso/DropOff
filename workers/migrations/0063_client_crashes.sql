-- 0063: client-side crash telemetry + server-side error events.
-- Why: the app shipped with zero visibility into production crashes. The
-- worker logs requests for hours then expires them; the app reported nothing.
-- This table set gives us: per-build crash digest (deduped by stack+device),
-- and a countable 5xx record for the daily health probe.
CREATE TABLE IF NOT EXISTS client_crashes (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  message TEXT NOT NULL,
  stack TEXT,
  platform TEXT,
  app_version TEXT,
  user_phone TEXT,
  device_id TEXT,
  dedupe_key TEXT NOT NULL,
  count INTEGER NOT NULL DEFAULT 1,
  first_seen_at TEXT NOT NULL DEFAULT (datetime('now')),
  last_seen_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_client_crashes_dedupe ON client_crashes(dedupe_key);
CREATE INDEX IF NOT EXISTS idx_client_crashes_last_seen ON client_crashes(last_seen_at);

CREATE TABLE IF NOT EXISTS error_events (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  req_id TEXT,
  method TEXT,
  path TEXT,
  status INTEGER,
  message TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_error_events_at ON error_events(created_at);
