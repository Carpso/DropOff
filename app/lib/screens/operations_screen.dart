import '../ui/app_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../data/analytics_service.dart';
import '../data/dropoff_api.dart';
import '../data/push_service.dart';
import '../state/app_store.dart';
import '../main.dart';
import '../ui/app_theme.dart';
import 'in_app_navigator_screen.dart';
import '../widgets/common.dart';
import 'rider_queue_screen.dart';
import '../ui/app_spinner.dart';

class OperationsScreen extends StatelessWidget {
  const OperationsScreen({super.key});

  Future<void> _linkDevice(BuildContext context) async {
    final store = AppScope.of(context);
    final phone = TextEditingController();
    final code = TextEditingController();
    String phrase = store.linked
        ? 'Linked as ${store.linkedPhone}. Lipila prompts and job receipts flow through this identity.'
        : 'Verify with a one-time code for receipts, live tracking and team access.';
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
            }, child: const Text('Sign out (unlink device)')),
          ],
        ]),
      )),
    );
    if (confirmed == true && context.mounted) {
      AppToast.show(context, 'Device identity updated.');
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
              AppToast.show(context, 'Enter a name and valid mobile number.');
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
        AppToast.show(context, error);
      }
    }
    name.dispose();
    phone.dispose();
  }

  Future<void> _editRider(BuildContext context, dynamic rider) async {
    final store = AppScope.of(context);
    if (!(store.isSuperAdmin || store.isAdminRole)) return;
    final name = TextEditingController(text: '${rider.name}');
    final phone = TextEditingController(text: '${rider.phone}');
    String vehicle = '${rider.vehicle}';
    const options = <String>['Motorcycle', 'Car', 'Van', 'Truck', 'Bicycle', 'Three-wheeler'];
    if (!options.contains(vehicle)) vehicle = 'Motorcycle';
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.canvas,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (sheetContext) => StatefulBuilder(builder: (context, setSheetState) => Padding(
        padding: EdgeInsets.fromLTRB(22, 22, 22, MediaQuery.of(context).viewInsets.bottom + 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Edit rider', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          const Text('Changes apply to the shared team roster.', style: TextStyle(color: AppColors.muted, fontSize: 12)),
          const SizedBox(height: 16),
          TextField(controller: name, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Full name', prefixIcon: Icon(Icons.person_outline))),
          const SizedBox(height: 12),
          TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Mobile number', hintText: '0971234567', prefixIcon: Icon(Icons.phone_outlined))),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: vehicle,
            decoration: InputDecoration(labelText: 'Vehicle', prefixIcon: Icon(_vehicleIcon(vehicle))),
            items: options.map((v) => DropdownMenuItem(value: v, child: Row(children: [Icon(_vehicleIcon(v), size: 20), const SizedBox(width: 10), Text(v == 'Truck' ? 'Truck (large cargo)' : v)]))).toList(),
            onChanged: (value) => setSheetState(() => vehicle = value ?? 'Motorcycle'),
          ),
          const SizedBox(height: 20),
          FilledButton(onPressed: () {
            if (name.text.trim().length < 2 || phone.text.trim().length < 9) {
              AppToast.show(context, 'Enter a name and valid mobile number.');
              return;
            }
            Navigator.of(sheetContext).pop(true);
          }, child: const Text('Save changes')),
        ]),
      )),
    );
    if (saved == true && context.mounted) {
      final numericId = int.tryParse('${rider.id}');
      if (numericId == null) return;
      final err = await store.updateRider(
        numericId,
        fullName: name.text,
        phone: phone.text,
        vehicle: vehicle,
        vehicleClass: _vehicleClassOf(vehicle),
      );
      if (context.mounted) {
        AppToast.show(context, err ?? 'Rider updated.');
      }
    }
    name.dispose();
    phone.dispose();
  }

  Future<void> _confirmRemoveRider(BuildContext context, dynamic rider) async {
    final store = AppScope.of(context);
    if (!(store.isSuperAdmin || store.isAdminRole)) return;
    final openCount = store.bookings.where((b) => b.riderId == '${rider.id}' && b.stage < b.timeline.length - 1).length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove rider from team?'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('This permanently removes ${rider.name} from the shared rider roster.', style: const TextStyle(height: 1.4)),
          const SizedBox(height: 10),
          if (openCount > 0)
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: const Color(0xFFFFF3E0), borderRadius: BorderRadius.circular(12)),
              child: Text('Blocked by condition: $openCount open booking(s) are still assigned to this rider. Reassign/complete them or deactivate the rider instead.',
                style: const TextStyle(fontSize: 12.5, height: 1.35, color: Color(0xFF7A4A00))),
            )
          else
            const Text('If this rider has historical deliveries, removal is only allowed when no open jobs are assigned (server-checked). Consider deactivating instead if unsure.',
              style: TextStyle(fontSize: 12.5, height: 1.35, color: AppColors.ink)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('Deactivate instead'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: openCount > 0 ? null : () => Navigator.pop(ctx, true),
            child: const Text('Delete permanently'),
          ),
        ],
      ),
    );
    if (confirmed == null && context.mounted) {
      // "Deactivate instead" convenience action
      final err = await store.toggleRider('${rider.id}', false);
      if (context.mounted) {
        AppToast.show(context, err ?? '${rider.name} deactivated.');
      }
      return;
    }
    if (confirmed == true && context.mounted) {
      final err = await store.removeRider('${rider.id}', confirm: true);
      if (context.mounted) {
        AppToast.show(context, err ?? '${rider.name} removed from the team.');
      }
    }
  }

  /// Live-position card: visible ON/OFF state + auto-ping for riders who opted
  /// in (the default). Requests GPS once, and shows precise feedback.
  Widget _riderLocationCard(BuildContext context) {
    final store = AppScope.of(context);
    return _RiderLocationCardInner(store: store);
  }

  Future<void> _pingMyLocation(BuildContext context) async {
    final store = AppScope.of(context);
    if (!store.linked) {
      AppToast.show(context, 'Link this device first so your rider phone is known.');
      return;
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      if (!context.mounted) return;
      AppToast.show(context, 'Location permission needed to share your live position.');
      return;
    }
    try {
      final pos = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high));
      final res = await DropOffApi.riderPing(phone: store.linkedPhone!, lat: pos.latitude, lng: pos.longitude);
      if (!context.mounted) return;
      AppToast.show(context, res.ok ? 'Live location shared with senders.' : 'Could not submit location right now.');
    } catch (e) {
      if (!context.mounted) return;
      AppToast.show(context, 'Location unavailable — check GPS.');
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
        child: RefreshIndicator(
          onRefresh: () async {
            await store.syncJobsFromServer();
          },
          child: ListView(padding: const EdgeInsets.fromLTRB(20, 22, 20, 28), children: [
          Row(children: [
            const Icon(Icons.two_wheeler, color: AppColors.forest),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Your riding day', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
              const SizedBox(height: 3),
              Text('Signed in as ${store.linkedPhone} — jobs assigned to you land here automatically.', style: AppType.caption),
            ])),
          ]),
          const SizedBox(height: 12),
          const _SelfieBanner(),
          Row(children: [
            Expanded(child: _Metric(value: '${store.bookings.length}', label: 'Bookings on device', icon: Icons.inventory_2_outlined)),
            const SizedBox(width: 12),
            Expanded(child: _TeamSizeChip(fallback: activeRiders)),
          ]),
          const SizedBox(height: 16),
          // Verification first: a new rider can't be assigned jobs until their
          // ID, plate and photos are approved, so it goes before the queue.
          const _RiderVerificationCard(),
          const SizedBox(height: 12),
          _TaskQueueCard(),
          const SizedBox(height: 12),
          const SizedBox(height: 12),
          const _RiderReviewsCard(),
          const SizedBox(height: 12),
          const _RiderTargetsCard(),
          const SizedBox(height: 12),
          _riderLocationCard(context),
          const SizedBox(height: 22),
          Card(
            child: ListTile(
              leading: Icon(store.linked ? Icons.verified_user : Icons.link_outlined, color: AppColors.forest),
              title: Text(store.linked ? 'Linked as ${store.linkedPhone}' : 'Device not linked', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
              subtitle: const Text('This number is your rider identity — jobs and COD are keyed to it.', style: AppType.caption),
              trailing: TextButton(onPressed: () => _linkDevice(context), child: const Text('Manage')),
            ),
          ),
        ]),
        ),
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
    final canAddRiders = store.isSuperAdmin || store.isAdminRole;
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: () async {
          await store.syncJobsFromServer();
        },
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
          // Live roster count from GET /team — same number riders and admins
          // see, straight from the riders table (device count is only a fallback).
          Expanded(child: _TeamSizeChip(fallback: activeRiders)),
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
            subtitle: const Text('Broadcast your GPS once so senders of your jobs can open a live map.', style: TextStyle(color: AppColors.ink, fontSize: 12.5, height: 1.35)),
            trailing: FilledButton.tonal(
              style: FilledButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8), minimumSize: const Size(0, 36)),
              onPressed: () => _pingMyLocation(context),
              child: const Text('Share'),
            ),
          ),
        ),
        const SizedBox(height: 26),
        SectionTitle('Riders & drivers', actionLabel: canAddRiders ? '+ Add' : null, onAction: canAddRiders ? () => _addRider(context) : null),
        const SizedBox(height: 8),
        if (store.riders.isEmpty) ...[
          EmptyState(
            eyebrow: 'TEAM',
            title: 'No riders yet.',
            message: canAddRiders
                ? 'Tap + Add to register your first rider or driver. They appear in the shared team once saved.'
                : 'Only admins can add riders. They appear here once added.',
            action: canAddRiders
                ? FilledButton.icon(
                    onPressed: () => _addRider(context),
                    icon: const Icon(Icons.add),
                    label: const Text('Add rider'),
                  )
                : null,
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
                  Text('${rider.vehicle} • ${rider.phone}', style: AppType.caption),
                ])),
                if (rider.isOwner)
                  const InfoPill(icon: Icons.verified, label: 'ADMIN')
                else if (canAddRiders) ...[
                  IconButton(
                    tooltip: 'Edit rider',
                    icon: const Icon(Icons.edit_outlined, color: AppColors.muted),
                    onPressed: () => _editRider(context, rider),
                  ),
                  Switch(
                    value: rider.active,
                    onChanged: (value) async {
                      final err = await store.toggleRider(rider.id, value);
                      if (err != null && context.mounted) {
                        AppToast.show(context, err);
                      }
                    },
                  ),
                  IconButton(
                    tooltip: 'Remove rider',
                    icon: const Icon(Icons.delete_outline, color: Color(0xFF9A5A5A)),
                    onPressed: () => _confirmRemoveRider(context, rider),
                  ),
                ] else
                  const InfoPill(icon: Icons.verified, label: 'VIEW ONLY'),
              ]))),
            ),
        ],
        const SizedBox(height: 22),
        // Driver economics are staff-only (admin/ops). This screen is already
        // behind the Team tab which only staff see — keep the card for them
        // but never surface rider payout splits to senders/recipients.
        if (AppScope.of(context).isStaff) ...[
          const SectionTitle('How DropOff earns'),
          const SizedBox(height: 8),
          const Card(child: Padding(padding: EdgeInsets.all(18), child: Column(children: [
            _RevenueRow(number: '01', title: 'Pay-as-you-go pickup', text: 'K45 per pickup, the DropOff leg accrues 100% to DropOff — riders are salaried (K3,000/mo incl. K300/wk fuel), pace-gated by delivery, never paid per parcel.'),
            _RevenueRow(number: '02', title: 'Subscription plans: Silver / Gold / Platinum', text: 'K250 / K500 / K750 per 30-day cycle for 10 / 25 / 50 parcels (plus Daily Rider K49/day and Weekly K399). Every parcel counts as one — even in the same trip.'),
            _RevenueRow(number: '03', title: 'Waiting & no-COD', text: 'Waiting over 10 min bills K2/min (K50 cap) — accrues to DropOff, never to the rider. There is no COD; recipients never pay cash, so riders never carry cash.'),
            _RevenueRow(number: '04', title: 'Door delivery & subscription plans', text: 'Last-mile door delivery priced like first-mile pay-as-you-go (recipient-city distance + vehicle). Plan parcels bundle the rider inside the monthly fee.'),
          ]))),
        ],
        ],
        ),
      ),
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

