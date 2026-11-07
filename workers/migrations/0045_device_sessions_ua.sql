-- 0045: web/app session details (user agent) + trusted default for REAL sessions.
-- Existing rows were fingerprinted via /auth/login but never called
-- trusted=1 — without flipping them now, /me/devices reports "untrusted"
-- for every real sign-in and the revoke flow feels broken.
ALTER TABLE device_sessions ADD COLUMN ua TEXT;
UPDATE device_sessions SET trusted = 1 WHERE trusted = 0;
