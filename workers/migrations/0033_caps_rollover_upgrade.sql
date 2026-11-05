-- 0033: cap nudges, rollover carry (Gold/Platinum), upgrade proration metadata.
ALTER TABLE subscriptions ADD COLUMN cap_nudge_period TEXT;
ALTER TABLE subscriptions ADD COLUMN rollover_parcels INTEGER NOT NULL DEFAULT 0;
ALTER TABLE subscriptions ADD COLUMN rollover_period TEXT;
ALTER TABLE payments ADD COLUMN meta TEXT;   -- JSON: upgrade bookkeeping (prevTier)