/// Rider live-position panel:
/// - Shows an obvious ON/OFF status with forest/OFF semantics.
/// - Default ON for riders (they can opt out any time it just stops sharing).
/// - Auto-pings when the card mounts if sharing is enabled + rider is linked.
class _RiderLocationCardInner extends StatefulWidget {
  final AppStore store;
  const _RiderLocationCardInner({required this.store});

  @override
  State<_RiderLocationCardInner> createState() => _RiderLocationCardInnerState();
}

class _RiderLocationCardInnerState extends State<_RiderLocationCardInner> {
  bool _pinging = false;
  String? _lastStatus;

  Timer? _loop;

  @override
  void initState() {
    super.initState();
    // Fully automatic: permission allowed + sharing on + linked rider →
    // continuous live pings every 12s for as long as this screen is open.
    // The sender tracking their job sees the rider's pin move; nobody presses
    // a button. Toggle in the card remains, but nothing requires it.
    _startLoop();
  }

  void _startLoop() {
    _loop?.cancel();
    if (widget.store.shareLocationOn && widget.store.linked && widget.store.isRider) {
      // immediate fix, then keep-alive cadence matching the sender's 12s refresh
      unawaited(_ping(silent: true));
      _loop = Timer.periodic(const Duration(seconds: 12), (_) => _ping(silent: true));
    }
  }

