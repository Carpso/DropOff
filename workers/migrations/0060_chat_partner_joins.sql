-- 0060: Partners linked to a depot may JOIN a job's parcel chat.
-- Joining is an explicit one-tap opt-in recorded per thread per partner —
-- before joining, the depot sees nothing (the thread 404s like for any
-- outsider); after joining, the partner reads/writes alongside sender,
-- recipient and rider (and the chat stays readable by all even when closed).
CREATE TABLE IF NOT EXISTS chat_partner_joins (
  thread_id INTEGER NOT NULL REFERENCES chat_threads(id),
  phone TEXT NOT NULL,
  joined_at TEXT NOT NULL DEFAULT (datetime('now')),
  PRIMARY KEY (thread_id, phone)
);
