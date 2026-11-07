import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:io';

import '../data/analytics_service.dart';
import '../data/dropoff_api.dart';
import '../main.dart';
import '../ui/app_theme.dart';
import '../widgets/common.dart';
import 'rider_queue_screen.dart';

class OperationsScreen extends StatelessWidget {
  const OperationsScreen({super.key});

  Future<void> _linkDevice(BuildContext context) async {
    final store = AppScope.of(context);
    final phone = TextEditingController();
    final code = TextEditingController();
    String phrase = store.linked
        ? 'Linked as ${store.linkedPhone}. Lipila prompts and job receipts flow through this identity.'
        : 'Verify with a one-time code for receipts, live tracking and ops access.';
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.canvas,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (sheetContext) => StatefulBuilder(builder: (context, setSheetState) => Padding(
        padding: EdgeInsets.fromLTRB(22, 22, 22, MediaQuery.of(context).viewInsets.bottom + 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Link this device', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
          if (!store.linked) ...[
            const SizedBox(height: 6),
            Text(phrase, style: const TextStyle(color: AppColors.muted)),
            const SizedBox(height: 16),
            TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Mobile number', hintText: '0971234567', prefixIcon: Icon(Icons.phone_outlined))),
            const SizedBox(height: 10),
            FilledButton.tonal(onPressed: () async {
              setSheetState(() => phrase = 'Sending code…');
              final res = await DropOffApi.requestOtp(phone.text);
              setSheetState(() {
                if (res.ok && res.body['sent'] == true) {
                  phrase = 'One-time code sent by SMS. Enter it below.';
                } else if (res.ok) {
                  phrase = 'SMS could not be delivered (${res.body['sms_error'] ?? 'gateway error'}). Sign in with email on the Account tab instead.';
                } else {
                  phrase = 'Could not send a code (${res.error}). Try again shortly.';
                }
              });
            }, child: const Text('Send one-time code')),
            const SizedBox(height: 16),
            TextField(controller: code, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '6-digit code', prefixIcon: Icon(Icons.password_outlined))),
            const SizedBox(height: 18),
            FilledButton(onPressed: () async {
              setSheetState(() => phrase = 'Verifying…');
              final ok = await AppScope.of(context).confirmOtp(phone.text, code.text);
              setSheetState(() {
                phrase = ok ? 'Device verified.' : 'Wrong or expired code — request a new one.';
              });
              if (ok && sheetContext.mounted) Navigator.of(sheetContext).pop(true);
            }, child: const Text('Verify & link')),
            const SizedBox(height: 8),
          ] else ...[
            const SizedBox(height: 10),
            Text(phrase, style: const TextStyle(color: AppColors.muted)),
            const SizedBox(height: 18),
            FilledButton.tonal(onPressed: () async {
              await AppScope.of(context).unlink();
              if (sheetContext.mounted) Navigator.of(sheetContext).pop(true);
            }, child: const Text('Unlink device')),
          ],
        ]),
      )),
    );
    if (confirmed == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Device identity updated.')));
    }
    phone.dispose();
    code.dispose();
  }

  Future<void> _addRider(BuildContext context) async {
    final name = TextEditingController();
    final phone = TextEditingController();
    String vehicle = 'Motorcycle';
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.canvas,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (sheetContext) => StatefulBuilder(builder: (context, setSheetState) => Padding(
        padding: EdgeInsets.fromLTRB(22, 22, 22, MediaQuery.of(context).viewInsets.bottom + 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Add a rider or driver', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
          const SizedBox(height: 20),
          TextField(controller: name, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Full name', prefixIcon: Icon(Icons.person_outline))),
          const SizedBox(height: 12),
          TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Mobile number', hintText: '0971234567', prefixIcon: Icon(Icons.phone_outlined))),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: vehicle,
            decoration: InputDecoration(
              labelText: 'Vehicle',
              prefixIcon: Icon(_vehicleIcon(vehicle)),
            ),
            items: const [
              DropdownMenuItem(value: 'Motorcycle', child: Row(children: [Icon(Icons.two_wheeler, size: 20), SizedBox(width: 10), Text('Motorcycle')])),
              DropdownMenuItem(value: 'Car', child: Row(children: [Icon(Icons.directions_car, size: 20), SizedBox(width: 10), Text('Car')])),
              DropdownMenuItem(value: 'Van', child: Row(children: [Icon(Icons.airport_shuttle, size: 20), SizedBox(width: 10), Text('Van')])),
              DropdownMenuItem(value: 'Truck', child: Row(children: [Icon(Icons.local_shipping, size: 20), SizedBox(width: 10), Text('Truck (large cargo)')])),
              DropdownMenuItem(value: 'Bicycle', child: Row(children: [Icon(Icons.pedal_bike, size: 20), SizedBox(width: 10), Text('Bicycle')])),
              DropdownMenuItem(value: 'Three-wheeler', child: Row(children: [Icon(Icons.local_taxi, size: 20), SizedBox(width: 10), Text('Three-wheeler')])),
            ],
            onChanged: (value) => setSheetState(() => vehicle = value ?? 'Motorcycle'),
          ),
          const SizedBox(height: 20),
          FilledButton(onPressed: () {
            if (name.text.trim().length < 2 || phone.text.trim().length < 9) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a name and valid mobile number.')));
              return;
            }
            Navigator.of(sheetContext).pop(true);
          }, child: const Text('Add to my team')),
        ]),
      )),
    );
    if (saved == true && context.mounted) {
      final error = await AppScope.of(context).addRider(
        name: name.text,
        phone: phone.text,
        vehicle: vehicle,
        vehicleClass: _vehicleClassOf(vehicle),
      );
      if (error != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
      }
    }
    name.dispose();
    phone.dispose();
  }

  Future<void> _pingMyLocation(BuildContext context) async {
    final store = AppScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    if (!store.linked) {
      messenger.showSnackBar(const SnackBar(content: Text('Link this device first so your rider phone is known.')));
      return;
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      messenger.showSnackBar(const SnackBar(content: Text('Location permission needed to share your live position.')));
      return;
    }
    try {
      final pos = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high));
      final res = await DropOffApi.riderPing(phone: store.linkedPhone!, lat: pos.latitude, lng: pos.longitude);
      messenger.showSnackBar(SnackBar(content: Text(res.ok ? 'Live location shared with senders.' : 'Could not submit location right now.')));
    } catch (e) {
      messenger.showSnackBar(const SnackBar(content: Text('Location unavailable — check GPS.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    AnalyticsService.instance.trackScreenView('operations');
    final store = AppScope.of(context);
    if (!store.linked) {
      // Rider/ops tools need an identity — show the link door only.
      return SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.lock_outline, size: 44, color: AppColors.muted),
              const SizedBox(height: 16),
              const Text('Team tools are locked', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900), textAlign: TextAlign.center),
              const SizedBox(height: 8),
              const Text('Link this device with a one-time code to run your team, share your GPS and receive jobs.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted, height: 1.45)),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () => _linkDevice(context),
                icon: const Icon(Icons.link),
                label: const Text('Link this device'),
              ),
            ]),
          ),
        ),
      );
    }
    if (!store.isStaff && store.isRider) {
      // Rider personal view: their own task queue (server keys it to the
      // signed-in rider phone) + GPS broadcast. No add-rider, no fleet routes,
      // no economics — those stay staff-only (routes/batch 403 for riders).
      final activeRiders = store.riders.where((item) => item.active).length;
      return SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(20, 22, 20, 28), children: [
          Row(children: [
            const Icon(Icons.two_wheeler, color: AppColors.forest),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Your riding day', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
              const SizedBox(height: 3),
              Text('Signed in as ${store.linkedPhone} — jobs assigned to you land here automatically.', style: const TextStyle(color: AppColors.muted, fontSize: 12, height: 1.4)),
            ])),
          ]),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: _Metric(value: '${store.bookings.length}', label: 'Bookings on device', icon: Icons.inventory_2_outlined)),
            const SizedBox(width: 12),
            Expanded(child: _Metric(value: '$activeRiders', label: 'Team size', icon: Icons.groups_outlined)),
          ]),
          const SizedBox(height: 16),
          // Verification first: a new rider can't be assigned jobs until their
          // ID, plate and photos are approved, so it goes before the queue.
          const _RiderVerificationCard(),
          const SizedBox(height: 12),
          _TaskQueueCard(),
          const SizedBox(height: 12),
          const _RiderCashCard(),
          const SizedBox(height: 12),
          const _RiderReviewsCard(),
          const SizedBox(height: 12),
          const _RiderPayCard(),
          const SizedBox(height: 12),
          const _RiderTargetsCard(),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.my_location, color: AppColors.forest),
              title: const Text('Share live position', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              subtitle: const Text('Broadcast your GPS so senders of your jobs can follow you live.', style: TextStyle(color: AppColors.muted, fontSize: 12, height: 1.35)),
              trailing: FilledButton.tonal(
                style: FilledButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8), minimumSize: const Size(0, 36)),
                onPressed: () => _pingMyLocation(context),
                child: const Text('Share'),
              ),
            ),
          ),
          const SizedBox(height: 22),
          Card(
            child: ListTile(
              leading: Icon(store.linked ? Icons.verified_user : Icons.link_outlined, color: AppColors.forest),
              title: Text(store.linked ? 'Linked as ${store.linkedPhone}' : 'Device not linked', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
              subtitle: const Text('This number is your rider identity — jobs and COD are keyed to it.', style: TextStyle(color: AppColors.muted, fontSize: 11.5, height: 1.35)),
              trailing: TextButton(onPressed: () => _linkDevice(context), child: const Text('Manage')),
            ),
          ),
        ]),
      );
    }
    if (!store.isStaff) {
      // Defense in depth: the Team tab is already hidden for non-staff, but a
      // deep link or stale shell must still land on this door — riders and
      // drivers are created ONLY by admin/ops (the server enforces it too).
      return SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.admin_panel_settings_outlined, size: 44, color: AppColors.muted),
              const SizedBox(height: 16),
              const Text('Staff access only', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900), textAlign: TextAlign.center),
              const SizedBox(height: 8),
              const Text('Riders, drivers, fleet routes and GPS tools are managed by DropOff staff. Your bookings live under Bookings.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted, height: 1.45)),
              const SizedBox(height: 20),
              FilledButton.tonal(
                onPressed: () => Navigator.of(context).maybePop(),
                child: const Text('Go back'),
              ),
            ]),
          ),
        ),
      );
    }
    final activeRiders = store.riders.where((item) => item.active).length;
    return SafeArea(
      child: ListView(padding: const EdgeInsets.fromLTRB(20, 22, 20, 28), children: [
        const Text('Your operation', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: -0.6)),
        const SizedBox(height: 5),
        const Text('Run your team, your routes and your live location from here.', style: TextStyle(color: AppColors.muted)),
        const SizedBox(height: 16),
        Card(child: ListTile(
          leading: Icon(store.linked ? Icons.verified_user : Icons.link_outlined, color: AppColors.forest),
          title: Text(store.linked ? 'Linked as ${store.linkedPhone}' : 'Device not linked', style: const TextStyle(fontWeight: FontWeight.w800)),
          subtitle: Text(store.linked ? 'Lipila receipts and tracking run on your identity.' : 'Tap to verify your number with a one-time code.'),
          trailing: TextButton(onPressed: () => _linkDevice(context), child: Text(store.linked ? 'Manage' : 'Link')),
        )),
        const SizedBox(height: 18),
        Row(children: [
          Expanded(child: _Metric(value: '${store.bookings.length}', label: 'Total bookings', icon: Icons.inventory_2_outlined)),
          const SizedBox(width: 12),
          Expanded(child: _Metric(value: '$activeRiders', label: 'Active team', icon: Icons.groups_outlined)),
        ]),
        const SizedBox(height: 26),
        const _SmartRouteCard(),
        const SizedBox(height: 12),
        _TaskQueueCard(),
        const SizedBox(height: 12),
        const _BatchPickupCard(),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: const Icon(Icons.my_location, color: AppColors.forest),
            title: const Text('Rider live position', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            subtitle: const Text('Broadcast your GPS once so senders of your jobs can open a live map.', style: TextStyle(color: AppColors.muted, fontSize: 12, height: 1.35)),
            trailing: FilledButton.tonal(
              style: FilledButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8), minimumSize: const Size(0, 36)),
              onPressed: () => _pingMyLocation(context),
              child: const Text('Share'),
            ),
          ),
        ),
        const SizedBox(height: 26),
        SectionTitle('Riders & drivers', actionLabel: '+ Add', onAction: () => _addRider(context)),
        const SizedBox(height: 8),
        if (store.riders.isEmpty) ...[
          EmptyState(            icon: Icons.directions_bike,
            title: 'No riders yet',
            message: 'Tap + Add to register your first rider or driver. They’ll appear here once verified.',
            action: FilledButton.icon(
              onPressed: () => _addRider(context),
              icon: const Icon(Icons.add),
              label: const Text('Add rider'),
            ),
          ),
        ] else ...[
          for (final rider in store.riders)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Card(child: Padding(padding: const EdgeInsets.all(14), child: Row(children: [
                CircleAvatar(
                  backgroundColor: rider.isOwner ? AppColors.amber : const Color(0xFFE4ECE6),
                  child: Icon(_vehicleIcon(rider.vehicle), color: AppColors.forest),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(rider.isOwner ? '${rider.name} (You)' : rider.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 3),
                  Text('${rider.vehicle} • ${rider.phone}', style: const TextStyle(color: AppColors.muted, fontSize: 11, height: 1.4)),
                ])),
                if (rider.isOwner)
                  const InfoPill(icon: Icons.verified, label: 'OWNER')
                else ...[
                  Switch(value: rider.active, onChanged: (value) => store.toggleRider(rider.id, value)),
                  IconButton(icon: const Icon(Icons.delete_outline, color: AppColors.muted), onPressed: () => store.removeRider(rider.id)),
                ],
              ]))),
            ),
        ],
        const SizedBox(height: 22),
        // Driver economics are staff-only (admin/ops). This screen is already
        // behind the Team tab which only staff see — keep the card for them
        // but never surface rider payout splits to sellers/recipients.
        if (AppScope.of(context).isStaff) ...[
          const SectionTitle('How DropOff earns'),
          const SizedBox(height: 8),
          const Card(child: Padding(padding: EdgeInsets.all(18), child: Column(children: [
            _RevenueRow(number: '01', title: 'Pay-as-you-go pickup', text: 'K45 per pickup. Platform takes 10% (K4.50 to DropOff, K40.50 to the rider) — thin on purpose so riders stay loyal.'),
            _RevenueRow(number: '02', title: 'Subscription plans: Silver / Gold / Platinum', text: 'K250 / K500 / K750 per 30-day cycle for 10 / 25 / 50 parcels (plus Daily Rider K49/day and Weekly K399). Every parcel counts as one — even in the same trip.'),
            _RevenueRow(number: '03', title: 'Waiting & COD float', text: 'Waiting over 10 min bills K2/min (K50 cap) — paid to the driver in full. COD cash floats with the rider/driver — sender paid via momo disbursement minus our 2%.'),
            _RevenueRow(number: '04', title: 'Door delivery & subscription plans', text: 'Last-mile door delivery priced like first-mile pay-as-you-go (recipient-city distance + vehicle). Plan parcels bundle the rider inside the monthly fee.'),
          ]))),
        ],
      ]),
    );
  }

  IconData _vehicleIcon(String vehicle) {
    final v = vehicle.toLowerCase();
    if (v.contains('truck')) return Icons.local_shipping;
    if (v.contains('van')) return Icons.airport_shuttle;
    if (v.contains('car')) return Icons.directions_car;
    if (v.contains('bicycle') || v.contains('bike')) return Icons.pedal_bike;
    if (v.contains('three') || v.contains('trike') || v.contains('tuk')) return Icons.local_taxi;
    return Icons.two_wheeler;
  }

  /// Pricing class sent to the riders table (bicycle/tricycle ride the
  /// motorcycle rate bands).
  String _vehicleClassOf(String vehicle) {
    final v = vehicle.toLowerCase();
    if (v.contains('truck')) return 'truck';
    if (v.contains('van')) return 'van';
    if (v.contains('car')) return 'car';
    return 'motorcycle';
  }
}

