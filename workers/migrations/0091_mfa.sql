-- 0091: TOTP MFA for every account (owner 2026-11-26).
-- Opt-in per account: enabled=1 makes both email/password and phone-OTP
-- sign-in stop at a short-lived challenge until the 6-digit code is supplied.
-- Recovery codes are stored hashed (same helper as OTP hashes), never clear.

CREATE TABLE IF NOT EXISTS mfa_settings (
  phone           TEXT PRIMARY KEY,
  secret          TEXT NOT NULL,              -- base32, 160-bit
  enabled         INTEGER NOT NULL DEFAULT 0,
  recovery_codes  TEXT NOT NULL DEFAULT '[]', -- JSON array of hashes
  created_at      TEXT NOT NULL DEFAULT (datetime('now')),
  enabled_at      TEXT
);
