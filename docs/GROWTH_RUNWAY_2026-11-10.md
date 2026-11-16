> **Pricing note (2026-11):** the catalog rebalanced. Weekly Sprint K399 (20/7d), Silver K250 / 10 (30d), Gold K500 / 25, Platinum K750 / 50 are the only live packs; Daily Rider K49 and Daily Dash K69 are retired. Any number contradicting this in the body of this document is stale — `/plans` and `docs/PLANS_BENEFITS.md` are authoritative.

# Growth Runway & Reinvestment Plan — 2026-11-10

Companion to `docs/PLAN_ECONOMICS_2026-11-10.md` (the per-tier money audit). Data basis: D1 snapshot 2026-11-10 — 30 accounts, 4 jobs, **K0 collected revenue to date**, 0 active subscriptions. Low-confidence zone; revisit at 30+ paid jobs.

## 1. Week-one truth check: 100–500 Silver (K250) subscribers via a Facebook campaign?

**No.** This is not pessimism, it's arithmetic and trust-stage mathematics:

**The funnel for "pay K250 today for a subscription from a brand they've never shipped with":**

| Funnel stage (Zambia, FB, vigorous spend K500–K2,000) | Realistic range |
|---|---|
| Reach from a K500–K2,000 budget (Zambian CPM ~K15–K45 est.) | 30,000–100,000 impressions |
| Click-through (cold offer, no brand) | ~1–2% → 300–2,000 clicks |
| App install from click | ~15–30% → 50–600 installs |
| Installs that activate (train accounts, no job yet) | ~30–50% |
| Second action = FIRST EVER BOOKING (the real barrier) | ~10–25% of actives → 15–150 |
| Booking → **pay K250 subscription in week one** | ~5–20% → **5–30 subs** |

- The conversion drop from "I shipped one parcel, it went well, I got my delivery" (a proven experience) to "trust us with K250 upfront" is the widest, deepest drop in the funnel — and week one you have **0 completed deliveries, 0 reviews, 0 ratings, no rider fleet evidence**.
- **100+ paying subscribers week one** requires either a strong existing brand, a physical presence people can walk into, or someone genuinely going door-to-door with day-one capacity — none of which can be bought with a week of ads.
- **The REAL week-one goals that a vigorous campaign can hit**: 200–600 installs; 30–100 first bookings if pickup capacity is actually ready; and Daily Rider days purchased (K49 has a 40× lower trust barrier than K250/month).

**What a K250 Silver week-one pitch will instead teach the market:** that a pre-launch app asks for big money → installs without conversions + negative comments ("they charge how much?") in review posts. Spend the same budget on Daily Rider (get them INTO trucks/shipping transactions), then let the Predict card upsell Silver at the moment of proven value.

### Convert trial → subscriber (the actual engine)

The honest Predict recommender was deployed today without needing an app update (worker version `1aa99aa4`): it shows break-even teasers, honest Daily Rider comparisons, and recommends a plan only when it genuinely saves money. That IS your subscription-sales engine — but it sells when the DATA says yes, not when ads say yes.

## 2. Money behaviour when subscriptions DO start arriving — the lump-sum problem

Subscriptions arrive as upfront lumps (K250 × N). Treat them as **prepaid service liabilities with a delivery obligation attached**, not as profit. Subscription money is ONLY yours once the month's trips actually run under the plan cap.

### Suggested allocation at each payout cycle

| Bucket | Share | Purpose |
|---|---|---|
| **Service float (OBVIOUS priority)** | 55–65% | Rider payouts on plan jobs, fleet coordination, wait-time float, cover claims reserve |
| **Ops reserve** | 15–20% | SMS/infra, depot incidentals, refunds |
| **Growth spend** | 15–20% | Ads, rider onboarding, loyalty/referral — spent only on measurable channel CAC |
| **Plain runway (untouched)** | 5–10% | Never allocated; absorb surprises (a claim, a Lipila delay, a strike week) |

**Do not count plan revenue as yours until that plan month closes within cap and zero unresolved payouts.** That single rule is what keeps the startup alive.

## 3. Reinvestment priorities (in order)

