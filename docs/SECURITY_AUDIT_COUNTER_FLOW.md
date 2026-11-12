# Security audit — depot counter flow & payment paths (2026-11-12)

Audit of the counter-receipt money flow against network drops, retries,
races and abuse, plus the fixes applied. Companion to
`PAYMENT_COMPLIANCE.md` (guard rules) and `MANY_PARCELS.md`.

## Threat model in one line

Someone tries to get a depot receipt paid, unlocked or reimbursed twice — or
an amount other than the depot's own written figure — by abusing network
drops, retries or role confusion.

## What the server enforces (verified + fixes)

1. **The client never sets money.** `counter_fare` amounts are computed
   server-side from `jobs.counter_receipt_zmw` (written receipt transcription),
   never from request bodies. The rider's transcription is bounded
   `0 < amount ≤ K20 000` at event time.
2. **Only the job's sender (or ops) may pay.** `/payments` kind
   `counter_fare` rejects any customer whose phone ≠ `jobs.sender_phone`.
   The receipt amount/photos/URL are stripped from partners, recipients and
   strangers on every read path (list, detail, evidence).
3. **Network drop on the rider's submit (self-healing).** While a receipt is
   UNPAID, a retried `delivered` event simply overwrites it — a dropped
   response must not brick a rider's stop. Multi-receipt drops file each
   photographed document with its own exact amount; the rider NEVER sums
   them — the server totals the photographed receipts
   (`counter_receipts_json`, per-receipt bounds enforced). **FIX:** once the
   sender has PAID, resubmission is rejected with 409
   `counter_receipt_locked` — paid receipts are money-movement evidence and
   can never be rewritten.
4. **Network drop on the sender's pay (idempotent).** A pending
   `counter_fare` prompt for the job IS the payment — re-tapping Pay now
   reuses it (`reused_prompt`), never double-prompts. **FIX:** a FAILED
   attempt now gets a fresh Lipila reference (`cfare-<ref>-<n>`); a telco
   cannot accept a reused reference, so retries after a failure no longer
   dead-end.
5. **Double-settlement race (webhook vs status poll).** `settled = 0 → 1` is
   claimed with a guarded UPDATE; only the claimer runs the unlock +
   ledger + event batch. Receipt unlock uses `counter_receipt_paid = 0 → 1`
   the same way.
6. **Double reimbursement.** `reimburseRider` fires only from inside the
   settled claim, so it runs at most once per payment. Payout failures raise
   `reimbursement_failed` job events for manual ops payout — the money is
   owed, never lost, never silently retried.
7. **Rate limits.** `/payments` creation is rate-limited (`payment_create`).
   Webhook is signature-gated (`LIPILA_WEBHOOK_SECRET`) and never trusts the
   body for money decisions — it only triggers re-verification/claims.
8. **REAL receipt, visible but locked (owner decision).** The sender now
   receives the rider's actual depot receipt photo immediately (not a
   placeholder); the app renders it blurred behind a lock until payment.
   Accepted trade-off: the lock is client-side presentation, so a
   tech-savvy sender could extract the URL before paying — the payment is
   enforced by the booking gate (409 `counter_fare_due` blocks their NEXT
   booking until settled) and by reimbursement logic, not by URL hiding.
   Partners/recipients still get nothing.
9. **Plan-active senders pay only for the reveal (owner directive).**
   `counterFareFees()` waives the processing fee for senders with an active
   subscription (momo collection pass-through stays — a real telco cost).
   The same helper drives the SMS/push total, so the quoted figure never
   changes between notification and prompt.
10. **Booking gate.** A sender with any unpaid counter receipt gets 409
    `counter_fare_due` on the next booking — staff (ops/admin) are exempt
    for reconciliation drops.

## Remaining known limits (accepted)

- The receipt photo's pre-payment visibility relies on client blur (see 8).
- Reimbursement depends on live Lipila disbursement keys; until verified,
  failed payouts surface as `reimbursement_failed` job events for manual
  settlement.
- If Lipila's webhook and the client's poll both die mid-flight, the payment
  row stays `pending`; the client's pending-reuse and status poll recover it
  on next open.
