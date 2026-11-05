-- Ratings & comments for the three sides of a delivery: the seller (the person
-- who books and hands over the parcel), the driver (rider who collects it), and
-- the courier (the company that moves it). One rating per reviewer per job per
-- target; re-submitting the form updates the previous score and comment.
CREATE TABLE IF NOT EXISTS ratings (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  job_ref TEXT NOT NULL,
  job_id INTEGER REFERENCES jobs(id),
  target_type TEXT NOT NULL CHECK (target_type IN ('seller', 'driver', 'courier')),
  target_key TEXT NOT NULL,                 -- phone:260..., rider:12, courier:3
  reviewer_phone TEXT NOT NULL,             -- 260XXXXXXXXX
  reviewer_role TEXT NOT NULL DEFAULT 'customer',
  stars INTEGER NOT NULL CHECK (stars BETWEEN 1 AND 5),
  comment TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now')),
  UNIQUE(job_ref, target_type, reviewer_phone)
);

CREATE INDEX IF NOT EXISTS idx_ratings_target ON ratings(target_type, target_key);
CREATE INDEX IF NOT EXISTS idx_ratings_job ON ratings(job_ref);
