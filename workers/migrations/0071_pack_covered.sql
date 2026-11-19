-- Plan consumption marker (owner 2026-11-19): a job booked under an active pack
-- (rider fee 0, plan-covered) stores pack_covered=1. Usage counters now count
-- only plan-covered jobs — a processing-fee payment no longer hides the parcel
-- from the cycle total ("3 of 10" stuck at 3).
ALTER TABLE jobs ADD COLUMN pack_covered INTEGER NOT NULL DEFAULT 0;
UPDATE jobs SET pack_covered = 1
 WHERE rider_fee_zmw = 0
   AND sender_phone IN (SELECT phone FROM subscriptions WHERE status = 'active')
   AND COALESCE(status, '') NOT IN ('canceled', 'cancelled', 'deleted');