  @override
  void dispose() {
    _loop?.cancel();
    super.dispose();
  }

  Future<void> _ping({bool silent = false}) async {
    if (_pinging) return;
    if (!widget.store.linked) return;
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      if (mounted && !silent) {
        setState(() => _lastStatus = 'Location permission needed to share your live position.');
        AppToast.show(context, 'Enable location permission to share your position.');
      }
      return;
    }
    setState(() => _pinging = true);
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      final res = await DropOffApi.riderPing(phone: widget.store.linkedPhone!, lat: pos.latitude, lng: pos.longitude);
      if (!mounted) return;
      setState(() {
        _pinging = false;
        _lastStatus = res.ok ? 'Live position ON — senders can follow you.' : 'Location saved locally; ping failed — try again.';
      });
      if (!silent && res.ok) {
        AppToast.show(context, 'Live position shared with senders of your jobs.');
      } else if (!silent && !res.ok) {
        AppToast.show(context, 'Could not submit position (network) — retry when online.');
      }
    } catch (_) {
      if (!mounted) return;
      setState(() { _pinging = false; _lastStatus = 'Location unavailable — GPS off or no fix.'; });
      if (!silent) AppToast.show(context, 'Location unavailable — check GPS.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final on = store.shareLocationOn;
    return Card(
      color: on ? AppColors.forest.withValues(alpha: 0.07) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: on ? AppColors.forest.withValues(alpha: 0.45) : AppColors.line),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.my_location, color: AppColors.forest),
            const SizedBox(width: 10),
            const Expanded(child: Text('Live position sharing', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15))),
            Switch(
              value: on,
              activeTrackColor: AppColors.forest,
              onChanged: (value) async {
                await store.setShareLocationOn(value);
                _startLoop();
                if (value) await _ping();
                if (mounted) setState(() {});
              },
            ),
          ]),
          const SizedBox(height: 4),
          Text(
            on
                ? 'On — automatic while this screen is open. Permission granted = the sender of your active jobs sees your exact pin; nobody presses anything.'
                : 'Off — senders will see your name, vehicle and ETA only; never your live coordinates.',
            style: AppType.caption,
          ),
          if (_lastStatus != null) ...[
            const SizedBox(height: 6),
            Text(_lastStatus!, style: const TextStyle(fontSize: 10.5, color: AppColors.muted, height: 1.3)),
          ],
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: Text(
                on ? 'Syncing automatically — GPS granted, sharing every 12s.' : 'Enable to sync automatically.',
                style: const TextStyle(fontSize: 11, color: AppColors.muted),
              ),
            ),
            IconButton(
              tooltip: 'Refresh position now',
              onPressed: _pinging ? null : () => _ping(),
              icon: _pinging
                  ? const AppLogoSpinner(size: 16)
                  : const Icon(Icons.gps_fixed, size: 18, color: AppColors.forest),
            ),
          ]),
        ]),
      ),
    );
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
              Text('Slot batches with stop times, parcel counts and target depot drop-off.', style: TextStyle(color: AppColors.ink, fontSize: 12.5, height: 1.35)),
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
    Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
    Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, color: AppColors.ink)),
  ])));
}

