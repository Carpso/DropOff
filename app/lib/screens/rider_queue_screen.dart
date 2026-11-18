// ─────────────────────────────────────────────────────────────────────
// DROPOFF — ownership stamp (do not remove)
// :Godfrey Moses Kalambo:Carpso Solutions:0968551110.
// © 2026 Godfrey Moses Kalambo · Carpso Solutions · Lusaka, Zambia.
// All rights reserved — unauthorised copying, resale or rebranding of
// this source code is prohibited.
// ─────────────────────────────────────────────────────────────────────
import 'dart:async';

import '../ui/app_toast.dart';
import '../widgets/help_sheet.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';

import '../data/dropoff_api.dart';
import '../data/map_services.dart';
import '../data/analytics_service.dart';
import '../main.dart';
import '../ui/app_theme.dart';
import '../widgets/common.dart';
import '../ui/in_app_browser.dart';
import 'account_screen.dart';
import 'in_app_navigator_screen.dart';

/// The rider's day as slot-batched task queues:
///   BATCH: 10:00—11:30 slot · 6:00—7:30 AM window · 23 min in
///   TOTAL PARCELS: 6 · STOPS: 3 (1 picked) · DESTINATION: Mercury — Kabulonga
///   1. 10:05 AM · 14 Reedbuck Rd (Beauty Hub) — 2 parcels ...
///
/// Owner directives (2026-11-17) built into this screen:
///  • Pull-to-refresh + a 20s auto-sync poll; the queue is the rider's
///    FIRST tab (AppShell), highly visible, never lost between cards.
///  • The "How did the parcel move on?" sheet is SEQUENTIAL: steps tick ✓
///    as they are filed and only the next step stays open. The first leg
///    ends at the DEPOT (sender → depot); only last-mile/collection jobs
///    continue to the recipient's door with the recipient's 4-digit code.
///  • Pickup: the SENDER holds the 4-digit code (booking SMS) and the rider
///    photographs EVERY parcel exactly once — one capture per parcel, no
///    repeats. The server locks the pickup evidence on first file.
///  • Arrival: GPS auto-marks "ARRIVED" within ~80 m of a stop (even when
///    the map itself is off), and a rider tap marks it too. Slot cards then
///    flip navigation from the sender to the DEPOT.
///  • Live ticking: slot elapsed time and stop ETAs recompute every second.
class RiderQueueScreen extends StatefulWidget {
  const RiderQueueScreen({super.key, this.phone});

  final String? phone;

  @override
  State<RiderQueueScreen> createState() => _RiderQueueScreenState();
}

class _RiderQueueScreenState extends State<RiderQueueScreen> with WidgetsBindingObserver {
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _busyRef;
  Timer? _pollTimer;

  // LIVE ARRIVAL WATCH (owner directive 2026-11-17): a GPS position stream
  // marks stops ARRIVED within [_arrivalMetres]; a manual tap marks too.
  static const double _arrivalMetres = 80;
  final Set<String> _arrivedRefs = {};
  StreamSubscription<Position>? _posSub;
  Position? _riderPos;

  // AUTOMATIC LIVE-LOCATION SHARING (owner directive 2026-11-17: "make rider
  // share live location automatically to seller/sender"): while the rider is
  // on duty (the queue has batches), the GPS stream feeds POST /rider/ping —
  // throttled to one ping per ≥20 s AND ≥30 m of real movement — keeping the
  // server's riders.last_lat/last_lng fresh so the SENDER's tracking map
  // (GET /jobs/:ref/live, polled every 12 s) shows the rider pin with no
  // action from the rider. Honours the Team-screen share toggle; pings are
  // fire-and-forget (a failed one simply waits for the next GPS fix).
  DateTime? _lastPingAt;
  double? _lastPingLat;
  double? _lastPingLng;

