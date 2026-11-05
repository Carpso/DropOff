-- DropOff 0004: production hardening
-- (a) phone OTP login -> JWT identity, (b) wallet float + COD receipts,
-- (c) subscription auto-renewal via Lipila, (d) courier partner profiles.

CREATE TABLE IF NOT EXISTS otp_codes (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  phone TEXT NOT NULL,               -- 260XXXXXXXXX
  code_hash TEXT NOT NULL,           -- sha-256(code + secret) hex
  expires_at TEXT NOT NULL,          -- 10 minutes validity
  used INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_otp_phone ON otp_codes(phone, created_at);

-- jobs: who pays how + COD receipts recorded on delivery
ALTER TABLE jobs ADD COLUMN pay_method TEXT NOT NULL DEFAULT 'mobile_money'; -- mobile_money | wallet | cash
ALTER TABLE jobs ADD COLUMN paid INTEGER NOT NULL DEFAULT 0;
ALTER TABLE jobs ADD COLUMN cod_collected_zmw REAL NOT NULL DEFAULT 0;

-- payments: idempotent settlement + subscription billing rows
ALTER TABLE payments ADD COLUMN subscription_id INTEGER;
ALTER TABLE payments ADD COLUMN settled INTEGER NOT NULL DEFAULT 0;
ALTER TABLE payments ADD COLUMN kind TEXT NOT NULL DEFAULT 'job'; -- job | topup | subscription

-- courier partner profiles shown in the app
ALTER TABLE couriers ADD COLUMN website TEXT;
ALTER TABLE couriers ADD COLUMN price_status TEXT;
ALTER TABLE couriers ADD COLUMN note TEXT;
