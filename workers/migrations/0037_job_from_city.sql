-- 0037: store the pickup city on the job (repeat-booking prefill, city analytics).
-- Existing rows were Lusaka-first-mile trips, so backfill the known default.
-- NOTE: plain ALTER (D1 has no ADD COLUMN IF NOT EXISTS); safe to ignore a
-- 'duplicate column name' error when already applied.
ALTER TABLE jobs ADD COLUMN from_city TEXT;
UPDATE jobs SET from_city = 'Lusaka' WHERE from_city IS NULL;
