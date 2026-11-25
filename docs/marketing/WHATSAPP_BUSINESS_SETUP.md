# DropOff on WhatsApp — Setup Guide
### Business entity: **Carpso Solutions** · Product line: **DropOff**

Support / sales line: **0968551110** → international **+260 968 551 110** → `260968551110`

---

## 0. First, the naming decision (read this before you touch anything)

Meta enforces a **display-name policy**: the name on WhatsApp must represent the business, must not be generic, must not be a slogan, and must match what is on your business registration / website / socials. That is why "listed under Carpso Solutions" matters.

You have three workable options. Pick one now — changing later means re-verification.

| Option | Display name | Where "DropOff" lives | Risk | Verdict |
|---|---|---|---|---|
| **A** | `Carpso Solutions` | Description, catalogue, greeting, all copy, profile photo | **Lowest** — matches registration exactly | ✅ **Start here** |
| **B** | `Carpso Solutions · DropOff` | In the name itself | Medium — separators/brand stacking sometimes rejected on first review | Try after A is verified |
| **C** | `DropOff` | Nowhere — brand is the name | High — needs trademark/brand proof tying DropOff to Carpso Solutions | Only with paperwork |

**Recommendation:** launch as **A** (`Carpso Solutions`), make the profile photo the DropOff logo, and put "DropOff — we carry it to the courier" in the first line of the description. Once verified and in good standing, submit **B** as a display-name change request with your brand assets. Never launch as **C** — a rejected name can lock the number for days.

**Do not** use a name like "DropOff Delivery Zambia Official ✅" — emoji, "official", and generic words are auto-rejected.

---

## 1. Choose the product

| | **WhatsApp Business App** (free) | **WhatsApp Business Platform / Cloud API** |
|---|---|---|
| Setup time | 30 minutes | 2–5 days (business verification) |
| Cost | Free | Free tier + per-conversation pricing |
| Agents | 1 phone + up to **4 linked devices** | Unlimited agents via inbox software |
| Catalogue | ✅ built in | ✅ via Commerce Manager |
| Broadcast | Status only (no bulk) | ✅ approved templates |
| Automation | Greeting/away/quick replies only | ✅ chatbots, CRM, webhooks |
| Best for | **Now** — 100 senders | Month 2+, when you have 2+ agents and order updates |

**Do both, in order.** Run on the Business App today so the campaign is not blocked, then migrate to Cloud API when volume demands it. Migration is supported but the number must be removed from the Business App first — so **keep the Business App free of anything you cannot re-create** (everything below is documented, so you can).

---

## 2. Option A — WhatsApp Business App (do this today)

### 2.1 Install and claim the number

1. Confirm **0968551110** is not already on WhatsApp. If it is on a personal account:
   - Back up chats (Settings → Chats → Chat backup).
   - Install **WhatsApp Business** on the same phone and register with the same number → choose **"Migrate account"** when offered. Chat history and contacts carry over.
2. If the number is on a different handset, move the SIM to the phone that will run support.
3. Verify the 6-digit code by **SMS** (call fallback if SMS fails).
4. Set a **two-step verification PIN** (6 digits) and store it in the company password manager. Losing it means re-verification delays.

> **Critical:** the phone holding the SIM must stay reachable. If support staff change, re-registering takes days. Consider a dedicated Android handset that never leaves the office.

### 2.2 Business profile — exact fields to paste

| Field | Value |
|---|---|
| **Profile photo** | DropOff logo on forest-green, 640×640 PNG, logo occupying ~70% of frame, no text under 24 px |
| **Business name** | `Carpso Solutions` |
| **Category** | `Logistics Service` (secondary: `Delivery Service`) |
| **Description** (256 max) | `DropOff — we carry it to the courier. Book a pickup in the app, a rider collects from your door, photographs every item, and delivers it to the courier counter. Lusaka, Ndola, Kitwe. Call 0968551110.` |
| **Address** | Your real registered Lusaka address (do not use a PO box alone — it weakens verification) |
| **Business hours** | Mon–Sat 06:00–19:00, Sun 08:00–14:00 (match the pickup windows) |
| **Website** | `https://dropoff.carpsosolutions.store` |
| **Email** | `support@carpsosolutions.store` (or the real support inbox) |
| **Catalogue link** | Auto-generated: `https://wa.me/c/260968551110` |

