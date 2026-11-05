-- DropOff 0005: customer-covered Lipila collection fee
-- payments.amount_zmw = what Lipila collects (incl. K2.50 momo fee);
-- payments.credit_zmw = what actually lands (wallet top-up base amount).

ALTER TABLE payments ADD COLUMN credit_zmw REAL NOT NULL DEFAULT 0;
