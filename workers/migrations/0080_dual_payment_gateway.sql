-- Dual payment gateway support: Lipila remains primary, Lenco is an explicit
-- alternative and safe auth-failure fallback. Existing rows stay Lipila.
ALTER TABLE payments ADD COLUMN gateway TEXT NOT NULL DEFAULT 'lipila';
ALTER TABLE payments ADD COLUMN gateway_reference TEXT;
UPDATE payments SET gateway_reference = lipila_reference WHERE gateway_reference IS NULL;
CREATE INDEX IF NOT EXISTS idx_payments_gateway_ref ON payments(gateway, gateway_reference);

ALTER TABLE payouts ADD COLUMN gateway TEXT NOT NULL DEFAULT 'lipila';
ALTER TABLE payouts ADD COLUMN gateway_identifier TEXT;
UPDATE payouts SET gateway_identifier = lipila_identifier WHERE gateway_identifier IS NULL;

ALTER TABLE rider_payroll ADD COLUMN gateway TEXT NOT NULL DEFAULT 'lipila';
ALTER TABLE rider_payroll ADD COLUMN gateway_reference TEXT;
ALTER TABLE rider_payroll ADD COLUMN gateway_identifier TEXT;
UPDATE rider_payroll SET gateway_reference = lipila_reference WHERE gateway_reference IS NULL;

ALTER TABLE platform_disbursements ADD COLUMN gateway TEXT NOT NULL DEFAULT 'lipila';
ALTER TABLE platform_disbursements ADD COLUMN gateway_reference TEXT;
ALTER TABLE platform_disbursements ADD COLUMN gateway_identifier TEXT;
UPDATE platform_disbursements SET gateway_identifier = lipila_reference WHERE gateway_identifier IS NULL;

ALTER TABLE lipila_logs ADD COLUMN gateway TEXT NOT NULL DEFAULT 'lipila';
CREATE INDEX IF NOT EXISTS idx_lipila_logs_gateway_ref ON lipila_logs(gateway, reference);