/// The rider's day, batched by sweep slot — the Team-tab door into the queue.
class _TaskQueueCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => RiderQueueScreen(phone: store.linkedPhone),
        )),
        child: const Padding(
          padding: EdgeInsets.all(16),
          child: Row(children: [
            Icon(Icons.format_list_numbered, color: AppColors.forest),
            SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text("Today's task queue", style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              SizedBox(height: 3),
              Text('Slot batches with stop times, parcel counts and target depot drop-off.', style: TextStyle(color: AppColors.muted, fontSize: 12, height: 1.35)),
            ])),
            Icon(Icons.chevron_right, color: AppColors.muted),
          ]),
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  final String value;
  final String label;
  final IconData icon;
  const _Metric({required this.value, required this.label, required this.icon});

  @override
  Widget build(BuildContext context) => Card(child: Padding(padding: const EdgeInsets.all(17), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Icon(icon, color: AppColors.forest),
    const SizedBox(height: 14),
    Text(value, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
    Text(label, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
  ])));
}

/// COD cash the signed-in rider is still floating: collected at the door for
/// sellers, not yet remitted. One tap pushes it to the seller's momo (minus the
/// platform cut) — the same settlement admin/payouts performs.
class _RiderCashCard extends StatefulWidget {
  const _RiderCashCard();

