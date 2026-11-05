-- 0019: hardening + wiring fixes (see /audit 2026-11-05)
--   • otp_codes.attempts      — brute-force guard: 5 wrong tries burn the code
--   • auth_users.token_version— bumped on password reset; middleware compares the
--                               JWT `ver` claim so old sessions die instantly
--   • recurring_plans.*       — the cron can now materialise standing orders
--                               (courier + route must exist; never invent a fare)
ALTER TABLE otp_codes ADD COLUMN attempts INTEGER NOT NULL DEFAULT 0;
ALTER TABLE auth_users ADD COLUMN token_version INTEGER NOT NULL DEFAULT 0;
ALTER TABLE recurring_plans ADD COLUMN courier_id INTEGER REFERENCES couriers(id);
ALTER TABLE recurring_plans ADD COLUMN from_city TEXT NOT NULL DEFAULT 'Lusaka';
ALTER TABLE recurring_plans ADD COLUMN last_created_at TEXT;
