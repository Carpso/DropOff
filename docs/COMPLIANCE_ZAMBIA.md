# DropOff — Zambia Compliance Checklist

**Product:** DropOff (first-mile parcel delivery app)
**Operator:** Carpso Solutions (registered company, Zambia)
**Contact:** 0968551110 (user-facing) · transactions 0976847775
**Date:** 2026-11-25
**Status:** Pre-launch compliance review — items marked ✅ done, ⚠️ in progress, ❌ not started

> This document is a working checklist for the owner and legal counsel. It is
> not legal advice. Engage a Zambian lawyer for filings and sign-off.

---

## 1. Business registration (PACRA)

| # | Requirement | Status | Notes |
|---|---|---|---|
| 1.1 | Carpso Solutions registered as a limited company (or sole proprietorship) with PACRA | ⚠️ | Required before any commercial activity. Keep certificate + CR14. |
| 1.2 | DropOff registered as a trading name / business name under Carpso Solutions | ❌ | If DropOff is marketed publicly, register the name. |
| 1.3 | Registered office address in Zambia | ⚠️ | Must match ZRA and bank records. |
| 1.4 | Annual returns filed with PACRA | ❌ | Recurring obligation. |

## 2. Tax (ZRA)

| # | Requirement | Status | Notes |
|---|---|---|---|
| 2.1 | TPIN (Taxpayer Identification Number) for Carpso Solutions | ⚠️ | Required for all tax filings and invoicing. |
| 2.2 | VAT registration (if turnover exceeds K800,000/yr) | ❌ | Voluntary registration possible earlier. DropOff charges processing fees — VAT may apply. |
| 2.3 | PAYE for salaried riders (K3,000/mo) | ❌ | Monthly remittance to ZRA. |
| 2.4 | Withholding tax on payments to courier partners (if applicable) | ❌ | Review with accountant. |
| 2.5 | Income tax returns (annual) | ❌ | |
| 2.6 | E-invoicing / smart invoice compliance (ZRA mandate) | ❌ | New ZRA requirement — verify current threshold. |

## 3. Employment (riders are salaried staff)

Governing law: **Employment Code Act, 2019**.

| # | Requirement | Status | Notes |
|---|---|---|---|
| 3.1 | Written employment contracts for all riders | ❌ | Fixed K3,000/mo package incl. K300/week fuel. |
| 3.2 | NAPSA (National Pension Scheme Authority) registration + monthly contributions | ❌ | Employer + employee contributions. |
| 3.3 | NHIMA (National Health Insurance Management Authority) registration + contributions | ❌ | |
| 3.4 | PAYE remittance (see 2.3) | ❌ | |
| 3.5 | Leave entitlements (annual, sick, maternity/paternity) per Employment Code | ❌ | |
| 3.6 | Termination procedures (notice, severance, unfair dismissal protections) | ❌ | |
| 3.7 | Workplace injury / occupational safety | ❌ | Riders on motorcycles — high risk. Consider group personal accident cover. |

## 4. Data protection (Data Protection Act, 2021)

| # | Requirement | Status | Notes |
|---|---|---|---|
| 4.1 | Privacy policy published (in-app + web) | ⚠️ | Must state: what data collected, purpose, retention, sharing, rights. |
| 4.2 | Consent at sign-up (phone, name, location, photos) | ⚠️ | App collects location, photos, recipient details. |
| 4.3 | Data Protection Officer (DPO) designated | ❌ | Required for organisations processing personal data at scale. |
| 4.4 | Data subject rights process (access, correction, deletion) | ⚠️ | `/delete-data` endpoint exists (OTP-gated). Verify completeness. |
| 4.5 | Cross-border data transfer safeguards (Cloudflare D1 is global) | ❌ | Disclose in privacy policy; consider region pinning. |
| 4.6 | Breach notification procedure (to Data Protection Commissioner + subjects) | ❌ | |
| 4.7 | Data retention policy (jobs, photos, tracking tokens) | ❌ | Define retention periods; implement purge cron. |