/// Live team size — synced from the server roster (`GET /team`) so it's the
/// same on every device and only counts verified+active riders. Falls back to
/// the device-cached count when the network is down.
class _TeamSizeChip extends StatefulWidget {
  const _TeamSizeChip({required this.fallback});
  final int fallback;

  @override
  State<_TeamSizeChip> createState() => _TeamSizeChipState();
}

class _TeamSizeChipState extends State<_TeamSizeChip> {
  int? _size;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await DropOffApi.teamRoster();
    if (!mounted) return;
    final total = (data?['total'] as num?)?.toInt();
    if (total != null) setState(() => _size = total);
  }

  @override
  Widget build(BuildContext context) => _Metric(
        value: '${_size ?? widget.fallback}',
        label: 'Team size',
        icon: Icons.groups_outlined,
      );
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
              child: Text('No ratings yet — senders and recipients rate you after each delivery; they show up here.', style: AppType.caption),
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
                        child: Text('“${r['comment']}”', style: const TextStyle(fontSize: 11.5, height: 1.35)),
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
    if (mounted) AppToast.show(context, 'Manifest copied — paste it into your dispatch group.');
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
                const Center(child: Padding(padding: EdgeInsets.symmetric(vertical: 16), child: AppLogoSpinner(size: 22)))
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
                return const Padding(padding: EdgeInsets.symmetric(vertical: 20), child: Center(child: AppLogoSpinner(size: 26)));
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
                        onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                          builder: (_) => InAppNavigatorScreen(
                            destLat: (stops[i]['lat'] as num).toDouble(),
                            destLng: (stops[i]['lng'] as num).toDouble(),
                            label: '${stops[i]['ref'] ?? 'Stop ${i + 1}'} — ${stops[i]['address'] ?? ''}',
                          ),
                        )),
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




