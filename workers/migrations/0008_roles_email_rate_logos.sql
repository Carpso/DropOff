-- 0008: partner/admin roles on email accounts, email tokens (verify/reset),
-- per-IP rate limiting, courier logos for the app's courier list.

ALTER TABLE auth_users ADD COLUMN role TEXT NOT NULL DEFAULT 'customer'; -- customer | partner | admin
ALTER TABLE auth_users ADD COLUMN email_verified INTEGER NOT NULL DEFAULT 0;
ALTER TABLE auth_users ADD COLUMN courier_id INTEGER;                     -- partner shop → courier row

CREATE TABLE IF NOT EXISTS email_tokens (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  email       TEXT NOT NULL,
  token_hash  TEXT NOT NULL,
  kind        TEXT NOT NULL,             -- verify_email | reset_password
  used        INTEGER NOT NULL DEFAULT 0,
  expires_at  TEXT NOT NULL,             -- verify 24h · reset 1h
  created_at  TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_email_tokens_email ON email_tokens(email, kind);

-- naive per-IP throttle: key like 'ip:1.2.3.4:auth'
CREATE TABLE IF NOT EXISTS rate_hits (
  key        TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_rate_hits ON rate_hits(key, created_at);

-- courier logo (bundled asset or https URL; the app falls back to initials)
ALTER TABLE couriers ADD COLUMN logo_url TEXT;
