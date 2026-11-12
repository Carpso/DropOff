-- 0057: multi-receipt depot drops (2026-11-12, owner request).
-- A trip may arrive at a depot that splits the batch across MORE THAN ONE
-- written receipt. Each receipt is photographed with its own exact amount —
-- a submitted receipt is always a single, exact, photographed document,
-- never a rider-computed sum. The rider may file several:
--   counter_receipts_json = [{amount_zmw, url}, ...] (all receipts, in order)
--   counter_receipt_url   = FIRST receipt photo (drives the locked preview)
--   counter_receipt_zmw   = SERVER-computed total of all receipt amounts
--                           (the sender owes the sum of exact documents)
ALTER TABLE jobs ADD COLUMN counter_receipts_json TEXT;
