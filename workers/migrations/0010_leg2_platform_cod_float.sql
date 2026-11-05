-- DropOff 0010: explicit last-mile (leg-2) platform fee, stored per job.
-- Customer pays leg2 fee + leg2 processing at the door; cash floats with the
-- rider/driver until remittance (wallet credit is deferred, not instant).
ALTER TABLE jobs ADD COLUMN leg2_processing_fee_zmw REAL NOT NULL DEFAULT 0;
