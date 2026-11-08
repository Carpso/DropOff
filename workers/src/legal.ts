// Legal page content for the Play Store listing (privacy policy URL must be
// live at https://dropoff-api.godfreymoseskalambo.workers.dev/legal/privacy).
// Rendered with a tiny markdown subset converter in index.ts.

export const PRIVACY_MD: string = `# DropOff — Privacy Policy

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

export const PRIVACY_TITLE = 'DropOff — Privacy Policy';
