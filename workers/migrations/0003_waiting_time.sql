-- DropOff 0003: rider waiting / depot-queue time billing (per parcel)
-- Rider records minutes waited; first 10 min free, K2/min after, capped K50.

ALTER TABLE jobs ADD COLUMN wait_minutes INTEGER NOT NULL DEFAULT 0;
ALTER TABLE jobs ADD COLUMN wait_fee_zmw REAL NOT NULL DEFAULT 0;
