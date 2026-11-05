-- Push-device registration for FCM (job status + payment pushes to senders).
CREATE TABLE IF NOT EXISTS push_tokens (
  token   TEXT PRIMARY KEY,
  phone   TEXT NOT NULL,
  platform TEXT NOT NULL DEFAULT 'android',
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  last_seen   TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_push_tokens_phone ON push_tokens (phone);
