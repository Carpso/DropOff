-- 0042: remove Daily Dash from saleable plans.
-- Pay-as-you-go (Yango-competitive rate) is the default; Weekly Sprint +
-- Silver / Gold / Platinum monthly packs remain. Daily Dash is deactivated so
-- it is never returned by /plans; existing subscribers run out their cycle.
UPDATE tiers SET active = 0 WHERE tier = 'daily';
