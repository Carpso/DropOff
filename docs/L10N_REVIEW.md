# Localization review (best-effort)

Status: **machine-assisted pass done; native-speaker review still required before treating translations as final.**

## Locales
- `en` — English (source)
- `ny` — Nyanja / Chinyanja
- `bem` — Bemba / Ichibemba
- `toi` — **Tonga (Zambia) / Chitonga** (ISO 639-3 `toi`, Zambezi/Zambian Tonga — not Malawian `tog`, not Tongan `to`)
- `loz` — Lozi / Silozi

## What was checked (best-effort)
- Keys/structure parity across ARBs and generated `app_localizations*.dart` for critical flows (booking warnings, hold/deposit/slot, handover/OTP warning, cover terms/acceptance, recipients/quick rebook, evidence).
- `toi` consistently labeled as **Tonga (Zambia) / Chitonga** and uses locale code `toi`.
- Product/protocol terms intentionally kept recognizable where appropriate: **DropOff, rider, OTP, SMS, wallet, Sweep, no-show strike** (mixed-language UX is common; confirm with native reviewers).
- Critical meaning preserved: cover is **quoted protection, not insurance**; acceptance/limits/evidence language present; hold/strike/slot warnings are cautionary, not punitive ambiguity.

## Requires human native-speaker review (do before production-final sign-off)
- [ ] **ny**: naturalness, tone (polite/clear), and SMS-length suitability for any future localized SMS.
- [ ] **bem**: naturalness and regional consistency (Copperbelt vs other variants as appropriate).
- [ ] **toi (Zambia/Chitonga)**: confirm Zambian Tonga phrasing (not Malawian Tonga); validate key warnings/consent wording.
- [ ] **loz**: naturalness and diacritics/orthography preferences used in-app.
- [ ] Verify critical consent/legal-adjacent strings (cover terms/acceptance, hold/strike warnings) with a qualified reviewer; **translations do not constitute legal sign-off**.
- [ ] Test on real devices with font scaling; confirm truncation/wrapping in booking, account, rider, and evidence screens.

## Operational notes
- SMS is **English-only** until the user’s locale preference is applied server-side for notifications (by design, to avoid over-texting/misrouting). In-app UI follows `locale_pref`.
- Regenerate after ARB edits: `cd app && flutter gen-l10n` (`l10n.yaml` present).
