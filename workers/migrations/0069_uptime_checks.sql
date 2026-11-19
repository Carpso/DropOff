-- Uptime monitor history (Cloudflare Cron every 5 minutes). Gives us an
-- UptimeRobot-style record and down/recovery alerts without an external account.
CREATE TABLE IF NOT EXISTS uptime_checks (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  checked_at TEXT NOT NULL DEFAULT (datetime('now')),
  ok INTEGER NOT NULL,
  status INTEGER NOT NULL DEFAULT 0,
  latency_ms INTEGER NOT NULL DEFAULT 0,
  detail TEXT
);
CREATE INDEX IF NOT EXISTS idx_uptime_checks_time ON uptime_checks(checked_at);
