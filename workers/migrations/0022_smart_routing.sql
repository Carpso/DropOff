-- Smart routing layer: rider capacity, live status, assigned jobs + ETAs.
-- Additive only: existing jobs/riders keep working unchanged.
ALTER TABLE riders ADD COLUMN status TEXT NOT NULL DEFAULT 'available';      -- available | on_route | offline
ALTER TABLE riders ADD COLUMN capacity INTEGER NOT NULL DEFAULT 8;           -- max concurrent open stops
ALTER TABLE riders ADD COLUMN current_load INTEGER NOT NULL DEFAULT 0;       -- open jobs assigned to this rider
ALTER TABLE riders ADD COLUMN route_json TEXT;                               -- last computed route (JSON)
ALTER TABLE riders ADD COLUMN route_updated_at TEXT;
ALTER TABLE jobs ADD COLUMN assigned_at TEXT;
ALTER TABLE jobs ADD COLUMN eta_minutes INTEGER;                             -- rider ETA to pickup (min)
CREATE INDEX IF NOT EXISTS idx_riders_status ON riders(status, active);
CREATE INDEX IF NOT EXISTS idx_jobs_rider_status ON jobs(rider_id, status);
CREATE INDEX IF NOT EXISTS idx_jobs_eta ON jobs(eta_minutes);
