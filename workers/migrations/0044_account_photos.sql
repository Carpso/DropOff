-- 0044: universal profile photos for EVERY account (riders, sellers, recipients,
-- admins/ops). NULL = never uploaded (app shows initials). The selfie key lives
-- under uploads/selfie/* which any signed-in user may read (sellers see who is
-- collecting their parcel). KYC documents are untouched and stay staff-or-owner.
ALTER TABLE auth_users ADD COLUMN photo_url TEXT;
