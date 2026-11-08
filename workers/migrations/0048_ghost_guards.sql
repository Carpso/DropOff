-- Anti-false-parcel / anti-ghost-booking kit (pay-as-you-go deposit, strikes,
-- depot counter confirmation, seller parcel photo + AI parcel check).
CREATE TABLE IF NOT EXISTS booking_strikes (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  phone TEXT NOT NULL,
  job_id INTEGER,
  reason TEXT NOT NULL,             -- no_show_pickup | otp_abuse | ...
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_strikes_phone_time ON booking_strikes (phone, created_at);

ALTER TABLE jobs ADD COLUMN parcel_photo_url TEXT;      -- seller's booking-time capture
ALTER TABLE jobs ADD COLUMN partner_confirmed INTEGER DEFAULT 0; -- depot counter/POS webhook
ALTER TABLE jobs ADD COLUMN parcel_check TEXT;          -- AI photo-compare verdict JSON