  @override
  State<_RiderCashCard> createState() => _RiderCashCardState();
}

class _RiderCashCardState extends State<_RiderCashCard> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _busyRef;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!DropOffApi.enabled) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final data = await DropOffApi.riderCod();
    if (!mounted) return;
    setState(() {
      _data = data;
      _loading = false;
    });
  }

  Future<void> _remit(Map<String, dynamic> job) async {
    final ref = '${job['ref'] ?? ''}';
    final cod = (job['cod_collected_zmw'] as num?)?.toDouble() ?? 0;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remit this COD?'),
        content: Text('K${cod.toStringAsFixed(2)} collected on $ref will be pushed to the seller\'s mobile money (platform keeps its cut). This moves money — cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remit')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busyRef = ref);
    final res = await DropOffApi.riderCodRemit(ref);
    if (!mounted) return;
    setState(() => _busyRef = null);
    final error = res.error ?? (res.ok ? null : 'Remittance failed.');
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(error ?? 'Remitted — seller notified, K${((res.body['credited_zmw'] as num?) ?? 0).toStringAsFixed(2)} sent.'),
    ));
    if (error == null) _load();
  }

  @override
  Widget build(BuildContext context) {
    if (!DropOffApi.enabled || _loading) {
      return const Card(child: Padding(padding: EdgeInsets.all(16), child: Center(child: SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)))));
    }
    final jobs = ((_data?['jobs'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final open = jobs.where((j) => ((j['remitted'] as num?)?.toInt() ?? 0) == 0).toList();
    final total = ((_data?['total_unremitted_zmw'] as num?)?.toDouble()) ?? 0;
    final cut = ((_data?['platform_cut_pct'] as num?)?.toInt()) ?? 0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.account_balance_wallet_outlined, color: AppColors.forest),
            const SizedBox(width: 10),
            const Expanded(child: Text('Cash in your float', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15))),
            Text('K${total.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: AppColors.forest)),
          ]),
          const SizedBox(height: 6),
          Text(
            open.isEmpty
                ? 'All settled — nothing waiting. COD you collect at the door shows here until you remit it.'
                : 'Collected at the door for sellers. Remitting pushes it straight to their mobile money${cut > 0 ? ' (platform keeps $cut%)' : ''}.',
            style: const TextStyle(color: AppColors.muted, fontSize: 11.5, height: 1.35),
          ),
          ...open.take(4).map((job) => Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${job['ref'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
                      Text('K${((job['cod_collected_zmw'] as num?) ?? 0).toStringAsFixed(2)} · ${job['recipient_name'] ?? 'recipient'}',
                          style: const TextStyle(color: AppColors.muted, fontSize: 11)),
                    ]),
                  ),
                  FilledButton.tonal(
                    style: FilledButton.styleFrom(visualDensity: VisualDensity.compact, minimumSize: const Size(0, 34)),
                    onPressed: _busyRef == null ? () => _remit(job) : null,
                    child: Text(_busyRef == '${job['ref']}' ? 'Sending…' : 'Remit'),
                  ),
                ]),
              )),
        ]),
      ),
    );
  }
}

