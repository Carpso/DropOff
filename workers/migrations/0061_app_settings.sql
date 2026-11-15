-- 0061: Platform feature flags (owner toggles, not deploys).
-- Delivery: door-to-door drop-off service (sender's door -> recipient's door).
--   OFF by default: first-mile startup on a subscription model; door-to-door
--   is a later, paid convenience and must be opt-in for the business.
-- Discounts: tier overage discount on PAYG overage parcels (Silver 15%,
--   Gold 25%, Platinum 35%, weekly 10%). OFF by default — the model is
--   already lean; the owner can re-enable from /admin/settings.
CREATE TABLE IF NOT EXISTS app_settings (
  key         TEXT PRIMARY KEY,
  value       TEXT NOT NULL,
  updated_at  TEXT DEFAULT (datetime('now')),
  updated_by  TEXT
);

-- Defaults are intentionally the OFF position; rows absent ⇒ treated as OFF
-- by the code. Seed explicit rows so Railway/Dashboard editing is obvious.
INSERT OR IGNORE INTO app_settings (key, value, updated_by) VALUES
  ('door_to_door_enabled', '0', 'seed-0061'),
  ('overage_discount_enabled', '0', 'seed-0061');
