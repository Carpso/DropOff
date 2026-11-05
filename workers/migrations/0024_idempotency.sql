-- Idempotency guard for money-moving writes. A client retry (poor Zambian
-- networks) with the same Idempotency-Key replays the original response instead
-- of creating a second job or a second mobile-money collect.
CREATE TABLE IF NOT EXISTS idempotency_keys (
  key TEXT PRIMARY KEY,
  scope TEXT NOT NULL,                 -- job | payment | rating
  phone TEXT,
  status INTEGER NOT NULL,
  response TEXT NOT NULL,              -- JSON body of the first successful reply
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_idem_created ON idempotency_keys(created_at);
