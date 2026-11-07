import 'package:flutter/material.dart';

import '../data/analytics_service.dart';
import '../data/catalog.dart';
import '../main.dart';
import '../ui/app_theme.dart';
import '../widgets/common.dart';
import 'account_screen.dart';
import 'booking_screen.dart';
import 'bookings_screen.dart';
import 'collections_screen.dart';
import 'couriers_screen.dart';
import 'track_screen.dart';

class HomeScreen extends StatelessWidget {
  final VoidCallback onOpenCouriers;
  final VoidCallback onOpenBookings;

  const HomeScreen({super.key, required this.onOpenCouriers, required this.onOpenBookings});

  Future<void> _book(BuildContext context, [String? courierId]) async {
    final store = AppScope.of(context);
    if (!store.linked) {
      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => const AccountScreen(),
      ));
      if (!context.mounted || !AppScope.of(context).linked) return;
    }
    if (!context.mounted) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => BookingScreen(initialCourierId: courierId),
    ));
  }

  Future<void> _openAccount(BuildContext context) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => const AccountScreen(),
    ));
  }

  Future<void> _collect(BuildContext context) async {
    final store = AppScope.of(context);
    if (!store.linked) {
      await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AccountScreen()));
      if (!context.mounted || !AppScope.of(context).linked) return;
    }
    if (!context.mounted) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const CollectionsScreen()));
  }

  @override
  Widget build(BuildContext context) {
    AnalyticsService.instance.trackScreenView('home');
    final store = AppScope.of(context);
    final active = store.bookings.where((item) => item.stage < item.timeline.length - 1).toList();
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        children: [
          Row(children: [
            const DropOffLogo(size: 46),
            const SizedBox(width: 12),
            Expanded(
              child: Text('DropOff', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: scaleText(context, 25), fontWeight: FontWeight.w900, letterSpacing: -0.7)),
            ),
            IconButton(
              tooltip: 'Account',
              onPressed: () => _openAccount(context),
              icon: Icon(
                (store.linked && store.email != null) ? Icons.account_circle : Icons.account_circle_outlined,
                color: (store.linked && store.email != null) ? AppColors.forest : AppColors.muted,
                size: 30,
              ),
            ),
            const SizedBox(width: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: AppColors.line)),
              child: const Text('🇿🇲  Zambia', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
            ),
          ]),
          // Tagline lives on its OWN full-width line under the row — it used to
          // share the header row with the icons and rendered truncated ("WE CAR…").
          // FittedBox scales it down instead of cutting it off at any width.
          const SizedBox(height: 2),
          Padding(
            padding: const EdgeInsets.only(left: 58),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text('WE CARRY IT TO THE COURIER',
                  maxLines: 1,
                  softWrap: false,
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.1, color: AppColors.muted)),
            ),
          ),
          const SizedBox(height: 24),
          Container(
            decoration: BoxDecoration(color: AppColors.forest, borderRadius: BorderRadius.circular(28)),
            clipBehavior: Clip.antiAlias,
            child: Stack(children: [
              const Positioned(right: -45, top: -45, child: CircleAvatar(radius: 105, backgroundColor: Color(0xFF1B4B3E))),
              const Positioned(right: 20, bottom: 72, child: Icon(Icons.two_wheeler_rounded, color: Color(0x33FFFFFF), size: 112)),
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const InfoPill(icon: Icons.bolt_rounded, label: 'HOME / SHOP → COURIER DEPOT', color: AppColors.amber),
                  const SizedBox(height: 18),
                  Text('Send it anywhere.\nWithout going anywhere.', style: TextStyle(color: Colors.white, fontSize: scaleText(context, 29), height: 1.12, fontWeight: FontWeight.w900, letterSpacing: -0.8)),
                  const SizedBox(height: 12),
                  const Text('A rider collects your parcel and drops it at the courier you choose.', style: TextStyle(color: Color(0xFFC9D9D2), height: 1.45, fontSize: 14)),
                  const SizedBox(height: 22),
                  Row(children: [
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(backgroundColor: AppColors.amber, foregroundColor: AppColors.ink, minimumSize: const Size(0, 52)),
                        onPressed: () => _book(context),
                        icon: const Icon(Icons.add_box_outlined, size: 19),
                        // FittedBox keeps the label on ONE line at any device
                        // width / system font size — it shrinks instead of
                        // wrapping into the icon (the old "Book a collection
                        // text overlap" bug).
                        label: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text('Book a pickup', maxLines: 1, softWrap: false, style: TextStyle(
                            fontSize: scaleText(context, 15),
                            fontWeight: FontWeight.w800,
                          )),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: AppColors.forest,
                          minimumSize: const Size(0, 52),
                        ),
                        onPressed: () => _collect(context),
                        icon: const Icon(Icons.inventory_2_outlined, size: 19),
                        label: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text('Book a collection', maxLines: 1, softWrap: false, style: TextStyle(
                            fontSize: scaleText(context, 15),
                            fontWeight: FontWeight.w800,
                          )),
                        ),
                      ),
                    ),
                  ]),
                ]),
              ),
            ]),
          ),
          const SizedBox(height: 14),
          // Recipients: same public tracking the SMS link opens — no account needed.
          Card(
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const TrackScreen())),
              child: const Padding(
                padding: EdgeInsets.all(16),
                child: Row(children: [
                  Icon(Icons.location_on_outlined, color: AppColors.forest),
                  SizedBox(width: 12),
                  Expanded(child: Text('Expecting a parcel? Track it', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14))),
                  Icon(Icons.chevron_right, color: AppColors.muted),
                ]),
              ),
            ),
          ),
          const SizedBox(height: 18),
          const Row(children: [
            Expanded(child: _TrustItem(icon: Icons.schedule, title: 'Pickup that fits', subtitle: 'From your doorstep')),
            SizedBox(width: 8),
            Expanded(child: _TrustItem(icon: Icons.receipt_long, title: 'Clear pricing', subtitle: 'Courier + rider fee')),
            SizedBox(width: 8),
            Expanded(child: _TrustItem(icon: Icons.verified_outlined, title: 'Proof of drop', subtitle: 'Receipt & tracking')),
          ]),
          if (active.isNotEmpty) ...[
            const SizedBox(height: 28),
            SectionTitle('On the move', actionLabel: 'View all', onAction: onOpenBookings),
            BookingCard(booking: active.first, onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => BookingDetailScreen(bookingId: active.first.id)))),
          ],
          const SizedBox(height: 28),
          SectionTitle('Choose your courier', actionLabel: 'See all', onAction: onOpenCouriers),
          const SizedBox(height: 4),
          SizedBox(
            height: 168,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: couriers.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final courier = couriers[index];
                return GestureDetector(
                  onTap: () {
                    final store = AppScope.of(context);
                    if (!store.linked) {
                      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AccountScreen()));
                      return;
                    }
                    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => CourierDetailScreen(courier: courier)));
                  },
                  child: Container(
                    width: 156,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: AppColors.line)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      CourierAvatar(courier: courier, size: 42),
                      const Spacer(),
                      Text(courier.name.replaceAll(' Courier Services', '').replaceAll(' Express Logistics', ''), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, height: 1.2)),
                      const SizedBox(height: 5),
                      Text(courier.hasVerifiedRates ? 'Rates available' : 'Get a depot quote', style: TextStyle(fontSize: 11, color: courier.hasVerifiedRates ? AppColors.forest : AppColors.muted, fontWeight: FontWeight.w600)),
                    ]),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 28),
          const SectionTitle('One booking. Three simple steps.'),
          const SizedBox(height: 6),
          const _HowItWorks(),
        ],
      ),
    );
  }
}

