// Legal page content for the Play Store listing (privacy policy URL must be
// live at https://api.carpsosolutions.store/legal/privacy).
// Rendered with a tiny markdown subset converter in index.ts.

export const PRIVACY_MD: string = `# DropOff - Privacy Policy

Last updated: November 2026

## Who we are

DropOff is Zambia's first-mile parcel marketplace: senders book a local rider to pick up a parcel at their door and drop it at a nominated courier depot branch **within the same city**, and pay through Lipila mobile money. City-to-city transport is handled entirely by the courier you choose — DropOff does not carry parcels between cities and is not a courier itself. This policy explains what personal information we collect, why, and your rights over it.

## Handover codes, parcel photos and proof of delivery

At booking we send the parcel recipient a 4-digit DropOff code by SMS. The assigned rider must enter this code to mark a door delivery complete. Senders may attach a photo of the parcel at booking; riders may photograph the parcel at pickup and at the depot/courier drop-off or handover. We may compare booking and drop-off photos (including with automated checks) to help detect parcel swaps or false-parcel disputes. Codes and photos exist solely as delivery and anti-fraud evidence — not for advertising.

## What we collect

- **Account details:** email address, full name, and mobile-money phone number (used for refunds, payouts, and job status).
- **Job details:** pickup location, the nominated depot branch, the recipient's city for the onward courier leg, recipient name and phone, parcel description, declared parcel value, weight class, payment method, booking history, and any parcel photo you attach at booking.
- **Location:** your live GPS fix only when you explicitly share it through the Rider live position feature; it is shown to the sender of your jobs so they can track the parcel. Riders may capture pickup/drop-off or handover photos as booking evidence.
- **Device & security:** your Firebase Cloud Messaging token, device identifiers and platform so we can send you job status and payment notifications and detect unauthorised devices. You can turn this off by signing out.
- **Payments:** Lipila transaction references and payment status. We never see or store mobile-money PINs or card numbers.

## Why we collect it

- To match you with riders and nominated depot branches, complete first-mile bookings, and hand the parcel to your chosen courier.
- To pay riders and send refunds via mobile money.
- To show you your booking history and standing orders.
- To send push notifications about your parcels and payments.
- To prevent fraud (velocity checks, duplicate-booking detection, handover/parcel-photo verification, booking-deposit and no-show controls) and meet legal obligations.
- To verify access to shared parcel tracking links, we may send a one-time SMS code to the sender or recipient phone number on the booking before showing tracking details.

## Sharing

- Your pickup and drop-off details go only to the rider handling your job and the depot branch you nominated. The onward city-to-city leg is operated by your chosen courier under their own arrangements.
- Payment processing goes through Lipila under Lipila's own terms.
- We do not sell your personal data.

## Optional parcel cover (quoted protection)

If you choose optional parcel cover, we record your declared value and provide a **quote** (fee/cap) for tracking and dispute context. **This is not automatic insurance.** Cover is not active unless and until DropOff confirms eligibility and terms in writing or in-app. Limits, exclusions, evidence requirements (photos, handover/OTP, parcel-check, partner confirmation), and claim review rules apply. Do not rely on a quote as insurance coverage.

## Your rights

You may ask to see, correct, or delete your account data at any time by emailing support or using the sign-out/unlink flow, which removes your stored session and push token from this device. Server records needed for financial audit are kept as required by law.

## Security

API calls are JWT-authenticated over HTTPS. Sessions are device-scoped and can be revoked with a password reset, push tokens are keyed to your phone so another user on the same device cannot receive your notifications, and admin actions are audit-logged.

## Contact

Questions about this policy: support@carpsosolutions.store
`;

/** Minimal markdown renderer: h1/h2, bullet lists, **bold**, paragraphs. */
export function mdToHtml(md: string): string {
  const esc = (s: string) =>
    s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
  return md.split('\n').map((raw) => {
    const line = raw.trimEnd();
    if (!line.trim()) return '';
    const strong = (s: string) =>
      esc(s).replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>');
    if (line.startsWith('## ')) return `<h2>${strong(line.slice(3))}</h2>`;
    if (line.startsWith('# ')) return `<h1>${strong(line.slice(2))}</h1>`;
    if (line.startsWith('- ')) return `<li>${strong(line.slice(2))}</li>`;
    return `<p>${strong(line)}</p>`;
  }).filter(Boolean).join('\n')
    // wrap consecutive <li> runs in <ul>
    .replace(/((?:<li>.*<\/li>\n?)+)/g, (_m, lis) => `<ul>${lis.replace(/\n(?=<)/g, '').replace(/\n$/, '')}</ul>\n`);
}

export const PRIVACY_TITLE = 'DropOff - Privacy Policy';

