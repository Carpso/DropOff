-- Linked devices: show real handset names (X-Device-Name) and an estimated
-- location (Cloudflare country header) instead of raw "Dart/3.9" user agents.
ALTER TABLE device_sessions ADD COLUMN device_name TEXT;
ALTER TABLE device_sessions ADD COLUMN location TEXT;
