-- 0034b: jobs.branch — one-shot column add (SQLite has no IF NOT EXISTS for
-- ADD COLUMN). Already applied on the production database; only run this on a
-- FRESH database where jobs.branch does not exist yet. Re-running it on prod
-- fails with "duplicate column name: branch" — that is expected; skip it.
ALTER TABLE jobs ADD COLUMN branch TEXT;