/// The rider's own reputation: average stars + latest written reviews.
class _RiderReviewsCard extends StatefulWidget {
  const _RiderReviewsCard();

  @override
  State<_RiderReviewsCard> createState() => _RiderReviewsCardState();
}

class _RiderReviewsCardState extends State<_RiderReviewsCard> {
  Map<String, dynamic>? _data;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!DropOffApi.enabled) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final data = await DropOffApi.riderReviews();
    if (!mounted) return;
    setState(() {
      _data = data;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!DropOffApi.enabled || _loading) return const SizedBox.shrink();
    final n = ((_data?['n'] as num?)?.toInt()) ?? 0;
    final avg = ((_data?['average'] as num?)?.toDouble()) ?? 0;
    final reviews = ((_data?['reviews'] as List?) ?? const []).cast<Map<String, dynamic>>();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.star_outline_rounded, color: AppColors.amber),
            const SizedBox(width: 10),
            const Expanded(child: Text('Your ratings', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15))),
            if (n > 0) ...[
              ...List.generate(5, (i) => Icon(i < avg.round() ? Icons.star_rounded : Icons.star_border_rounded, size: 16, color: AppColors.amber)),
              const SizedBox(width: 6),
              Text('${avg.toStringAsFixed(1)} · $n', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
            ],
          ]),
          if (n == 0)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text('No ratings yet — sellers and recipients rate you after each delivery; they show up here.', style: TextStyle(color: AppColors.muted, fontSize: 11.5, height: 1.35)),
            )
          else
            ...reviews.take(2).map((r) => Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      ...List.generate(5, (i) => Icon(i < ((r['stars'] as num?)?.toInt() ?? 0) ? Icons.star_rounded : Icons.star_border_rounded, size: 12, color: AppColors.amber)),
                      const SizedBox(width: 6),
                      Text('${r['created_at'] ?? ''}'.split(' ').first, style: const TextStyle(color: AppColors.muted, fontSize: 10.5)),
                    ]),
                    if ('${r['comment'] ?? ''}'.trim().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text('“${r['comment']}”', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, height: 1.35)),
                      ),
                  ]),
                )),
        ]),
      ),
    );
  }
}

