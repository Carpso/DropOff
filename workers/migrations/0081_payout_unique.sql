CREATE UNIQUE INDEX IF NOT EXISTS idx_payouts_payment_kind_unique
  ON payouts(payment_id, kind) WHERE payment_id IS NOT NULL;
