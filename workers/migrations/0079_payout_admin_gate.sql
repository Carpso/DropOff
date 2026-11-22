-- 0079 — admin gate for rider reimbursements.
ALTER TABLE payouts ADD COLUMN needs_admin_confirm INTEGER NOT NULL DEFAULT 0;
ALTER TABLE payouts ADD COLUMN admin_confirm_by TEXT;
ALTER TABLE payouts ADD COLUMN admin_confirm_at TEXT;
