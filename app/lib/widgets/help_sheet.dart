import 'package:flutter/material.dart';

import '../ui/app_theme.dart';

/// Full-text help behind a "?" icon — every screen carries no narration,
/// only one short line + "?" opens this. Nothing is deleted, only moved.
abstract final class HelpTopic {
  static const signIn = 'sign_in';
  static const courierFare = 'courier_fare';
  static const parcelPhoto = 'parcel_photo';
  static const forbiddenItems = 'forbidden_items';
  static const depositRejection = 'prepay_rejected';
  static const planCap = 'plan_cap';
  static const plansBlurb = 'plans_blurb';
  static const depotReceipts = 'depot_receipts';
  static const recurring = 'recurring';
  static const packCode = 'pack_code';
  static const referralReward = 'referral';
  static const deviceList = 'devices';
  static const biometric = 'biometric';
  static const offlineBuild = 'offline';
}

const _topics = <String, ({String title, List<({String heading, String body})> rows})>{
  HelpTopic.signIn: (
    title: 'How sign-in works',
    rows: [
      (heading: 'No password, no email required', body: 'Your phone number is your identity. D1 stores a hash of the 6-digit code we SMS you — never the code itself.'),
      (heading: 'Passwordless sign-in', body: 'Type your number → tap "Send code" → enter the code → you\'re in. Works for senders and riders.'),
      (heading: 'Sessions on this device', body: 'The sessions list shows every phone/tablet this account has opened DropOff from. Tap "Revoke" to sign one out — it can\'t be used again until you re-authenticate.'),
      (heading: 'Your phone is also your payout', body: 'The number you sign in with is the momo that refunds and payouts land on. Double-check it — changing it means a fresh verification.'),
    ],
  ),
  HelpTopic.courierFare: (
    title: 'Depot fare — heard at the counter',
    rows: [
      (heading: 'The courier sets their own price', body: 'The fare the courier charges for inter-town freight is quoted at their counter. DropOff never collects partner money — we only front the rider leg to the depot.'),
      (heading: 'The same conversation for every route', body: 'This applies to Lusaka → Ndola, Copperbelt, Southern Province, international — wherever your parcel is going. The depot sets it; we hand it over at cost.'),
      (heading: 'Our fee is separate', body: 'What you pay DropOff up front is the rider leg only (pickup → depot). The rider fronts the depot fare; the sender repays the exact photographed receipt through DropOff, which releases the photo and reimburses the rider fee-free.'),
      (heading: 'No invented fares', body: 'We don\'t quote the depot fare in-app. The rider fronts it at the counter and you repay the exact photographed receipt here. If anyone asks you to pay that receipt to a personal account instead, that is not DropOff.'),
    ],
  ),
  HelpTopic.parcelPhoto: (
    title: 'Parcel photo — why we ask',
    rows: [
      (heading: 'Protects YOU in disputes', body: 'A clear photo at booking is evidence. If the parcel is lost or damaged in transit, the before/after comparison settles the claim.'),
      (heading: 'Checked at drop-off', body: 'The rider photographs the parcel again when they hand it to the depot. Yours vs. theirs — mismatch triggers a review before the waybill is signed.'),
      (heading: 'What makes it "clear"', body: 'Parcel label visible, packing intact, no other parcels in frame. One photo per parcel, taken in daylight if you can.'),
      (heading: 'Privacy', body: 'Photos go to DropOff for the parcel\'s lifetime only — dispute evidence or the receiver\'s re-pack inspection. Not shared, not marketed.'),
    ],
  ),
  HelpTopic.forbiddenItems: (
    title: 'What DropOff cannot carry',
    rows: [
      (heading: 'Declare every parcel', body: 'Parcel contents are mandatory. The rider and depot must know what is inside before a parcel enters a bag. A blank or false description cancels the booking.'),
      (heading: 'Never book these', body: 'Illegal drugs/narcotics, firearms and ammunition, explosives/fireworks, petrol/fuel and other flammables, poisons/corrosives, radioactive material, live animals and human remains. These follow the same published restrictions as DHL, UPS and FedEx.'),
      (heading: 'Restricted, not banned', body: 'Medicines, liquids, glass and high-value goods need secure packaging and an accurate description — declare them clearly so the rider can handle them properly.'),
      (heading: 'If in doubt', body: 'Contact DropOff support before booking. If a parcel is found to contain a prohibited item, the booking is cancelled with no refund.'),
    ],
  ),
  HelpTopic.depositRejection: (
    title: 'Prepayment prompt rejected',
    rows: [
      (heading: 'What that means', body: 'The mobile-money provider refused (or never started) the prompt for your prepayment. The booking is saved and HELD — no rider is dispatched until the prepayment lands.'),
      (heading: 'Check your momo balance', body: 'The #1 cause is insufficient funds for the exact amount. Top up, then tap "Pay now" in the booking to resend the prompt.'),
      (heading: 'If it still fails', body: 'Tap "Pay now" again — the server resends the prompt. If it rejects again, contact DropOff support with your booking reference.'),
      (heading: 'Held ≠ Lost', body: 'Nothing is lost. The booking is saved; when the prepayment finally lands, an algorithm dispatches the rider automatically. No manual step either side.'),
    ],
  ),
  HelpTopic.planCap: (
    title: 'Plan cap — how it counts',
    rows: [
      (heading: 'One parcel = one slot', body: 'Every parcel consumes one plan slot, even when two parcels share one trip to the same receiver. Your cap is a PARCEL count, not a trip count.'),
      (heading: 'When you exceed the cap', body: 'Extra parcels past your pack bill at full PAYG — the pack price applies only inside the pack. The price is always visible before you confirm a booking. Nothing is charged silently.'),
      (heading: 'Cancelled jobs don\'t count', body: 'A booking cancelled before pickup does not consume slots. Payment-held bookings do not consume slots either (no payment = no dispatch = no slot consumed).'),
    ],
  ),
  HelpTopic.plansBlurb: (
    title: 'Plans bundle everything',
    rows: [
      (heading: 'One momo prompt per cycle', body: 'A 7-day Weekly Sprint, or a monthly Silver (10) / Gold (25) / Platinum (50). Every parcel counts as one — two parcels in one trip to the same receiver = two parcels.'),
      (heading: 'Held ≠ lost', body: 'Plans never hold a booking. If you book without prepayment, the job is saved and waits for the plan\'s momo prompt to land. No money moves until you approve it.'),
      (heading: 'Pricing truth', body: 'Packs deduct automated at approval. Inside your pack — the trip leg is free; past your pack, it is PAYG at full rate. The momo prompt always shows the exact figure before you approve it.'),
    ],
  ),
  HelpTopic.depotReceipts: (
    title: 'Depot receipts — filing them',
    rows: [
      (heading: 'Photograph EVERY depot receipt', body: 'Each receipt needs its own photo and the EXACT amount handwritten on it. Never sum them — DropOff totals the photographed documents.'),
      (heading: 'One photo per receipt', body: 'If the depot splits your batch across two receipts, file BOTH. One photo and one amount field on each receipt sheet.'),
      (heading: 'Sender repays you', body: 'The exact amounts photographed go to the sender as the repayment request. The sender pays that amount (+ processing) to DropOff; the rider is reimbursed the same amount fee-free.'),
      (heading: 'Documents stay locked', body: 'The photos you file stay masked from the sender until they pay — then they reveal, and the reimbursement triggers automatically.'),
    ],
  ),
  HelpTopic.recurring: (
    title: 'Repeat drops — weekly/monthly',
    rows: [
      (heading: 'What it is', body: 'Weekly, biweekly or monthly recurring drops ready at your usual depot door. You type the details once — we remember and create the booking when the window opens.'),
      (heading: 'Confirm in one tap', body: 'You get a push when it\'s time; one tap confirms. No cold-starts, no re-typing.'),
      (heading: 'Change or cancel', body: 'Manage all recurring routes from the Recurring card in Account. Stop, pause or edit scope any time.'),
    ],
  ),
  HelpTopic.packCode: (
    title: 'Redeeming a plan code',
    rows: [
      (heading: 'Bought a plan from an agent or market day?', body: 'Paste the code in this box. It activates instantly on your number — no payment prompt, no second step.'),
      (heading: 'One-time activation', body: 'Codes are single-use. Once it activates it\'s yours; no anonymisation, no reuse.'),
      (heading: 'No signal? Keep the code', body: 'The code is saved on the server. It works next time you open the app — no loss if the app closes mid-redeem.'),
    ],
  ),
  HelpTopic.referralReward: (
    title: 'How referral rewards work',
    rows: [
      (heading: 'You get a single-use 20% promo', body: 'When someone books through your invite code, you receive a single-use promo on DropOff legs.'),
      (heading: 'Single-use, once', body: 'One promo per friend who completes their first booking through your code. No stacking.'),
      (heading: 'Where', body: 'Your earned FRIEND code appears in Account → Invite senders once your friend\'s first booking is confirmed. Copy it and use it at booking — the admin can switch the bonus on or off.'),
    ],
  ),
  HelpTopic.deviceList: (
    title: 'Your devices',
    rows: [
      (heading: 'What this list is', body: 'Every phone/tablet that has opened DropOff for this account. Revoke one to sign it out — it cannot be used again until you re-authenticate.'),
      (heading: 'Revoke resets sessions', body: 'Revoking removes the device\'s session key. The device must re-verify (SMS or email) before opening DropOff again.'),
    ],
  ),
  HelpTopic.biometric: (
    title: 'Biometric sign-in',
    rows: [
      (heading: 'On', body: 'Opening DropOff asks for your fingerprint or face. Your parcels and bookings stay private to you.'),
      (heading: 'Off', body: 'DropOff opens straight away. Pairs well with a strong PIN phone if you prefer.'),
    ],
  ),
  HelpTopic.offlineBuild: (
    title: 'Offline development build',
    rows: [
      (heading: 'What happened', body: 'This device was compiled without the server key — accounts aren\'t available.'),
      (heading: 'What does work', body: 'Bookings still save locally and sync when a linked build is installed or the key is added.'),
    ],
  ),
};