## 5. Financial services / payments

Governing: **Bank of Zambia** (mobile money regulations), **Financial Intelligence Centre (FIC)** (AML/CFT).

| # | Requirement | Status | Notes |
|---|---|---|---|
| 5.1 | Agreement with licensed payment provider (Lenco and/or Lipila) | ⚠️ | Lenco is primary (`PAYMENT_GATEWAY=lenco`). Confirm merchant agreement signed. |
| 5.2 | Mobile money collection/disbursement compliance (BoZ circulars) | ⚠️ | DropOff collects momo from senders and disburses to business + riders. May need agent registration. |
| 5.3 | KYC/AML for high-value transactions | ❌ | FIC obligations if DropOff is deemed a financial service. |
| 5.4 | Transaction records retained for audit (5+ years) | ⚠️ | D1 stores payments/payouts. Ensure backups. |
| 5.5 | Reconciliation & float monitoring | ✅ | Money-ops card + Lenco float tracking shipped. |
| 5.6 | Refund/settlement payout engine (guarded, idempotent) | ✅ | Migration 0073 + retry engine shipped. |

## 6. Transport / courier regulation (RTSA)

| # | Requirement | Status | Notes |
|---|---|---|---|
| 6.1 | RTSA operator licence (if DropOff operates vehicles) | ❌ | DropOff uses salaried riders on motorcycles + partner couriers. Clarify whether DropOff itself needs a licence or only partners. |
| 6.2 | Partner courier agreements (Mercury, Icypeed, PostDotNet) | ❌ | Written contracts defining fare responsibility, liability, SLA. |
| 6.3 | Vehicle insurance (third-party minimum) for rider motorcycles | ❌ | Mandatory under Zambian road traffic law. |
| 6.4 | Rider driving licences (motorcycle class) | ❌ | Verify at onboarding; store licence number + expiry. |
| 6.5 | Goods-in-transit / parcel insurance | ❌ | Cover is "quoted protection, not insurance" until legal sign-off — do not market as insured. |

## 7. Consumer protection (CCPC)

Governing: **Competition and Consumer Protection Act**.

| # | Requirement | Status | Notes |
|---|---|---|---|
| 7.1 | Terms of Service published (in-app + web) | ⚠️ | Must cover: fees, cancellations, refunds, liability limits, dispute resolution. |
| 7.2 | No misleading claims (cover ≠ insurance) | ✅ | Enforced in AGENTS.md and UI copy. |
| 7.3 | Clear fee disclosure before payment | ✅ | Processing fee shown; counter-fare shows receipt + processing. |
| 7.4 | Refund policy | ⚠️ | Refund engine exists; policy text needed. |
| 7.5 | Complaints handling / support tickets | ✅ | Tickets system shipped. |
| 7.6 | Price transparency (no hidden charges) | ✅ | |

## 8. Cybersecurity & electronic transactions

| # | Requirement | Status | Notes |
|---|---|---|---|
| 8.1 | Cyber Security and Cyber Crimes Act 2021 compliance | ❌ | Security measures, incident reporting. |
| 8.2 | Electronic Communications and Transactions Act | ⚠️ | Digital signatures/consent for bookings. |
| 8.3 | Secure data storage (encryption at rest, in transit) | ✅ | HTTPS, JWT auth, auth-gated media. |
| 8.4 | Screenshot protection on sensitive screens | ✅ | FLAG_SECURE on OTPs/waybills/finance (selective). |

## 9. App store compliance (Google Play)

| # | Requirement | Status | Notes |
|---|---|---|---|
| 9.1 | Google Play developer account (Carpso Solutions) | ⚠️ | |
| 9.2 | Data safety form (data collected, shared, retained) | ❌ | Must match privacy policy. |
| 9.3 | Target SDK 36 (edge-to-edge) | ✅ | Shipped 0.5.78+. |
| 9.4 | R8 full mode + keep rules | ✅ | |
| 9.5 | Version codes strictly increasing (never reuse) | ✅ | Enforced in AGENTS.md. |
| 9.6 | Privacy policy URL in store listing | ❌ | |

