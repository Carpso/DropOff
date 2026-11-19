import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

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

  Future<void> _refresh(BuildContext context) => AppScope.of(context).syncJobsFromServer();

  @override
  Widget build(BuildContext context) {
    AnalyticsService.instance.trackScreenView('home');
    final store = AppScope.of(context);
    final active = store.bookings.where((item) => item.stage < item.timeline.length - 1).toList();
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: () => _refresh(context),
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
          const Padding(
            padding: EdgeInsets.only(left: 58),
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
              const Positioned(right: -45, top: -45, child: CircleAvatar(radius: 105, backgroundColor: AppColors.forest)),
              const Positioned(right: 20, bottom: 72, child: Icon(Icons.two_wheeler_rounded, color: Color(0x33FFFFFF), size: 112)),
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const InfoPill(icon: Icons.bolt_rounded, label: 'HOME / SHOP → COURIER DEPOT', color: AppColors.amber),
                  const SizedBox(height: 18),
                  Text('Send it anywhere.\nWithout going anywhere.', style: TextStyle(color: Colors.white, fontSize: scaleText(context, 29), height: 1.12, fontWeight: FontWeight.w900, letterSpacing: -0.8)),
                  const SizedBox(height: 12),
                  const Text('A rider collects it. You pick the courier.', style: TextStyle(color: Color(0xFFC9D9D2), height: 1.45, fontSize: 15, fontWeight: FontWeight.w600)),
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
          const SizedBox(height: 14),
          const _FareChecker(),
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
                      const Text('Quoted at counter', style: TextStyle(fontSize: 11, color: AppColors.muted, fontWeight: FontWeight.w600)),
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
        Text(title, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.callout),
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

/// Enhancement: "Check a fare" right on the home screen — turns price-
/// shoppers into bookings. Prices the HOME/OFFICE/STORE → nominated depot
/// leg only; the courier fare is heard at the counter.
class _FareChecker extends StatefulWidget {
  const _FareChecker();

  @override
  State<_FareChecker> createState() => _FareCheckerState();
}

/// Prices the user's pinned pickup → the fixed Lusaka depot anchor — the SAME
/// formula and the SAME anchor the booking wizard and the Worker use, so the
/// card can never contradict the prompt.
class _FareCheckerState extends State<_FareChecker> {
  String _courierId = 'platinum';
  String _vehicle = 'motorcycle';
  double? _lat;
  double? _lng;
  bool _locating = false;
  bool _feeChecked = false;
  final _place = TextEditingController(text: 'Home');

  static const Map<String, double> _multiplier = {'motorcycle': 1.0, 'car': 1.2, 'van': 1.4, 'truck': 2.0};

  // The one authoritative anchor for every price in this app: matches the
  // Worker's baseRiderFee (workers/src/pricing.ts) distance bands exactly.
  // Do not price against the selected courier's depot — the fee has to be
  // identical wherever the sender looks.
  static const double _anchorLat = -15.4255;
  static const double _anchorLng = 28.2805;

  double _haversineKm(double aLat, double aLng, double bLat, double bLng) {
    const R = 6371.0, d = 3.141592653589793 / 180;
    final h = 0.5 - math.cos((bLat - aLat) * d) / 2 +
        math.cos(aLat * d) * math.cos(bLat * d) * (1 - math.cos((bLng - aLng) * d)) / 2;
    return 2 * R * math.asin(math.sqrt(h));
  }

  /// MUST match the server's baseRiderFee (K55 ≤ 5 km · K75 ≤ 12 km · K95 beyond,
  /// × vehicle multiplier; trucks K100 minimum).
  double _fee(double km) {
    var base = km <= 5 ? 55.0 : km <= 12 ? 75.0 : 95.0;
    base = base * (_multiplier[_vehicle] ?? 1.0);
    if (_vehicle == 'truck') base = base < 100 ? 100 : base;
    return base;
  }

  Future<void> _locate() async {
    setState(() => _locating = true);
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Location permission is needed to pin the pickup.')));
        }
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      ).timeout(const Duration(seconds: 12));
      if (!mounted) return;
      setState(() {
        _lat = pos.latitude;
        _lng = pos.longitude;
        _feeChecked = false;
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not get your location — the fee locks exactly when you book.')));
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _checkFee() {
    final from = _place.text.trim();
    if (from.length < 3 && _lat == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Type where we collect from — or pin your location.')));
      return;
    }
    setState(() => _feeChecked = true);
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('✓ Fee checked — your rider fee is on the card. Book when ready.')));
  }

  /// Check the rider fee → Book: carry over EVERYTHING the sender already
  /// typed on the checker (pickup name, courier, vehicle class, pinned GPS)
  /// so they never retype it in the booking wizard.
  void _book() {
    BookingScreen.prefill = {
      'from': 'Lusaka',
      'pickup': _place.text.trim().isEmpty ? 'Home' : _place.text.trim(),
      'courier': _courierId,
      'vehicle_class': _vehicle,
      if (_lat != null) 'pickup_lat': _lat,
      if (_lng != null) 'pickup_lng': _lng,
    };
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const BookingScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final km = (_lat != null && _lng != null) ? _haversineKm(_lat!, _lng!, _anchorLat, _anchorLng) : null;
    final fee = km != null ? _fee(km) : null;
    // Checked-fee result: exact fee when pinned, honest band list for the
    // chosen vehicle when the pickup is not pinned yet.
    String feeAmount = 'K${_fee(3).toStringAsFixed(0)} / K${_fee(8).toStringAsFixed(0)} / K${_fee(20).toStringAsFixed(0)}';
    String feeDetail = 'Distance bands ≤5 km / ≤12 km / beyond — pin your pickup for your exact fee (it locks at booking).';
    if (fee != null) {
      final k = km!;
      feeAmount = 'K${fee.toStringAsFixed(0)}';
      feeDetail = 'Pickup → depot, ${k.toStringAsFixed(1)} km (${k <= 5 ? '≤5 km' : k <= 12 ? '≤12 km' : 'beyond 12 km'} band) — the exact amount booking will charge.';
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [
            Icon(Icons.calculate_outlined, size: 18, color: AppColors.forest),
            SizedBox(width: 8),
            Expanded(child: Text('Check the rider fee', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15))),
          ]),
          const SizedBox(height: 4),
          const SizedBox(height: 12),
          TextField(
            controller: _place,
            onChanged: (_) => setState(() => _feeChecked = false),
            decoration: const InputDecoration(
              labelText: 'Pickup from (home, office, store)',
              isDense: true,
              hintText: 'e.g. Kabulonga office, Matero home, Cairo Road shop',
            ),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: DropdownButtonFormField<String>(
              initialValue: _courierId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Courier depot', isDense: true),
              items: [for (final c in mergedCouriers(AppScope.of(context).activeServerCouriers)) DropdownMenuItem(value: c.id, child: Text(c.name, overflow: TextOverflow.ellipsis))],
              onChanged: (v) => setState(() { _courierId = v ?? _courierId; _feeChecked = false; }),
            )),
          ]),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _vehicle,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Vehicle class', isDense: true),
            items: const [
              DropdownMenuItem(value: 'motorcycle', child: Text('Motorcycle')),
              DropdownMenuItem(value: 'car', child: Text('Car')),
              DropdownMenuItem(value: 'van', child: Text('Van')),
              DropdownMenuItem(value: 'truck', child: Text('Truck (large cargo)')),
            ],
            onChanged: (v) => setState(() { _vehicle = v ?? _vehicle; _feeChecked = false; }),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _locating ? null : _locate,
            icon: _locating
                ? const SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.my_location, size: 18),
            label: Text(_locating ? 'Pinning…' : (_lat != null ? 'Pickup pinned ✓ — tap to re-pin' : 'Use my current location')),
          ),
          const SizedBox(height: 10),
          if (!_feeChecked) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppColors.line.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(12)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  fee != null
                      ? 'Rider leg K${fee.toStringAsFixed(0)} (${km!.toStringAsFixed(1)} km) — same number at booking'
                      : 'Rider leg K55/K75/K95 by km band — pin your pickup for the exact fee.',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5),
                ),
                const SizedBox(height: 4),
                const Text('Courier fare: heard at the counter on drop-off.',
                    style: TextStyle(color: AppColors.muted, fontSize: 11.5)),
              ]),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _checkFee,
              icon: const Icon(Icons.calculate_outlined, size: 18),
              label: const Text('Check fee'),
            ),
            const SizedBox(height: 6),
            const Text('The booking button unlocks after you have seen your price.',
                style: TextStyle(color: AppColors.muted, fontSize: 10.5)),
          ] else ...[
            // Price FIRST, then the option to book — "Check fee" must end with
            // the sender seeing their fee, never a bare Book button.
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.forest.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.forest.withValues(alpha: 0.35)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('YOUR DROPOFF RIDER FEE',
                    style: TextStyle(color: AppColors.muted, fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 0.6)),
                const SizedBox(height: 2),
                Text(feeAmount,
                    style: AppType.price),
                const SizedBox(height: 4),
                Text(feeDetail, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, height: 1.35)),
                const SizedBox(height: 4),
                const Text('Courier fare: heard at the counter on drop-off.',
                    style: TextStyle(color: AppColors.muted, fontSize: 11)),
              ]),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: _book,
              icon: const Icon(Icons.arrow_forward, size: 18),
              label: const Text('Book the pickup — fee checked ✓'),
            ),
          ],
        ]),
      ),
    );
  }
}


