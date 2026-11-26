-- 0090: owner / admin password resets can never be completed from an emailed
-- link (owner directive 2026-11-26: "protect it as the app owner").
--
-- `issued_via` records how a token reached the account:
--   email  - a link emailed to the address (normal customer flow)
--   sms    - a link texted to the account phone (owner/staff flow)
--   admin  - minted by the superadmin key (recovery)
--
-- The worker refuses to redeem an `email` token for a protected account, so
-- every link already sitting in the owner's mailbox stops working the moment
-- this ships.

ALTER TABLE email_tokens ADD COLUMN issued_via TEXT NOT NULL DEFAULT 'email';
ALTER TABLE email_tokens ADD COLUMN requested_ip TEXT;

CREATE INDEX IF NOT EXISTS idx_email_tokens_via ON email_tokens(email, kind, issued_via);