class _BatchPickupCard extends StatefulWidget {
  const _BatchPickupCard();

  @override
  State<_BatchPickupCard> createState() => _BatchPickupCardState();
}

class _BatchPickupCardState extends State<_BatchPickupCard> {
  Future<Map<String, dynamic>?> _future = DropOffApi.batchPickup();

  Future<void> _copyManifest(List<Map<String, dynamic>> stops) async {
    final text = stops
        .map((s) => '${s['seq']}. ${s['ref']} — ${s['address']} (+${s['km_from_prev']} km)')
        .join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Manifest copied — paste it into your dispatch group.')));
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: FutureBuilder<Map<String, dynamic>?>(
          future: _future,
          builder: (context, snap) {
            final routes = (snap.data?['routes'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
            final total = (snap.data?['stop_count'] as num?)?.toInt() ?? 0;
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Expanded(child: Text('Batch sweep — professional routes', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
                IconButton(tooltip: 'Re-plan', icon: const Icon(Icons.refresh), onPressed: () => setState(() => _future = DropOffApi.batchPickup())),
              ]),
              const SizedBox(height: 2),
              const Text('Scattered stops are ordered snake (alternating east–west sweep) — no criss-cross, no backtracking.', style: TextStyle(color: AppColors.muted, fontSize: 11.5)),
              const SizedBox(height: 10),
              if (snap.connectionState == ConnectionState.waiting)
                const Center(child: Padding(padding: EdgeInsets.symmetric(vertical: 16), child: CircularProgressIndicator(strokeWidth: 2)))
              else if (routes.isEmpty)
                Text('Nothing scheduled for today yet ($total stops queued).', style: const TextStyle(color: AppColors.muted, fontSize: 12))
              else
                ...routes.map((route) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: DecoratedBox(
                        decoration: BoxDecoration(border: Border.all(color: AppColors.line), borderRadius: BorderRadius.circular(14)),
                        child: ExpansionTile(
                          leading: const Icon(Icons.route_rounded, color: AppColors.forest),
                          title: Text('Route ${route['route']} — ${(route['stops'] as List).length} stops · ${route['total_km']} km · ~${route['est_minutes']} min', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                          subtitle: Text('rider: ${route['rider_hint']}', style: const TextStyle(color: AppColors.muted, fontSize: 11)),
                          children: [
                            ...(route['stops'] as List).cast<Map<String, dynamic>>().map((stop) => ListTile(
                                  dense: true,
                                  leading: CircleAvatar(radius: 13, backgroundColor: AppColors.amber, child: Text('${stop['seq']}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900))),
                                  title: Text('${stop['address'] ?? ''}', style: const TextStyle(fontSize: 12)),
                                  trailing: Text('+${stop['km_from_prev']} km', style: const TextStyle(color: AppColors.muted, fontSize: 11)),
                                )),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton.icon(
                                icon: const Icon(Icons.copy_all_rounded, size: 16),
                                label: const Text('Copy manifest', style: TextStyle(fontSize: 12)),
                                onPressed: () => _copyManifest((route['stops'] as List).cast<Map<String, dynamic>>()),
                              ),
                            ),
                          ],
                        ),
                      ),
                    )),
            ]);
          },
        ),
      ),
    );
  }
}

