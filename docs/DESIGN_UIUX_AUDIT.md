# DropOff — UI/UX & Typography Audit (2026-11-15)

> Direction requested: Paula Scher's typographic discipline applied to our
> texts — a few sizes, extreme jumps, bold statement-making type, no decoration
> doing the work words should do. The goal is not "design awards"; it is an app
> a rider can read standing in sunlight at a depot in Kanyama.

## Verdict in one line

The bones are good — one forest colour, one amber, flush-left copy. The voice
is broken: everything whispers at 12px, so nothing sounds decided. We have a
font-weight habit (w800/w900 on almost every line) instead of a **scale**.

---

## A. Findings — shared across every screen

| # | Problem (what it is today) | Fix | Severity |
|---|---|---|---|
| A1 | ~10 ad-hoc font sizes in play (10/11/12/12.5/13/14/15/16/18/20/25/28/29). No semantic scale — screens argue about size instead of deciding hierarchy. | 7-step scale (below). Nothing sits between steps. | High |
| A2 | w800/w900 everywhere → bold is noise, not emphasis. Emphasis by weight stops working when the baseline is bold. | One weight per role: Display/Title are w900; body w500–600; captions w600. Never w800 for body copy. | High |
| A3 | Body and helper text is `AppColors.muted` (#65736D) at 11–12px — fails the sunlight test for riders outdoors (contrast ~4.0 best case, smaller sizes worse). | Running text uses `AppColors.ink` ≥ 12.5px; muted only for captions, never for instructions. | High |
| A4 | No display-scale statement exists anywhere — the app never says one decisive thing per screen. | One hero statement per screen. Home already has one — keep it. | Medium |
| A5 | Cards everywhere, radius drift: 10/12/13/14/16/20/28 all used. | One radius family: 20 cards, 14 inputs, 16 CTA, 999 pills. 12 only for inside-card rows. | Low |
| A6 | Icons on every card header — decoration doing structure's job. | Icon = noun (truck, parcel), never a bullet point. | Low |
| A7 | Copy hedges: "… wouldn't it be nice / the courier you choose / we only run the local collection". | Declarative sentences. "You pick the courier." | Medium |
| A8 | Double assertions: "No cash, riders never handle the money" + "no hardcoded pricing" + "the rider never handles cash" repeat. | One clause, one claim, per card. | Medium |
| A9 | Numbers rarely use tabular figures; money at 13px unreadable at a glance. | All money = `AppType.price` (20–26px, w900, forest). | Medium |
| A10 | Every error hedges with "(${res.error})" raw codes in user copy. | Error = **What happened — what to do next**. Never a bare code outside admin. | High |

## B. The type scale (replaces ad-hoc sizes)

| Token | Size / line-height | Weight | Use |
|---|---|---|---|
| `AppType.display` | 32 / 34 | w900 | One hero statement per screen (home, bookings-empty, share sheet) |
| `AppType.title` | 22 / 26 | w900 | Screen titles / section headers |
| `AppType.subhead` | 16 / 21 | w800 | Card titles, list headers |
| `AppType.callout` | 13 / 17 | w700 | Labels, chips, phone rows |
| `AppType.body` | 12.5 / 17 | w500–600 | Running text (ink, never muted) |
| `AppType.caption` | 10.5 / 15 | w600 muted | Helper, footnotes — max one per card |
| `AppType.price` | 22 / 26 | w900 forest | **Every money figure on screen** |
| `AppType.eyebrow` | 10 / 12 | w800 +1.1 ls | Pills, tags, breadcrumb |

Rules
- Max two weights per screen.
- Any text the user must act on is ≥ 13px. Body below 12px is banned.
- Money, always the price token. Never inline 13px money again.
- Line-height ≥ 1.4 for ≤ 13px copy; 1.15–1.25 for display.
- Letter-spacing: −0.8 below 20px, 0 at 16px, +1.1 only for eyebrow caps.

## C. Copy rules (how we write)

1. **Say it once.** If the helper repeats the title, delete the helper.
2. **Verbs, not nouns, on buttons.** "Book a pickup" — not "Submit".
3. **Numbers beat adjectives.** "K75 one leg" beats "affordable rate".
4. **Cut the hedge.** no "please", "just", "actually", "in order to", "as well".
5. **Second person.** You/your. Never "the sender" in end-user copy.
6. **Errors answer two questions**: what broke + what to do. Pattern:
   `<plain fact> — <one action>.`
   e.g. `Prompt not sent — check the momo balance, tap Pay again.`
7. **Bans** (any string containing these must justify itself): "do not hesitate",
   "simply", "just", "unfortunately", "seamless", "leverage", "solutions",
   "please note", "kindly".
8. **Banned raw-error leaks** to non-staff users: network_error / lipila_init_failed /
   403 / 500 / constraint codes — map to plain language (admin console excepted,
   where codes earn their keep).
9. **One call-to-action per card.** Two CTAs max per screen, with strict dominance:
   amber primary, white secondary, text tertiary.
10. **Small caps only for the eyebrow** (11px, +1 ls). No faux-bold caps elsewhere.

## D. What was changed (2026-11-15, worker-side placeholders excluded)

- Card helper/microcopy consolidated; running text promoted from muted → ink
  where it carried instructions; money promoted to 16–22px w900 on price cards.
- All remaining `res.error` raw leaks in end-user toasts on booking / pay /
  share / subscribe paths now render through the plain-language mapper.
- Hero copy kept verbatim (it's the one line Scher would keep); one declarative
  line tightened in collections ("Rider fee from K45" → fee-check pattern).

## E. Backlog (next pass, not in this commit)

- Radius unification 20/16/12/999 across cards/CTA/inputs/pills.
- Icon austerity: remove decorative Icons from section headers; nouns only.
- Empty states: one monumental display line + one CTA (bookings-empty hero).
- Waybill print copy: "Hand this screen to the counter." (4 words).
- App icon + Play store: type-only lockup, no illustrative background.
- Reduce Roboto weights to Regular + Bold (halve the font payload).

## F. Pass/fail checklist for any new screen

- [ ] One word answers "what is this screen?" — said at Display/Title size
- [ ] Running text is ink on white, ≥ 12.5px
- [ ] Every money value uses the price token
- [ ] Buttons are verbs; max two per card
- [ ] Helper does not repeat the title
- [ ] Zero raw exception codes visible to customers
- [ ] Amber used for exactly one thing — the single best action on the screen
- [ ] Readable at arm's length in sunlight (riders/depots)
