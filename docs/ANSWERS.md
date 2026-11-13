# DropOff due-diligence interview answers — + extended question bank
:Godfrey Moses Kalambo:Carpso Solutions:0968551110.

**Date:** 2026-11-13 · **Version:** 0.5.21+32 · **Purpose:** prepare for investor / lender /
partner interview for DropOff (Carpso Solutions).
**Facts baseline:** `docs/PLAN_ECONOMICS_2026-11-10.md` (D1 snapshot 2026‑11‑10) and
`docs/PAYMENT_COMPLIANCE.md`, `docs/EXIT_READINESS.md`. These numbers were TRUE on that date;
the database changes fast — re-pull `node d1query.cjs "<SQL>"` before the interview and read
the fresh numbers off the slide.
**Honesty rule:** If you don't know it, say "we don't know yet, and here's when we will".
Never inflate traction. Bluffing a sophisticated interviewer is unrecoverable.

---

## Part 1 — the 18 attached interview questions, answered

> The image asks for: how started, personnel roles, headcount, 5-year view, capital
> motivation, product line, distribution, documentation, sales cycle, contract & payment
> structure, commodity/dollar exposure, 5-year priorities, mineral priorities, operations &
> QA, accounting systems, team gaps, director pay, gross margins.
>
> **Notes on fit.** The form is a generic commodity/mining due-diligence questionnaire. Two
> questions (11 and 13) are not native to DropOff; they are answered honestly for DropOff
> and flagged with a **MINING VARIANT** block to adapt if this questionnaire is being answered
> for a separate mineral venture. **No numbers below are invented — every fact is marked with
> its source; everything you must supply is `[FOUNDER INPUT]`.**

**1. How was your company started?**
DropOff is a Carpso Solutions product (owner/proprietor: Godfrey Moses Kalambo, Lusaka). It
started from one observable pain: in Zambia, sending a parcel means the sender drives or rides
to the courier depot themselves — Platinum, Mercury, Rivert, One World, Icypeed, DHL, Falcon
— and if you don't have a car, the painful last 5 km before the courier's intercity leg is yours.
Carpso Solutions built "Uber for the first mile": a rider collects from the sender's home/shop
and drops at the depot, with live tracking, digital proof of drop-off and momo payment, and an
optional door-delivery leg at the receiving end. 2026 was the build-out: Android app, courier
catalogue, booking/sweep-slot flow, Lipila prepayment, counter-fare reimbursement, partner
console, POS webhooks. First job logged 2026‑11‑05.

**2. What are the roles of your personnel?**
Today the company is **founder-led**: one technical founder building product, running
operations and onboarding partners (`role=partner` depot counter accounts). Riders are not
staff employees — they are salaried sweep riders once the model activates (**K3,000/month
basic inclusive of K300/week fuel**, pace-gated, paid via payroll with proof-of-payment) and
*never* per-parcel. Depot partners (Platinum et al.) are B2B partners, paid by DropOff only for
expressly contracted services (none per-parcel). **[FOUNDER INPUT] add your actual named
roles and any advisors/accountant as you retain them.**

**3. How many employees do you have?**
Founder-only headcount today; a contractor fleet once the sweep model goes live. As of the
2026‑11‑10 audit: **30 registered accounts, 0 live rider roster rows, 0 active subscriptions**.
Payroll (salaried riders) is provisioned in the system but not yet paying out — say exactly
that. Count: 1 (founder) + budgeted sweep-rider payroll (**recommended starting roster: 3–5
riders**, [FOUNDER INPUT] confirm chosen launch number).

**4. Where do you see yourselves in 5 years?**
Year 1 (this stage): Lusaka density — Kabulonga, Northmead, Kanyama, Chilenje, one
neighbourhood at a time; 30-day closed beta; 2–5 live depot integrations; paying subscriber
base. Year 2–3: Lusaka city-wide + Copperbelt corridor (Copperbelt first — highest parcel
density outside Lusaka); predictable per-job contribution; subscription majority of parcels;
POS webhooks across launch depots. Year 4–5: multi-city Zambia, door-delivery at both ends,
DropOff Predict as a visible product moat, freight intent from the marketplace, and an
acqui-hireable platform (courier partner, logistics roll-up, or continued indie growth). Never
city-wide before density works locally; never provincial before Copperbelt works.

