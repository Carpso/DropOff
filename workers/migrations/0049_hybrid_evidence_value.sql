-- Hybrid parcel-check evidence, human review feedback, declared value/cover,
-- locale preference hook, saved recipients, and returns/referral scaffolding.

ALTER TABLE jobs ADD COLUMN declared_value_zmw REAL;
ALTER TABLE jobs ADD COLUMN cover_opt_in INTEGER NOT NULL DEFAULT 0;
ALTER TABLE jobs ADD COLUMN cover_fee_zmw REAL NOT NULL DEFAULT 0;
ALTER TABLE jobs ADD COLUMN cover_status TEXT NOT NULL DEFAULT 'none'; -- none|quoted|active|declined
ALTER TABLE jobs ADD COLUMN parcel_check_review TEXT; -- JSON: reviewer, decision, note, reviewed_at
ALTER TABLE jobs ADD COLUMN return_job_ref TEXT; -- links a return leg to the original ref
ALTER TABLE jobs ADD COLUMN job_kind TEXT NOT NULL DEFAULT 'delivery'; -- delivery|return

ALTER TABLE auth_users ADD COLUMN locale_pref TEXT; -- e.g. en, ny, bem, toi, loz (NULL => English)

CREATE TABLE IF NOT EXISTS saved_recipients (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  owner_phone TEXT NOT NULL,
  name TEXT NOT NULL,
  phone TEXT NOT NULL,
  address TEXT,
  city TEXT,
  notes TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now')),
  UNIQUE(owner_phone, phone, name)
);
CREATE INDEX IF NOT EXISTS idx_saved_recipients_owner ON saved_recipients(owner_phone);

CREATE TABLE IF NOT EXISTS parcel_check_feedback (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  job_id INTEGER NOT NULL,
  job_ref TEXT NOT NULL,
  verdict TEXT,
  decision TEXT,          -- confirm_match|confirm_mismatch|inconclusive
  reviewer TEXT,
  note TEXT,
  signals_json TEXT,      -- the model/rule signals at review time (training/eval data)
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_parcel_feedback_ref ON parcel_check_feedback(job_ref);

-- referrals table already exists (0017); extend via ALTERs in a future migration if needed.
