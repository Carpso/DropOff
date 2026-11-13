-- 0059: Archive the job thread when the recipient or sender confirms the
-- delivery; all participants keep read-only access to history.
--   closed_by       'seller' | 'recipient' | 'ops' (who closed it)
--   closed_at       ISO datetime when the chat was closed / archived
-- Once closed the thread is read-only: nobody can post, but all participants
-- and staff can still read the full history.
ALTER TABLE chat_threads ADD COLUMN closed_by TEXT;
ALTER TABLE chat_threads ADD COLUMN closed_at TEXT;