### 2.3 Greeting message (auto-sends to every new chat)

```
Welcome to Carpso Solutions — home of DropOff 🚚

We carry your parcel to the courier so you never queue again.

Reply with a number:
1 — Send a parcel (book a pickup)
2 — Plans and prices
3 — Track a parcel
4 — Talk to a person

Or download the app: https://dropoff.carpsosolutions.store
Help line: 0968551110
```

### 2.4 Away message (outside 06:00–19:00)

```
Thanks for messaging Carpso Solutions (DropOff).

We are closed right now. Pickup windows are 05:30–07:30, 10:00–11:30 and 14:00–15:30.
Leave your name, pickup area and destination — we reply first thing.
For anything urgent call 0968551110.
```

### 2.5 Quick replies (type `/` + shortcut in any chat)

| Shortcut | Message |
|---|---|
| `/book` | `To book: open the DropOff app → Book pickup → choose your window (05:30–07:30, 10:00–11:30, 14:00–15:30) → add the item and the recipient. The rider comes to your door.` |
| `/plans` | `Plans (promo pricing, rises within 3–6 months — your current cycle keeps its rate):\n• Daily Rider — K49 — 1 parcel today\n• Silver — K250 — 10 trips / 30 days\n• Gold — K500 — 25 trips / 30 days\n• Platinum — K750 — 50 trips / 30 days\n• Weekly Sprint — K399 — 20 parcels / 7 days\nPay-as-you-go also available.` |
| `/fare` | `Courier fares are quoted at the counter — we never invent a price. Your rider photographs the depot receipt and you repay exactly that amount in the app. There is no depot queue fee.` |
| `/track` | `Send me the booking reference (starts with DRO-) and I will send your live tracking link.` |
| `/free` | `Your first parcel is free today (Daily Rider pass). Send me the phone number you signed up with and I will issue your code.` |
| `/install` | `Install DropOff: https://dropoff.carpsosolutions.store — sign in with your number, approve the SMS code, and you are in.` |
| `/pin` | `Your 4-digit code is the handover code — only share it with the rider at your door. Never send it in chat.` |
| `/refund` | `I have logged this. Our team reviews payments within 24 hours and replies here with the outcome.` |

### 2.6 Labels (colour-coded, applied to every chat)

| Label | Colour | Meaning |
|---|---|---|
| `01 New lead` | Grey | Messaged, not yet installed |
| `02 Installed` | Blue | App installed, no booking yet |
| `03 First booking` | Green | Booked at least once |
| `04 Plan holder` | Teal | Bought Silver/Gold/Platinum/Weekly |
| `05 Counter fare owed` | Orange | Receipt filed, sender has not repaid |
| `06 Complaint` | Red | Damaged, late, or disputed |
| `07 Rider applicant` | Purple | Wants to ride (route to rider onboarding, not support) |
| `08 Business account` | Yellow | Sends 10+/week, needs a plan pitch |

### 2.7 Catalogue — the "product" part

Catalogue is where "DropOff as a product under Carpso Solutions" becomes visible. Build **five plan items + three service items**.

**How:** Business App → **Business tools → Catalogue → Add item**. Square image, 1:1, 1080×1080, DropOff logo + plan name + price. Keep the artwork identical in style across all items — it reads as one product family.

#### Plan items (price required)

