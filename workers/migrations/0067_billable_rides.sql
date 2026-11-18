-- Round trips consume TWO rides (owner 2026-11-18): the rider goes to the
-- depot AND returns the parcel to the sender. Physical parcel count stays 1;
-- plan usage and PAYG pricing use billable_rides instead.
ALTER TABLE jobs ADD COLUMN billable_rides INTEGER NOT NULL DEFAULT 1;
UPDATE jobs SET billable_rides = 2 WHERE round_trip = 1 OR round_trip = '1';