/// Tapping the "?" next to a section title opens this — the full text lives
/// here, not on screen. Every body paragraph stays available to every user.
class HelpSheet extends StatelessWidget {
  final String topic;
  const HelpSheet({super.key, required this.topic});

  static Future<void> show(BuildContext context, String topic) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        backgroundColor: AppColors.canvas,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (_) => HelpSheet(topic: topic),
      );

  @override
  Widget build(BuildContext context) {
    final entry = _topics[topic] ?? _topics[HelpTopic.signIn]!;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
          children: [
            Text(entry.title, style: AppType.subhead),
            const SizedBox(height: 12),
            for (final row in entry.rows) ...[
              Text(row.heading, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: AppColors.forest)),
              const SizedBox(height: 3),
              Text(row.body, style: AppType.body),
              const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }
}

/// "?" icon + optional tooltip — put on the right edge of a section row;
/// tap opens the shared help sheet. The verbose body lives there, not here.
class HelpIconButton extends StatelessWidget {
  final String topic;
  final double size;
  const HelpIconButton({super.key, required this.topic, this.size = 19});

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: 'Help',
        visualDensity: VisualDensity.compact,
        icon: Icon(Icons.help_outline, size: size, color: AppColors.muted),
        onPressed: () => HelpSheet.show(context, topic),
      );
}
