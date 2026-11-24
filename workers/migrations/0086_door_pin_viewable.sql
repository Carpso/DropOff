-- Allow recipients to view/change their own door PIN (owner can see forgotten PIN).
ALTER TABLE auth_users ADD COLUMN door_pin TEXT;
-- Backfill is impossible from hash; existing users keep hash-only until they re-save.