-- 0035b: seed the new tiers (daily/weekly) + backfill tier columns.
-- Safe to run on ANY database (prod included): INSERT OR IGNORE + guarded
-- UPDATEs on the existing tiers rows. Run with:
--   npx wrangler d1 execute dropoff-db --remote --file=migrations/0035b_tier_seed.sql
INSERT OR IGNORE INTO tiers (tier, fee_zmw, parcels_per_day, parcels_per_month, rider_fee_zmw, overage_discount_pct, cycle_days, active, tag)
VALUES ('daily', 69, 6, 6, 0, 5, 1, 1, 'Daily Dash');
INSERT OR IGNORE INTO tiers (tier, fee_zmw, parcels_per_day, parcels_per_month, rider_fee_zmw, overage_discount_pct, cycle_days, active, tag)
VALUES ('weekly', 399, 0, 20, 0, 10, 7, 1, 'Weekly Sprint');

-- Backfill extended columns for the existing monthly packs (only when 0/NULL).
UPDATE tiers SET parcels_per_month = 10, overage_discount_pct = 15, cycle_days = 30 WHERE tier = 'silver' AND (parcels_per_month IS NULL OR parcels_per_month = 0);
UPDATE tiers SET parcels_per_month = 25, overage_discount_pct = 25, cycle_days = 30 WHERE tier = 'gold' AND (parcels_per_month IS NULL OR parcels_per_month = 0);
UPDATE tiers SET parcels_per_month = 50, overage_discount_pct = 35, cycle_days = 30 WHERE tier = 'platinum' AND (parcels_per_month IS NULL OR parcels_per_month = 0);
