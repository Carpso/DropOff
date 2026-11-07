-- 0043: Daily Rider - on-demand daily subscription plan (Yango-style casual use).
-- Re-introduced at the owner's request as a leaner product than the old Daily
-- Dash (which stays removed; its tier key 'daily' is still never surfaced).
--   K49 / day  ·  2 parcels included per day  ·  rider fee K0 inside allowance
--   overage 45% off PAYG  ·  1-day cycle, activates on payment  ·  windows incl. 'now'
-- Editable live via POST /admin/tiers (rider_daily row) without a deploy.

INSERT OR IGNORE INTO tiers (tier, fee_zmw, parcels_per_day, parcels_per_month, rider_fee_zmw, overage_discount_pct, cycle_days, tag, active)
VALUES ('rider_daily', 49, 2, 0, 0, 45, 1, 'Daily Rider', 1);
