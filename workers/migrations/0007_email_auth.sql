-- 0007: email + password accounts for customers.
-- JWT identity stays the phone (jobs/payments/wallets key on phone), so an
-- auth_user maps email -> its canonical phone. Password hashing is PBKDF2
-- (WebCrypto) done in the Worker, format: pbkdf2$<iter>$<saltHex>$<hashHex>.

CREATE TABLE IF NOT EXISTS auth_users (
  email         TEXT PRIMARY KEY,               -- lowercased at insert
  password_hash TEXT NOT NULL,
  phone         TEXT NOT NULL UNIQUE,           -- 260XXXXXXXXX (momo identity)
  full_name     TEXT,
  created_at    TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_auth_users_phone ON auth_users(phone);

-- failed-login throttle (10 per email per hour)
CREATE TABLE IF NOT EXISTS login_attempts (
  email      TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_login_attempts ON login_attempts(email, created_at);
