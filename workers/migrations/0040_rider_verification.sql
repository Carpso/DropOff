-- 0040: driver onboarding / KYC - ID, licence, plate, vehicle details and photos,
-- plus admin/owner verification. Existing riders are grandfathered as verified;
-- every new rider starts 'pending' until the owner or an admin approves.
ALTER TABLE riders ADD COLUMN nrc_number TEXT;
ALTER TABLE riders ADD COLUMN license_number TEXT;
ALTER TABLE riders ADD COLUMN plate_number TEXT;
ALTER TABLE riders ADD COLUMN vehicle_make TEXT;
ALTER TABLE riders ADD COLUMN vehicle_color TEXT;
ALTER TABLE riders ADD COLUMN photo_url TEXT;
ALTER TABLE riders ADD COLUMN nrc_photo_url TEXT;
ALTER TABLE riders ADD COLUMN license_photo_url TEXT;
ALTER TABLE riders ADD COLUMN plate_photo_url TEXT;
ALTER TABLE riders ADD COLUMN verification_status TEXT NOT NULL DEFAULT 'pending';
ALTER TABLE riders ADD COLUMN verification_note TEXT;
ALTER TABLE riders ADD COLUMN verified_by TEXT;
ALTER TABLE riders ADD COLUMN verified_at TEXT;
ALTER TABLE riders ADD COLUMN submitted_at TEXT;
ALTER TABLE riders ADD COLUMN ai_check_json TEXT;

-- Grandfather the fleet that was already running before KYC existed.
UPDATE riders SET verification_status = 'verified',
                   verified_by = 'migration:0040',
                   verified_at = datetime('now')
 WHERE verification_status = 'pending';

CREATE INDEX IF NOT EXISTS idx_riders_verification ON riders (verification_status);
