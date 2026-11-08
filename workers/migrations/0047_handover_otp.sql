-- Handover proof: recipient OTP gate + rider proof-of-delivery photos.
-- The OTP (4 digits, hashed) is SMSed to the RECIPIENT at booking; the rider
-- must supply it when marking a job 'delivered' — so a parcel cannot be
-- "delivered" into thin air and neither party can fake a handover.
ALTER TABLE jobs ADD COLUMN delivery_otp_hash TEXT;
ALTER TABLE jobs ADD COLUMN pod_pickup_url TEXT;
ALTER TABLE jobs ADD COLUMN pod_delivery_url TEXT;
ALTER TABLE jobs ADD COLUMN delivery_otp_attempts INTEGER DEFAULT 0;
