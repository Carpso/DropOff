-- 0032: admin/superadmin SMS communication + marketing, with an audit trail.
CREATE TABLE IF NOT EXISTS sms_broadcasts (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  sender TEXT,                        -- admin identity: owner phone or 'admin-key'
  audience TEXT NOT NULL,             -- single | all | accounts | sellers | subscribers
  recipient_count INTEGER NOT NULL DEFAULT 0,
  sent_count INTEGER NOT NULL DEFAULT 0,
  body TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_sms_broadcasts_created ON sms_broadcasts(created_at);