| Item name | Price | Description |
|---|---|---|
| `DropOff Daily Rider — 1 parcel today` | `K49` | `One parcel, one trip, valid 24 hours from activation. Rider collects from your door and carries it to the courier. No rider fee inside the plan. Promo pricing.` |
| `DropOff Silver — 10 trips / 30 days` | `K250` | `10 trips in 30 days. No per-trip rider fee inside the cap. Pickup windows 05:30–07:30, 10:00–11:30, 14:00–15:30. Promo pricing — rises within 3–6 months; your current cycle keeps its rate.` |
| `DropOff Gold — 25 trips / 30 days` | `K500` | `25 trips in 30 days. No per-trip rider fee inside the cap. Best for shops sending daily. Promo pricing.` |
| `DropOff Platinum — 50 trips / 30 days` | `K750` | `50 trips in 30 days. No per-trip rider fee inside the cap. For high-volume sellers. Promo pricing.` |
| `DropOff Weekly Sprint — 20 parcels / 7 days` | `K399` | `20 parcels in 7 days. For a launch, a restock, or a busy week. Promo pricing.` |

#### Service items

| Item name | Price | Description |
|---|---|---|
| `Pickup booking — pay as you go` | `From K49` | `A rider collects from your door and carries the parcel to the courier. You repay only the photographed depot receipt. Courier fares are quoted at the counter.` |
| `Last-mile collection — depot to door` | `From K49` | `Your parcel is already at the courier depot. We collect it and deliver to the recipient's door.` |
| `Business account — bulk sending` | `From K250` | `10+ parcels a week? We set you up on a plan with a named account contact and consolidated invoicing.` |

**Rules for catalogue items**
- One real price per item. Never write "call for price" — it kills the catalogue's value and Meta can flag it.
- Every description ends with a next step ("Reply BOOK" / "Open the app").
- Add the `wa.me/c/260968551110` link to every flyer, poster and business card. It opens the catalogue directly.
- Refresh images when prices change. Stale catalogue prices become disputes.

### 2.8 Status and Channel

- **Status:** post 1×/day, 9:00 and 17:00. Rotate: a rider at a door, a stamped photo, a depot counter, a satisfied recipient, a plan card. Text ≤ 8 words. This is your free reach engine — a support number with 400 contacts posting daily beats a boosted post.
- **Channel (optional, one-way):** `DropOff Zambia` — announcements only (price changes, new cities, holidays). Never put support questions there; route them to the chat.

---

## 3. Option B — Cloud API (when you outgrow the app)

Trigger to migrate: **2+ agents answering at once**, or you want automatic booking updates pushed to WhatsApp.

### 3.1 Prerequisites
1. **Meta Business Suite** portfolio named `Carpso Solutions` (business.facebook.com).
2. **Business verification** — upload: certificate of incorporation, TPIN, director ID, utility bill or lease, and a website/domain you control (`carpsosolutions.store`). Verification typically takes 2–10 business days.
3. **Domain verification** of `carpsosolutions.store` in Business Settings → Brand safety → Domains (DNS TXT or HTML file).
4. A **Facebook Page** for Carpso Solutions (required asset) and, ideally, an Instagram business account.
5. A **payment method** on the portfolio (needed for click-to-WhatsApp ads and paid conversations).
6. **Two admins** with 2FA on the portfolio. One admin is a single point of failure.

### 3.2 Create the WhatsApp Business Account (WABA)
1. Business Settings → **Accounts → WhatsApp accounts → Add**.
2. Name it `DropOff Support` (internal name — this one is free-form, it is *not* the public display name).
3. Add the phone number. **A number can only be on one WhatsApp product at a time.** If it is currently on the Business App, complete the app→API migration flow, or use a second number (`0968551111`) for API and keep `0968551110` on the app during transition.
4. Submit the **display name** — `Carpso Solutions` (see §0).
5. Enable **two-step verification** on the WABA and store the PIN.

