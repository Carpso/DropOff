-- 0065: SPLIT the handover code (owner decision 2026-11-18) — the sender's
-- PICKUP code and the recipient's DOOR code become independent secrets, so a
-- code shown at pickup can never also open the door, and the rider can never
-- be blamed for a shared code being abused.
--
-- Roles after this migration:
--   pickup_otp_hash    — the SENDER's 4-digit pickup code (new column)
--   delivery_otp_hash  — the RECIPIENT's 4-digit door code (existing column)
--
-- Backfill: every row that already carries a shared code gets
-- pickup_otp_hash = delivery_otp_hash, so codes already sitting in senders'
-- hands keep working at pickup. All NEW bookings (and every future resend)
-- mint two independent codes.
ALTER TABLE jobs ADD COLUMN pickup_otp_hash TEXT;
ALTER TABLE jobs ADD COLUMN pickup_otp_attempts INTEGER DEFAULT 0;

UPDATE jobs SET pickup_otp_hash = delivery_otp_hash WHERE delivery_otp_hash IS NOT NULL;
