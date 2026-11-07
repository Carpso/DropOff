# DropOff growth, trendiness & moat strategy

How to make DropOff interesting, shareable and hard to copy in Lusaka (and Zambia beyond it), and how to
pull sellers onto subscription plans instead of pay-as-you-go.

## 1. The honest baseline

DropOff's job is the painful **last 5 km before the courier's intercity leg**: the sender who can't carry a
parcel to Platinum/Mercury/One World/etc. DropOff is "Uber-for-the-first-mile" — and that framing *is* the
marketing. Everything else (app, plans, data) exists to make "a rider is at your door in 30 minutes" the
default expectation for anyone shipping a parcel in Lusaka.

## 2. What makes DropOff trendy & interesting (ship-visible features)

1. **A living map, not a link.** The recipient already gets live rider position on the tracking page. Make it
   the shareable moment: when a parcel is 10 minutes away, the tracking page (and push) says "Your parcel is
   on the last stretch — here's the rider live" with the driver's first name and vehicle. Recipients screenshot
   and post exactly this — it's free earned media with DropOff branding on it (add the wordmark + ref to the
   tracking card's OG/image rendering when we get to web tracking pages).
2. **"Addressed to you."** The tracking page now tags the parcel to the recipient by name/number. That tag is
   the recipient's first impression of the brand — make it delightful (small confetti animation on delivered,
   a "rate the rider" prompt, and a one-tap "I also sell — get my parcels picked up" CTA for recipients who
   are themselves sellers — they're the warmest leads we will ever have).
3. **DropOff Predict.** "Our app knows your parcel is arriving at 10:40 — before the depot tells us." A
   public, visibly-smart feature nobody else in the market has. Put a "How sure are we?" confidence pill on it.
   Sellers feel a smart partner, not a form. Internally it also drives dispatch (§5).
4. **Streaks & milestones for sellers** (Business tab): "12 parcels this month — Silver pays for itself."
   Gamify plan adoption with visible progress rings, not nags.
5. **The unboxing loop for referrals**: every delivered parcel gets a rate-and-refer card
   ("Give 20% off a first booking — get a reward after their first paid drop") shared via wa.me deep link.
   WhatsApp is where Zambian commerce happens; links must unfurl with the parcel image and ref.
6. **Seasonal spikes**: December (diaspora gifts), Easter, back-to-school, maize-harvest marketing,
   elective-government tender season — the admin **demand heatmap** (new, next 7 days per branch × window)
   is the calendar for staffing and for Push/SMS campaigns timed to predicted peaks.
