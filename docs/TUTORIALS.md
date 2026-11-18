# DropOff tutorials — rider & sender training pack

Purpose: one source of truth for the short in-app guides and any future video/PDF
tutorials. The app tutorial lives in `app/lib/widgets/tutorial_sheet.dart`
(Account → "How DropOff works", and the book icon on the rider Task Queue).
This document is the script to turn those steps into training material for every
new sender and rider.

## Vocabulary (fixed 2026-11-18)

Use **sender / senders** everywhere in UI, docs and training. Never "seller" in
user-facing copy. "Courier" is the partner who carries the parcel city-to-city;
"rider" is our local first-mile rider. DropOff never collects courier counter
fares.

## Tutorial 1 — Sending a parcel (6 screens, ~90 seconds)

1. **Set up** — "Sign in with your phone number or email. Add your photo so your
   rider recognises you. In Account → Door handover PIN you can set your own
   4-digit door code."
   - Show: Account screen → photo, Door handover PIN.
2. **Book** — "Pick the depot, your pickup address, what the parcel is and its
   size. Add a parcel photo. Choose a 06:00, 10:00 or 14:00 slot."
   - Show: Booking screen, photo preview, full-width vehicle field.
3. **Pay** — "Approve the momo prompt. Plan members use included parcel slots;
   otherwise you pay the quoted fee up front. The courier counter fare is paid
   separately at the counter."
   - Show: payment prompt, plan banner.
4. **Pickup code** — "You get a 4-digit PICKUP code by SMS. Give it to the rider
   when they arrive — never before."
   - Show: SMS example, dialog naming who holds the PIN.
5. **Track** — "Follow the parcel live door → depot → courier. Same-city
   recipients get no SMS PIN; confirm receipt in the app when it lands."
   - Show: tracking screen, receipt confirmation.
6. **Rate** — "Rate the rider, courier and sender after the trip."
   - Show: rating sheet.

## Tutorial 2 — Riding for DropOff (6 screens, ~2 minutes)

1. **Link device** — "Sign in, link this phone, add selfie and documents.
   Verification is required before dispatch."
2. **Task queue** — "The TODAY card shows live stats and your pace/bonus. Jobs
   arrive in timed batches, grouped by depot — one run, several senders."
3. **Navigate** — "Tap Navigate. The 3D bike faces your destination; the compass
   puts your heading at the top; the map auto-zooms near the stop; voice reads
   the turns."
4. **Collect** — "Ask the sender for their 4-digit pickup code. Photograph every
   parcel once. At a door, ask for the recipient's door PIN."
5. **Depot drop** — "Drop at the depot. Photograph the parcel and the WRITTEN
   receipt, type the exact amount on each receipt, tap Submit drop — the task
   ticks off. Never collect cash from senders."
6. **Pay & bonuses** — "Salary K3,000/month includes fuel. Month-close bonuses
   need the pace target; extras over target are capped. Stats sync live."

## Production checklist (for the training videos)

- Record on a real phone with notifications ON so prompts and toasts appear.
- Use a test account with a plan AND a pay-as-you-go account to show both paths.
- Capture each step as a 5–10 s clip; overlay the matching line from this doc.
- Keep clips under 15 s each; export one video per tutorial (sender / rider).
- Add captions in English (SMS stays English-only until locale preference lands).
- Review monthly with `docs/PLANS_BENEFITS.md` and current app copy; update both
  this file and `tutorial_sheet.dart` together so the app never drifts.

## Distribution

- In-app: this guide (offline, always available) from Account and Task Queue.
- Onboarding: share the app tutorial link/screen at registration and rider
  verification.
- Print: one-page QR to the in-app tutorial at agent/depot counters.
