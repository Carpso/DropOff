-- 0051: chat moderation — Play UGC compliance (report, block, escalation).
-- Message reports feed the admin console queue; blocking hides a participant's
-- messages per-viewer; strikes auto-suspend abusive senders after 3 hits.
CREATE TABLE IF NOT EXISTS chat_reports (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  message_id INTEGER NOT NULL REFERENCES chat_messages(id),
  thread_id INTEGER NOT NULL REFERENCES chat_threads(id),
  reported_by TEXT NOT NULL,             -- participant phone (never ops)
  reason TEXT,                           -- harassment | spam | other (+ free text)
  status TEXT NOT NULL DEFAULT 'open',   -- open | actioned | dismissed
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_chat_reports_status ON chat_reports(status, id);
CREATE INDEX IF NOT EXISTS idx_chat_reports_message ON chat_reports(message_id);

-- Viewer-side block list: a participant can hide another participant's
-- messages for themselves only. Ops/system senders can never be blocked.
CREATE TABLE IF NOT EXISTS user_blocks (
  blocker TEXT NOT NULL,
  blocked TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  PRIMARY KEY (blocker, blocked)
);
CREATE INDEX IF NOT EXISTS idx_user_blocks_blocked ON user_blocks(blocked);

-- Abuse escalation: 3 blocked/profanity attempts or confirmed reports
-- auto-suspend chat sending for 7 days (suspended_until datetime).
CREATE TABLE IF NOT EXISTS chat_strikes (
  phone TEXT PRIMARY KEY,
  strikes INTEGER NOT NULL DEFAULT 0,
  suspended_until TEXT,
  updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_chat_strikes_suspended ON chat_strikes(suspended_until);

-- Hidden messages: admin-confirmed abuse disappears from every viewer.
ALTER TABLE chat_messages ADD COLUMN hidden INTEGER NOT NULL DEFAULT 0;
