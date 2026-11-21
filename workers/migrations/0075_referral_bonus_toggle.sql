-- 0075 — owner-toggleable referral bonus + reward delivery tracking.
-- The bonus stays ON by default so existing behaviour is unchanged.
INSERT OR IGNORE INTO app_settings (key, value, updated_by)
VALUES ('referral_bonus_enabled', '1', 'seed-0075');

-- Track that the referrer has actually been told about their earned code.
ALTER TABLE referrals ADD COLUMN reward_notified_at TEXT;
