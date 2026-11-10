-- 0053: push_broadcasts — marketing/announcement push log (mirrors sms_broadcasts).
CREATE TABLE IF NOT EXISTS push_broadcasts (
  id              INTEGER PRIMARY KEY AUTOINCREMENT,
  sender          TEXT NOT NULL,
  audience        TEXT NOT NULL,            -- all | accounts | sellers | subscribers | riders
  title           TEXT NOT NULL,
  body            TEXT NOT NULL,
  recipient_count INTEGER NOT NULL DEFAULT 0,
  sent_count      INTEGER NOT NULL DEFAULT 0,
  created_at      TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_push_broadcasts_created ON push_broadcasts(created_at DESC);