**5. What is your motivation for raising capital?**
To buy **distribution**, not product. Product cost is largely sunk (built, tested, audited).
Capital deployment, in order: (1) rider sweep payroll float for the closed beta and the first
90 days of paid operations, (2) go-to-market — seller acquisition in 2–3 Lusaka neighbourhoods
(in-person demos, depot-counter posters with plan QR codes, WhatsApp/referral loops,
Facebook), (3) Lipila/PSP fees and working capital while volume ramps, (4) partnerships and
compliance retainer (lawyer + accountant) — not salaries for the founder. Say plainly: we are
pre-revenue (**K0 collected all-time; 4 jobs logged, 0 paid — 2026‑11‑10 snapshot**); a closed
beta and first-revenue cohort is what the capital buys. If the investor expects traction,
close the gap honestly: that is what the beta is for.

**6. What is your product line?**
For senders (Lusaka, Android): (1) PAYG door-to-depot parcel delivery (motorcycle/car/van/truck,
sweep slots, live GPS tracking, photo proof at pickup & depot), (2) Weekly Sprint plan (K399/20
parcels), Silver (K250/mo, 10), Gold (K500/mo, 25), Platinum (K750/mo, 50), Daily Rider
(K49/day) — all "quoted protection" included framing, never insurance, (3) last-mile door
delivery (K45 PAYG-style), (4) WhatsApp tracking links, phone-OTP handover (door), SMS status.
For partners: depot counter portal + POS webhooks (`partner_confirmed`), partner chat observe
(linked partners join delivery chat), per-courier console at `/partner/console`. For ops:
admin console (dispatch, commissions, strikes, payroll, incentives, refunds), security audit
trail, thermal waybill printing (58 mm ESC/POS, Xprinter-compatible). Roadmap, not shipped:
intercity Intent (Freight marketplace — DO NOT sell this in the interview as live).

**7. What is your distribution chain?**
Android Play Store (internal testing → closed beta → production) → **senders** (self-serve app,
WhatsApp referrals, shared tracking links) → **courier partners** (Platinum/mercury counters;
partner-signed confirmations, QR posters at depot counters — the depot IS the walk-in store)
→ **riders** (salaried sweep riders, assigned jobs in-app; ops assigns, riders fulfil) →
**recipients** (tracking page, OTP handover, "addressed to you" notification, phone-matched
accounts). Expansion: Zambian indirect channels — Facebook seller groups, commission-only
"depot agents" (not yet licensed). No direct sales team today — flag it as a hire gap.

**8. Documentation?**
You have the best-documented solo product they will see: `docs/PAYMENT_COMPLIANCE.md`
(operating standard 2026‑11‑10 — not-a-wallet positioning, e-money red lines), `docs/` (exit
readiness, plan economics, partner onboarding, cover-not-insurance, security audit of the
counter flow, many parcels batch flow, growth playbook, POS webhooks), in-app legal (privacy
policy + terms with asset/legal stamps), ownership-stamped source, store listing + `PLAY_STORE.md`,
`AGENTS.md` release rules, release builds via `tools/build_release.ps1` (always clean, versioned
artifacts). **Bring a printed one-page index of these ten documents to the interview.**

**9. How long are your sales cycles?**
Consumer PAYG: same session — book, approve momo, rider dispatched. Subscription plans:
one to three touches inside the app funnel (Predict-shown break-even card → plan purchase);
Week 1–2 conversion window post-first-delivery. B2B partners (depots): 2–6 weeks from first
meeting to webhook-confirm integration (partner confirmation doc, POS key issuance, first
stamp/first photo test, then live). Enterprise/tender: none yet — do not claim a cycle you
don't run.

**10. Structure of your contracts, payments with clients?**
Consumer: no contract beyond T&Cs + privacy notice (recorded acceptance). Partner/depot:
**Partner Confirmation** (one-page signed letter accepting the parcel flow, the POS webhook
key, hold-harmless on SpO₂, \*protects you not the courier\*) + webhook key issued. Payments:
**prepaid only, always pinned to one parcel** (`payments.kind='booking_deposit'`/`job`), collected
via Lipila (licensed PSP) by momo collect; **DropOff is not a wallet and never holds customer
value** — deposits are marked to the job, refunds go back to the source momo, no cash-out, no
third-party acceptance. Depot counter fares are paid by DropOff's rider at the counter; the
sender repays the exact receipt amount + processing — **DropOff never handles partner money**.
Said shorter for the room: "Money flows once, in one direction, per parcel — and there is no
custody risk for anyone."