  // 1-second ticker: slot elapsed + stop ETAs tick live once the rider
  // marks arrived/picked (owner: "under each slot time there should be
  // ticking automatically").
  Timer? _tickTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AnalyticsService.instance.trackScreenView('rider_queue');
    _load();
    // Keep the queue synced with new assignments without a manual refresh.
    _pollTimer = Timer.periodic(const Duration(seconds: 20), (_) => _load());
    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final batches = ((_data?['batches'] as List?) ?? const []);
      if (batches.isNotEmpty) setState(() {});
    });
    _startArrivalWatch();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    _tickTimer?.cancel();
    _posSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) _load();
  }

  Future<void> _load() async {
    final data = await DropOffApi.riderQueue(widget.phone);
    if (!mounted) return;
    setState(() { _data = data; _loading = false; });
  }

  /* ----------------------- live clock + arrival GPS ----------------------- */

  /// The server runs on CAT (UTC+2) — slot times and targets are CAT.
  DateTime get _nowCat => DateTime.now().toUtc().add(const Duration(hours: 2));

  /// '14:05' → '2:05 PM'. All slot-card times are 12-hour (owner audit
  /// 2026-11-17: the footer range looked "off" partly because 24h times).
  String _hhmm12(String hm) {
    final m = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(hm.trim());
    if (m == null) return hm;
    final h = int.parse(m.group(1)!);
    final min = m.group(2)!;
    final am = h < 12;
    var h12 = h % 12;
    if (h12 == 0) h12 = 12;
    return '$h12:$min ${am ? 'AM' : 'PM'}';
  }

  /// Minutes elapsed since the slot's start (CAT), or null when the slot
  /// has not started today. Negative ⇒ starts in that many minutes.
  int? _slotElapsedMin(Map<String, dynamic> b) {
    final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch('${b['slot'] ?? ''}'.trim());
    if (m == null) return null; // tomorrow's roll-up slot — not ticking yet
    final startMin = int.parse(m.group(1)!) * 60 + int.parse(m.group(2)!);
    final now = _nowCat;
    return now.hour * 60 + now.minute - startMin;
  }

  /// True once the parcel is collected or beyond — slot cards flip from
  /// "navigate to sender" to "navigate to depot" from this point.
  bool _picked(String st) =>
      ['picked_up', 'at_depot', 'departed', 'arrived', 'delivered', 'ready_for_collection'].contains(st);

  Future<void> _startArrivalWatch() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) return;
      if (!await Geolocator.isLocationServiceEnabled()) return;
      _posSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 12),
      ).listen(_onPosition);
    } catch (_) {
      // Arrival detection is a bonus — the rider can always tap arrived.
    }
  }

  void _onPosition(Position pos) {
    _riderPos = pos;
    _maybeAutoPing(pos);
    final batches = ((_data?['batches'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final newly = <String>[];
    for (final b in batches) {
      for (final s in ((b['stops'] as List?) ?? const []).cast<Map<String, dynamic>>()) {
        final ref = '${s['ref']}';
        if (_arrivedRefs.contains(ref) || _picked('${s['status'] ?? ''}')) continue;
        final lat = (s['lat'] as num?)?.toDouble();
        final lng = (s['lng'] as num?)?.toDouble();
        if (lat == null || lng == null) continue;
        if (Geolocator.distanceBetween(pos.latitude, pos.longitude, lat, lng) <= _arrivalMetres) {
          newly.add(ref);
        }
      }
    }
    if (newly.isEmpty || !mounted) return;
    setState(() => _arrivedRefs.addAll(newly));
    _snack(newly.length == 1
        ? '${newly.first} — ARRIVED at the sender ✓ File the pickup.'
        : 'ARRIVED at ${newly.length} stops ✓ File the pickups.');
  }

  /// One throttled auto-ping per GPS fix — see the field comment above.
  void _maybeAutoPing(Position pos) {
    if (!mounted) return;
    final store = AppScope.of(context);
    if (!store.linked || store.linkedPhone == null || !store.shareLocationOn) return;
    final batches = ((_data?['batches'] as List?) ?? const []);
    if (batches.isEmpty) return; // off duty — nothing to share
    final now = DateTime.now();
    if (_lastPingAt != null && now.difference(_lastPingAt!).inSeconds < 20) return;
    if (_lastPingLat != null && _lastPingLng != null &&
        Geolocator.distanceBetween(_lastPingLat!, _lastPingLng!, pos.latitude, pos.longitude) < 30) {
      return;
    }
    _lastPingAt = now;
    _lastPingLat = pos.latitude;
    _lastPingLng = pos.longitude;
    // Any collected stop still moving → on_route; otherwise available.
    final onRoute = batches.any((b) => (((b as Map<String, dynamic>)['stops'] as List?) ?? const [])
        .any((s) => _picked('${(s as Map<String, dynamic>)['status'] ?? ''}')));
    unawaited(DropOffApi.riderPing(
      phone: store.linkedPhone!,
      lat: pos.latitude,
      lng: pos.longitude,
      status: onRoute ? 'on_route' : 'available',
    ));
  }

  /* ------------------------ stop advancement (proof kit) -------------------- */
  // Anti-false-parcel handover: pickups confirm the SENDER's 4-digit code and
  // photograph every parcel exactly once; depot drops need the depot's own
  // receipt photos; door deliveries (last-mile/collection jobs only) require
  // the recipient's 4-digit DropOff code.

  /// CAMERA-ONLY capture for pickup parcel photos (owner directive
  /// 2026-11-17: "no repeat capture" — a gallery pick could re-file an old
  /// photo, so collection evidence is captured live, one photo per parcel).
  Future<String?> _captureParcelPhoto() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.camera, maxWidth: 1600, imageQuality: 82);
    if (picked == null) return null;
    final bytes = await picked.readAsBytes();
    final res = await DropOffApi.uploadImage(bytes, picked.name.isNotEmpty ? picked.name : 'pickup.jpg', kind: 'kyc');
    if (!mounted) return null;
    if (!res.ok) {
      AppToast.show(context, 'Photo upload failed (${res.error ?? 'network'}) — try the capture again.');
      return null;
    }
    return '${res.body['url'] ?? ''}';
  }

  Future<String?> _pickPodPhoto() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.photo_camera), title: const Text('Take photo with camera'), onTap: () => Navigator.pop(ctx, ImageSource.camera)),
          ListTile(leading: const Icon(Icons.photo_library), title: const Text('Pick from gallery'), onTap: () => Navigator.pop(ctx, ImageSource.gallery)),
        ]),
      ),
    );
    if (source == null) return null;
    final picked = await ImagePicker().pickImage(source: source, maxWidth: 1600, imageQuality: 82);
    if (picked == null) return null;
    final bytes = await picked.readAsBytes();
    final res = await DropOffApi.uploadImage(bytes, picked.name.isNotEmpty ? picked.name : 'proof.jpg', kind: 'kyc');
    if (!mounted) return null;
    if (!res.ok) {
      AppToast.show(context, 'Proof photo upload failed (${res.error ?? 'network'}) — moving on without it.');
      return null;
    }
    return '${res.body['url'] ?? ''}';
  }

  Future<void> _snack(String msg) async {
    if (!mounted) return;
    AppToast.show(context, msg);
  }

  /// One-tap navigation. BEFORE pickup → the sender's stop; AFTER pickup →
  /// the DEPOT (owner: once collected, the cards flip from sender navigation
  /// to depot navigation). Pinned bookings open the in-app navigator; a stop
  /// without any pin is GEOCODED in-app (hard-locked to Lusaka) so the rider
  /// still gets DropOff turn-by-turn — the device's maps handler is a silent
  /// last resort only, never a visible choice (no third-party names in this
  /// UI).
  Future<void> _navigateToStop(Map<String, dynamic> s) async {
    final picked = _picked('${s['status'] ?? ''}');
    final lat = picked
        ? (s['depot_lat'] as num?)?.toDouble()
        : (s['pickup_lat'] as num?)?.toDouble() ?? (s['lat'] as num?)?.toDouble();
    final lng = picked
        ? (s['depot_lng'] as num?)?.toDouble()
        : (s['pickup_lng'] as num?)?.toDouble() ?? (s['lng'] as num?)?.toDouble();
    final addr = '${s['address'] ?? ''}'.trim();
    final label = picked
        ? 'Depot — ${s['courier'] ?? 'DropOff'}'
        : '${s['ref'] ?? 'Stop'} — $addr'.trim();
    // Whole-job context on the map (owner 2026-11-18 "fix the rider map just
    // like the sender map tracking"): heading to the sender shows the depot
    // pin too, heading to the depot shows the sender's stop too.
    final otherLat = picked
        ? (s['pickup_lat'] as num?)?.toDouble() ?? (s['lat'] as num?)?.toDouble()
        : (s['depot_lat'] as num?)?.toDouble();
    final otherLng = picked
        ? (s['pickup_lng'] as num?)?.toDouble() ?? (s['lng'] as num?)?.toDouble()
        : (s['depot_lng'] as num?)?.toDouble();
    if (lat != null && lng != null) {
      Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => InAppNavigatorScreen(
          destLat: lat,
          destLng: lng,
          label: label,
          destIsDepot: picked,
          otherLat: otherLat,
          otherLng: otherLng,
          otherIsDepot: !picked,
        ),
      ));
      return;
    }
    // No pin on the booking — geocode the typed address OURSELVES and keep
    // the rider inside the DropOff navigator.
    final query = picked
        ? '${s['courier'] ?? ''} depot ${s['from_city'] ?? ''}'.trim()
        : '$addr${'${s['from_city'] ?? ''}'.trim().isNotEmpty ? ', ${s['from_city']}' : ''}'.trim();
    if (query.isEmpty) {
      _snack('This stop has no pin or address yet — refresh, or ask ops.');
      return;
    }
    _snack('Finding "$query"…');
    final hits = await MapServices.search(query);
    if (!mounted) return;
    if (hits.isNotEmpty) {
      final hit = hits.first;
      Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => InAppNavigatorScreen(
          destLat: hit.point.latitude,
          destLng: hit.point.longitude,
          label: label,
          destIsDepot: picked,
          otherLat: otherLat,
          otherLng: otherLng,
          otherIsDepot: !picked,
        ),
      ));
      return;
    }
    // Geocode found nothing — silent last resort: the device's default maps
    // handler. No button label, no brand name; just get the rider there.
    await openInApp('https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(query)}');
  }

  Widget _navBtn(String label, String tooltip, Color bg, IconData icon, VoidCallback onTap) {
    return Tooltip(
      message: tooltip,
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          backgroundColor: bg,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          shape: const StadiumBorder(),
          minimumSize: Size.zero,
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 15, color: Colors.white),
          const SizedBox(width: 5),
          Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 11)),
        ]),
      ),
    );
  }

  /* ---------------------- the sequential move sheet ----------------------- */

  Future<void> _advanceStop(Map<String, dynamic> s) async {
    final String ref = '${s['ref']}';
    if (_busyRef != null) return;
    final lastMile = (s['last_mile'] as num?)?.toInt() ?? 0;
    final parcels = (s['parcels'] as num?)?.toInt() ?? 1;
    // Live status — declared OUTSIDE the sheet builder so each filed step
    // survives setSheet rebuilds: the sheet auto-marks the done step and
    // leaves only the next one open (owner directive 2026-11-17).
    var st = '${s['status'] ?? 'assigned'}';
    // Manual arrival tap (owner: "auto turned OR tapped by rider — arrived at
    // pick up"): opening this stop's sheet marks the rider arrived.
    if (!_picked(st) && !_arrivedRefs.contains(ref) && mounted) {
      setState(() => _arrivedRefs.add(ref));
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: StatefulBuilder(
          builder: (ctx, setSheet) {
            final picked = _picked(st);
            final dropped = st == 'delivered';
            Widget step({
              required bool done,
              required bool unlocked,
              required IconData icon,
              required String title,
              required String subtitle,
              required VoidCallback onTap,
            }) {
              final active = !done && unlocked && _busyRef == null;
              return ListTile(
                enabled: active,
                onTap: active ? onTap : null,
                leading: Icon(done ? Icons.check_circle : icon,
                    color: done ? AppColors.forest : active ? AppColors.forest : AppColors.muted),
                title: Text(title, style: TextStyle(
                    fontWeight: FontWeight.w800, fontSize: 14,
                    color: done || active ? AppColors.ink : AppColors.muted)),
                subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
                trailing: _busyRef == ref
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : done
                        ? const Icon(Icons.lock, size: 15, color: AppColors.muted)
                        : null,
              );
            }
            return Column(mainAxisSize: MainAxisSize.min, children: [
              const Padding(padding: EdgeInsets.all(14), child: Text('How did the parcel move on?',
                style: AppType.subhead)),
              const Padding(padding: EdgeInsets.symmetric(horizontal: 14), child: Text(
                'Steps tick off as you file them — only the next one stays open.',
                style: TextStyle(fontSize: 11.5, color: AppColors.muted))),
              const SizedBox(height: 6),
              step(
                done: picked,
                unlocked: true,
                icon: Icons.local_shipping_outlined,
                title: 'Picked up from the sender',
                subtitle: picked ? 'Filed ✓' : 'Sender\'s 4-digit code + one photo per parcel ($parcels)',
                onTap: () async {
                  final res = await _pickUpFromSender(ref, parcels);
                  if (!mounted) return;
                  setState(() => _busyRef = null);
                  if (res != null && res.ok) {
                    setSheet(() => st = 'picked_up');
                    _load();
                    if (ctx.mounted) await _autoCloseWhenDone(ctx, true);
                  }
                },
              ),
              // FIRST LEG (owner directive 2026-11-17): sender → depot. The
              // depot step only exists for first-leg jobs; the sheet never
              // ends at the recipient for them.
              if (lastMile == 0)
                step(
                  done: dropped,
                  unlocked: picked,
                  icon: Icons.inventory_2_outlined,
                  title: 'Dropped at the depot branch',
                  subtitle: dropped ? 'Filed ✓' : !picked ? 'Locked — pick up first' : 'Parcel photos + every depot receipt, exact amounts',
                  onTap: () async {
                    final res = await _depotDropWithReceipt(ref);
                    if (!mounted) return;
                    setState(() => _busyRef = null);
                    if (res != null && res.ok) {
                      setSheet(() => st = 'delivered');
                      _load();
                      if (ctx.mounted) await _autoCloseWhenDone(ctx, true);
                    }
                  },
                ),
              // LAST MILE (collection/door jobs only): the RECIPIENT holds
              // the 4-digit code for this handover.
              if (lastMile == 1)
                step(
                  done: dropped,
                  unlocked: picked,
                  icon: Icons.home_outlined,
                  title: 'Handed to the recipient (door)',
                  subtitle: dropped ? 'Filed ✓' : !picked ? 'Locked — pick up first' : 'Recipient\'s 4-digit DropOff code + handover photo',
                  onTap: () async {
                    final res = await _deliverToDoor(ref);
                    if (!mounted) return;
                    setState(() => _busyRef = null);
                    if (res != null && res.ok) {
                      setSheet(() => st = 'delivered');
                      _load();
                      if (ctx.mounted) await _autoCloseWhenDone(ctx, true);
                    }
                  },
                ),
              if (lastMile == 0)
                const Padding(padding: EdgeInsets.fromLTRB(14, 2, 14, 0), child: Text(
                  'This run ends at the depot — the courier carries the parcel the rest of the way.',
                  style: TextStyle(fontSize: 11, color: AppColors.muted, height: 1.35))),
              ListTile(
                leading: const Icon(Icons.close),
                title: const Text('Not yet — go back'),
                onTap: () => Navigator.pop(ctx),
              ),
            ]);
          },
        ),
      ),
    );
  }

  /// When every step is filed, the sheet closes itself after a beat so the
  /// refreshed queue is immediately visible.
  Future<void> _autoCloseWhenDone(BuildContext sheetCtx, bool done) async {
    if (!done) return;
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (sheetCtx.mounted) Navigator.of(sheetCtx).pop();
  }

  /// PICKUP (owner directive 2026-11-17): the SENDER holds the 4-digit code
  /// from the booking SMS and the rider photographs EVERY parcel exactly
  /// once — exactly N captures for N parcels, no repeats. The server locks
  /// the pickup evidence on first file; further changes go through ops.
  Future<ApiResponse?> _pickUpFromSender(String ref, int parcels) async {
    if (_busyRef != null) return null;
    final otpCtrl = TextEditingController();
    final photos = <String>[];
    String? inlineError;
    bool submitting = false;
    final res = await showDialog<ApiResponse>(
      context: context,
      barrierDismissible: false,
      builder: (dctx) => StatefulBuilder(
        builder: (dctx, setDialog) => AlertDialog(
          title: Text('Pickup — $ref', style: AppType.subhead),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Collect from the sender. Ask them for the 4-digit PICKUP code from their booking SMS — never a code nobody showed you.',
                style: TextStyle(fontSize: 12.5, height: 1.4, color: AppColors.ink)),
              const SizedBox(height: 12),
              TextField(
                controller: otpCtrl,
                keyboardType: TextInputType.number,
                maxLength: 4,
                autofocus: true,
                decoration: const InputDecoration(
                  counterText: '',
                  labelText: '4-digit pickup code (from the SENDER)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Text('PARCEL PHOTOS — capture each of the $parcels parcel${parcels == 1 ? '' : 's'} ONCE',
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 11, color: AppColors.muted)),
              const SizedBox(height: 6),
              if (photos.isNotEmpty)
                SizedBox(
                  height: 84,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: photos.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    // NO remove button — no repeat captures; a mistake means
                    // cancel and start the pickup file again.
                    itemBuilder: (_, i) => ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: AuthedImage(photos[i], fit: BoxFit.cover, width: 84, height: 84),
                    ),
                  ),
                ),
              if (photos.length < parcels)
                TextButton.icon(
                  icon: const Icon(Icons.camera_alt_outlined, size: 18),
                  label: Text('Capture parcel ${photos.length + 1} of $parcels (camera)',
                      style: const TextStyle(fontSize: 12.5)),
                  onPressed: submitting ? null : () async {
                    final url = await _captureParcelPhoto();
                    if (url != null) setDialog(() { photos.add(url); inlineError = null; });
                  },
                )
              else
                Row(children: [
                  const Icon(Icons.check_circle, size: 16, color: AppColors.forest),
                  const SizedBox(width: 6),
                  Expanded(child: Text('All $parcels captured — locked (one photo per parcel).',
                      style: const TextStyle(fontSize: 12, color: AppColors.forest, fontWeight: FontWeight.w700))),
                ]),
              if (inlineError != null) ...[
                const SizedBox(height: 8),
                Text(inlineError!, style: const TextStyle(fontSize: 12, color: Color(0xFFB3261E), height: 1.35)),
              ],
            ]),
          ),
          actions: [
            TextButton(onPressed: submitting ? null : () => Navigator.pop(dctx, null), child: const Text('Cancel')),
            FilledButton(
              onPressed: submitting ? null : () async {
                final code = otpCtrl.text.trim();
                if (code.length != 4) {
                  setDialog(() => inlineError = 'Enter the sender\'s 4-digit pickup code.');
                  return;
                }
                if (photos.length < parcels) {
                  setDialog(() => inlineError = 'Capture each parcel once — ${parcels - photos.length} more photo${parcels - photos.length == 1 ? '' : 's'} to take.');
                  return;
                }
                submitting = true;
                setDialog(() {});
                final r = await DropOffApi.jobEvent(
                  jobRef: ref, status: 'picked_up', otp: code,
                  photoUrl: photos.first, stage: 'pickup',
                  parcelPhotos: photos,
                  lat: _riderPos?.latitude, lng: _riderPos?.longitude,
                );
                if (!dctx.mounted) return;
                if (r.ok) {
                  Navigator.pop(dctx, r);
                  return;
                }
                submitting = false;
                final err = r.error ?? '';
                final detail = (r.body['detail'] as String?) ?? '';
                // Inline errors keep the dialog open so the rider can fix
                // the code; evidence-lock errors explain that the file is
                // frozen and ops handles changes.
                setDialog(() => inlineError = switch (err) {
                  'otp_required' => 'Code rejected. ${detail.isEmpty ? 'The code is in the sender\'s booking SMS.' : detail}',
                  'otp_locked' => 'Too many wrong codes — DropOff support has been notified.',
                  'photo_locked' => 'Pickup photo already on file for $ref — the evidence is locked. Ask ops to correct a genuine mis-submission.',
                  _ => 'Could not file the pickup ($err).',
                });
              },
              child: const Text('Confirm pickup'),
            ),
          ],
        ),
      ),
    );
    if (res == null) return null;
    if (res.ok) {
      await _snack('$ref ✓ picked up from the sender');
      AnalyticsService.instance.track(feature: 'rider', action: 'picked_up', context: 'sender_stop');
      _load();
    }
    return res;
  }

  /// Depot drop with the counter-receipt kit (owner directive 2026-11-12):
  /// photograph EVERY parcel in the batch, and file EVERY depot receipt the
  /// depot wrote — each photographed, each with the EXACT amount written on
  /// it. A submitted receipt is a single, exact, photographed document, never
  /// a rider-computed sum; the SERVER totals the receipts. The rider fronts
  /// the fare with their own money; DropOff reimburses it fee-free the moment
  /// the sender pays.
  Future<ApiResponse?> _depotDropWithReceipt(String ref) async {
    if (_busyRef != null) return null;
    if (!mounted) return null;
    final parcelPhotos = <String>[]; // batch: one or more parcel photos
    final branchCtrl = TextEditingController();
    // Each depot receipt: its own amount field + its own photo. A batch may
    // be split across receipts by the depot — file them all, one by one.
    final receipts = <_ReceiptEntry>[];
    // The SELLER's booking photo travels with the stop (owner directive
    // 2026-11-17): the rider sees the parcel they are collecting next to the
    // one they just photographed, so swaps are caught at the drop, not at
    // delivery. Riders are authorized on /jobs/:ref/evidence.
    final evData = await DropOffApi.jobEvidence(ref);
    final evMap = (evData?['evidence'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
    if (!mounted) return null;
    final sellerPhoto = '${evMap['booking_photo'] ?? ''}';
    final res = await showDialog<ApiResponse>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: Text('Depot drop — $ref', style: AppType.subhead),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Row(children: [
                Expanded(child: Text('Photograph every parcel, photograph every depot receipt exactly as written.', style: TextStyle(fontSize: 12.5, height: 1.4, color: AppColors.ink))),
                HelpIconButton(topic: HelpTopic.depotReceipts),
              ]),
              const SizedBox(height: 12),
              // ── Sender's booking photo — compare before you drop ──
              if (sellerPhoto.isNotEmpty) ...[
                const Text('SELLER PHOTO (FROM BOOKING)', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11, color: AppColors.muted)),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: AuthedImage(sellerPhoto, fit: BoxFit.cover, width: double.infinity, height: 140),
                ),
                const SizedBox(height: 4),
                const Text('Compare this with the parcel you photograph below — they must be the same parcel.',
                    style: TextStyle(fontSize: 10.5, color: AppColors.muted, height: 1.35)),
                const SizedBox(height: 10),
              ],
              // ── Parcel photos (one or more) ──
              Text('PARCEL PHOTOS (${parcelPhotos.length})', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 11, color: AppColors.muted)),
              const SizedBox(height: 4),
              if (parcelPhotos.isNotEmpty)
                SizedBox(
                  height: 96,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: parcelPhotos.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (_, i) => Stack(children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: AuthedImage(parcelPhotos[i], fit: BoxFit.cover, width: 96, height: 96),
                      ),
                      Positioned(
                        top: 2,
                        right: 2,
                        child: InkWell(
                          onTap: () => setDialog(() => parcelPhotos.removeAt(i)),
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                            child: const Icon(Icons.close, size: 12, color: Colors.white),
                          ),
                        ),
                      ),
                    ]),
                  ),
                ),
              TextButton.icon(
                icon: const Icon(Icons.camera_alt_outlined, size: 18),
                label: Text(parcelPhotos.isEmpty ? 'Add parcel photo (required)' : 'Add another parcel photo',
                    style: const TextStyle(fontSize: 12.5)),
                onPressed: () async {
                  final url = await _pickPodPhoto();
                  if (url != null) setDialog(() => parcelPhotos.add(url));
                },
              ),
              const SizedBox(height: 12),
              const Text('DEPOT BRANCH', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11, color: AppColors.muted)),
              const SizedBox(height: 4),
              TextField(
                controller: branchCtrl,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  hintText: 'e.g. Platinum — Kabwata',
                  prefixIcon: Icon(Icons.storefront_outlined),
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 4),
              const Text('Optional — the branch the parcel landed at. Route stays "to Platinum" until this is filled.',
                  style: TextStyle(fontSize: 10.5, color: AppColors.muted, height: 1.35)),
              const Divider(height: 20),
              // ── Depot receipts (one or more, each exact) ──
              Text('DEPOT RECEIPTS (${receipts.length})', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 11, color: AppColors.muted)),
              const SizedBox(height: 4),
              for (var i = 0; i < receipts.length; i++) _receiptEntryTile(setDialog, receipts, i),
              TextButton.icon(
                icon: const Icon(Icons.receipt_long_outlined, size: 18),
                label: Text(receipts.isEmpty ? 'Add depot receipt (required)' : 'Add another depot receipt (if the depot split the batch)',
                    style: const TextStyle(fontSize: 12.5)),
                onPressed: () => setDialog(() => receipts.add(_ReceiptEntry())),
              ),
              const Row(children: [
                Expanded(child: Text('Photos stay masked until the sender pays — then they reveal and the reimbursement triggers.', style: AppType.caption)),
                HelpIconButton(topic: HelpTopic.depotReceipts),
              ]),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, null), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                if (parcelPhotos.isEmpty) {
                  _snack('At least one parcel photo is required.');
                  return;
                }
                if (receipts.isEmpty) {
                  _snack('Add the depot receipt — photo + the exact amount written on it.');
                  return;
                }
                for (var i = 0; i < receipts.length; i++) {
                  final r = receipts[i];
                  if (r.url == null) {
                    _snack('Receipt ${i + 1} needs its photo.');
                    return;
                  }
                  final amt = double.tryParse(r.amountCtrl.text.replaceAll(RegExp(r'[^0-9.]'), ''));
                  if (amt == null || amt <= 0) {
                    _snack('Receipt ${i + 1}: type the exact amount written on it.');
                    return;
                  }
                }
                final branch = branchCtrl.text.trim();
                final r = await DropOffApi.jobEvent(
                  jobRef: ref, status: 'delivered',
                  photoUrl: parcelPhotos.first, stage: 'delivery',
                  parcelPhotos: parcelPhotos,
                  branch: branch.isEmpty ? null : branch,
                  receipts: [
                    for (final e in receipts)
                      {
                        'amount_zmw': double.parse(e.amountCtrl.text.replaceAll(RegExp(r'[^0-9.]'), '')),
                        'url': e.url,
                      }
                  ],
                );
                if (!ctx.mounted) return;
                Navigator.pop(ctx, r);
              },
              child: const Text('Submit drop'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return null;
    if (res == null) return null; // cancelled
    if (res.ok) {
      setState(() => _busyRef = null);
      await _snack('$ref ✓ ${'Dropped at the depot branch'}');
      AnalyticsService.instance.track(feature: 'rider', action: 'delivered', context: 'depot_stop');
      // Best-effort: compare seller's booking photo vs this drop photo.
      final chk = await DropOffApi.parcelCheck(ref);
      if (!mounted) return res;
      if (chk.ok) {
        final verdict = chk.body['same_parcel'] ?? 'uncertain';
        final flagged = chk.body['flagged'] == true;
        await _snack(flagged
            ? '$ref parcel check: possible mismatch — ops flagged for review'
            : '$ref parcel check: $verdict');
      } else {
        // AI check is best-effort; a slow/unavailable vision model must not
        // confuse a rider who just filed the drop correctly.
        await _snack('$ref drop filed. Parcel check skipped (${chk.error ?? 'unavailable'}) — ops will eyeball the photos.');
      }
      _load();
      return res;
    }
    final err = res.error ?? '';
    final detail = (res.body['detail'] as String?) ?? '';
    setState(() => _busyRef = null);
    await _snack(switch (err) {
      'receipt_required' => detail.isEmpty ? 'Every depot receipt needs its photo and exact amount.' : detail,
      'photo_required' => detail.isEmpty ? 'A parcel photo is required.' : detail,
      'two_photos_required' => detail.isEmpty ? 'Parcel photos and receipt photos must be separate images.' : detail,
      _ => 'Could not submit the drop ($err).',
    });
    return res;
  }

  /// One filed depot receipt inside the drop dialog: its own photo + its own
  /// exact amount (never summed by the rider).
  Widget _receiptEntryTile(void Function(void Function()) setDialog, List<_ReceiptEntry> receipts, int i) {
    final e = receipts[i];
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppColors.amber.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.amber.withValues(alpha: 0.4)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('Receipt ${i + 1}${e.url != null ? ' — photo attached ✓' : ''}',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12))),
          IconButton(
            icon: const Icon(Icons.close, size: 16),
            tooltip: 'Remove receipt',
            onPressed: () => setDialog(() => receipts.removeAt(i)),
          ),
        ]),
        TextField(
          controller: e.amountCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Exact amount written on THIS receipt (K)',
            prefixText: 'K ',
            isDense: true,
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 6),
        TextButton.icon(
          icon: Icon(e.url == null ? Icons.camera_alt_outlined : Icons.check_circle, size: 16,
              color: e.url == null ? null : AppColors.forest),
          label: Text(e.url == null ? 'Photo of THIS receipt (required)' : 'Receipt photo attached ✓',
              style: const TextStyle(fontSize: 12)),
          onPressed: () async {
            final url = await _pickPodPhoto();
            if (url != null) setDialog(() => e.url = url);
          },
        ),
      ]),
    );
  }

  /// Door delivery: the server enforces the recipient's 4-digit handover code.
  Future<ApiResponse?> _deliverToDoor(String ref) async {
    if (_busyRef != null) return null;
    if (!mounted) return null;
    final otpCtrl = TextEditingController();
    String? podUrl;
    final res = await showDialog<ApiResponse>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: Text('Handover — $ref', style: AppType.subhead),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Ask the recipient for their 4-digit DropOff code. Never enter a code the parcel owner hasn\'t shown you.',
              style: TextStyle(fontSize: 12.5, height: 1.4, color: AppColors.ink)),
            const SizedBox(height: 12),
            TextField(
              controller: otpCtrl,
              keyboardType: TextInputType.number,
              maxLength: 4,
              autofocus: true,
              decoration: const InputDecoration(
                counterText: '',
                labelText: '4-digit DropOff code',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            // CAMERA-CAPTURE POLICY: the photo is required, not recommended —
            // a door delivery is marked by camera capture like a depot drop.
            TextButton.icon(
              icon: Icon(podUrl == null ? Icons.camera_alt_outlined : Icons.check_circle, size: 18),
              label: Text(podUrl == null ? 'Add proof photo (required)' : 'Proof photo attached ✓',
                style: const TextStyle(fontSize: 12.5)),
              onPressed: () async {
                setDialog(() => podUrl = null); // visual pending state
                final url = await _pickPodPhoto();
                setDialog(() => podUrl = url);
              },
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, null), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                final code = otpCtrl.text.trim();
                if (code.length < 4) {
                  _snack('Enter the recipient\'s 4-digit code.');
                  return;
                }
                if (podUrl == null) {
                  _snack('Attach the camera photo of the handover to confirm.');
                  return;
                }
                final r = await DropOffApi.jobEvent(
                  jobRef: ref, status: 'delivered', otp: code,
                  photoUrl: podUrl, stage: 'delivery');
                if (!ctx.mounted) return;
                Navigator.pop(ctx, r);
              },
              child: const Text('Confirm handover'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return null;
    if (res == null) return null; // cancelled
    if (res.ok) {
      await _snack('$ref — delivered and code-verified ✓');
      _load();
      return res;
    }
    // Server-side OTP errors map to rider-readable guidance.
    final err = res.error ?? '';
    final detail = (res.body['detail'] as String?) ?? '';
    await _snack(switch (err) {
      'otp_required' => 'Code rejected. ${detail.isEmpty ? 'Ask the recipient to re-check their SMS.' : detail}',
      'otp_locked' => 'Too many wrong codes — support has been notified.',
      _ => 'Could not mark delivered ($err).',
    });
    return res;
  }

  @override
  Widget build(BuildContext context) {
    // Fleet view is staff-only (Team tab + this gate). The server also
    // validates the phone belongs to an active rider — a seller whose phone
    // is not a rider row gets an empty queue, never someone else's stops.
    final store = AppScope.of(context);
    if (!store.linked) {
      return Scaffold(
        appBar: AppBar(title: const Text('Task queue', style: TextStyle(fontWeight: FontWeight.w900))),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.lock_outline, size: 44, color: AppColors.muted),
              const SizedBox(height: 16),
              const Text('Sign in for the task queue', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900), textAlign: TextAlign.center),
              const SizedBox(height: 8),
              const Text('Link this device to a rider account to see slot-batched pickup runs.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted, height: 1.45)),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AccountScreen())),
                icon: const Icon(Icons.person_add_alt_1),
                label: const Text('Sign in / Create account'),
              ),
            ]),
          ),
        ),
      );
    }
    final batches = ((_data?['batches'] as List?) ?? const []).cast<Map<String, dynamic>>();
    return Scaffold(
      // ACCOUNT ENTRY (owner question 2026-11-17: Tasks REPLACED Home for
      // riders, and the account button lived on Home): a person icon on the
      // rider's first screen opens the Account screen — profile, plans and
      // the sign-out path live there.
      appBar: AppBar(
        title: const Text('Task queue', style: TextStyle(fontWeight: FontWeight.w900)),
        actions: [
          IconButton(
            tooltip: 'Account & sign out',
            icon: Icon(store.email != null ? Icons.account_circle : Icons.account_circle_outlined),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AccountScreen())),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _loading ? null : _load,
        icon: const Icon(Icons.refresh),
        label: const Text('Refresh'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : batches.isEmpty
              // Pull-to-refresh works on the empty state too — new assignments
              // drop in without leaving the screen.
              ? RefreshIndicator(
                  onRefresh: _load,
                  child: LayoutBuilder(builder: (ctx, cons) => SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: SizedBox(
                      height: cons.maxHeight,
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                            const Icon(Icons.assignment_turned_in_outlined, size: 46, color: AppColors.muted),
                            const SizedBox(height: 14),
                            const Text('No rides on your queue yet',
                                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900), textAlign: TextAlign.center),
                            const SizedBox(height: 8),
                            const Text(
                              'Slot batches land here the moment ops assigns you a run — you do not have to book anything. Pull down or tap refresh to sync.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: AppColors.muted, height: 1.5),
                            ),
                            const SizedBox(height: 20),
                            OutlinedButton.icon(
                              onPressed: _load,
                              icon: const Icon(Icons.refresh),
                              label: const Text('Check for new rides'),
                            ),
                          ]),
                        ),
                      ),
                    ),
                  )),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 90),
                    itemCount: batches.length,
                    itemBuilder: (context, i) => _batchCard(batches[i]),
                  ),
                ),
    );
  }

  Widget _batchCard(Map<String, dynamic> b) {
    final dest = b['destination'] as Map<String, dynamic>?;
    final stops = ((b['stops'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final pickedCount = stops.where((s) => _picked('${s['status'] ?? ''}')).length;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            color: AppColors.forest,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${b['label']}', style: const TextStyle(color: AppColors.amber, fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 0.8)),
              const SizedBox(height: 5),
              Text('TOTAL PARCELS TO PICK UP: ${b['total_parcels']}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
              const SizedBox(height: 2),
              Text('STOPS: $pickedCount of ${b['total_stops']} picked', style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w700)),
              if (dest != null)
                Text('DESTINATION: ${dest['courier']} — ${dest['branch']}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
              const SizedBox(height: 6),
              // LIVE slot window — ticks every second once the slot starts.
              Row(children: [
                const Icon(Icons.schedule, size: 13, color: AppColors.amber),
                const SizedBox(width: 6),
                Expanded(child: Text(_slotWindowLine(b),
                    style: const TextStyle(color: AppColors.amber, fontWeight: FontWeight.w800, fontSize: 12))),
              ]),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Builder(builder: (ctx) {
              // The rider's NEXT stop (first not-yet-picked) gets the amber
              // guide bar — the eye lands on the active task first.
              var activeSeen = false;
              final rows = <Widget>[];
              for (final s in stops) {
                final active = !activeSeen && !_picked('${s['status'] ?? ''}');
                if (active) activeSeen = true;
                rows.add(Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: _stopRow(s, isActive: active),
                ));
              }
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                ...rows,
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: AppColors.line.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(12)),
                  child: Row(children: [
                    const Icon(Icons.flag_outlined, size: 16, color: AppColors.forest),
                    const SizedBox(width: 8),
                    Expanded(child: Text(
                      _slotFooterLine(b),
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: AppColors.forest),
                    )),
                  ]),
                ),
              ]);
            }),
          ),
        ]),
      ),
    );
  }

  Widget _stopRow(Map<String, dynamic> s, {required bool isActive}) {
    final ref = '${s['ref']}';
    final picked = _picked('${s['status'] ?? ''}');
    final arrived = !picked && _arrivedRefs.contains(ref);
    final row = Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('${s['n']}.', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12.5, color: AppColors.forest)),
      const SizedBox(width: 8),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Flexible(child: Text('${_hhmm12('${s['time'] ?? ''}')} — ${s['address']}',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13,
                  color: picked ? AppColors.muted : AppColors.ink))),
          if (arrived) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: AppColors.amber.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(6)),
              child: const Text('ARRIVED ✓', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 9.5, color: AppColors.ink, letterSpacing: 0.4)),
            ),
          ],
        ]),
        const SizedBox(height: 2),
        Text(
          picked
              ? '✓ picked — ${'${s['last_mile'] ?? 0}' == '1' ? 'door handover next' : 'drop at the depot'}'
              : arrived
                  ? 'ARRIVED — tap ✓ to file the pickup'
                  : 'Seller: ${s['seller']} · ${s['parcels']} parcel${s['parcels'] == 1 ? '' : 's'} · ${'${s['status']}'.replaceAll('_', ' ')}',
          style: TextStyle(color: picked ? AppColors.forest : arrived ? AppColors.ink : AppColors.muted, fontSize: 11.5,
              fontWeight: picked || arrived ? FontWeight.w800 : FontWeight.w400),
        ),
      ])),
      if ('${s['seller_phone'] ?? ''}'.trim().isNotEmpty)
        IconButton(
          tooltip: 'Call the seller',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.phone_outlined, color: AppColors.forest),
          onPressed: () async {
            final number = '${s['seller_phone']}';
            final ok = await callPhoneNumber(number);
            if (!ok && mounted) _snack('Dialer not available here — call $number');
          },
        ),
      _navBtn(
        picked ? 'To depot' : 'Navigate',
        picked ? 'Navigate to the depot in the DropOff map' : 'Navigate to pickup in the DropOff map',
        picked ? const Color(0xFF0F5C40) : const Color(0xFF17855F),
        Icons.navigation_rounded,
        () => _navigateToStop(s),
      ),
      IconButton(
        tooltip: 'Update stop',
        visualDensity: VisualDensity.compact,
        icon: _busyRef == ref
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : Icon(picked ? Icons.check_circle : Icons.check_circle_outline, color: AppColors.forest),
        onPressed: () => _advanceStop(s),
      ),
    ]);
    // The rider's NEXT stop gets the amber guide bar — the eye lands there.
    if (!isActive) return row;
    return Container(
      decoration: const BoxDecoration(border: Border(left: BorderSide(width: 3, color: AppColors.amber))),
      padding: const EdgeInsets.only(left: 8),
      child: row,
    );
  }

  /// Header line: slot window range + live elapsed ("23 min in"), or the
  /// start countdown before the slot opens. Tomorrow's roll-up never ticks —
  /// its range already says "Tomorrow".
  String _slotWindowLine(Map<String, dynamic> b) {
    var range = '${b['range'] ?? ''}'.trim();
    if (range.isEmpty) range = _hhmm12('${b['slot'] ?? ''}');
    final elapsed = _slotElapsedMin(b);
    if (elapsed == null) return range;
    if (elapsed < 0) return '$range · starts in ${-elapsed} min';
    return '$range · $elapsed min in';
  }

  /// Footer line (owner audit 2026-11-17 — the old footer showed an unclear
  /// 24h target with no window): full CAT window + 12-hour depot target.
  String _slotFooterLine(Map<String, dynamic> b) {
    final range = '${b['range'] ?? ''}'.trim();
    final target = _hhmm12('${b['target_dropoff'] ?? ''}');
    final parts = <String>[
      if (range.isNotEmpty) 'Window $range',
      'Target depot drop-off: before $target',
      '· ~${b['minutes_on_road']} min on the road',
    ];
    return parts.join(' · ');
  }
}

/// One depot receipt filed by the rider in the drop dialog: its own photo and
/// its own exact amount - receipts are never summed by the rider; the server
/// totals the photographed documents.
class _ReceiptEntry {
  final TextEditingController amountCtrl = TextEditingController();
  String? url;
}
