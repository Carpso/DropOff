-- 0055: Depot counter receipt flow (2026-11-12, owner directive)
-- The rider fronts the depot's counter fare, photographs the parcel AND the
-- depot's written receipt, transcribes the exact receipt amount, and the
-- sender pays that amount + processing fee through DropOff by momo. The
-- receipt photo stays locked (URL withheld) until the sender pays; the rider
-- is then reimbursed the exact counter amount fee-free.
ALTER TABLE jobs ADD COLUMN counter_receipt_url TEXT;
ALTER TABLE jobs ADD COLUMN counter_receipt_zmw REAL;
ALTER TABLE jobs ADD COLUMN counter_receipt_paid INTEGER NOT NULL DEFAULT 0;
