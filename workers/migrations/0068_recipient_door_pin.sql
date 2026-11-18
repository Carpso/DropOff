-- Recipient door PIN (owner 2026-11-18): a registered recipient sets their own
-- 4-digit handover PIN in the app. Riders verify it at the door even for
-- same-city parcels that carry no SMS code.
ALTER TABLE auth_users ADD COLUMN door_pin_hash TEXT;
