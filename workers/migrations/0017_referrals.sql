-- 0017: seller referral engine — track every invite to rewarded booking.
ALTER TABLE auth_users ADD COLUMN referral_code TEXT;
CREATE UNIQUE INDEX IF NOT EXISTS auth_users_referral_code_unique ON auth_users(referral_code) WHERE referral_code IS NOT NULL;
CREATE TABLE IF NOT EXISTS referrals (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  referrer_phone TEXT NOT NULL,
  referred_phone TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending',   -- pending | rewarded | void
  reward_code TEXT,
  referred_job_id INTEGER,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  rewarded_at TEXT,
  UNIQUE(referred_phone)
);
CREATE INDEX IF NOT EXISTS referrals_referrer ON referrals(referrer_phone);
