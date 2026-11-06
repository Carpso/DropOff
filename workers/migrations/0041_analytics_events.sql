-- 0041: app feature usage / click analytics (app-first KPI for superadmin & admin).
-- Every screen view, button tap, form submit and feature interaction is logged
-- here from the Flutter app (batched, offline-first) and aggregated by the
-- /admin/analytics/kpi endpoint for the owner/admin console.
-- No PII beyond the signed-in phone (which is already the account identity);
-- meta is free-form JSON (parcel count, tier, route, etc.) and never stores
-- passwords, OTPs or payment secrets.
CREATE TABLE IF NOT EXISTS analytics_events (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  phone TEXT,                                          -- signed-in caller (may be NULL for anonymous public views)
  role TEXT,                                           -- customer | admin | ops | rider | partner | NULL
  feature TEXT NOT NULL,                               -- booking | collections | pack_codes | rider_verification | admin_users | fraud | sms_broadcast | branches | support | track | rating | subscriptions | admin_analytics
  action TEXT NOT NULL,                                -- view | tap | submit | approve | reject | redeem | generate | clear | confirm | broadcast | pay | rate | share
  context TEXT,                                        -- screen / page where the event happened (e.g. 'home', 'admin_console', 'booking_step_2')
  meta TEXT,                                           -- JSON free-form extras (parcels, tier, amount, ref, etc.)
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Query-friendly indexes for the KPI endpoint.
CREATE INDEX IF NOT EXISTS idx_analytics_created ON analytics_events (created_at);
CREATE INDEX IF NOT EXISTS idx_analytics_feature ON analytics_events (feature, created_at);
CREATE INDEX IF NOT EXISTS idx_analytics_role ON analytics_events (role, created_at);
CREATE INDEX IF NOT EXISTS idx_analytics_phone ON analytics_events (phone);

-- Keep the table bounded: older than 90 days is pure history; the KPI endpoint
-- reads the last 30 days by default. A nightly sweep (cron) can DELETE WHERE
-- created_at < datetime('now', '-90 days') if ops wants to cap storage.