7. **Counter-press presence**: branded rider gear + depot counter posters with plan QR codes ("Scan →
   your parcel goes to the depot without you leaving home"). The depot *is* our walk-in store.

## 3. Bringing sellers onto subscription plans (the retention machine)

Push constant, honest, maths-first nudges — never nags:

| Stage | Signal | Message |
|---|---|---|
| PAYG → Daily Rider | seller ships 1–2 parcels on burst days | "Bursting this week? Daily Rider: K49/day, 2 parcels, rider included — only the days you ship." (visible as `daily_option` in Business → DropOff Predict) |
| Regular → Weekly Sprint | 3+ parcels in 30 days, no plan | "You shipped N parcels at K45. Weekly Sprint is K399/20." (already implemented as the 3+ upsell; now data-driven from Predict) |
| Weekly → Silver | consistently hitting weekly cap | "50% more headroom: Silver K250/mo = 10 parcels, K25 each." |
| Silver → Gold/Platinum | hitting monthly cap mid-cycle | "You'll outgrow Silver 7 days before month-end — Gold keeps the same rate, zero drama." (existing overage nudge, keep) |
| Renewal | 3 days before period_end | momo prompt + SMS, exactly as built — plus a "your parcels last month: N, saved K X" receipt email so the value is felt, not claimed. |

**Offer design that actually converts (and doesn't leak money):**
- **First plan free month** for sellers who complete 2 paid PAYG bookings (KYC-lite = email verified + phone match). Cost of one free Silver month is K0 marginal (rider time is already swept) — buys an entire season of habit.
- **Launch Friday**: every Friday for 4 weeks, one depot branch gets "plan activation day" with an agent + QR signup bonus (the agent and the depot partner both earn K50 per activated plan — self-funding acquisition).
- **Hard rule**: never discount the plan below cost to hook sellers. Discount the *trial*, not the product — margin is the moat's fuel.

## 4. The moat — what stops a copycat

| # | Moat | How we build/defend it |
|---|---|---|
| 1 | **Density flywheel** | Every rider in Kabulonga/Northmead makes every nearby seller's ETA better; every new seller makes riders denser. This is the same moat that made Yango/inDrive dominant — copycats can't buy density, they can only buy *time*. Blitz Kabulonga → Northmead → Kanyama → Chilenje, one neighbourhood at a time (never city-wide, never provincial). |
| 2 | **Proprietary data flywheel (DropOff Predict)** | Every completed leg refines the p50s: pickup→depot, depot→door, by courier, window, branch, weekday. A competitor starting today has zero observations; we have thousands and get better every day. Data is useless to them and priceless to us — this is why Predict ships as visible magic, not a hidden number. |
| 3 | **Trust moat (the only real moat in African logistics)** | KYC'd riders with selfie photos shown to sellers on the tracking page (with a "Verified rider" badge), AI selfie review (catches documents/screenshots/avatars before the admin sees them), photo POD + AI receipt check, named rider on the tracking page, verified-signature chain of custody, escrow-ish wallet float, and a human support inbox that answers in minutes. Trust is what the courier brands (Platinum etc.) already sell — we borrow their credibility and add ride-level accountability they never had. |
| 4 | **Subscription lock-in** | Plans with cycle-based metering, rollover-free expiry, overage discounts and one-tap renewals: the *switching cost* is an identity habit ("my shop runs on DropOff") plus tangibly better unit economics the longer the tenure. The referral loop (20% first-booking promo each side) compounds this socially. |
| 5 | **Depot partnerships** | The couriers are not our competitors, they're the *destination*. Partner-confirmed hand-off (`partner_confirmed` status), counter price capture at depot, partner webhooks/POS — every depot we onboard tightens the knot: sellers get convenience, depots get a steady parcel flow and price authority. A rival would have to re-negotiate the same depots while we're already exclusive. |

## 5. The Yango question — "extend plan usage for normal daily parcel delivery like Yango"

Done, in both of the ways that matter:

1. **One allowance for every normal delivery.** A plan's parcels now pay for any in-app delivery:
   door pickup, courier-depot collection → door, and the last-mile leg — not only the classic drop-off booking.
   Collections consume the same slots. So "my shop's daily parcel runs" are just... covered by the plan, exactly
   like Yango bundling rides into a daily commuter pass.
2. **Daily Rider (K49/day)** — the literal Yango answer: activate today, ship today, done. 2 parcels/day,
   rider included, overage 45% off, windows include `now`. It is deliberately the *top* of the plan ladder's
   psychology (cheapest entry) and deliberately *not* a flat discount — it exists to convert PAYG occasionals,
   then graduate them up (Daily → Weekly → monthly) by showing them their own monthly spend every time they
   open Business.

What we deliberately did **not** do: unlimited/flat daily plans (margin suicide against K45 PAYG), and weekly
auto-renewing subscriptions (Lipila sits on the momo float; weekly churn would drown support).

## 6. 90-day action list (owner-level)

**Week 1–2**
- Sign the first 3 depot partners with confirmed price capture (Platinum Lusaka flagship first).
- Activate 20 founding sellers (seed from your own network): free first plan month.
- Turn on push (FIREBASE_SERVICE_ACCOUNT) so the "rider in 3 minutes" moment actually buzzes.
- Print depot QR posters (K-Yall Studio) and launch "Plan Fridays."

**Week 3–6**
- Market Kabulonga only: 5 riders dedicated + targeted Facebook/WhatsApp (Audience: Kabulonga/Northmead
  small-business groups, grocery/general-dealer corners, 22–45). KPI: 60 plan activations in 30 days.
- Ship rider PWA/manifest polish and the delivered-confetti on tracking (1-day Flutter change, brand-defining).
- Start the WhatsApp catalog bot (seller → "new parcel to Kirunda — pickup now" → booking prefilled by phone match).

**Week 7–10**
- Northmead micro-launch: same playbook; reassign 2 Kabulonga riders to seed density.
- Publish the first DropOff Predict accuracy claim publicly ("Our estimate vs actual: X% within 10 min") —
  press-worthy and links plan-worthiness to app intelligence.
- Introduce referral rewards for *plan activations* (not just bookings): +1 free plan week for both sides on the 3rd referred activation.

**Week 11–13**
- Review Predict vs actuals honestly; tighten the confidence labels; publish the ops heatmap internally as the sweep scheduler.
- Price review with `POST /admin/tiers`: if Silver saturates (over 40% of plan users hitting cap), raise Silver K25→K275 (no grandfathering; grandfather via `cycle_days` loyalty if needed).
- Decision gate: if Kabulonga shows ≥35% week-4 retention and K20+ contribution margin per plan, greenlight Chilenje/Kanyama expansion and one full-time ops person.

## 7. What *not* to do

- **Don't chase B2B e-commerce fulfilment yet** — we'd lose to couriers on volume economics before density pays off.
- **Don't chase price perception fights** — counter fares are partners'; we never undercut them, we vanish the sender's friction to them.
- **Don't sell the plan as "subscription"** — in Zambian SME language: "your parcels ride free every time" / "parcel pass".
- **Don't automate support replies** — AI drafts, humans send. Trust is the brand.
- **Don't expand beyond first-mile + last-mile** until Predict ≥60% within 10 min for a full quarter.
