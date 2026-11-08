-- Cover T&Cs acceptance capture (quoted protection only; NOT insurance activation).
-- Legal/commercial sign-off is still required before treating cover as active insurance.
ALTER TABLE jobs ADD COLUMN cover_tos_accepted INTEGER NOT NULL DEFAULT 0;
ALTER TABLE jobs ADD COLUMN cover_tos_version TEXT;
ALTER TABLE jobs ADD COLUMN cover_tos_accepted_at TEXT;
