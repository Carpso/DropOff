-- 0076 — owner feature switches, sender car preference, referral-promo marker.
-- Vehicle class is DECIDED by the server from parcel size + needs_car; the
-- sender never chooses it. Existing rows stay motorcycle by default.
ALTER TABLE jobs ADD COLUMN needs_car INTEGER NOT NULL DEFAULT 0;

-- Distinguish referral (FRIEND...) promos from admin promos so they can be
-- restricted to PAYG bookings/collections by senders.
ALTER TABLE promo_codes ADD COLUMN kind TEXT NOT NULL DEFAULT 'admin';

-- Owner-flippable feature switches (ON preserves current behaviour).
INSERT OR IGNORE INTO app_settings (key, value, updated_by) VALUES
  ('auto_assign_enabled', '1', 'seed-0076'),
  ('claim_board_enabled', '1', 'seed-0076'),
  ('bookings_enabled', '1', 'seed-0076'),
  ('rider_transfer_enabled', '1', 'seed-0076'),
  ('photo_stamp_enabled', '1', 'seed-0076'),
  ('step_sounds_enabled', '1', 'seed-0076'),
  ('voice_guidance_enabled', '1', 'seed-0076');