class _TrustItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const _TrustItem({required this.icon, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) => Column(children: [
        Icon(icon, color: AppColors.forest, size: 25),
        const SizedBox(height: 8),
        Text(title, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
        const SizedBox(height: 3),
        Text(subtitle, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, color: AppColors.muted)),
      ]);
}

class _HowItWorks extends StatelessWidget {
  const _HowItWorks();

  @override
  Widget build(BuildContext context) => const Card(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Column(children: [
            _Step(number: '01', title: 'We collect', text: 'Tell us where you are and what you are sending.'),
            _Step(number: '02', title: 'We drop off', text: 'Your rider takes it to Platinum, Mercury, DHL or another courier.'),
            _Step(number: '03', title: 'You follow it', text: 'Keep the DropOff reference and the courier waybill in one place.', last: true),
          ]),
        ),
      );
}

class _Step extends StatelessWidget {
  final String number;
  final String title;
  final String text;
  final bool last;
  const _Step({required this.number, required this.title, required this.text, this.last = false});

  @override
  Widget build(BuildContext context) => IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Column(children: [
            CircleAvatar(radius: 16, backgroundColor: AppColors.amber, child: Text(number, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: AppColors.ink))),
            if (!last) const Expanded(child: VerticalDivider(color: AppColors.line, thickness: 1, width: 24)),
          ]),
          const SizedBox(width: 12),
          Expanded(child: Padding(
            padding: EdgeInsets.only(bottom: last ? 0 : 22),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              const SizedBox(height: 4),
              Text(text, style: const TextStyle(color: AppColors.muted, height: 1.4, fontSize: 13)),
            ]),
          )),
        ]),
      );
}


