-- 0062: Smart reprompt pause.
-- The sender may silence DropOff's payment reminders for a booking (USSD pushes
-- already on their phone are out of app control, but nothing more goes out).
-- Paused pending payments are excluded from the advance-prompt reuse check so
-- "Resume" re-enables a fresh prompt with the next deliberate tap.
ALTER TABLE payments ADD COLUMN paused_at TEXT;
