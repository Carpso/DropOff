import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

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
          const SizedBox(height: 6),
          const Text('Add riders and drivers only when you are ready.', style: TextStyle(color: AppColors.muted)),
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
      await AppScope.of(context).addRider(
        name: name.text,
        phone: phone.text,
        vehicle: vehicle,
        vehicleClass: _vehicleClassOf(vehicle),
      );
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
        const SizedBox(height: 22),
        const SectionTitle('How DropOff earns'),
        const SizedBox(height: 8),
        const Card(child: Padding(padding: EdgeInsets.all(18), child: Column(children: [
          _RevenueRow(number: '01', title: 'Pay-as-you-go pickup', text: 'K45 per pickup. Platform takes 10% (K4.50 to DropOff, K40.50 to the rider) — thin on purpose so riders stay loyal.'),
          _RevenueRow(number: '02', title: 'Seller packs: Silver / Gold / Platinum', text: 'K250 / K500 / K750 per month for 10 / 25 / 50 parcels (30-day cycle). Every parcel counts as one — even in the same trip. Swept pack parcels pay the rider K5 each; after the cap you keep a tier discount off pay-as-you-go.'),
          _RevenueRow(number: '03', title: 'Waiting & COD float', text: 'Waiting over 10 min bills K2/min (K50 cap). COD cash floats with the rider/driver — sender paid via momo disbursement minus our 2%.'),
          _RevenueRow(number: '04', title: 'Door delivery & packs', text: 'Last-mile door delivery priced like first-mile pay-as-you-go (recipient-city distance + vehicle). Pack parcels bundle the rider inside the monthly fee.'),
        ]))),
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