### 3.3 Connect an inbox
Use a provider (360dialog, Twilio, Gupshup, Wati, Respond.io) or build against the Cloud API directly. Requirements for whichever you pick:
- Multi-agent with assignment + labels (mirrors §2.6).
- **Template management** from inside the inbox.
- Webhook into your worker so booking events can trigger messages.
- Conversation-based billing visibility.

### 3.4 Message templates to submit

Templates are pre-approved copy. Categories matter: **UTILITY** (about an existing transaction) is cheaper and more likely approved than **MARKETING**.

**UTILITY — booking confirmed**
```
Hi {{1}}, your DropOff pickup {{2}} is confirmed for the {{3}} window. The rider will call when he arrives. Track: {{4}}
```

**UTILITY — item collected**
```
{{1}}, your {{2}} item was collected at {{3}} and is on the way to the courier. Photo evidence is in the app.
```

**UTILITY — delivered to courier**
```
{{1}}, your item {{2}} reached the courier counter. Depot receipt: K{{3}}. Repay it in the app to unlock the receipt photo.
```

**UTILITY — delivered to recipient**
```
{{1}}, your item {{2}} was delivered and confirmed by the recipient. Thank you for using DropOff.
```

**MARKETING — plan offer** *(opt-in only)*
```
{{1}}, your DropOff plan is running low. Gold gives you 25 trips for K500. Reply PLAN to renew. Promo pricing — your current cycle keeps its rate.
```

**Rules that get templates rejected**
- No ALL CAPS, no excessive punctuation, no "FREE!!!", no misleading urgency.
- Variables must have a sample value when you submit.
- Marketing templates require **documented opt-in**. Keep an opt-in record per number (a WhatsApp reply saying "yes" is enough if you log it).

**Do not move OTP to WhatsApp.** Your sign-in codes stay on SMS — WhatsApp authentication templates need a separate, dedicated number and add a failure mode during the exact moment a new sender is trying to join. Keep OTP on SMS.

### 3.5 Green tick (official business account)

You do **not** need the green tick to launch, but it lifts reply rates noticeably. Requirements in practice:
- Business verification complete.
- Display name approved and matching your brand/registration.
- Two-step verification on.
- Messaging quality rating **green** (i.e. people do not block/report you).
- Public presence: website mentioning the brand, plus press or a verified Facebook/Instagram.
- Then request "Official Business Account" — approval is discretionary and can take weeks.

**Quality rating is the real gate.** One bulk blast to people who never opted in can drop you to yellow/red and delay the tick for months.

---

## 4. Wiring WhatsApp into the DropOff funnel

### 4.1 Links
| Purpose | Link |
|---|---|
| General chat | `https://wa.me/260968551110` |
| Prefilled campaign text (attribution) | `https://wa.me/260968551110?text=SEND100-TT` |
| Catalogue | `https://wa.me/c/260968551110` |
| Flyer QR | QR encoding `https://wa.me/260968551110?text=FLYER` |

Generate one QR per channel (`FLYER`, `TT`, `FB`, `STATUS`, `RIDER`) and print the tag under the QR in small text. That single detail tells you which poster produced which signup.

### 4.2 Click-to-WhatsApp ads
Meta ads → objective **Engagement → Messaging apps → WhatsApp**. Use the video ad from the campaign doc. Put the offer in the ad's greeting, not in the video, so the first message does the closing.

### 4.3 Handover to the app
The chat's job is to get one action: install and sign in. Then the app does everything else (booking, tracking, receipts, repayment). Keep the chat for:
- onboarding a sender who is stuck,
- issuing free-parcel codes,
- counter-fare questions,
- complaints,
- plan renewals.

Never take a booking *in the chat*. If you do, you lose the audit trail, the photo evidence, and the repayment flow — and you create the exact disputes the app exists to prevent.

---

## 5. Compliance and brand guardrails

