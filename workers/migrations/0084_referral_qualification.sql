-- Referral payout/qualification: reward after first paid delivery.
ALTER TABLE referrals ADD COLUMN qualified_at TEXT;
ALTER TABLE referrals ADD COLUMN qualified_job_id INTEGER;
ALTER TABLE referrals ADD COLUMN reward_kind TEXT;
ALTER TABLE referrals ADD COLUMN reward_amount_zmw REAL NOT NULL DEFAULT 0;
ALTER TABLE referrals ADD COLUMN void_reason TEXT;
CREATE INDEX IF NOT EXISTS idx_referrals_qualified_job ON referrals(qualified_job_id);