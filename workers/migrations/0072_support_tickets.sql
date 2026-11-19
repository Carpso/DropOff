-- Support tickets (owner 2026-11-19). Support threads (chat_threads kind='support')
-- become real tickets: subject, category and an explicit open/pending/closed
-- status. The existing chat_messages thread is the ticket's conversation.
ALTER TABLE chat_threads ADD COLUMN subject TEXT;
ALTER TABLE chat_threads ADD COLUMN category TEXT NOT NULL DEFAULT 'general';
ALTER TABLE chat_threads ADD COLUMN status TEXT NOT NULL DEFAULT 'open';
ALTER TABLE chat_threads ADD COLUMN updated_at TEXT;

UPDATE chat_threads SET status = 'closed' WHERE closed_at IS NOT NULL;
UPDATE chat_threads SET updated_at = COALESCE(updated_at, created_at);

CREATE INDEX idx_chat_threads_ticket_status ON chat_threads(kind, status, updated_at);
