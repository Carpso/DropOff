-- 0035: smarter plan tiers — extended columns on `tiers` (price/cycle model).
-- One-shot column adds (SQLite has no IF NOT EXISTS for ADD COLUMN). Applied
-- on prod 2026-11-06 ahead of 0035b; skip if the columns already exist.
ALTER TABLE tiers ADD COLUMN parcels_per_month INTEGER NOT NULL DEFAULT 0;
ALTER TABLE tiers ADD COLUMN overage_discount_pct INTEGER NOT NULL DEFAULT 0;
ALTER TABLE tiers ADD COLUMN cycle_days INTEGER NOT NULL DEFAULT 30;

