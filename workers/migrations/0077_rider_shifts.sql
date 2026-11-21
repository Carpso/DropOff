-- 0077 — rider sweep shifts (owner 2026-11-21).
-- Every rider is committed to ALL THREE sweeps by default (06:00, 10:00,
-- 14:00 CAT). Between shifts they may do other work; dispatch and the claim
-- board simply stop offering them DropOff jobs outside an active shift.
ALTER TABLE riders ADD COLUMN shifts TEXT NOT NULL DEFAULT '["06:00","10:00","14:00"]';
ALTER TABLE riders ADD COLUMN on_shift INTEGER NOT NULL DEFAULT 1;
ALTER TABLE riders ADD COLUMN shift_terms_accepted INTEGER NOT NULL DEFAULT 0;
