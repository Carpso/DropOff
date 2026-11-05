-- DropOff 0006: fee-engine columns (Chisomo / Wardrobe-Valet pattern)
-- payments.amount_zmw = the full prompt (base + platform fee + Lipila legs
-- + payout settlement). platform_fee_zmw = DropOff's earned cut,
-- lipila_fee_zmw = Lipila's pass-through legs.

ALTER TABLE payments ADD COLUMN platform_fee_zmw REAL NOT NULL DEFAULT 0;
ALTER TABLE payments ADD COLUMN lipila_fee_zmw REAL NOT NULL DEFAULT 0;