class _SmartRouteCard extends StatefulWidget {
  const _SmartRouteCard();

  @override
  State<_SmartRouteCard> createState() => _SmartRouteCardState();
}

class _SmartRouteCardState extends State<_SmartRouteCard> {
  Future<Map<String, dynamic>?> _future = DropOffApi.routePickup();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Expanded(child: Text('Today’s smart pickup route', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
            IconButton(
              tooltip: 'Re-optimize',
              icon: const Icon(Icons.refresh),
              onPressed: () => setState(() => _future = DropOffApi.routePickup()),
            ),
          ]),
          const Text('Stops are ordered nearest-neighbor from the Chibolya depot so you sweep the city, not zigzag it.', style: TextStyle(color: AppColors.muted, fontSize: 11.5)),
          const SizedBox(height: 10),
          FutureBuilder<Map<String, dynamic>?>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Padding(padding: EdgeInsets.symmetric(vertical: 20), child: Center(child: CircularProgressIndicator(strokeWidth: 2.5)));
              }
              final stops = (snap.data?['stops'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
              if (stops.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('No pickups queued today — the smart list fills as jobs come in.', style: TextStyle(color: AppColors.muted, fontSize: 12)),
                );
              }
              return Column(children: [
                for (var i = 0; i < stops.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(children: [
                      CircleAvatar(radius: 13, backgroundColor: AppColors.amber, child: Text('${i + 1}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900))),
                      const SizedBox(width: 10),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${stops[i]['ref'] ?? ''} — ${stops[i]['address'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                        if (stops[i]['km_from_previous'] != null) Text('+${stops[i]['km_from_previous']} km from previous stop', style: const TextStyle(color: AppColors.muted, fontSize: 11)),
                      ])),
                      IconButton(
                        icon: const Icon(Icons.navigation_rounded, color: AppColors.forest),
                        tooltip: 'Navigate this stop',
                        onPressed: () => launchUrl(
                          Uri.parse('https://waze.com/ul?ll=${stops[i]['lat']},${stops[i]['lng']}&navigate=yes&follow_deep=1'),
                          mode: LaunchMode.externalApplication,
                        ),
                      ),
                    ]),
                  ),
              ]);
            },
          ),
        ]),
      ),
    );
  }
}

class _RevenueRow extends StatelessWidget {
  final String number;
  final String title;
  final String text;
  const _RevenueRow({required this.number, required this.title, required this.text});

  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(bottom: 18), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
    CircleAvatar(radius: 15, backgroundColor: AppColors.amber, child: Text(number, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900))),
    const SizedBox(width: 12),
    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
      const SizedBox(height: 4),
      Text(text, style: const TextStyle(color: AppColors.muted, height: 1.45, fontSize: 12)),
    ])),
  ]));
}




/// Flat driver pay + daily expectation. Shown ONLY on the rider view (never in
/// seller-facing copy); staff see the full economics in the revenue card.
class _RiderPayCard extends StatelessWidget {
  const _RiderPayCard();

  @override
  Widget build(BuildContext context) => const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.payments_outlined, color: AppColors.forest),
              SizedBox(width: 10),
              Expanded(child: Text('Your pay', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15))),
            ]),
            SizedBox(height: 6),
            Text('K3,000/month flat with a 30-parcels/day target. After the cap you keep your tier discount off pay-as-you-go.',
                style: TextStyle(color: AppColors.muted, fontSize: 12, height: 1.4)),
          ]),
        ),
      );
}

/// Driver's daily 30-parcel target, with the month pace line so a missed day
/// is caught up inside the month instead of silently sliding.
class _RiderTargetsCard extends StatefulWidget {
  const _RiderTargetsCard();

  @override
  State<_RiderTargetsCard> createState() => _RiderTargetsCardState();
}

