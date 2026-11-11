-- 0054: self-learning chargebook.
-- 1) jobs.service — persisted so a recorded counter fare can upsert the exact
--    quotes row (courier + route + weight + service) it belongs to.
-- 2) quotes.source — 'ops' (keyed in by staff) or 'recorded' (learned from the
--    counter price the rider recorded at the depot drop). The badge/search
--    surfaces treat both as verified; the source is provenance only.
-- NOTE: plain ALTER (D1 has no ADD COLUMN IF NOT EXISTS); re-running errors
-- harmlessly with "duplicate column name" once applied.
ALTER TABLE jobs ADD COLUMN service TEXT NOT NULL DEFAULT 'standard';
ALTER TABLE quotes ADD COLUMN source TEXT NOT NULL DEFAULT 'ops';
UPDATE jobs SET service = 'standard' WHERE service IS NULL OR service = '';
UPDATE quotes SET source = 'ops' WHERE source IS NULL OR source = '';