export const TERMS_MD: string = `# DropOff - Terms of Service

Last updated: November 2026

## Who we are

DropOff is a first-mile parcel marketplace operated in Zambia by Carpso Solutions. We match a sender whose parcel needs a door-to-depot ride with an independent local rider, and we arrange delivery to the courier depot branch you nominate. **DropOff is not a courier, not a carrier, not a logistics company and not an insurer, and we never take custody of parcels between cities.** The city-to-city leg is a contract between you and the courier you choose.

## How a booking works

- You book in the app with pickup address, recipient, parcel weight class and description.
- DropOff dispatches algorithmically to the nearest available verified rider. Staff cannot hand-pick a rider for you.
- The rider collects, drops at the branch you nominated. You pay the rider's leg via Lipila mobile money **up front**; your rider is dispatched once the prepayment lands.
- The courier's counter fare is **your arrangement with the courier**, paid by you at the depot counter. DropOff never collects courier counter fares; if your rider fronted it on your behalf, you repay exactly the receipt amount plus processing in the app.
- Delivery to your recipient's door (last mile) is an optional add-on with its own code (OTP) handover.

## What we charge

- **PAYG trip:** rider leg price + processing (the live quote shown at booking).
- **Packs & subscriptions:** the pack price you pay buys the pack benefits shown at purchase time (parcel caps, free legs, lower per-parcel processing). Silver / Gold / Platinum monthly packs and Daily Pass / Sprint passes; terms print at checkout and are changeable at renewal.
- **No hidden fees:** counter fare is always the courier's price with the courier. Pack upcharges or overage rates apply only if you exceed the pack's entitlements; your app shows them before you confirm.
- **Refunds:** if the leg can't run (rider no-show, cancelled hold that never dispatched), the DropOff prepayment returns to your original momo. If we fail you after pickup, we investigate with evidence (photos, OTP, GPS).
- **Cancel before pickup:** cancel in the app before pickup and the unspent prepayment is refunded. After pickup, cancellation closes as delivered-to-depot at the counter.

## Booking and no-show policy

- Repeatedly ghosting riders (3 unattended pickups / 14 days) can restrict booking for two weeks.
- Unpaid held bookings auto-cancel after 24 hours; no money is taken.
- If your parcel never reaches the depot, contact support with your booking ref; we review photos, OTP and GPS.

## Your account

- One account per phone number. Don't share riders, passwords or OTP codes; a compromised account can be reset from the app or via support@carpsosolutions.store.
- You remain responsible for what you put in parcels: **no dangerous goods, no cash, no documents of forged value.** We can refuse parcels and will report illegal contents.
- **Quoted protection** (the optional parcel value cover at booking) is not insurance: it is a **quote** — fee and cap — not coverage, not an insurance product, and not a guarantee. Cover applies only when confirmed and only as stated at the point of booking.
- By using DropOff you agree to receive transactional SMS/push for your bookings. You can reply STOP to our SMS sender at any time; transactional messages (OTP, codes, payment and parcel status) still arrive, marketing does not.

## Disputes and evidence

- Delivery disputes are settled on evidence: booking/drop-off photos, GPS pings, chat history, OTP confirmation, and the depot counter receipt for courier-paid legs.
- We may record and store that evidence to resolve parcel disputes and prevent fraud.
- Claims fade fast — 14 days from delivery/dispute first reported. Unverified claims on missing evidence may be declined.

## Liability

- DropOff's maximum total liability for any parcel is limited to the lower of (a) the DropOff fees you paid for that parcel, or (b) the declared value at booking (if your parcel exceeded courier mass/dimensions limits, also capped at the courier's own admission).
- We are not liable for: indirect or consequential loss (lost profit, events), parcels booked under false description, courier delay or loss on the onward leg, or courier counter-fare disputes between you and the courier.
- Nothing here limits liability that cannot be limited by Zambian law.

## Pack codes and refunds

- Offline pack codes are single-use, non-transferable, and their remaining value is forfeited on refund. All sales of pack codes are final.

## Privacy

See our [Privacy Policy](/legal/privacy). We collect the minimum needed to run the service and do not sell personal data.

## Law and disputes

- These terms are governed by the laws of the Republic of Zambia.
- Parties must attempt to resolve disputes by written notice to support@carpsosolutions.store before any legal action. If unresolved within 30 days, disputes proceed to the courts of Lusaka, Zambia.
- We may update these terms; current terms always at /legal/terms. Continued use after a material change is acceptance.

## Contact

support@carpsosolutions.store

Carpso Solutions, Lusaka, Zambia
`;

export const TERMS_TITLE = 'DropOff - Terms of Service';