## 10. Recommended immediate actions (before launch)

1. **Register Carpso Solutions** with PACRA + get TPIN (if not done).
2. **Sign Lenco merchant agreement** and confirm `LENCO_API_KEY` secret is live.
3. **Publish Privacy Policy + Terms of Service** (web + in-app). Draft from the data collected: phone, name, location, photos, recipient details, payment history.
4. **Get written contracts** with courier partners (Mercury, Icypeed, PostDotNet) defining fare responsibility and liability.
5. **Verify rider motorcycle insurance + licences** at onboarding.
6. **Register with NAPSA + NHIMA** for salaried riders.
7. **Designate a DPO** and document data retention periods.
8. **Complete Google Play data safety form** before upload.

## 11. Out of scope (not applicable)

- Banking licence (DropOff is not a bank; it routes payments via licensed providers).
- Telecommunications licence (SMS via Africa's Talking, an aggregator).
- Insurance underwriting (DropOff offers "quoted protection", not insurance — legal sign-off required before marketing as insured).

---

## 12. Rider engagement model (avoiding employer scrutiny)

**Question:** Can we call rider payments "salary" or use an alternative (part-time stipend, per-task pay, contractor) to avoid being classified as an employer (NAPSA, NHIMA, PAYE, contracts, leave, termination)?

**Zambian law (Employment Code Act 2019, s.2):** There is a **presumption of employment** — regular, ongoing, controlled work is employment regardless of the label on the contract. If DropOff sets shifts (06:00/10:00/14:00), assigns jobs, and pays regularly, riders are likely deemed employees by ZRA/NAPSA regardless of what the contract says.

### Options

| Option | Description | Employer obligations? | Risk |
|---|---|---|---|
| **A. Keep salary + comply** | Register NAPSA/NHIMA, do PAYE, issue contracts. Cost ~K300-500/rider/month in contributions. | Yes (full) | None — safest |
| **B. Per-task / per-shift pay (gig)** | Pay per completed delivery or shift attended, not fixed monthly. | Likely yes (presumption of employment) | High — label won't hold up |
| **C. Third-party agency (manpower)** | Engage a licensed employment agency that employs riders; Carpso pays the agency. | No (agency is employer) | Low — cleanest legal shield |
| **D. Volunteer / stipend** | Call riders "volunteers" receiving a stipend. | Likely yes | High — regular stipends = wages |
| **E. Mixed (small base + per-task bonus)** | Small availability stipend + per-delivery bonus. | Likely yes | High |

### Recommendation

- **If you want to avoid employer obligations entirely → Option C (agency).** Carpso Solutions pays the agency a flat fee; the agency handles NAPSA, NHIMA, PAYE, contracts, leave, termination. Cost: ~10-15% agency fee. This is the cleanest legal shield and is common in Zambia for last-mile/delivery fleets.
- **If you accept employer obligations (few riders, manageable cost) → Option A (comply).** Register with NAPSA + NHIMA, do PAYE, issue written contracts. Cost ~K300-500/rider/month. This builds rider loyalty and is the safest.
- **Options B/D/E are legally risky** in Zambia because of the presumption of employment. Calling it "stipend", "allowance", or "contractor fee" does not change the substance. ZRA/NAPSA look at the reality (regular work, set shifts, assigned jobs, regular pay), not the label.

### Practical note

Even under Option C, Carpso Solutions should:
- Keep rider PII minimal (phone + name for dispatch; the agency holds employment records).
- Not control riders' daily schedule beyond shift windows (let the agency manage attendance).
- Document the agency agreement clearly (scope, fee, who is employer of record).

*Last updated: 2026-11-25. Owner: Carpso Solutions / DropOff product team.*