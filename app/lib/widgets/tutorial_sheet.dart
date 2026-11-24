import 'package:flutter/material.dart';

import '../ui/app_theme.dart';

/// In-app tutorial (owner 2026-11-20: sender accounts see ONLY the sender
/// tutorial). Opens as a single-purpose bottom sheet — no network, works
/// offline. [senderOnly] hides the rider steps; [rider] hides the sender steps.
/// With neither set, both tabs remain for backwards compatibility.
class TutorialSheet extends StatelessWidget {
  const TutorialSheet({super.key, this.rider = false, this.senderOnly = false});

  static Future<void> show(BuildContext context, {bool rider = false, bool senderOnly = false}) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        backgroundColor: AppColors.canvas,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        builder: (_) => TutorialSheet(rider: rider, senderOnly: senderOnly),
      );

  final bool rider;
  final bool senderOnly;

  static const _senderSteps = [
    (Icons.person_add_alt_1, '1. Set up your account',
        'Sign in with your phone number (or email). Add a photo so riders recognise you. In Account → Door handover PIN you can set your own 4-digit code for door deliveries.'),
    (Icons.local_shipping_outlined, '2. Book a pickup',
        'Pick a depot, address and item size. Add a photo for protection, then choose a sweep slot.'),
    (Icons.payments_outlined, '3. Pay on your phone',
        'Approve the momo prompt. Plan members use their included item slots; pay-as-you-go pays the quoted fee up front. If the rider fronts a depot counter fare, you repay the receipt amount plus processing fee in DropOff to unlock the receipt and reimburse the rider.'),
    (Icons.pin_outlined, '4. Show the pickup code',
        'Show your rider the pickup code when they arrive.'),
    (Icons.track_changes, '5. Follow it live',
        'Track the item in-app from door to depot and on to the courier. Same-city recipients get no SMS PIN — you confirm receipt in the app when it lands.'),
    (Icons.star_outline, '6. Rate and repeat',
        'Rate the rider, courier and sender after the trip. Your feedback keeps the network honest.'),
  ];

  static const _riderSteps = [
    (Icons.badge_outlined, '1. Link this device',
        'Sign in and link your phone so jobs dispatch to you. Add your selfie and documents — verification is required before you receive items.'),
    (Icons.schedule, '2. Watch your slots',
        'The TODAY card shows your live stats and pace/bonus. Jobs arrive in 06:00 / 10:00 / 14:00 batches; grouped by depot so one run serves several senders.'),
    (Icons.navigation, '3. Navigate & collect',
        'Tap Navigate to open our map. The bike faces your destination; tap the compass to put your heading at the top, and the map auto-zooms as you approach. Voice guidance reads the turns.'),
    (Icons.help_outline, '4. Ask for the codes',
        'Ask the SENDER for their 4-digit pickup code. Photograph EVERY item once. At a door delivery, ask the recipient for their DropOff door PIN (intercity SMS code or their own PIN).'),
    (Icons.receipt_long_outlined, '5. Depot drop',
        'Drop at the depot, photograph the item and the written receipt, type the EXACT amount on each receipt, then tap Submit drop. The sender repays the receipt amount plus processing fee in DropOff; the rider is reimbursed the exact receipt amount.'),
    (Icons.insights_outlined, '6. Stats & bonuses',
        'Your card shows today, in hand and done. Pay and bonuses follow your agreement and the monthly target.'),
  ];

  @override
  Widget build(BuildContext context) {
    final singleKind = senderOnly || rider;
    final steps = senderOnly ? _senderSteps : rider ? _riderSteps : null;
    final height = MediaQuery.of(context).size.height * 0.58;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Row(children: [
            Icon(Icons.menu_book, color: AppColors.forest),
            SizedBox(width: 8),
            Text('How DropOff works', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 19)),
          ]),
          const SizedBox(height: 4),
          Text(
            senderOnly
                ? 'Six quick steps. Works offline.'
                : rider
                    ? '6 quick steps for DropOff riders — keep it handy, it works offline.'
                    : 'A quick guide for every item — keep it handy, it works offline.',
            style: AppType.caption,
          ),
          const SizedBox(height: 10),
          if (singleKind)
            SizedBox(height: height, child: _steps(steps!))
          else
            DefaultTabController(
              length: 2,
              initialIndex: 0,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const TabBar(tabs: [Tab(text: 'SENDERS'), Tab(text: 'RIDERS')], labelColor: AppColors.forest),
                SizedBox(height: height, child: TabBarView(children: [_steps(_senderSteps), _steps(_riderSteps)])),
              ]),
            ),
        ]),
      ),
    );
  }

  Widget _steps(List<(IconData, String, String)> steps) => ListView.separated(
        padding: const EdgeInsets.only(top: 12),
        itemCount: steps.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          final (icon, title, body) = steps[i];
          return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.line)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(width: 34, height: 34,
                decoration: BoxDecoration(color: AppColors.forest.withValues(alpha: 0.09), borderRadius: BorderRadius.circular(10)),
                child: Icon(icon, size: 19, color: AppColors.forest)),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5)),
                const SizedBox(height: 3),
                Text(body, style: const TextStyle(fontSize: 12, height: 1.4, color: AppColors.ink)),
              ])),
            ]),
          );
        },
      );
}
