-- 0013: persist promo applied per job (discount applies to the DropOff leg only).
ALTER TABLE jobs ADD COLUMN promo_code TEXT;
ALTER TABLE jobs ADD COLUMN promo_discount_zmw REAL NOT NULL DEFAULT 0;
