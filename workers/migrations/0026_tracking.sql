-- Public, revocable tracking links for recipients (no account needed). The
-- token is random, scoped to one job, and safe to share over SMS/WhatsApp.
CREATE TABLE IF NOT EXISTS tracking_tokens (
  token TEXT PRIMARY KEY,
  job_id INTEGER NOT NULL REFERENCES jobs(id),
  job_ref TEXT NOT NULL,
  phone TEXT,                                  -- recipient the link was issued to
  expires_at TEXT,                             -- NULL = until revoked
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_tracking_job ON tracking_tokens(job_id);
