-- Refund audit trail + receipts. A refund is a new payments row that points at
-- the original; the original flips to 'refunded' once the momo disbursement is
-- accepted by Lipila.
ALTER TABLE payments ADD COLUMN refund_of_payment_id INTEGER;
ALTER TABLE payments ADD COLUMN refunded_at TEXT;

CREATE INDEX IF NOT EXISTS idx_payments_refund_of ON payments(refund_of_payment_id);
CREATE INDEX IF NOT EXISTS idx_payments_status_created ON payments(status, created_at);
