-- Float/risk controls: batch reimbursement payouts and track batch members.
ALTER TABLE payouts ADD COLUMN meta TEXT;
CREATE INDEX IF NOT EXISTS idx_payouts_kind_phone_status ON payouts(kind, phone, status);