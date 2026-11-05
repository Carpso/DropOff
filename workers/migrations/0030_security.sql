-- 0030: intrusion detection, device fingerprinting, owner alerts. (Idempotent.)
ALTER TABLE login_attempts ADD COLUMN ip TEXT;
ALTER TABLE login_attempts ADD COLUMN user_agent TEXT;
ALTER TABLE login_attempts ADD COLUMN success INTEGER NOT NULL DEFAULT 0;
ALTER TABLE login_attempts ADD COLUMN locked_until TEXT;

CREATE TABLE IF NOT EXISTS device_sessions (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  phone TEXT NOT NULL,
  device_id TEXT NOT NULL,
  ip TEXT,
  first_seen TEXT NOT NULL DEFAULT (datetime('now')),
  last_seen TEXT NOT NULL DEFAULT (datetime('now')),
  trusted INTEGER NOT NULL DEFAULT 0,
  UNIQUE(phone, device_id)
);
CREATE INDEX IF NOT EXISTS idx_device_sessions_phone ON device_sessions(phone);

CREATE TABLE IF NOT EXISTS security_alerts (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  phone TEXT NOT NULL,
  type TEXT NOT NULL,           -- new_device | brute_force | lockout | password_reset
  severity TEXT NOT NULL,       -- low | medium | high | critical
  detail TEXT,
  acknowledged INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_security_alerts_phone ON security_alerts(phone, acknowledged);
