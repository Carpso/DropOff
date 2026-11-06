-- 0039: revised seller pack prices - 250 / 500 / 750 for Silver / Gold / Platinum.
-- Keeps the parcel ladder (10 / 25 / 50) and 30-day cycles unchanged; this is a
-- price-only revision so the app, /plans and the chargebook all agree.
UPDATE tiers SET fee_zmw = 250 WHERE tier = 'silver';
UPDATE tiers SET fee_zmw = 500 WHERE tier = 'gold';
UPDATE tiers SET fee_zmw = 750 WHERE tier = 'platinum';