class _RiderTargetsCardState extends State<_RiderTargetsCard> {
  Map<String, dynamic>? _t;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final res = await DropOffApi.riderTargets();
    if (!mounted) return;
    setState(() {
      _t = (res?['targets'] as Map?)?.cast<String, dynamic>();
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = _t;
    final today = (t?['today'] as num?)?.toInt() ?? 0;
    final daily = (t?['daily_target'] as num?)?.toInt() ?? 30;
    final month = (t?['month'] as num?)?.toInt() ?? 0;
    final monthTarget = (t?['month_target'] as num?)?.toInt() ?? 0;
    final pace = (t?['pace_target'] as num?)?.toInt() ?? 0;
    final met = t?['daily_met'] == true;
    final onTrack = t?['on_track'] == true;
    final behind = (t?['behind_by'] as num?)?.toInt() ?? 0;
    final day = (t?['day_of_month'] as num?)?.toInt() ?? 0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.flag_outlined, color: AppColors.forest),
            const SizedBox(width: 10),
            const Expanded(child: Text('Your targets', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15))),
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: () { setState(() => _loading = true); _load(); },
              icon: const Icon(Icons.refresh, size: 18),
            ),
          ]),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
            )
          else if (t == null)
            const Text('Targets unavailable offline.', style: TextStyle(color: AppColors.muted, fontSize: 12))
          else ...[
            Row(children: [
              Expanded(child: Text('Today: $today / $daily parcels', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5))),
              Text(met ? 'MET' : '${daily - today} to go',
                  style: TextStyle(color: met ? AppColors.forest : const Color(0xFF8A5A00), fontWeight: FontWeight.w900, fontSize: 11.5)),
            ]),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: daily == 0 ? 0 : (today / daily).clamp(0.0, 1.0),
                minHeight: 8,
                backgroundColor: AppColors.line.withValues(alpha: 0.4),
                color: met ? AppColors.forest : AppColors.amber,
              ),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: Text('Month: $month / $monthTarget', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5))),
              Text('pace $pace', style: const TextStyle(color: AppColors.muted, fontSize: 11.5)),
            ]),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: monthTarget == 0 ? 0 : (month / monthTarget).clamp(0.0, 1.0),
                minHeight: 8,
                backgroundColor: AppColors.line.withValues(alpha: 0.4),
                color: onTrack ? AppColors.forest : AppColors.amber,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              onTrack
                  ? 'On pace: $pace expected by day $day of the month.'
                  : '$behind behind pace - clear the daily $daily first, then use the rest of the month to catch up.',
              style: TextStyle(color: onTrack ? AppColors.forest : const Color(0xFF8A5A00), fontSize: 11.5, height: 1.4, fontWeight: FontWeight.w600),
            ),
          ],
        ]),
      ),
    );
  }
}

/// Rider KYC: NRC, licence, plate, vehicle details and photos. Submits to the
/// owner/admin verification queue; riders cannot mark themselves verified.
class _RiderVerificationCard extends StatefulWidget {
  const _RiderVerificationCard();

  @override
  State<_RiderVerificationCard> createState() => _RiderVerificationCardState();
}

