-- Ratings quality: verified-delivery flag, moderation/hide switch, and user
-- reports. Hidden comments drop out of public averages; admins can review.
ALTER TABLE ratings ADD COLUMN verified INTEGER NOT NULL DEFAULT 1;
ALTER TABLE ratings ADD COLUMN hidden INTEGER NOT NULL DEFAULT 0;
ALTER TABLE ratings ADD COLUMN report_reason TEXT;
ALTER TABLE ratings ADD COLUMN reported_at TEXT;

CREATE TABLE IF NOT EXISTS rating_reports (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  rating_id INTEGER NOT NULL REFERENCES ratings(id),
  reporter_phone TEXT,
  reason TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_rating_reports_rating ON rating_reports(rating_id);