/// PAY DEPENDS ON TARGET REACH (owner 2026-11-21): the standalone "Your pay"
/// card is gone. The rule lives with the targets it depends on.
/// (Full salary only when the month target is met; pro-rated by rides done if
/// the target is missed.) Split out so rider economics stay out of seller copy.

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
  Timer? _poll; // same 20 s cadence as the Task Queue card

  @override
  void initState() {
    super.initState();
    _load();
    _poll = Timer.periodic(const Duration(seconds: 20), (_) => _load());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
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
    final targetBonus = (t?['bonus'] as Map?)?.cast<String, dynamic>();
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
              child: Center(child: AppLogoSpinner(size: 18)),
            )
          else if (t == null)
            const Text('Targets unavailable offline.', style: TextStyle(color: AppColors.muted, fontSize: 12))
          else ...[
            Row(children: [
              Expanded(child: Text('Today: $today / $daily parcels', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5))),
              Text(met ? 'MET' : '${daily - today} to go',
                  style: TextStyle(color: met ? AppColors.forest : AppColors.warning, fontWeight: FontWeight.w900, fontSize: 11.5)),
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
              style: TextStyle(color: onTrack ? AppColors.forest : AppColors.warning, fontSize: 11.5, height: 1.4, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 8),
            const Text(
              'Pay follows the target: the K3,000 monthly salary (K300/week fuel included) is paid in full when the month target is reached. '
              'If you finish below target, pay is calculated from the rides you actually completed. '
              'Paid weekly on Sundays (16:00 CAT) or monthly on the 1st.',
              style: TextStyle(color: AppColors.muted, fontSize: 11.5, height: 1.45),
            ),
            if (targetBonus != null) ...[
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 10),
              const Row(children: [
                Icon(Icons.savings_outlined, size: 15, color: AppColors.forest),
                SizedBox(width: 6),
                Text('Over-target bonus', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12.5)),
              ]),
              const SizedBox(height: 4),
              Text(
                targetBonus['target_met'] == true
                    ? 'K200 completion locked ✓  ·  +K${(targetBonus['over_target_bonus_zmw'] ?? 0).toStringAsFixed(0)} over target so far (${targetBonus['counted_extra'] ?? 0} parcels)  ·  K150 stretch at 1.25× target'
                    : 'Hit the month target ($monthTarget parcels) and you bank K200 + K5 per parcel beyond it (max K675) + K150 stretch at 1.25× target.',
                style: AppType.caption,
              ),
            ],
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

class _RiderVerificationCardState extends State<_RiderVerificationCard> with WidgetsBindingObserver {
  final _nrc = TextEditingController();
  final _license = TextEditingController();
  final _plate = TextEditingController();
  final _make = TextEditingController();
  final _color = TextEditingController();
  final Map<String, String> _local = {};
  String? _selfieUrl, _nrcUrl, _plateUrl, _licenseUrl;
  Map<String, dynamic>? _rider;
  Map<String, dynamic>? _faceCheck;
  bool _loading = true;
  bool _saving = false;
  bool _faceBusy = false;
  String? _busyField;
  bool _submitted = false;
  /// Collapsed by default — the verified rider is busy, not editing. Tap to open.
  bool _collapsed = true;
  /// Auto-sync of the admin's verdict (owner bug report 2026-11-17: "approved
  /// on the rider side doesn't sync"). Rejections/approvals land while the
  /// app sits in the background; three sources refresh this card without a
  /// manual pull: app resume, a periodic poll while the verdict is still
  /// pending, and the rider_verification push tap.
  StreamSubscription<Map<String, dynamic>?>? _pushSub;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _pushSub = PushService.onPayloadTap.stream.listen((payload) {
      final kind = '${payload?['kind'] ?? ''}'.toLowerCase();
      if (kind.contains('rider_verification')) _load();
    });
    _schedulePoll();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pushSub?.cancel();
    _poll?.cancel();
    for (final c in [_nrc, _license, _plate, _make, _color]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Coming back to the foreground is the moment the admin verdict may have
    // landed — refresh immediately instead of waiting for the poll.
    if (state == AppLifecycleState.resumed) _load();
  }