| Rule | Why |
|---|---|
| Users only ever see **0968551110**. Never publish **0976847775**. | The second line is the transaction/disbursement number. Publishing it invites fraud attempts. |
| Never say "insured". Say "you can declare a value and add quoted protection". | Cover is quoted protection, not insurance, until legal sign-off. |
| Never quote a courier fare. Say "quoted at the counter". | We do not invent courier prices. |
| Always say **repay**, never "we charge you the depot fare". | It is a reimbursement of the rider's outlay. |
| Say "no depot queue fee" — never show K15. | The queue fee is waived. |
| Plans are "promo pricing — rises within 3–6 months; your current cycle keeps its rate". | It is a real commercial commitment and must be disclosed. |
| Marketing messages only to numbers that opted in. | Meta policy + Zambia data protection. |
| Delete catalogue/price images within 24h of a price change. | Stale prices become refund disputes. |
| Never ask for a customer's 4-digit handover code in chat. | It is the door/pickup secret. |
| No screenshots of a sender's address or phone in Status. | Privacy; also the app blocks screenshots for this reason. |

---

## 6. Daily runbook (15 minutes, twice a day)

**Morning (07:30)**
1. Clear the overnight queue. Reply to everything within 15 minutes — reply speed is the single biggest driver of conversion.
2. Issue free-parcel codes to new signups (label `02 Installed`).
3. Check `05 Counter fare owed` — message each sender the amount and the pay link.
4. Post one Status.

**Evening (18:00)**
5. Follow up every `02 Installed` from the last 48h: *"Your free parcel is still waiting — when should the rider come?"*
6. Move converted chats to `03 First booking`.
7. Log the day's numbers in the tracking sheet.
8. Post one Status.

**Weekly (Monday)**
9. Report: new chats, installs, signups, first bookings, plans sold, average first-reply time.
10. Archive resolved chats; keep `04 Plan holder` and `08 Business account` permanently.

---

## 7. KPIs

| Metric | Target |
|---|---|
| First reply time | **< 15 min** in business hours |
| Chat → install | > 50% |
| Install → signup | > 55% |
| Signup → first booking | > 40% |
| Catalogue views per week | > 200 |
| Block/report rate | < 0.5% (keeps quality green) |
| Status views per post | > 250 |

---

## 8. Common rejection reasons and the fix

| Problem | Cause | Fix |
|---|---|---|
| Display name rejected | Name does not match registration, or contains slogans/emoji/"official" | Use exactly `Carpso Solutions`; resubmit after business verification |
| Business verification rejected | Blurry documents, name mismatch, address not matching | Re-upload high-resolution scans; ensure the legal name matches the certificate character-for-character |
| Template rejected (marketing) | Too promotional, ALL CAPS, no opt-in evidence | Rewrite in plain sentences; keep the offer in one clause |
| Number cannot be registered | Still active on WhatsApp / Business App | Delete the account on the old device first, or use a second number |
| Quality dropped to yellow | Bulk messaging to non-opt-ins | Stop broadcasts; reply only; wait for the rating to recover |
| Catalogue item rejected | Price missing, image with too much text, prohibited category | Use a clean 1:1 image, real price, plain description |

---

## 9. Launch checklist

- [ ] `0968551110` registered on WhatsApp Business, 2FA PIN stored
- [ ] Profile: name `Carpso Solutions`, DropOff logo, category Logistics, description pasted
- [ ] Hours, address, website, email filled
- [ ] Greeting message live
- [ ] Away message live
- [ ] 8 quick replies created
- [ ] 8 labels created
- [ ] 8 catalogue items published (5 plans + 3 services)
- [ ] `wa.me/c/260968551110` added to flyer, poster, business card, app support link
- [ ] 5 QR codes generated with channel tags
- [ ] Meta Business Suite portfolio `Carpso Solutions` created, 2 admins with 2FA
- [ ] Domain `carpsosolutions.store` verified
- [ ] Business verification submitted
- [ ] Tracking sheet live with the 9 columns
- [ ] Staff briefed on the 10 compliance guardrails in §5
- [ ] Cloud API migration scheduled for month 2
