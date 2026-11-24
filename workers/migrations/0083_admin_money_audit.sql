-- Admin money-action audit trail (Step 3 follow-up).
CREATE TABLE IF NOT EXISTS admin_money_audit (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  action TEXT NOT NULL,               -- refund | payout_confirm | payout_retry | payout_pay_now | counter_fare_prompt | counter_fare_waive
  actor_phone TEXT,
  actor_role TEXT,
  target_type TEXT,                   -- payment | payout | job
  target_id TEXT,
  idempotency_key TEXT,
  request_json TEXT,
  result_json TEXT,
  ok INTEGER NOT NULL DEFAULT 1,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_admin_money_audit_target ON admin_money_audit(target_type, target_id);
CREATE INDEX IF NOT EXISTS idx_admin_money_audit_created ON admin_money_audit(created_at);