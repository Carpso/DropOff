-- 0052: Rider payroll (salaried, K3,000/month inclusive of K300/week fuel,
-- paid weekly Sunday 16:00 CAT or monthly on the 1st 16:00 CAT, pace-gated,
-- auto-confirmed chain admin → superadmin, with downloadable proof of payment)
-- + ZRA turnover tax ledger (0% ≤ K2,500 monthly turnover; 5% above,
-- due by the 14th of the following month).

ALTER TABLE riders ADD COLUMN pay_cycle TEXT NOT NULL DEFAULT 'weekly';

CREATE TABLE IF NOT EXISTS rider_payroll (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  rider_phone TEXT NOT NULL,
  rider_name TEXT,
  period_kind TEXT NOT NULL,            -- weekly | monthly | monthly_balance
  period_start TEXT NOT NULL,           -- CAT ISO
  period_end TEXT NOT NULL,             -- CAT ISO
  base_zmw REAL NOT NULL DEFAULT 0,
  fuel_zmw REAL NOT NULL DEFAULT 0,
  trips INTEGER NOT NULL DEFAULT 0,
  period_target INTEGER NOT NULL DEFAULT 0,
  pace_met INTEGER NOT NULL DEFAULT 1,
  amount_zmw REAL NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending', -- pending | admin_confirmed | paid | failed | void
  confirmed_by TEXT,                    -- second signature (superadmin)
  admin_confirm_by TEXT,
  admin_confirm_at TEXT,
  confirmed_at TEXT,
  paid_at TEXT,
  lipila_reference TEXT,
  note TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_payroll_period
  ON rider_payroll (rider_phone, period_kind, period_start);
CREATE INDEX IF NOT EXISTS idx_payroll_status ON rider_payroll (status, created_at);

CREATE TABLE IF NOT EXISTS tax_periods (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  year_month TEXT NOT NULL UNIQUE,      -- 'YYYY-MM' (CAT month)
  gross_turnover_zmw REAL NOT NULL DEFAULT 0,
  zero_band_zmw REAL NOT NULL DEFAULT 0,      -- K2,500 monthly 0% band applied
  taxable_zmw REAL NOT NULL DEFAULT 0,
  rate REAL NOT NULL DEFAULT 0.05,            -- 5% above the K2,500 band (2026 rules)
  tax_zmw REAL NOT NULL DEFAULT 0,
  due_date TEXT NOT NULL,                     -- 14th of the following month
  status TEXT NOT NULL DEFAULT 'open',        -- open | submitted | paid
  breakdown TEXT,                             -- JSON component lines
  submitted_note TEXT,
  submitted_by TEXT,
  paid_at TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);
