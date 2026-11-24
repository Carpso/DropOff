# DropOff Payment Positioning — Prepaid Delivery Credit (not e-money)

**Status: operating standard, 2026-11-10.** Owner directive.

## Why this document exists

Zambia regulates stored-value/e-money under the National Payment Systems Act 2007 (as replaced by the **National Payment System Act, 2026 (No. 5 of 2026)**), the **Banking and Financial Services Act, 2026**, and the **Bank of Zambia Directives on Electronic Money Issuance (2023, Gazette Notice No. 958/2023)**, which define e-money as an electronic store of value that is:

1. issued on receipt of funds,
2. stored on an electronic device,
3. **accepted as payment by persons other than the issuer**, and
4. **redeemable on demand**.

Issuing e-money without a BoZ designation can attract severe criminal penalties (in the 2026 framework, up to decades' imprisonment). DropOff is a delivery-logistics company that happens to take payments — **it is not, and must never look like, an e-money issuer or a wallet operator.**

## What DropOff actually does (and does not do)

| Guard | Implementation | Location |
|---|---|---|
| 1. Single-purpose money only | Every prepayment is pinned to **exactly one parcel** (`payments.kind='booking_deposit'` → `job_id`). The credit can pay only DropOff's own delivery service — trip price + processing fee. | rides through booking, never free-form |
| 2. No cash-out, ever | There is no cash-out/withdraw feature for customers. Refunds go back to the **original momo number** via Lipila (a licensed PSP), under `/admin/payments/:id/refund` (manual) and `refundUnspentPrepaid()` (automatic on cancel-before-pickup). | workers/src/index.ts |
| 3. Unspent prepayment is returned | Cancellation before pickup (auto no-show cron, both branches) automatically momo-refunds the unspent portion to the sender's source number; on payout failure, the job is flagged `prepaid_refund_failed` and ops executes the manual refund. | `refundUnspentPrepaid()` |
| 4. Prepayment capped at the quote | The momo prompt is the server-computed quote for that parcel only (rider leg + processing + momo leg). It can never exceed what the delivery costs. There is **no free-form customer top-up**: `/payments` `kind='topup'` is gated to rider/ops (COD float) and capped at `WALLET_TOPUP_CAP_ZMW`; customers have no top-up surface at all. On approval the deposit **marks the job paid directly — customer balances are never credited** (the `wallet_ledger` 'deposit' row is a job-linked audit trail only); unspent residue is computed job-scoped (`refundUnspentPrepaid`) and returned to momo. No customer store of value exists at any point. | `/payments`, `/wallet`, quotes |
| 5. Never accept third parties | The prepayment is accepted ONLY by DropOff for DropOff parcels. Not at depots, courier counters, riders, other merchants, or P2P transfers. Customer `GET /wallet` and customer role gating enforce this. **Depot counter fare exception (owner directive 2026-11-12, updated 2026-11-24):** when the rider fronts the depot's counter fare, the sender repays DropOff the **exact receipt amount + processing fee + K15 depot queue fee** (kind `counter_fare`); the receipt photo stays locked/blurred until payment settles, then the rider is reimbursed the exact receipt amount. Plan-active senders have the DropOff platform cut waived inside the processing fee, but still pay the gateway provider fee and depot queue fee. DropOff is reimbursing its own rider's out-of-pocket expense, not holding depot money — the depot is paid by the rider at the counter as always. | role gates, 403s |

Additional positioning:

- **Terminology**: never "DropOff wallet", "e-wallet", "top-up" in customer copy — say **"prepayment for your parcel delivery"** / internal ledger field `wallet_ledger` (DB name stays — schema migration for a label is pointless; it is not customer-facing).
- **Rider cash handling**: none. Riders never touch ride money (salaried, `docs/PLAN_ECONOMICS_2026-11-10.md` §9).
- **Collections**: momo → Lipila (licensed PSP) → per-leg fees; platform sweeps its income to the business number (`sweepPlatformIncome`).
- **Refunds at customer's request** (outside cancel flow): admin reviews and pays via `/admin/payments/:id/refund`.
- **Tax treatment**: prepaid legs are recognised as turnover when spent (ZRA turnover tax ledger, §see TODOS) — not on receipt.

## Red lines that would flip us into e-money territory

- Leaving a customer-selectable **"Top up"** UI or marketing that invites accumulating a balance.
- **Cash-out** of delivery credit at any point (including via Lipila disbursement, except to the source momo as refunds).
- **Third-party acceptance** of delivery credit (agents, depots, marketplaces).
- **P2P** transfer of credit between accounts.
- Expanding "credit" into any rewards/loyalty that is spendable elsewhere.
- Marketing language implying DropOff is a wallet ("top up your DropOff wallet!"), or distributing balance promotions.

Any of these require **written BoZ designation first** (see the 2023 Directives: application, Holding Account ≥ outstanding float, 2% continuing capital, KYC, monthly reconciliation).

## Verification checklist for 2026-Q4

- [ ] Lipila live: confirm webhook/status-poll credits job-tagged `booking_deposit` payments (not float top-ups).
- [ ] End-to-end: momo prompt at booking → approved → rider dispatch → delivery OTP/POD → pickup debit → unspent remainder back to sender on cancel.
- [ ] Confirm `prepaid_refund_failed` events surface to ops if a payout cannot be delivered (recipient off, insufficient float in the Lipila disbursement pool, network error). Note: rider/customer momo numbers receiving payouts need **no** Lipila registration — they only receive; same for the platform's own momo main number.
- [ ] Re-test no-show auto-cancel returns the prepayment log and SMS.

## Legal note

This is an operating standard authored by the owner and the engineering team, not legal advice. Before scaling any of this (top-ups, agent networks, multi-parcel subscription-ish credit), obtain a written legal opinion or BoZ non-objection/designation as required.
