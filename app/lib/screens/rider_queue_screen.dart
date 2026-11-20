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
import '../widgets/tutorial_sheet.dart';
import '../widgets/photo_preview.dart';
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
import 'waybill_screen.dart' show waybillDepotTitle;

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

class _RiderQueueScreenState extends State<RiderQueueScreen> with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  // Empty-state radar + pending-task pulse (owner 2026-11-18).
  late final AnimationController _radar = AnimationController(
    vsync: this, duration: const Duration(seconds: 2))..repeat();
  Map<String, dynamic>? _data;
  Map<String, dynamic>? _stats; // TODAY · LIVE card (rider daily stats)
  Map<String, dynamic>? _targets; // pace/bonus strip on the same card
  String _statsSynced = '--:--'; // visible proof the card is live
  bool _offline = false; // last-synced data shown while the network is down
  bool _loading = true;
  String? _busyRef;
  Timer? _pollTimer;

  // CLAIM BOARD — jobs auto-assign could not place (no online rider in range,
  // rider at a depot, everyone at capacity). Every verified rider sees the
  // same list; the first to claim owns it and it disappears for the others.
  List<Map<String, dynamic>> _available = const [];
  String? _claimingRef;

  // LIVE ARRIVAL WATCH (owner directive 2026-11-17): a GPS position stream
  // marks stops ARRIVED within [_arrivalMetres]; a manual tap marks too.
  static const double _arrivalMetres = 80;
  final Set<String> _arrivedRefs = {};
  StreamSubscription<Position>? _posSub;
  Position? _riderPos;

  // AUTOMATIC LIVE-LOCATION SHARING (owner directive 2026-11-17: "make rider
  // share live location automatically to seller/sender"): while the Team-screen
  // share toggle is on, the GPS stream feeds POST /rider/ping even with an
  // EMPTY queue — throttled to ≥20 s, and at least once a minute even when
  // stationary. This keeps riders.last_seen_at fresh so (a) the SENDER's
  // tracking map shows the rider pin and (b) auto-assign still considers the
  // rider for the FIRST order. Pings are fire-and-forget.
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
    _radar.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) _load();
  }

  Future<void> _load() async {
    final data = await DropOffApi.riderQueue(widget.phone);
    if (!mounted) return;
    setState(() {
      // OFFLINE: keep the last successful queue instead of blanking the screen.
      if (data != null) _data = data;
      _offline = data == null;
      _loading = false;
    });
    unawaited(_loadAvailable());
    // Stats ride the same 20 s poll — the card stays live with the queue.
    final stats = await DropOffApi.riderStats(widget.phone);
    if (!mounted) return;
    final s = stats?['stats'] as Map<String, dynamic>?;
    if (s != null) {
      // Sync the card to the EXACT queue on screen — the figures a rider sees
      // in the batches must equal the figures in the stats card. Server keeps
      // the fields the queue cannot know (delivered today, earnings).
      final qBatches = ((data?['batches'] as List?) ?? const []).cast<Map<String, dynamic>>();
      var stops = 0, pickedStops = 0, parcels = 0;
      for (final b in qBatches) {
        parcels += (b['total_parcels'] as num?)?.toInt() ?? 0;
        final ss = ((b['stops'] as List?) ?? const []);
        stops += ss.length;
        pickedStops += ss.where((x) => _picked('${(x as Map)['status'] ?? ''}')).length;
      }
      final merged = Map<String, dynamic>.from(s);
      if (qBatches.isNotEmpty) {
        merged['total'] = stops;
        merged['waiting'] = stops - pickedStops;
        merged['picked'] = pickedStops;
        merged['parcels'] = parcels;
      }
      setState(() {
        _stats = merged;
        final n = DateTime.now();
        _statsSynced = '${n.hour.toString().padLeft(2, '0')}:${n.minute.toString().padLeft(2, '0')}:${n.second.toString().padLeft(2, '0')}';
      });
    }
    final tdata = await DropOffApi.riderTargets();
    if (!mounted) return;
    final t = tdata?['targets'] as Map<String, dynamic>?;
    if (t != null) setState(() => _targets = t);
  }

  /// Leftovers after automated dispatch. Refreshed with the queue — a claim by
  /// another rider removes the card here too (server-side exclusivity).
  Future<void> _loadAvailable() async {
    final data = await DropOffApi.riderAvailable();
    if (!mounted) return;
    setState(() => _available = ((data?['jobs'] as List?) ?? const []).cast<Map<String, dynamic>>());
  }

  Future<void> _claim(Map<String, dynamic> job) async {
    final ref = '${job['ref'] ?? ''}';
    if (ref.isEmpty || _claimingRef != null) return;
    setState(() => _claimingRef = ref);
    final res = await DropOffApi.claimJob(ref);
    if (!mounted) return;
    setState(() => _claimingRef = null);
    if (res.ok) {
      AppToast.show(context, '$ref is yours — it is now on your queue.');
      await _load();
      return;
    }
    if (res.error == 'already_claimed') {
      AppToast.show(context, '$ref was just claimed by another rider — refreshing.');
      await _load();
      return;
    }
    if (res.error == 'at_capacity') {
      AppToast.error(context, 'You are at your capacity limit — finish a stop before claiming another.');
      return;
    }
    if (res.error == 'payment_required') {
      AppToast.error(context, 'This parcel is waiting for the sender\'s prepayment.');
      return;
    }
    AppToast.error(context, 'Could not claim $ref (${res.error}). Try again.');
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
    // NO empty-queue bail-out (owner 2026-11-19 "riders not getting orders"):
    // dispatch only considers riders pinged in the last 15 minutes. A rider
    // waiting for their FIRST order has an empty queue — if we stop pinging,
    // their last_seen_at goes stale and the algorithm can never pick them.
    final now = DateTime.now();
    if (_lastPingAt != null && now.difference(_lastPingAt!).inSeconds < 20) return;
    // A stationary rider still refreshes every 60 s. Distance filtering alone
    // would let last_seen_at expire while they wait at the same spot.
    final mustRefresh = _lastPingAt == null || now.difference(_lastPingAt!).inSeconds >= 60;
    if (!mustRefresh && _lastPingLat != null && _lastPingLng != null &&
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
  /// "To Platinum" / "To Icypeed" (owner 2026-11-18): the depot leg button
  /// names the DEPOT by its first word, never a generic "depot".
  String _depotShort(Map<String, dynamic> s) {
    final name = '${s['depot'] ?? s['courier'] ?? ''}'.trim();
    if (name.isEmpty) return 'depot';
    return name.split(RegExp(r'\s+')).first;
  }

  Future<void> _navigateToStop(Map<String, dynamic> s) async {
    final picked = _picked('${s['status'] ?? ''}');
    // COLLECTION jobs run DEPOT → RECIPIENT (the reverse of a drop-off). The
    // first leg is the courier counter where the parcel is already waiting;
    // only after the pickup does the rider head to the recipient's door.
    final isCollection = '${s['service'] ?? ''}' == 'collection';
    // After a collection pickup there is no door pin on the job (only the
    // typed dest_address) — leave coords null so the address is geocoded.
    final lat = picked
        ? (isCollection ? null : (s['depot_lat'] as num?)?.toDouble())
        : (s['pickup_lat'] as num?)?.toDouble() ?? (s['lat'] as num?)?.toDouble();
    final lng = picked
        ? (isCollection ? null : (s['depot_lng'] as num?)?.toDouble())
        : (s['pickup_lng'] as num?)?.toDouble() ?? (s['lng'] as num?)?.toDouble();
    final addr = '${s['address'] ?? ''}'.trim();
    // "To Platinum" / "To Icypeed" (owner 2026-11-18): the depot leg is named
    // by the DEPOT, not a generic "depot" — stop rows carry `depot` now.
    final depotName = '${s['depot'] ?? s['courier'] ?? 'DropOff'}'.trim();
    final senderName = '${s['seller'] ?? ''}'.trim();
    final label = isCollection
        ? (picked
            ? 'Deliver to ${'${s['recipient'] ?? 'recipient'}'}'
            : '$depotName depot — collect the parcel')
        : (picked
            ? '$depotName depot'
            : (senderName.isNotEmpty ? '$senderName — $addr' : '${s['ref'] ?? 'Stop'} — $addr').trim());
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
          destIsDepot: isCollection ? !picked : picked,
          otherLat: otherLat,
          otherLng: otherLng,
          otherIsDepot: isCollection ? picked : !picked,
        ),
      ));
      return;
    }
    // No pin on the booking — geocode the typed address OURSELVES and keep
    // the rider inside the DropOff navigator.
    final query = isCollection
        ? (picked
            ? '${s['dest_address'] ?? ''}'.trim()
            : '$depotName depot ${s['from_city'] ?? ''}'.trim())
        : (picked
            ? '$depotName depot ${s['from_city'] ?? ''}'.trim()
            : '$addr${'${s['from_city'] ?? ''}'.trim().isNotEmpty ? ', ${s['from_city']}' : ''}'.trim());
    if (query.isEmpty) {
      _snack('This stop has no pin or address yet — refresh, or ask ops.');
      return;
    }
    // Toast wording (owner 2026-11-18): say WHAT is being located and that the
    // DropOff map is doing it — a raw geocoder query reads like an error.
    _snack(isCollection
        ? (picked
            ? 'Finding the recipient door on the DropOff map…'
            : 'Finding the $depotName depot on the DropOff map…')
        : (picked
            ? 'Finding the $depotName depot on the DropOff map…'
            : 'Finding the pickup point on the DropOff map…'));
    final hits = await MapServices.search(query);
    if (!mounted) return;
    if (hits.isNotEmpty) {
      final hit = hits.first;
      Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => InAppNavigatorScreen(
          destLat: hit.point.latitude,
          destLng: hit.point.longitude,
          label: label,
          destIsDepot: isCollection ? !picked : picked,
          otherLat: otherLat,
          otherLng: otherLng,
          otherIsDepot: isCollection ? picked : !picked,
        ),
      ));
      return;
    }
    // Geocode found nothing — silent last resort: the device's default maps
    // handler. No button label, no brand name; just get the rider there.
    await openInApp('https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(query)}');
  }

  /// Full-screen proof-of-payment receipt — the rider shows this at the
  /// courier counter to collect the goods. Pinch to zoom, tap to close.
  void _showCollectionReceipt(String url) {
    if (url.isEmpty) return;
    Navigator.of(context).push<void>(MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: const Text('Receipt — show at the depot counter'),
        ),
        body: InteractiveViewer(
          maxScale: 5,
          child: Center(
            child: Image.network(
              '${DropOffApi.baseUrl}$url',
              headers: DropOffApi.authHeaders,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Padding(
                padding: EdgeInsets.all(28),
                child: Text('Receipt could not load — check your connection.',
                    style: TextStyle(color: Colors.white), textAlign: TextAlign.center),
              ),
            ),
          ),
        ),
      ),
    ));
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
            final isCollection = '${s['service'] ?? ''}' == 'collection';
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
              // COLLECTION: the sender's proof-of-payment receipt is shown
              // full-screen at the depot counter before the items are handed
              // over. Then the rider photographs every collected parcel.
              if ('${s['service'] ?? ''}' == 'collection' && '${s['collection_receipt_url'] ?? ''}'.isNotEmpty) ...[
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: OutlinedButton.icon(
                    onPressed: () => _showCollectionReceipt('${s['collection_receipt_url']}'),
                    icon: const Icon(Icons.receipt_long_outlined),
                    label: const Text('Show payment receipt at the counter'),
                  ),
                ),
              ],
              const SizedBox(height: 6),
              step(
                done: picked,
                unlocked: true,
                icon: Icons.local_shipping_outlined,
                title: isCollection ? 'Collected from the depot' : 'Picked up from the sender',
                subtitle: picked
                    ? 'Filed ✓'
                    : isCollection
                        ? 'Show the payment receipt, then photograph every collected item ($parcels)'
                        : 'Sender\'s 4-digit code + one photo per parcel ($parcels)',
                onTap: () async {
                  final res = await _pickUpFromSender(s);
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
                    final res = await _deliverToDoor(s);
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
              const Divider(height: 16),
              // ORDER WAYBILL (owner 2026-11-18): the rider's read-only copy of
              // the full order sheet — contacts, both addresses, depot,
              // parcels — no money fields. Available any time on this stop.
              ListTile(
                enabled: _busyRef == null,
                leading: const Icon(Icons.receipt_long_outlined),
                title: const Text('View order waybill',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                subtitle: const Text('Full order sheet — contacts, addresses, depot',
                    style: TextStyle(fontSize: 12)),
                onTap: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => OrderWaybillSheet(ref: ref),
                ),
              ),
              // RESEND (owner 2026-11-18): the sender's booking SMS may never
              // have landed — without the 4-digit code the pickup can never be
              // verified. One tap re-fires a FRESH code to both phones.
              if (!picked)
                ListTile(
                  enabled: _busyRef == null,
                  leading: const Icon(Icons.sms_outlined),
                  title: const Text('Resend the 4-digit code SMS',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                  subtitle: const Text('Sender never got it? Send a fresh code to their phone',
                      style: TextStyle(fontSize: 12)),
                  onTap: () async {
                    final msg = await _resendPinCode(ref);
                    if (mounted) _snack(msg);
                  },
                ),
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

  /// Capitalized handover title (owner 2026-11-18): the parcel CONTENT from
  /// the booking rides with the reference so every sheet names the job the
  /// way the sender wrote it — "PICKUP-BOOKS-DRO-261113-ZMAMZ" /
  /// "COLLECTION-BOOKS-DRO-261113-ZMAMZ" — always in capital letters.
  String _handoverTitle(Map<String, dynamic> s, String kind) {
    final content = '${s['description'] ?? ''}'.trim();
    final words = content.split(RegExp(r'[^A-Za-z0-9]+')).where((w) => w.isNotEmpty).toList();
    final word = words.isEmpty ? 'PARCEL' : words.first.toUpperCase();
    return '$kind-$word-${s['ref']}'.toUpperCase();
  }

  /// Re-fires the 4-digit handover code SMS (owner 2026-11-18). The server
  /// generates a FRESH code and texts BOTH copies — the sender's pickup code
  /// and the recipient's door code — so a missing booking SMS can never dead-
  /// end a pickup. Max 3 per job per day, server-side.
  Future<String> _resendPinCode(String ref) async {
    final r = await DropOffApi.resendPickupPin(ref);
    return _resendPinMessage(r);
  }

  String _resendPinMessage(ApiResponse r) {
    if (r.ok) {
      final detail = '${r.body['detail'] ?? ''}'.trim();
      return detail.isNotEmpty
          ? detail
          : (r.body['sent'] == true ? 'New 4-digit code sent to the sender.' : 'Resend logged but the SMS may not have gone out.');
    }
    final detail = '${r.body['detail'] ?? ''}'.trim();
    return switch (r.error ?? '') {
      'rate_limited' => detail.isEmpty ? 'Resend limit reached today (3) — call DropOff support.' : detail,
      'not_needed' => detail.isEmpty ? 'This stop no longer needs a code.' : detail,
      _ => detail.isNotEmpty ? detail : 'Could not resend the code (${r.error ?? 'network'}).',
    };
  }

  /// PICKUP (owner directive 2026-11-17): the SENDER holds the 4-digit code
  /// from the booking SMS and the rider photographs EVERY parcel exactly
  /// once — exactly N captures for N parcels, no repeats. The server locks
  /// the pickup evidence on first file; further changes go through ops.
  Future<ApiResponse?> _pickUpFromSender(Map<String, dynamic> s) async {
    if (_busyRef != null) return null;
    final ref = '${s['ref']}';
    final parcels = (s['parcels'] as num?)?.toInt() ?? 1;
    final senderName = '${s['seller'] ?? ''}'.trim();
    final senderPhone = '${s['seller_phone'] ?? ''}'.trim();
    final otpCtrl = TextEditingController();
    final photos = <String>[];
    String? inlineError;
    String? lastErrCode; // the rejected-code errors unlock the resend helper
    bool resending = false;
    bool submitting = false;
    final res = await showDialog<ApiResponse>(
      context: context,
      barrierDismissible: false,
      builder: (dctx) => StatefulBuilder(
        builder: (dctx, setDialog) => AlertDialog(
          title: Text(_handoverTitle(s, 'PICKUP'), style: AppType.subhead),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              // WHO holds the PIN (owner 2026-11-18): the rider must never
              // wonder whose code to ask for.
              Text('Get the 4-digit PICKUP PIN from: ${senderName.isEmpty ? 'the sender' : senderName}${senderPhone.isNotEmpty ? ' · $senderPhone' : ''}',
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: AppColors.forest, height: 1.35)),
              const SizedBox(height: 8),
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
                Text(inlineError!, style: const TextStyle(fontSize: 12, color: AppColors.danger, height: 1.35)),
                // The stuck moment (owner 2026-11-18): the sender never got
                // a booking SMS, so no code exists to show. One tap re-fires
                // a fresh code to their phone — no dead-end pickup.
                if (!resending && (lastErrCode == 'otp_required' || lastErrCode == 'otp_locked'))
                  TextButton.icon(
                    icon: const Icon(Icons.sms_outlined, size: 16),
                    label: const Text('Sender never got the SMS? Resend a fresh code',
                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                    onPressed: () async {
                      setDialog(() => resending = true);
                      final msg = await _resendPinCode(ref);
                      if (!dctx.mounted) return;
                      setDialog(() { resending = false; inlineError = msg; });
                    },
                  ),
                if (resending)
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
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
                setDialog(() {
                  inlineError = switch (err) {
                    'otp_required' => 'Code rejected. ${detail.isEmpty ? 'The code is in the sender\'s booking SMS.' : detail}',
                    'otp_locked' => 'Too many wrong codes — DropOff support has been notified.',
                    'photo_locked' => 'Pickup photo already on file for $ref — the evidence is locked. Ask ops to correct a genuine mis-submission.',
                    _ => 'Could not file the pickup ($err).',
                  };
                  lastErrCode = err; // rejected-code errors unlock the resend helper
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
    bool filing = false;
    // The SENDER's booking photo travels with the stop (owner directive
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
                const Text('SENDER PHOTO (FROM BOOKING)', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11, color: AppColors.muted)),
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
              onPressed: filing ? null : () async {
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
                setDialog(() => filing = true); // visible progress while filing
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
              child: Text(filing ? 'Filing drop...' : 'Submit drop'),
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
      'photo_locked' => detail.isEmpty ? 'That proof photo is already filed — pull to refresh; contact support if the task stays open.' : detail,
      'counter_receipt_locked' => detail.isEmpty ? 'The depot receipt is already paid and locked — contact support.' : detail,
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

  /// Door delivery: the server enforces the recipient's 4-digit handover code
  /// for INTERCITY collections (e.g. Ndola). Same-city parcels carry no PIN
  /// (owner directive 2026-11-18) — the code field is optional; the recipient
  /// confirms receipt in-app instead.
  Future<ApiResponse?> _deliverToDoor(Map<String, dynamic> s) async {
    if (_busyRef != null) return null;
    if (!mounted) return null;
    final ref = '${s['ref']}';
    final recName = '${s['recipient'] ?? ''}'.trim();
    final recPhone = '${s['recipient_phone'] ?? ''}'.trim();
    final otpCtrl = TextEditingController();
    String? podUrl;
    final res = await showDialog<ApiResponse>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: Text(_handoverTitle(s, 'COLLECTION'), style: AppType.subhead),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Hand this parcel to: ${recName.isEmpty ? 'the recipient' : recName}${recPhone.isNotEmpty ? ' · $recPhone' : ''}',
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: AppColors.forest, height: 1.35)),
            const SizedBox(height: 8),
            const Text('Intercity parcels: the recipient shows their 4-digit DropOff code from the handover SMS. Lusaka parcels carry no SMS PIN — but if the recipient set their own door PIN in the app, ask for it here. Otherwise attach the proof photo; they confirm receipt in their own app.',
              style: TextStyle(fontSize: 12.5, height: 1.4, color: AppColors.ink)),
            const SizedBox(height: 12),
            TextField(
              controller: otpCtrl,
              keyboardType: TextInputType.number,
              maxLength: 4,
              decoration: const InputDecoration(
                counterText: '',
                labelText: '4-digit door PIN / code (if the recipient has one)',
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
          if (podUrl != null) ...[
            const SizedBox(height: 8),
            Row(children: [
              PhotoPreview(pathOrUrl: podUrl!, label: 'PROOF', size: 96),
              const SizedBox(width: 10),
              const Expanded(child: Text('Check this is the parcel you handed over before you confirm.', style: AppType.caption)),
            ]),
          ],
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, null), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                final code = otpCtrl.text.trim();
                if (podUrl == null) {
                  _snack('Attach the camera photo of the handover to confirm.');
                  return;
                }
                // Intercity parcels NEED the code; Lusaka parcels hand over on
                // the photo alone — the server enforces whichever applies.
                final r = await DropOffApi.jobEvent(
                  jobRef: ref, status: 'delivered',
                  otp: code.length == 4 ? code : null,
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

  /// Available-orders board — only present when auto-assign left parcels over.
  /// A claim is exclusive: another rider claiming it removes the card here on
  /// the next 20 s poll (or the immediate refresh after the attempt).
  Widget _claimCard() {
    if (_available.isEmpty) return const SizedBox.shrink();
    return Card(
      color: AppColors.amberSoft,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const Icon(Icons.front_hand, color: AppColors.forest, size: 18),
            const SizedBox(width: 8),
            const Expanded(child: Text('Available orders', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14))),
            Text('${_available.length}', style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.forest)),
          ]),
          const SizedBox(height: 3),
          const Text('Auto-assign could not place these. First to claim owns the parcel.', style: TextStyle(fontSize: 11, color: AppColors.muted)),
          const SizedBox(height: 8),
          for (final j in _available.take(5)) ...[
            Container(
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${j['ref']} · ${j['pickup_address']}', maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text('${j['sender_name'] ?? ''} → ${j['dest_city'] ?? ''} · ${j['parcels'] ?? 1} parcel(s) · ${j['pickup_window'] ?? ''}',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10.5, color: AppColors.muted)),
                ])),
                const SizedBox(width: 8),
                FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size(72, 36)),
                  onPressed: _claimingRef != null ? null : () => _claim(j),
                  child: _claimingRef == '${j['ref']}'
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Claim'),
                ),
              ]),
            ),
            const SizedBox(height: 6),
          ],
          if (_available.length > 5)
            Text('+ ${_available.length - 5} more — refresh to see all', style: const TextStyle(fontSize: 10.5, color: AppColors.muted)),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Fleet view is staff-only (Team tab + this gate). The server also
    // validates the phone belongs to an active rider — a sender whose phone
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
        title: const Text('Task Queue', style: TextStyle(fontWeight: FontWeight.w900)),
        actions: [
          IconButton(
            tooltip: 'Rider tutorial',
            icon: const Icon(Icons.menu_book_outlined),
            onPressed: () => TutorialSheet.show(context, rider: true),
          ),
          IconButton(
            tooltip: 'Account & sign out',
            icon: (store.photoUrl ?? '').isNotEmpty
                ? ClipOval(child: Image.network(
                    '${DropOffApi.baseUrl}${store.photoUrl}',
                    width: 28, height: 28, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const Icon(Icons.account_circle)))
                : Icon(store.email != null ? Icons.account_circle : Icons.account_circle_outlined),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AccountScreen())),
          ),
        ],
      ),
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (_offline)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            color: AppColors.amber.withValues(alpha: 0.18),
            child: const Row(children: [
              Icon(Icons.cloud_off, size: 16, color: AppColors.ink),
              SizedBox(width: 8),
              Expanded(child: Text('Offline — showing your last synced queue. It refreshes automatically when you reconnect.',
                  style: TextStyle(fontSize: 11.5, color: AppColors.ink, fontWeight: FontWeight.w700))),
            ]),
          ),
        Expanded(
          child: _loading
          ? const Center(child: CircularProgressIndicator())
          : batches.isEmpty
              // Pull-to-refresh works on the empty state too — new assignments
              // drop in without leaving the screen.
              ? RefreshIndicator(
                  onRefresh: _load,
                  child: LayoutBuilder(builder: (ctx, cons) => SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: Column(
                      children: [
                        // The day's numbers survive an empty queue — a rider
                        // who has delivered everything still sees the score.
                        _statsCard(),
                        if (_available.isNotEmpty) ...[
                          _claimCard(),
                          const SizedBox(height: 8),
                        ],
                        SizedBox(
                          height: cons.maxHeight - 160,
                          child: Center(
                            child: Padding(
                              padding: const EdgeInsets.all(32),
                              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                                 _radarEmpty(),
                                const SizedBox(height: 14),
                                const Text('No rides on your queue yet',
                                    style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900), textAlign: TextAlign.center),
                                const SizedBox(height: 8),
                                const Text(
                                  'Slot batches land here the moment the system assigns you a run — you do not have to book anything. Pull down or tap Check for new rides to sync.',
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
                      ],
                    ),
                  )),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 90),
                    itemCount: batches.length + (_available.isNotEmpty ? 2 : 1),
                    itemBuilder: (context, i) {
                      if (i == 0) return _statsCard();
                      if (_available.isNotEmpty && i == 1) return _claimCard();
                      return _batchCard(batches[i - 1 - (_available.isNotEmpty ? 1 : 0)]);
                    },
                  ),
                ),
        ),
      ]),
    );
  }

  /// TODAY · LIVE — the rider's daily scoreboard (owner 2026-11-18): all
  /// assigned, still waiting to be picked up, in hand, done, parcels moved
  /// and fees earned — bucketed by the rider's CAT day server-side and
  /// refreshed with the same 20 s poll as the queue.
  /// Animated "scanning for signal" radar for the empty queue (owner 2026-11-18).
  Widget _radarEmpty() => LayoutBuilder(builder: (context, cons) {
    final screenW = cons.maxWidth;
    return AnimatedBuilder(
      animation: _radar,
      builder: (context, _) {
        final t = _radar.value;
        // Rings start near the logo and expand past the screen edges, so the
        // radar reads as searching the whole city for a parcel signal.
        return ClipRect(
          child: SizedBox(
            width: double.infinity,
            height: 210,
            child: Stack(alignment: Alignment.center, children: [
              for (final phase in const [0.0, 0.34, 0.67])
                Transform.scale(
                  scale: 0.35 + 1.85 * ((t + phase) % 1.0),
                  child: Container(
                    width: screenW * 0.9, height: screenW * 0.9,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppColors.forest.withValues(alpha: 0.42 * (1 - ((t + phase) % 1.0))),
                        width: 2.5),
                    ),
                  ),
                ),
              Transform.rotate(
                angle: t * 6.2832,
                child: Container(
                  width: screenW * 0.92, height: 3,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [
                      Colors.transparent, AppColors.amber.withValues(alpha: 0.65), Colors.transparent,
                    ]),
                  ),
                ),
              ),
              // OUR APP LOGO in the centre of the radar.
              Container(
                width: 76, height: 76,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.forest,
                  border: Border.all(color: Colors.white, width: 2.5),
                  boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 14, offset: Offset(0, 5))],
                ),
                clipBehavior: Clip.antiAlias,
                // Cover fills the whole circle with the green app artwork —
                // no white corners/patches around the pin + parcel mark.
                child: Image.asset('assets/brand/dropoff_logo.png', width: 76, height: 76, fit: BoxFit.cover),
              ),
            ]),
          ),
        );
      },
    );
  });
  Widget _statsCard() {
    final s = _stats ?? const {};
    final total = (s['total'] as num?)?.toInt() ?? 0;
    final waiting = (s['waiting'] as num?)?.toInt() ?? 0;
    final picked = (s['picked'] as num?)?.toInt() ?? 0;
    final delivered = (s['delivered'] as num?)?.toInt() ?? 0;
    final parcels = (s['parcels'] as num?)?.toInt() ?? 0;
    final earned = (s['earned_zmw'] as num?)?.toDouble() ?? 0;
    // Always visible (owner 2026-11-18): a quiet day still shows the card —
    // a zero-total card used to shrink away and look "missing".
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.forest,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.forest.withValues(alpha: 0.5)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.insights, size: 16, color: AppColors.amber),
            const SizedBox(width: 7),
            Text('TODAY · LIVE',
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w900, letterSpacing: 1.4,
                    color: Colors.white.withValues(alpha: 0.85))),
            const Spacer(),
            // Manual sync — pull-to-refresh and the 20 s timer also refresh.
            IconButton(tooltip: 'Sync now', onPressed: _load,
              icon: const Icon(Icons.sync, size: 16, color: Colors.white70)),
            Text('K${earned.toStringAsFixed(0)}',
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: AppColors.amber)),
            const SizedBox(width: 4),
            const Text('earned', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Colors.white70)),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            _statTile('$total', 'ALL', Colors.white),
            _statTile('$waiting', 'TO PICK UP', waiting > 0 ? AppColors.amber : Colors.white70),
            _statTile('$picked', 'IN HAND', AppColors.mint),
            _statTile('$delivered', 'DONE', Colors.white),
          ]),
          // Pace + bonus strip (owner 2026-11-18) from /rider/targets.
          if (_targets != null) _targetsStrip(),
          const SizedBox(height: 8),
          Row(children: [
            Icon(Icons.circle, size: 7, color: Colors.greenAccent.withValues(alpha: 0.9)),
            const SizedBox(width: 6),
            Text('$parcels parcels · synced $_statsSynced · auto 20 s',
                style: TextStyle(fontSize: 10.5, color: Colors.white.withValues(alpha: 0.6), fontWeight: FontWeight.w600)),
          ]),
        ]),
      ),
    );
  }

  /// Pace gate + bonus in one compact strip under the stats tiles.
  Widget _targetsStrip() {
    final t = _targets ?? const {};
    final today = (t['today'] as num?)?.toInt() ?? 0;
    final daily = (t['daily_target'] as num?)?.toInt() ?? 30;
    final month = (t['month'] as num?)?.toInt() ?? 0;
    final pace = (t['pace_target'] as num?)?.toInt() ?? 0;
    final behind = (t['behind_by'] as num?)?.toInt() ?? 0;
    final bonus = (t['bonus'] as Map?) ?? const {};
    final bonusZmw = (bonus['total_bonus_zmw'] as num?)?.toDouble() ?? 0;
    final progress = daily > 0 ? (today / daily).clamp(0.0, 1.0) : 0.0;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.flag_outlined, size: 13, color: AppColors.amber),
          const SizedBox(width: 6),
          Expanded(child: Text('TODAY $today/$daily  ·  MONTH $month/$pace',
              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800))),
          Text('BONUS K${bonusZmw.toStringAsFixed(0)}',
              style: const TextStyle(color: AppColors.amber, fontSize: 11, fontWeight: FontWeight.w900)),
        ]),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(value: progress, minHeight: 5,
              backgroundColor: Colors.white24, color: AppColors.amber),
        ),
        const SizedBox(height: 4),
        Text(behind > 0
            ? 'Behind monthly pace by $behind trips — bonus needs the pace target.'
            : 'On pace — keep the streak for the month-close bonus.',
            style: const TextStyle(color: Colors.white70, fontSize: 10)),
      ]),
    );
  }

  Widget _statTile(String value, String label, Color color) => Expanded(
        child: Column(children: [
          Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: color, height: 1)),
          const SizedBox(height: 3),
          Text(label,
              style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 0.7,
                  color: Colors.white.withValues(alpha: 0.55)), textAlign: TextAlign.center),
        ]),
      );

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
              if (pickedCount < ((b['total_stops'] as num?)?.toInt() ?? 0)) ...[
                const SizedBox(height: 4),
                AnimatedBuilder(animation: _radar, builder: (_, __) => Row(children: [
                  Container(width: 8, height: 8,
                    decoration: BoxDecoration(shape: BoxShape.circle,
                      color: AppColors.amber.withValues(alpha: 0.35 + 0.65 * (_radar.value % 1)))),
                  const SizedBox(width: 6),
                  const Text('TASKS PENDING — pulse until you file these stops',
                      style: TextStyle(color: Colors.white70, fontSize: 10.5, fontWeight: FontWeight.w700)),
                ])),
              ],
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
    final depotName = '${s['depot'] ?? s['courier'] ?? 'depot'}'.trim();
    // READABLE STOP ROW (owner 2026-11-18): the old single-row cram squeezed
    // the time+address until it clipped at the left margin. The title now
    // gets full width and wraps to two lines, the meta line runs full width,
    // and the action buttons live on their own row — nothing is cut.
    final col = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${s['n']}.', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12.5, color: AppColors.forest)),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${_hhmm12('${s['time'] ?? ''}')} — ${s['address']}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, height: 1.25,
                    color: picked ? AppColors.muted : AppColors.ink)),
            const SizedBox(height: 2),
            Text(
              picked
                  ? '✓ picked — ${'${s['last_mile'] ?? 0}' == '1' ? 'door handover next' : 'drop at the $depotName depot'}'
                  : arrived
                      ? ('${s['service'] ?? ''}' == 'collection'
                          ? 'ARRIVED at the depot — tap ✓ to collect the parcel'
                          : 'ARRIVED — tap ✓ to file the pickup')
                      : 'Sender: ${s['seller']} · ${s['depot'] ?? 'depot'} · ${s['parcels']} parcel${s['parcels'] == 1 ? '' : 's'} · ${'${s['status']}'.replaceAll('_', ' ')}',
              style: TextStyle(color: picked ? AppColors.forest : arrived ? AppColors.ink : AppColors.muted,
                  fontSize: 11.5, fontWeight: picked || arrived ? FontWeight.w800 : FontWeight.w400),
            ),
            if (arrived) ...[
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: AppColors.amber.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(6)),
                child: const Text('ARRIVED ✓', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 9.5, color: AppColors.ink, letterSpacing: 0.4)),
              ),
            ],
          ]),
        ),
      ]),
      const SizedBox(height: 4),
      Row(children: [
        if ('${s['seller_phone'] ?? ''}'.trim().isNotEmpty)
          IconButton(
            tooltip: 'Call the sender',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.phone_outlined, size: 20, color: AppColors.forest),
            onPressed: () async {
              final number = '${s['seller_phone']}';
              final ok = await callPhoneNumber(number);
              if (!ok && mounted) _snack('Dialer not available here — call $number');
            },
          ),
        const Spacer(),
        _navBtn(
          picked
              ? ('${s['service'] ?? ''}' == 'collection'
                  ? 'To ${'${s['recipient'] ?? 'recipient'}'}'
                  : 'To ${_depotShort(s)}')
              : ('${s['service'] ?? ''}' == 'collection'
                  ? 'To ${_depotShort(s)}'
                  : 'To ${'${s['seller'] ?? 'Sender'}'.trim().isEmpty ? 'Sender' : '${s['seller']}'.trim()}'),
          picked ? 'Navigate to the ${s['depot'] ?? s['courier'] ?? 'depot'} depot in the DropOff map' : 'Navigate to ${s['seller'] ?? 'the sender'} in the DropOff map',
          picked ? AppColors.forest : AppColors.forestLight,
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
      ]),
    ]);
    // The rider's NEXT stop gets the amber guide bar — the eye lands there.
    if (!isActive) return col;
    return Container(
      decoration: const BoxDecoration(border: Border(left: BorderSide(width: 3, color: AppColors.amber))),
      padding: const EdgeInsets.only(left: 8),
      child: col,
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

/// ORDER WAYBILL (owner 2026-11-18): the rider's read-only copy of the order
/// sheet — the same facts the sender's waybill carries (contacts, both
/// addresses, depot/branch, parcels, window) with every money field stripped
/// server-side. The rider reaches it from the stop sheet → "View order
/// waybill", any time before the drop is filed. When the rider sees it:
/// before navigating to a pickup (who/what/where), when the sender or
/// recipient needs confirming by voice (call buttons), and at the depot drop
/// (depot + branch names to quote at the counter).
class OrderWaybillSheet extends StatefulWidget {
  final String ref;
  const OrderWaybillSheet({super.key, required this.ref});

  @override
  State<OrderWaybillSheet> createState() => _OrderWaybillSheetState();
}

class _OrderWaybillSheetState extends State<OrderWaybillSheet> {
  Map<String, dynamic>? _wb;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await DropOffApi.riderWaybill(widget.ref);
    if (!mounted) return;
    setState(() {
      _wb = data?['waybill'] as Map<String, dynamic>?;
      _error = _wb == null ? 'Waybill not available — refresh the queue and try again.' : null;
    });
  }

  /// CAT timestamps arrive as "YYYY-MM-DDTHH:MM:SS.fffZ" — show "D MMM · HH:MM".
  String _when(String? iso) {
    final s = (iso ?? '').replaceFirst('T', ' ');
    return s.length >= 16 ? s.substring(0, 16) : (s.isEmpty ? '—' : s);
  }

  Future<void> _call(String? raw) async {
    final tel = (raw ?? '').trim();
    if (tel.isEmpty) return;
    final ok = await callPhoneNumber(tel);
    if (!ok && mounted) AppToast.error(context, 'Dialer not available here — call $tel');
  }

  Widget _row(String k, String v, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 92, child: Text(k, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.muted))),
          Expanded(child: Text(v.isEmpty ? '—' : v,
              style: TextStyle(fontSize: 12.5, color: AppColors.ink, fontWeight: bold ? FontWeight.w800 : FontWeight.w500))),
        ]),
      );

  Widget _contactRow(String label, String? name, String? phone) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          SizedBox(width: 92, child: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.muted))),
          Expanded(child: Text((name ?? '').trim().isEmpty ? '—' : name!,
              style: const TextStyle(fontSize: 12.5, color: AppColors.ink, fontWeight: FontWeight.w700))),
          if ((phone ?? '').trim().isNotEmpty)
            IconButton(
              tooltip: 'Call $name',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.phone_outlined, size: 18, color: AppColors.forest),
              onPressed: () => _call(phone),
            ),
        ]),
      );

  Widget _section(String title, List<Widget> kids) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.1, color: AppColors.forest)),
          const SizedBox(height: 3),
          ...kids,
        ]),
      );

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const Icon(Icons.receipt_long_outlined, size: 18, color: AppColors.ink),
            const SizedBox(width: 8),
            const Expanded(
              child: Text('ORDER WAYBILL',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 1.2, color: AppColors.ink)),
            ),
            IconButton(icon: const Icon(Icons.close, size: 20), onPressed: () => Navigator.pop(context)),
          ]),
          Flexible(
            child: SingleChildScrollView(
              child: _error != null
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 28),
                      child: Column(children: [
                        Text(_error!, textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 12.5, color: AppColors.muted, height: 1.5)),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: () { setState(() { _error = null; }); _load(); },
                          icon: const Icon(Icons.refresh, size: 18),
                          label: const Text('Try again'),
                        ),
                      ]),
                    )
                  : _wb == null
                      ? const Padding(
                          padding: EdgeInsets.symmetric(vertical: 40),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      : _card(),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _card() {
    final w = _wb!;
    final depotTitle = waybillDepotTitle('', '${w['courier_name'] ?? ''}');
    final lastMile = '${w['last_mile'] ?? 0}' == '1';
    final branch = '${w['branch'] ?? ''}'.trim();
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.line.withValues(alpha: 0.6)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(depotTitle, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: 0.6, color: AppColors.ink)),
        const SizedBox(height: 2),
        Row(children: [
          Expanded(child: Text('${w['ref'] ?? ''}', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: AppColors.forest))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(color: AppColors.forest.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
            child: Text('${w['status'] ?? ''}'.replaceAll('_', ' '),
                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.forest)),
          ),
        ]),
        Text('Booked ${_when('${w['created_at'] ?? ''}')} · ${w['pickup_window'] ?? 'window pending'}',
            style: const TextStyle(fontSize: 11, color: AppColors.muted)),
        const Divider(height: 20),
        _section('FROM — SENDER', [
          _contactRow('Sender', '${w['sender_name'] ?? ''}', '${w['sender_phone'] ?? ''}'),
          _row('Pickup at', '${w['pickup_address'] ?? ''}'),
          _row('City', '${w['from_city'] ?? ''}'),
        ]),
        _section(lastMile ? 'TO — RECIPIENT (DOOR)' : 'TO — DEPOT (COUNTER)', [
          if (lastMile) ...[
            _contactRow('Recipient', '${w['recipient_name'] ?? ''}', '${w['recipient_phone'] ?? ''}'),
            _row('Deliver to', '${w['dest_address'] ?? ''}'),
            _row('City', '${w['dest_city'] ?? ''}'),
          ] else ...[
            _row('Depot', '${w['depot_name'] ?? w['courier_name'] ?? ''}'),
            _row('Branch', branch),
            _row('City', '${w['from_city'] ?? ''}'),
            const SizedBox(height: 4),
            const Text('This run ends at the depot — the courier carries the parcel the rest of the way.',
                style: TextStyle(fontSize: 11, color: AppColors.muted, height: 1.4)),
          ],
        ]),
        _section('PARCEL', [
          _row('Parcels', '${w['parcels'] ?? 1}'),
          _row('Contents', '${w['description'] ?? ''}'),
          _row('Size', '${w['weight_class'] ?? ''}'),
          // Declared parcel VALUE (owner request): for the counter receipt.
          // No fees, rates or rider payouts are ever shown on this sheet.
          if ((w['declared_value_zmw'] as num?)?.toDouble() != null &&
              (w['declared_value_zmw'] as num).toDouble() > 0)
            _row('Declared value', 'K${(w['declared_value_zmw'] as num).toStringAsFixed(2)}'),
        ]),
        const Divider(height: 12),
        Text('Depot fare is paid at the counter — DropOff never collects partner money. Money fields are never shown on the rider sheet.',
            style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600, height: 1.4)),
      ]),
    );
  }
}