  /// Poll every 45s while a verdict is outstanding so an approval surfaces on
  /// its own once the worker flips the row (D1 writes don't notify clients).
  void _schedulePoll() {
    _poll?.cancel();
    final status = '${_rider?['verification_status'] ?? ''}';
    if (_loading || status == 'pending' || status == 'rejected' || status.isEmpty) {
      _poll = Timer.periodic(const Duration(seconds: 45), (_) => _load());
    }
  }

  Map<String, dynamic>? _parseFace(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      final face = (decoded is Map ? decoded['face'] : null);
      return face is Map ? face.cast<String, dynamic>() : null;
    } catch (_) {
      return null;
    }
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
        _faceCheck = _parseFace(rider['ai_check_json'] as String?);
        // Hiding stall photos after submission: a rider whose status is pending
        // signed off already — no need to keep their document photos on screen.
        if ('${rider['verification_status'] ?? ''}' == 'pending') _submitted = true;
      }
    });
    // Re-arm the poll with the fresh status: once verified it stops ticking.
    _schedulePoll();
  }

  /// Riders run the AI face review on their own selfie before submitting —
  /// catches wrong-document uploads and "not a person" photos up front.
  Future<void> _checkFace() async {
    if (_faceBusy) return;
    setState(() => _faceBusy = true);
    final res = await DropOffApi.riderFaceCheck();
    if (!mounted) return;
    setState(() => _faceBusy = false);
    if (!res.ok) {
      _snack(res.error == 'no_selfie'
          ? 'Upload a selfie first, then check it.'
          : (res.error == 'network_error'
              ? 'Could not reach the AI right now — check your connection and retry in a moment.'
              : 'AI check unavailable (${res.error}).'));
      return;
    }
    setState(() => _faceCheck = (res.body['face'] as Map?)?.cast<String, dynamic>());
  }

  Future<void> _pick(String field) async {
    // PHOTO LOCK (owner directive 2026-11-17): once documents are submitted
    // (pending) or verified, the rider can no longer swap them from this
    // screen — any change goes through an admin request. Rejected stays
    // editable so a fixable rejection can be corrected and resubmitted.
    if (_locked) {
      _snack('Photos are locked — request a change from the admin team.');
      return;
    }
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.photo_camera), title: const Text('Take photo with camera'), onTap: () => Navigator.pop(ctx, ImageSource.camera)),
          ListTile(leading: const Icon(Icons.photo_library), title: const Text('Pick from gallery'), onTap: () => Navigator.pop(ctx, ImageSource.gallery)),
        ]),
      ),
    );
    if (source == null) return;
    final picked = await ImagePicker().pickImage(source: source, maxWidth: 1600, imageQuality: 82);
    if (picked == null) return;
    setState(() => _busyField = field);
    final bytes = await picked.readAsBytes();
    final name = picked.name.isNotEmpty ? picked.name : 'photo.jpg';
    final res = await DropOffApi.uploadImage(bytes, name, kind: field == 'selfie' ? 'selfie' : 'kyc');
    if (!mounted) return;
    setState(() => _busyField = null);
    if (!res.ok) {
      AppToast.show(context, 'Photo upload failed (${res.error}).');
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

  bool get _canSubmit =>
      _nrc.text.trim().length >= 6 &&
      _plate.text.trim().length >= 3 &&
      _make.text.trim().isNotEmpty &&
      _selfieUrl != null &&
      _nrcUrl != null &&
      _plateUrl != null;

  /// SUBMITTED-OR-VERIFIED = LOCKED (owner directive 2026-11-17): the rider
  /// screen locks the moment documents go in; only a rejection re-opens it.
  bool get _locked {
    final status = '${_rider?['verification_status'] ?? ''}';
    return status == 'pending' || status == 'verified';
  }

  Future<void> _submit() async {
    if (_locked) return _snack('Verification is locked — request changes from the admin team.');
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
        ? 'Submitted - the admin team will verify your documents.'
        : 'Could not submit (${res.error}).');
    if (res.ok) {
      unawaited(_checkFace()); // auto-review the selfie right after submit
      _load();
      setState(() => _submitted = true);
    }
  }

  void _snack(String text) => AppToast.show(context, text);

  Widget _photoTile(String field, String label, String? url, {bool locked = false}) {
    final local = _local[field];
    final busy = _busyField == field;
    Widget preview;
    if (busy) {
      preview = const Center(child: AppLogoSpinner(size: 18));
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
      borderRadius: BorderRadius.circular(12),
      onTap: busy || locked ? null : () => _pick(field),
      child: Column(children: [
        Stack(children: [
          Container(
            width: 96,
            height: 78,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: AppColors.line.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.line),
            ),
            child: preview,
          ),
          if (locked)
            const Positioned(
              top: 4,
              right: 4,
              child: Icon(Icons.lock, size: 13, color: AppColors.muted),
            ),
        ]),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: AppColors.muted)),
      ]),
    );
  }

  /// AI face verdict chip for the selfie: pass / review / fail. Informational
  /// only — the owner/admin still clicks Approve or Reject.
  Widget _faceChip() {
    final f = _faceCheck;
    if (_faceBusy) {
      return const Row(mainAxisSize: MainAxisSize.min, children: [
        AppLogoSpinner(size: 12),
        SizedBox(width: 6),
        Text('AI is looking…', style: TextStyle(fontSize: 11, color: AppColors.muted)),
      ]);
    }
    if (f == null) return const SizedBox.shrink();
    final verdict = '${f['verdict'] ?? 'review'}';
    final (color, label) = switch (verdict) {
      'pass' => (AppColors.forest, 'One real photo of you'),
      'fail' => (AppColors.danger, 'Not one person - retake?'),
      _ => (AppColors.warning, 'AI unsure - admin will decide'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(verdict == 'pass' ? Icons.face : verdict == 'fail' ? Icons.no_photography_outlined : Icons.help_outline,
            size: 14, color: color),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: color)),
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
            ? (AppColors.danger, 'REJECTED')
            : (AppColors.warning, 'PENDING REVIEW');
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: InkWell(
          onTap: () => setState(() => _collapsed = !_collapsed),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.verified_user_outlined, color: AppColors.forest),
            const SizedBox(width: 10),
            const Expanded(child: Text('Rider verification', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: chipColor.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20)),
              child: Text(chipText, style: TextStyle(color: chipColor, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 0.4)),
            ),
            const SizedBox(width: 6),
            AnimatedRotation(
              turns: _collapsed ? 0 : 0.5,
              duration: const Duration(milliseconds: 220),
              child: const Icon(Icons.expand_more, color: AppColors.muted),
            ),
          ]),
          if (!_collapsed) ...[
          const SizedBox(height: 4),
          const Text('Your NRC, licence, plate and vehicle photos. An admin verifies these before you can be assigned jobs.',
              style: AppType.caption),
          if (rejected && note.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: AppColors.danger.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
              child: Text('Reviewer: $note', style: const TextStyle(color: AppColors.danger, fontSize: 11.5, height: 1.4, fontWeight: FontWeight.w600)),
            ),
          ],
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Center(child: AppLogoSpinner(size: 18)),
            )
          else if (_submitted || _locked)
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: AppColors.forest.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.forest.withValues(alpha: 0.3))),
                child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(Icons.check_circle, color: AppColors.forest),
                    SizedBox(width: 8),
                    Text('Verification submitted', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: AppColors.forest)),
                  ]),
                  SizedBox(height: 6),
                  Text('Your documents are in the admin review queue. You will be notified once verified.', style: AppType.caption),
                ]),
              ),
              const SizedBox(height: 10),
              // LOCK BANNER (owner directive 2026-11-17): submitted photos are
              // submitted ONCE — the rider screen locks; changes go through an
              // admin request. A REJECTION re-opens editing.
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.warning.withValues(alpha: 0.35)),
                ),
                child: const Row(children: [
                  Icon(Icons.lock_outline, size: 16, color: AppColors.warning),
                  SizedBox(width: 8),
                  Expanded(child: Text(
                    'Photos and details are locked. To change them, request it from the admin team — they re-open your file.',
                    style: TextStyle(fontSize: 11.5, height: 1.35, color: AppColors.warning, fontWeight: FontWeight.w600),
                  )),
                ]),
              ),
              if (rejected)
                TextButton(onPressed: () => setState(() => _submitted = false), child: const Text('Edit details and resubmit')),
            ])
          else ...[
            const SizedBox(height: 12),
            TextField(controller: _nrc, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'NRC number', hintText: '123456/11/1', prefixIcon: Icon(Icons.badge_outlined)), onChanged: (_) => setState(() {})),
            const SizedBox(height: 10),
            TextField(controller: _plate, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'Number plate', hintText: 'ABC 1234', prefixIcon: Icon(Icons.pin_outlined)), onChanged: (_) => setState(() {})),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: TextField(controller: _make, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Vehicle make/model'), onChanged: (_) => setState(() {}))),
              const SizedBox(width: 10),
              Expanded(child: TextField(controller: _color, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Colour'))),
            ]),
            const SizedBox(height: 10),
            TextField(controller: _license, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'Driving licence (optional)', prefixIcon: Icon(Icons.credit_card_outlined))),
            const SizedBox(height: 12),
            const Text('Photos', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
            const SizedBox(height: 8),
            Wrap(spacing: 12, runSpacing: 10, children: [
              _photoTile('selfie', 'Selfie', _selfieUrl, locked: _locked),
              _photoTile('nrc', 'NRC', _nrcUrl, locked: _locked),
              _photoTile('plate', 'Plate', _plateUrl, locked: _locked),
              _photoTile('license', 'Licence', _licenseUrl, locked: _locked),
            ]),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
              TextButton.icon(
                onPressed: _faceBusy || _selfieUrl == null ? null : _checkFace,
                icon: _faceBusy
                    ? const AppLogoSpinner(size: 15)
                    : const Icon(Icons.auto_awesome, size: 17),
                label: Text(_faceCheck == null ? 'AI check my selfie' : 'Re-check my selfie'),
              ),
              _faceChip(),
            ]),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _saving || !_canSubmit ? null : _submit,
                icon: _saving
                    ? const AppLogoSpinner(size: 16, color: Colors.white)
                    : const Icon(Icons.send_outlined, size: 18),
                label: Text(verified
                    ? 'Update details (re-review)'
                    : rejected
                        ? 'Fix and resubmit'
                        : 'Submit for verification'),
              ),
            ),
          ],
          ],
          ]),
          ), // Padding
        ), // InkWell
      ), // Theme
    ); // Card
  }
}