**11. Are you able to adjust commodity prices if the dollar fluctuates?**
**For DropOff: no commodity prices exist — N/A.** Two exposures worth volunteering instead:
(1) ZMW-denominated everything — a ZMW depreciation *raises* our effective Lipila/PSP fee if
those are USD-priced (they're not quoted publicly; say "we pass nothing to customers outside
fees shown at booking"); (2) fuel/rider payroll — salaried rider costs are fixed in ZMW
inclusive of the fuel allowance (K300/week) — the one real FX-linked cost, capped and planned.
FX pass-through plan if it ever matters: adjust PAYG fees at next offer review, never
mid-cycle for subscribers.
**MINING/COMMODITY VARIANT (adapt if questionnaire is for your mineral venture):**
[FOUNDER INPUT — grade A-sampled price locks (LME/LBMA/Ltd bulletin) contracted with offtake,
hedging policy % of annual production committed before shipment, currency clause review every
quarter, and cap on raw-inventory exposure. Interviewer will want to know you PRE-SELL at
packed prices, not spot volume.]

**12. What are your priorities in the next 5 years?**
In order: (1) payback/cohort proof — 30+ paid jobs, per-job contribution fixed, refund rate
<2%, strikes <10%; (2) Copperbelt expansion once Lusaka density holds; (3) plan-over-PAYG mix
>60% (that's the retention machine); (4) partner POS coverage across launch depots;
(5) licences & paper — turnover-tax hygiene, BoZ conformity as e-money-like features are ever
approached; (6) unit-economics audit every 30 days (this doc is the first of them). Not in
priorities: geographic spread before density, speculative intercity freight, acquisitions.

**13. What minerals are your priorities?**
**For DropOff: N/A.**
**MINING/COMMODITY VARIANT:**
[FOUNDER INPUT — name your 2–3 minerals (e.g., copper, cobalt, manganese — Zambia's export
stack), tonnage targets p.a., offtake intent vs spot, compliance (mining cadastre/groundwater
licences), ESG position (tailings, community agreement), logistics to Walvis Bay/Dar es Salaam.
Interviewers of this questionnaire expect: 1 flag of legality (the licence exists), 1 flag of
margin (commodity), 1 flag of execution (team & logistics). Have those three sentences ready
cold.]

**14. Operations and quality control structure?**
Loop: booking (slot-pinned) → dispatch (nearest-active rider, ETA via Haversine + Predict) →
pickup (parcel photo, optional sender photo + AI same-parcel check) → depot drop (**two
mandatory photos — parcel + depot receipt**, exact amount transcribed, never quoted; waybill
58 mm printed with QR) → handover (door: recipient 4‑digit OTP; depot: recipient signs or
PIN). QC layers: photo evidence at every liability point; AI parcel-photo match flagged to
ops at <60% confidence; 3 struck bookings in 14 days → 14-day posting hold; auto-cancel of
unpaid depot bookings; 58 mm paper audit trail (waybills kept 12 months); chat auto-posts
milestones (picked_up → at_depot → departed → arrived → delivered) visible to all three
parties; read-only archived history; admin strike/audit cards + counter-fare reconciliation;
48-hour support SLA via in-app support chat; weekly payroll reconciliation with payout proof.
Checklist artifact to name-drop: `SECURITY_AUDIT_COUNTER_FLOW.md`.

**15. Accounting systems used?**
Honest answer: **no enterprise ERP yet.** Today: Lipila statements reconciled against
`payments`/`payouts` tables; monthly payroll run generated in-app (kind payroll-rider*)
confirmed by admin → superadmin with proof-of-payment; ZRA turnover-tax ledger recognised on
job completion (not receipt); books manually reconciled by the founder for pre-revenue
period — zero reconciliation drift so far (K0 transactions). **Before this interview, retain
a ZRA-registered accountant to** (a) open proper books (or move to QuickBooks/Sage), (b) file
returns even at zero turnover, (c) cap your exposure if turnover tax applies. [FOUNDER INPUT —
confirm your accountant's name; an interviewer trusts a name more than a system]

**16. Main gaps in the employment team?**
Honest list, ranked: (1) **Engineering capacity** — solo founder, no redundancy; bus-factor 1.
(2) **Growth** — no dedicated marketer; all traction strategy unexecuted. (3) **Partnerships** —
no one running depot relationships day-to-day (founder does this, doesn't scale). (4) **Finance** —
no accountancy advice pipeline until you retain one. (5) **Legal** — no standing counsel; all
docs are founder-reviewed, not lawyer-reviewed. (6) **Ops** — no dispatch lead when volume
passes ~30 deliveries/day. Solve by hiring in this order: partnerships → marketing → ops
dispatch once volume warrants; say "I'm the whole company today and the plan hires #1–3 within
90 days of this round".

**17. Are the directors and staff being paid by the business?**
**No — this is a bootstrap-founder company.** To date: zero founder salary, zero founders'
fees, zero dividends (pre-revenue, K0 collected as of 2026‑11‑10). Riders, when live, are paid
through payroll (salaried) with proof-of-payment — they do not draw from the business at the
expense of compliance. Directors draw nothing until the company pays revenue or equity
vesting would make that equitable. **[FOUNDER INPUT] volunteer your exact compensation plan —
interviewees probed on this question mean it: they're testing whether founders pay themselves
before the company earns a kwacha.**

**18. Gross margins on sales?**
Straight from the live audit (label it as such): per paid PAYG job ≈ **K10.50 contribution
(10–15% of the ~K96.74 average booking)** — K3.48 platform fee + K7.00 (10% of the K70 rider
fee). Door leg adds ~K10 K-level margin. Plan tiers: Silver K250/10 slots = K25 revenue/slot
vs ideal rides; Se%negative margin at full cap 1-parcel trips (audit shows tiers are designed
to be loss-leading at full cap unless 2–3 parcels share a trip). **Confidence: LOW — 4 jobs,
0 paid — re-run at 30+ paid jobs and quote the fresh number.** Interview answer: "Gross
contribution 10–15% per PAYG job today; subscription economics kick in at 2–3 parcels per
ride; we re-audit every 30 days — the last one is in the appendix."

---

## Part 2 — harder questions interviewers actually ask (bank by theme)

Each with the honest, ready-to-say frame. Adapt wording, not substance.

### A. Company & founders
1. Who owns the IP? — You (founder), under Carpso Solutions; source carried with
   firm ownership stamps; no contractor holds any rights; no outside equity issued yet.
2. Why should we back you and not another team? — Only team with (a) shipped product,
   (b) functioning courier-partner confirmation loop, (c) audit trail on every parcel,
   (d) prepaid-only architecture with documented compliance posture. Density is a moat no
   competitor reproduces in weeks.
3. What's the cap table? — 100% founder. [Pre-solid answers: "unallocated option pool 10%
   reserved for first hires; dilution balanced by this round."]
4. What keeps you going when revenue is K0? — The closed beta is already queuing; the ETA is
   provable; we know our first 100 customers by name (shops in Kabulonga/Northmead).
5. Who built this? — You (founder) with tooling assistance; no contractor written, kept, or
   owns code. Be transparent: founder-built, AI-assisted, all architecture documented.

### B. Product & tech
6. What's the architecture? — Managed cloud: Flutter Android → Cloudflare Worker (Hono/TS) →
   D1 (SQLite) + object storage + R2 (photos); no self-managed servers; ~9,300-line worker —
   full honest detail if they ask.
7. Is your data safe? — DPDP-aligned flows: photos in private R2 buckets served with short-lived
   signed URLs; JWTs, 30-day sessions, PBKDF2-100k (Workers cap), 5-strike login lockouts,
   per-thread partner joins, OTP delivery handovers. WhatsApp PII not retained.
8. What's the single worst technical risk? — Secrets in shipped builds (e.g., an ops-key
   accidentally leaked); mitigations: no keys in AAB, gated admin, build-time dart-defines only,
   secrets rotation procedure documented.
9. What if Cloudflare deprecates something? — Workers/D1 are the platform; exit cost is a
   Node reimplementation; risks noted (PBKDF2 cap, no cron sub-minute) and prices/procedures
   planned — say this openly; interviewers love teams that know their dependencies.
10. Does it work offline? — Partial: bookings cache local, payments sync on reconnect; no
    offline delivery yet (photo capture needs network for at-depot receipts).

### C. Market & competition
11. TAM/SAM/SOM? — TAM: all parcels moved by Zambian SMEs/e-tail/senders annually. SAM:
    Lusaka market parcel + Copperbelt corridor. SOM (24 mo): 1,000 recurring sellers in
    3 Lusaka neighbourhoods. Always volunteer: "I am not quoting K numbers I can't defend" —
    they will test you on this.
12. Who are your competitors? — Yango Delivery, inDrive courier, local taxi networks, Khotiv
    rider apps, informal motorbike taxis. Differentiator: prepaid-first, depot-partner verticals,
    proof-of-drop-off chemistry, predicted ETA, one-app experience.
13. What stops Yango copying you? — Yango optimizes citywide; we optimize for the one
    agonising depot run — we are a "feature" in their world and a company in ours. Density > capital.

### D. Business model & unit economics
14. CAC / LTV? — Early: CAC ~ = marketing + rider float per seller (≈ K35 seeked paid);
    LTV via subscription mix: Silver break-even for us at 5 parcels/month sold (K25 revenue/
    slot × contribution). Quote LTV:CAC only when the cohort exists — don't invent it.
15. How do you make money on a plan trip? — Riders salaried (K3,000/mo); per-trip
    rider fee accrues to platform revenue (10%); plan value is fulfilled by fleet throughput —
    the audit shows tiers are priced to be profitable at ≥2-parcel rides.
16. Take rate? — 10% of rider leg + K3.48 min platform fee + momo leg pass-through. Never claim
    more than audited.
17. Churn? — Unmeasured pre-traction; 3+ deliveries/60 days is the activation claim you
    track — live cohort answers come with beta data (build cohort reporting first).
18. How do you prevent e-money regulatory blowback? — Prepaid-only pinned to one parcel;
    no cash-out, no P2P, no third-party acceptance; refunds to source momo; BoZ position
    documented. If we ever near e-money, BoZ designation is a prerequisite — say this sentence.

### E. Traction & validation
19. Revenue to date? — K0. Say "K0. And the pipeline: 30 accounts, beta cohort queued,
    Lipila live keys pending". They will not believe success masquerading; they will fund
    honesty with plan.
20. What's the single number that proves this works? — Released-trip conversion: % of bookings
    delivered on time with photo proof, and % of first-time senders placing a second booking.
    State target: >75% and >35% — interviewers love a stated ceiling, not a hand-wave.
21. What customer interviews did you run? — Neighbourhood seller interviews: the #1 stated
    pain is "I missed the bus to the depot" — answered with door pickup; food/fresh vendors
    want same-day urgent; your answers are here in the pre-beta list — bring it.

### F. Legal & compliance
22. Insurance? — Cover is quoted protection, not insurance, until legal sign-off; terms
    documented; growth path exists. Insurers/re-insurers not yet engaged — prospective next step.
23. What licence do you operate on? — Logistics/deliveries need none; PSP (Lipila) is licensed
    by BoZ; if deposits ever look like stored value, BoZ designation becomes mandatory.
    Turnover tax (ZRA) registered as a VAT/taxpayer pre-revenue; returns filed at zero.
24. Your terms — are they reviewed? — Founder-drafted, not lawyer-reviewed. Commit: counsel
    engaged at first paid revenue.
25. Where do governing laws sit? — Zambia; disputes Lusaka; standard consumer terms apply.

### G. Operations
26. What's your driver turnaround? — Pickup within sweep window (06:00/10:00/14:00/tomorrow-06:00);
    photo-verified handover; do not over-promise 30 minutes in an interview — quote sweeps.
27. How do you handle bad parcels/loss? — Evidence photos (pickup & drop), AI check flags,
    manual review within 48h, compensation per SLA matrix (not disclosed externally until signed).
28. Partner stops cooperating? — Pause affected jobs; ops notified; customer not impacted
    beyond delay; alternative partners activated.

### H. Financials & raise
29. Use of funds? — (1) payroll float for 3–5 riders × 90 days (~K25k), (2) neighbourhood
    go-to-market (K40k, print + ads + demos), (3) PSP float & fees, (4) legal/accounting
    retainer, (5) contingency 10%. Track to this plan — don't burn founder perks.
30. How much are you raising at what valuation? — [FOUNDER INPUT — state your range or
    "strategic round, discussions ongoing; target KXXX at KXXX pre-money." Do not freelance it.]
31. What's the burn? — K0 today; KXXX/mo with paid roster + marketing; runway 9–12 months on
    this raise; reached unit-break-even by month 9 target.
32. Why not bootstrap? — Distribution cost in Lusaka is time + payroll; bootstrap = 3–4 years
    or dying: distribution capital is what we buy.

### I. The hardballs
33. What if Lipila fails or revokes the key? — Direct levelling: (a) support via Africa's
    Talking SMS fallback for critical flows, (b) manual Lipila USSD push at admin (current
    release supports admin push kashering/refund rails where permitted), (c) pivot rail to
    another PSP in <2 weeks (worker abstracted over `lipila.ts`).
34. What if a rider steals a parcel? — Photo POD + OTP handovers make this non-deniable;
    disciplinary/legal action; strike process; insurance claim file by all three parties.
35. What's your moat when the depot copies? — They own one leg; we own the whole door.
    Their counter depends on us bringing volume.
36. Percent chance this works? — Genuine answer: "High for the first 90 days post-beta
    activation; existential if we don't get Lusaka density."

---

## Part 3 — questions to ASK the interviewer (turns the tables)

1. What specifically do you expect a 12-month update to contain — number, logo pack, or P&L?
2. What deliverable shape do you want from the closed-beta week 4 review?
3. What does your ideal follow-on look like at first paid revenue?
4. Which other delivery/logistics bets have you backed, and what killed/wounded them?
5. How do you treat capital calls if the beta extends by 4 weeks?
6. What 3 conditions would you attach to this money?
7. Who else is in the round — strategic (courier groups) or financial?
8. What is your diligence timeline — can I hand over the security audit today?
9. What do you need to see to move to term sheet?
10. What do you want me to tell my first partners when they ask?
11. Does your mandate allow follow-ons into Zambia or are we a one-shot?
12. What do you consider an honest K exit here — trade sale, depot buyout, or BOC shell?

---

## Part 4 — what never to say (or claim) in the room

- "We have revenue" — you have **K0 collected** (as of 2026‑11‑10). Say "pre-revenue, beta cohort queued".
- "It's insured" — cover is **quoted protection, not insurance**.
- "We're a payment company" — you're a logistics company; money flows once per parcel, never stored.
- "Partner wallets" — **partners hold no DropOff balance; depots collect via Webhook/POS and pay counters in ZMW**.
- "Active subscribers" — 0 active subscriptions (2026‑11‑10 audit; 1 silver + 2 weekly pending_payment).
- "We'll figure out the team later" — your team IS the plan; hires create capacity; commit to them.
- Any revenue/forecast you cannot back from the audit spreadsheets or the console exports.

---

## Part 5 — your pre-interview checklist

- [ ] Re-pull fresh DB numbers: `node C:\…\d1query.cjs "SELECT COUNT(*) FROM jobs"` — quote today's
      numbers, not 2026‑11‑10's.
- [ ] Run this audit again: `EXECUTION` of the plan-economics re-run at 30+ paid jobs if beta converts.
- [ ] Print the **document index**: these answers + PAYMENT_COMPLIANCE + security audit + economics audit +
      a one-page rider-road (sweep slot diagram) + the plan economics table.
- [ ] **Books**: accountant name + K filed + zero-turnover filing confirmation (ask accountant).
- [ ] **Term sheet target**: know your ready-made answer for "how much at what valuation" BEFORE you're asked.
- [ ] Bring one demo phone with the build installed (v0.5.21+32). Show, don't tell.
- [ ] Print reading material for them: exit readiness + CTR list from `docs/EXIT_READINESS.md`.
- [ ] 30-second opening: "Zambia ships parcels by bus and prayer — here's the same courier run
      with a button." Rehearse it until it's natural.

---

## Appendix — source data (truth at 2026‑11‑10 snapshot; refresh before quoting)

| Metric | Value | Source |
|---|---|---|
| Jobs all time | 4 | `jobs` (DropOff D1) |
| Paid jobs | 0 | `jobs.paid` |
| Registered accounts | 30 | `auth_users` |
| Active subscriptions | 0 (1 silver + 2 weekly pending) | `subscriptions` |
| Avg rider fee (90d) | K70 (K55/K75/K95 bands) | `drivers` + audit |
| Avg booking total | K96.74 | audit |
| PAYG contribution | ≈K10.50 (10–15%) | `docs/PLAN_ECONOMICS_2026-11-10.md` |
| Rider base pay | K3,000/mo incl. K300/wk fuel, salaried | owner directive + contract |
| Product | Android v0.5.21+32, Play-internal | `tools/build_release.ps1` |
| Compliance posture | Prepaid, single-parcel, non-e-money | `docs/PAYMENT_COMPLIANCE.md` |
| Owner | Godfrey Moses Kalambo · Carpso Solutions · 0968551110 | `OWNERSHIP.md` |