1. **Rider supply一周 reliability** — nothing kills conversion like an unmet pickup window. Each failed window is a lost trust event that costs roughly 5+ future referrals.
2. **Depot float & partner relationships** — counter procedures greased, small float for exceptional days.
3. **First-mile/last-mile consistency BEFORE scale** — with <100 deliveries/month, your competitive attack is reliability per trip, not reach.
4. **Retention pivots** — SMS nudges, delivery reliability metrics (on-time %), Predict-based plan upsell.
5. **Paid acquisition** — reinvest only after CAC ≤ K40–60 per ACTIVATED (first-booking) user, not per install.

## 4. On your "buy low, sell high" idea to lift the business

**Direct answer: don't run speculative trading with startup delivery cash.** Reasons specific to DropOff:

1. **Liquidity structure is wrong way round.** Subscriptions arrive upfront but are owed back as service; trading positions (commodities, goods, FX) lock the exact liquidity you'll need for rider payouts — with a settlement horizon you don't control.
2. **Concentration inside a startup**: your business ALREADY has 100% of your time + reputation + energy committed. A second high-variance bet means when one of the two goes sideways you're firefighting both with the same night's sleep.
3. **It's the wrong optimisation anyway.** DropOff's actual "buy low sell high" — the one already inside your economics — is **capacity arbitrage**: buy rider off-peak day capacity (they need days filled), sell it through Daily Rider passes and plan slots at peak convenience. That's the same trade with products you control and at margins you set. Everything else is a distraction until 1,000+ active trips/month.

**If you still want to trade from the side**, use money that is:
- Outside the business ledger entirely (a separate wallet, never merged)
- ≤10% of your personal savings, ≤ a strict cap written down
- Funded by money you could lose 100% of without noticing
- Never topping up from business revenue, and never "borrowed back" mid-trade

That version doesn't hurt. The version that silently takes rider payout money and puts it into a position is how courier startups die.

## 5. The ladder to 5,000 subscribers

Each rung has a trigger metric; don't skip to ads for the next rung before hitting it.

| Stage | Subs | Trigger metric (hit BEFORE spending here) | Primary lever | Est. duration |
|---|---|---|---|---|
| 0. Proof | 0 | 30+ paid jobs, first K0→paid conversion | Personal network + WhatsApp + depot walk-ins | Now → 4–6 weeks |
| 1. First 100 subs | 0→100 | Delivery reliability ≥90% on-time; ≥50 5-star or no-rating deliveries | Predict recommender upsell + Daily Rider→plan convert | Months 1–3 |
| 2. Local repeat merchants | 100→500 | Churn <5%/mo; 10 merchants sending weekly | Merchant outreach, custom routes, FB retargeting (warm) | Months 3–6 |
| 3. Inter-city scaling | 500→1,500 | Partner courier coverage on 5–10 routes; depot ops tested | Route expansion + reviews flywheel | Months 6–12 |
| 4. Paid acquisition engine | 1,500→5,000 | CAC ≤ K50/activated user; W1 retention ≥40% | Full-funnel paid ads with measured CAC + referral system | Year 1–2 |

At 5,000 subs on an ARPU of ~K275/mo (mix), monthly top-line is ~K1.37M with net (post-Levers) ~K500K+/mo. Every part of that outcome depends on the payout policy and reliability being correct at stage 1 — not on ads magic at stage 4.

## 6. What to do this week (priority order)

1. **Decide the in-plan rider payout policy** (Plan Economics doc, Lever A). This single decision determines whether plans are profitable.
2. Ship what's already built: Predict's honest recommender (live), Daily Rider flow. Show it to 10 real merchants and watch their reaction before spending a kwacha on ads.
3. Do the first paid jobs end-to-end (money collected, rider paid, POD uploaded) — you have 4 unpaid jobs; close that loop 10 times before the first real marketing.
4. Spend the FIRST ad budget on: Daily Rider intro ads (K49 trust barrier) in ONE city, ONE vehicle class, one depot. Measure installs→activations→first bookings→K49 conversion. Only then scale.
5. Revisit these docs at 30+ paid jobs.