/// Grandfathered verified riders have no selfie yet - sellers still see
/// initials. A slim nudge to add one (uploaded as kind=selfie). The Worker
/// AI-reviews inline; a clear fail demotes a verified rider back to pending
/// until an admin re-verifies - pass/review keeps verified standing.
class _SelfieBanner extends StatefulWidget {
  const _SelfieBanner();

  @override
  State<_SelfieBanner> createState() => _SelfieBannerState();
}

class _SelfieBannerState extends State<_SelfieBanner> {
  bool _loading = true;
  bool _needed = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _probe();
  }

  Future<void> _probe() async {
    final res = await DropOffApi.riderProfile();
    if (!mounted) return;
    final rider = (res?['rider'] as Map?)?.cast<String, dynamic>();
    setState(() {
      _loading = false;
      // banner only when we KNOW the rider has no photo on file
      _needed = rider != null && '${rider['photo_url'] ?? ''}'.isEmpty;
    });
  }

  Future<void> _addPhoto() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.photo_camera), title: const Text('Take photo with camera'), onTap: () => Navigator.pop(ctx, ImageSource.camera)),
          ListTile(leading: const Icon(Icons.photo_library), title: const Text('Pick from gallery'), onTap: () => Navigator.pop(ctx, ImageSource.gallery)),
        ]),
      ),
    );
    if (source == null) return;
    final picked = await ImagePicker().pickImage(source: source, maxWidth: 1600, imageQuality: 82);
    if (picked == null) return;
    setState(() => _busy = true);
    final bytes = await picked.readAsBytes();
    final name = picked.name.isNotEmpty ? picked.name : 'selfie.jpg';
    final up = await DropOffApi.uploadImage(bytes, name, kind: 'selfie');
    if (!mounted) return;
    if (!up.ok) {
      setState(() => _busy = false);
      _snack('Upload failed (${up.error}).');
      return;
    }
    final url = '${up.body['url'] ?? ''}';
    final res = await DropOffApi.addMePhoto(url);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!res.ok) {
      _snack('Could not save photo (${res.error}).');
      return;
    }
    final st = '${res.body['verification_status'] ?? ''}';
    _snack(st == 'pending'
        ? 'This photo does not look like one person - you are back in the review queue.'
        : 'Photo added - senders will see you on the tracking page.');
    setState(() => _needed = false);
  }

  void _snack(String t) => AppToast.show(context, t);

  @override
  Widget build(BuildContext context) {
    if (_loading || !_needed) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.amber.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.amber.withValues(alpha: 0.4)),
        ),
        child: Row(children: [
          const Icon(Icons.face, color: AppColors.forest, size: 26),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text("Senders can't see you yet", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
              SizedBox(height: 3),
              Text('Add your photo - the person collecting their parcel should be a face, not an icon.',
                  style: AppType.caption),
            ]),
          ),
          const SizedBox(width: 10),
          FilledButton(
            style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
            onPressed: _busy ? null : _addPhoto,
            child: _busy
                ? const AppLogoSpinner(size: 18)
                : const Text('Add'),
          ),
        ]),
      ),
    );
  }
}
