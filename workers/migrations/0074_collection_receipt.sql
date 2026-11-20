-- Collection receipt (owner 2026-11-20): the sender uploads a photo of the
-- payment receipt for the goods to be collected. The rider shows it in full
-- screen at the courier depot, then photographs the collected items.
ALTER TABLE jobs ADD COLUMN collection_receipt_url TEXT;
