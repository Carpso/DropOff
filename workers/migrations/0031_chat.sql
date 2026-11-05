-- 0031: job-scoped chat. Participants: seller, recipient (via tracking token),
-- assigned rider, depot partner (courier), ops/admin. Plus support threads.
CREATE TABLE IF NOT EXISTS chat_threads (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  kind TEXT NOT NULL DEFAULT 'job',   -- 'job' | 'support'
  job_id INTEGER REFERENCES jobs(id), -- NULL for support threads
  phone TEXT,                         -- owner of a support thread
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  UNIQUE(job_id)
);
CREATE INDEX IF NOT EXISTS idx_chat_threads_phone ON chat_threads(phone);

CREATE TABLE IF NOT EXISTS chat_messages (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  thread_id INTEGER NOT NULL REFERENCES chat_threads(id),
  sender_phone TEXT NOT NULL,
  sender_role TEXT NOT NULL,          -- seller | recipient | rider | courier | ops
  body TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_chat_messages_thread ON chat_messages(thread_id, id);

CREATE TABLE IF NOT EXISTS chat_reads (
  thread_id INTEGER NOT NULL REFERENCES chat_threads(id),
  phone TEXT NOT NULL,
  last_read_id INTEGER NOT NULL DEFAULT 0,
  updated_at TEXT NOT NULL DEFAULT (datetime('now')),
  PRIMARY KEY (thread_id, phone)
);