class _RiderVerificationCardState extends State<_RiderVerificationCard> {
  final _nrc = TextEditingController();
  final _license = TextEditingController();
  final _plate = TextEditingController();
  final _make = TextEditingController();
  final _color = TextEditingController();
  final Map<String, String> _local = {};
  String? _selfieUrl, _nrcUrl, _plateUrl, _licenseUrl;
  Map<String, dynamic>? _rider;
  bool _loading = true;
  bool _saving = false;
  String? _busyField;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_nrc, _license, _plate, _make, _color]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final res = await DropOffApi.riderProfile();
    if (!mounted) return;
    final rider = (res?['rider'] as Map?)?.cast<String, dynamic>();
    setState(() {
      _rider = rider;
      _loading = false;
      if (rider != null) {
        _nrc.text = '${rider['nrc_number'] ?? ''}';
        _license.text = '${rider['license_number'] ?? ''}';
        _plate.text = '${rider['plate_number'] ?? ''}';
        _make.text = '${rider['vehicle_make'] ?? ''}';
        _color.text = '${rider['vehicle_color'] ?? ''}';
        _selfieUrl = rider['photo_url'] as String?;
        _nrcUrl = rider['nrc_photo_url'] as String?;
        _plateUrl = rider['plate_photo_url'] as String?;
        _licenseUrl = rider['license_photo_url'] as String?;
      }
    });
  }

  Future<void> _pick(String field) async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1600, imageQuality: 82);
    if (picked == null) return;
    setState(() => _busyField = field);
    final bytes = await picked.readAsBytes();
    final name = picked.name.isNotEmpty ? picked.name : 'photo.jpg';
    final res = await DropOffApi.uploadImage(bytes, name);
    if (!mounted) return;
    setState(() => _busyField = null);
    if (!res.ok) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Photo upload failed (${res.error}).')));
      return;
    }
    final url = '${res.body['url'] ?? ''}';
    if (url.isEmpty) return;
    setState(() {
      _local[field] = picked.path;
      switch (field) {
        case 'selfie': _selfieUrl = url;
        case 'nrc': _nrcUrl = url;
        case 'plate': _plateUrl = url;
        case 'license': _licenseUrl = url;
      }
    });
  }

  Future<void> _submit() async {
    if (_nrc.text.trim().length < 6) return _snack('Enter your NRC number.');
    if (_plate.text.trim().length < 3) return _snack('Enter your number plate.');
    if (_make.text.trim().isEmpty) return _snack('Enter the vehicle make/model.');
    if (_selfieUrl == null || _nrcUrl == null || _plateUrl == null) {
      return _snack('Add your selfie, NRC photo and number-plate photo.');
    }
    setState(() => _saving = true);
    final res = await DropOffApi.riderProfileSubmit({
      'nrc_number': _nrc.text.trim(),
      'license_number': _license.text.trim(),
      'plate_number': _plate.text.trim(),
      'vehicle_make': _make.text.trim(),
      'vehicle_color': _color.text.trim(),
      'photo_url': _selfieUrl,
      'nrc_photo_url': _nrcUrl,
      'license_photo_url': _licenseUrl,
      'plate_photo_url': _plateUrl,
    });
    if (!mounted) return;
    setState(() => _saving = false);
    _snack(res.ok
        ? 'Submitted - the owner/admin will verify your documents.'
        : 'Could not submit (${res.error}).');
    if (res.ok) _load();
  }

  void _snack(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Widget _photoTile(String field, String label, String? url) {
    final local = _local[field];
    final busy = _busyField == field;
    Widget preview;
    if (busy) {
      preview = const Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)));
    } else if (local != null) {
      preview = Image.file(File(local), fit: BoxFit.cover);
    } else if (url != null && url.isNotEmpty) {
      preview = Image.network(
        '${DropOffApi.baseUrl}$url',
        headers: DropOffApi.authHeaders,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined, color: AppColors.muted),
      );
    } else {
      preview = const Icon(Icons.add_a_photo_outlined, color: AppColors.muted);
    }
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: busy ? null : () => _pick(field),
      child: Column(children: [
        Container(
          width: 96,
          height: 78,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: AppColors.line.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.line),
          ),
          child: preview,
        ),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: AppColors.muted)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = '${_rider?['verification_status'] ?? 'pending'}';
    final note = '${_rider?['verification_note'] ?? ''}'.trim();
    final verified = status == 'verified';
    final rejected = status == 'rejected';
    final (chipColor, chipText) = verified
        ? (AppColors.forest, 'VERIFIED')
        : rejected
            ? (const Color(0xFFB3261E), 'REJECTED')
            : (const Color(0xFF8A5A00), 'PENDING REVIEW');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.verified_user_outlined, color: AppColors.forest),
            const SizedBox(width: 10),
            const Expanded(child: Text('Driver verification', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: chipColor.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20)),
              child: Text(chipText, style: TextStyle(color: chipColor, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 0.4)),
            ),
          ]),
          const SizedBox(height: 4),
          const Text('Your NRC, licence, plate and vehicle photos. The owner/admin verifies these before you can be assigned jobs.',
              style: TextStyle(color: AppColors.muted, fontSize: 11.5, height: 1.4)),
          if (rejected && note.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: const Color(0xFFB3261E).withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10)),
              child: Text('Reviewer: $note', style: const TextStyle(color: Color(0xFFB3261E), fontSize: 11.5, height: 1.4, fontWeight: FontWeight.w600)),
            ),
          ],
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
            )
          else ...[
            const SizedBox(height: 12),
            TextField(controller: _nrc, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'NRC number', hintText: '123456/11/1', prefixIcon: Icon(Icons.badge_outlined))),
            const SizedBox(height: 10),
            TextField(controller: _plate, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'Number plate', hintText: 'ABC 1234', prefixIcon: Icon(Icons.pin_outlined))),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: TextField(controller: _make, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Vehicle make/model'))),
              const SizedBox(width: 10),
              Expanded(child: TextField(controller: _color, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Colour'))),
            ]),
            const SizedBox(height: 10),
            TextField(controller: _license, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'Driving licence (optional)', prefixIcon: Icon(Icons.credit_card_outlined))),
            const SizedBox(height: 12),
            const Text('Photos', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
            const SizedBox(height: 8),
            Wrap(spacing: 12, runSpacing: 10, children: [
              _photoTile('selfie', 'Selfie', _selfieUrl),
              _photoTile('nrc', 'NRC', _nrcUrl),
              _photoTile('plate', 'Plate', _plateUrl),
              _photoTile('license', 'Licence', _licenseUrl),
            ]),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _saving ? null : _submit,
                icon: _saving
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.send_outlined, size: 18),
                label: Text(verified
                    ? 'Update details (re-review)'
                    : rejected
                        ? 'Fix and resubmit'
                        : 'Submit for verification'),
              ),
            ),
          ],
        ]),
      ),
    );
  }
}
