# Depot confirmation without a POS — low-tech counter workflow (internal)

> Draft. Use as partner onboarding checklist; not legal advice.

Goal: courier counters confirm receipt without running DropOff app.

## Recommended flows
### A) Snapshot + token (preferred when no app)
1. Sender/rider shows DropOff waybill at counter.
2. Counter stamps/writes “RECEIVED <date> <initials>” on the waybill.
3. Counter takes a photo of the stamped waybill using their own phone.
4. Counter sends the photo to a saved DropOff partner number/email (or via `POST /partner/console` token).
5. DropOff (ops) marks the job delivered manually; counter never opens the app.

### B) QR/app-lite (when counter has a smartphone)
1. Counter opens `https://dropoff.carpsosolutions.store/partner/console`
2. Enters the **DropOff ref** or **the courier waybill number** shown on the DropOff waybill
3. Taps “Confirm arrival” / “Departed” / “Delivered” — closes the loop with no POS integration
4. If counter has a scanner, scan the QR from the DropOff waybill; enters the same ref/waybill.

### C) POS/webhook (preferred, scalable)
1. `POST /webhooks/partner-status` with `X-Partner-Key` header.
2. Body: `{ ref | waybill, status, note?, at? }`.
3. Rate-limited/idempotency: repeats within 5 min are deduped.
4. Status values accepted: `created`, `rider_assigned`, `picked_up`, `at_depot`, `departed`, `arrived`, `delivered`, `ready_for_collection`, `partner_confirmed`.
5. `404` for unknown waybill/ref; `403` for unknown key; `409` for wrong-pin confirm if enabled.

## Failure modes to design for
- Counter refuses unknown paper → use waybill number on paper; it’s the same ref either way.
- Counter loses photo → accept later photo; mark job `partner_confirmed` later.
- Counter wrongly confirms → use audit log; require PIN if mis-dispatch happens; alert admin console.
- Multiple depots for the same ride → first `at_depot` wins; subsequent ones are logged, not reverted.

## Onboarding checklist for a counter
- [ ] Give them the partner key (or a one-time link/pin) — never share into the app.
- [ ] Show one-page “Stamp + send” laminate for non-tech counters.
- [ ] Set expectation: confirmation triggers **readiness for collection**, not refunds.
- [ ] Test one real drop with a real seller.
- [ ] Add their depot line to the coverage page.
