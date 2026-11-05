ALTER TABLE subscriptions ADD COLUMN period_start TEXT;
ALTER TABLE subscriptions ADD COLUMN period_end TEXT;
UPDATE subscriptions SET period_start = started_at,
       period_end = datetime(started_at, '+30 days')
 WHERE period_start IS NULL;
ALTER TABLE jobs ADD COLUMN parcels INTEGER NOT NULL DEFAULT 1;
ALTER TABLE jobs ADD COLUMN vehicle_class TEXT NOT NULL DEFAULT 'motorcycle';
CREATE INDEX IF NOT EXISTS idx_jobs_sender_period ON jobs(sender_phone, created_at);
ALTER TABLE riders ADD COLUMN vehicle_class TEXT NOT NULL DEFAULT 'motorcycle';
