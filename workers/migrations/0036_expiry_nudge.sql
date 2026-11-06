-- 0036: expiry/grace nudge marker for the renewal safety net (notifyExpiryNudges).
-- NOTE: plain ALTER (D1 has no ADD COLUMN IF NOT EXISTS); re-running errors with
-- 'duplicate column name' when already applied — safe to ignore.
ALTER TABLE subscriptions ADD COLUMN expiry_nudge_period TEXT;
