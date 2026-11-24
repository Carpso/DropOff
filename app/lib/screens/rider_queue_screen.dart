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
import '../ui/receipt_viewer.dart';
import '../ui/proof_upload_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../data/catalog.dart';
import '../data/dropoff_api.dart';
import '../data/map_services.dart';
import '../data/analytics_service.dart';
import '../data/push_service.dart';
import '../main.dart';
import '../ui/app_theme.dart';
import '../ui/app_sheet.dart';
import '../widgets/common.dart';
import 'account_screen.dart';
import 'rider_history_screen.dart';
import 'in_app_navigator_screen.dart';
import 'waybill_screen.dart' show waybillDepotTitle;
import '../ui/app_spinner.dart';
import '../services/step_sounds.dart';
import '../services/order_alert.dart';
import 'incoming_order_screen.dart';

/// Result of a server-side, verify-only PIN check. The UI must only tick
/// "verified" on [ok] (real match) or [notNeeded] (no code exists for this
/// job) — never merely because 4 digits were typed (owner 2026-11-23).
enum _PinCheck { idle, checking, ok, wrong, locked, notNeeded }

/// The rider's day as slot-batched task queues:
///   BATCH: 10:00—11:30 slot · 6:00—7:30 AM window · 23 min in
///   TOTAL PARCELS: 6 · STOPS: 3 (1 picked) · DESTINATION: Mercury — Kabulonga
///   1. 10:05 AM · 14 Reedbuck Rd (Beauty Hub) — 2 items ...
///
/// Owner directives (2026-11-17) built into this screen:
///  • Pull-to-refresh + a 20s auto-sync poll; the queue is the rider's
///    FIRST tab (AppShell), highly visible, never lost between cards.
///  • The "How did the item move on?" sheet is SEQUENTIAL: steps tick ✓
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
  Timer? _claimTimer;

  // CLAIM BOARD — jobs auto-assign could not place (no online rider in range,
  // rider at a depot, everyone at capacity). Every verified rider sees the
  // same list; the first to claim owns it and it disappears for the others.
  List<Map<String, dynamic>> _available = const [];
  String? _availableHint;
  String? _claimingRef;

  // NEW-ORDER ALERT (owner 2026-11-20): when the queue gains NEW assigned
  // jobs, vibrate the phone AND keep the screen awake so the rider sees them
  // even with the phone idle. Pings the user to notice a new order.
  static const Duration _alarmWindow = Duration(seconds: 45);
  final Set<String> _alarmSeenRefs = <String>{};
  // First queue load only PRIMES the seen set — a rider opening the app must
  // not get an alarm for every job already assigned to them.
  bool _alarmPrimed = false;
  String? _alertRef; // guards against pushing duplicate incoming-order sheets

  // LIVE ARRIVAL WATCH (owner directive 2026-11-17): a GPS position stream
  // marks stops ARRIVED within [_arrivalMetres]; a manual tap marks too.
  static const double _arrivalMetres = 80;
  final Set<String> _arrivedRefs = {};
  StreamSubscription<Position>? _posSub;
  String? _gpsIssue; // 'permission' | 'service' — drives the recovery banner
  Position? _riderPos;

  // SWEEP SHIFTS (owner 2026-11-21): all riders commit to 06:00–08:30,
  // 10:00–12:30 and 14:00–16:30 CAT. Between shifts they can do other rides.
  static const Map<String, String> _shiftLabels = {
    '06:00': '05:30–07:30 (06:00 pickup)',
    '10:00': '10:00–11:30',
    '14:00': '14:00–15:30',
  };
  Map<String, dynamic>? _shifts;
  Set<String> _selectedShifts = {'06:00', '10:00', '14:00'};
  bool _shiftBusy = false;

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
    // Claim board: poll every 5 s so a rider who just came online (or just
    // freed up) sees claimable jobs quickly — other riders claiming them
    // removes them from this list almost immediately.
    _claimTimer = Timer.periodic(const Duration(seconds: 5), (_) => _loadAvailable());
    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final batches = ((_data?['batches'] as List?) ?? const []);
      if (batches.isNotEmpty) setState(() {});
    });
    _startArrivalWatch();
    _loadShifts();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    _claimTimer?.cancel();
    _tickTimer?.cancel();
    _posSub?.cancel();
    _radar.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      _load();
      // The rider may have granted location in Settings while the app was in
      // the background — restart the watch instead of staying silent forever.
      unawaited(_startArrivalWatch());
      // Same for Android 13+ notification permission: a rider who just turned
      // alerts on in Settings must not keep seeing the "alerts off" banner.
      unawaited(PushService.refreshPermission().then((_) {
        if (mounted) setState(() {});
      }));
    }
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
    if (data != null) await _ringForNewJobs(data['batches']);
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
      var stops = 0, pickedStops = 0, items = 0;
      for (final b in qBatches) {
        items += (b['total_parcels'] as num?)?.toInt() ?? 0;
        final ss = ((b['stops'] as List?) ?? const []);
        stops += ss.length;
        pickedStops += ss.where((x) => _picked('${(x as Map)['status'] ?? ''}')).length;
      }
      final merged = Map<String, dynamic>.from(s);
      if (qBatches.isNotEmpty) {
        merged['total'] = stops;
        merged['waiting'] = stops - pickedStops;
        merged['picked'] = pickedStops;
        merged['parcels'] = items;
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

  /// RIDER TRIP TRANSFER (owner 2026-11-21): hand a LIVE stop to another active
  /// rider at any stage — e.g. stuck in a depot queue. The worker updates
  /// rider_id everywhere.
  Future<void> _transferStop(Map<String, dynamic> s) async {
    final ref = '${s['ref']}';
    final pickup = '${s['pickup'] ?? s['pickup_address'] ?? 'Pickup'}';
    final status = '${s['status'] ?? ''}';
    setState(() => _busyRef = ref);
    try {
      final data = await DropOffApi.teamRoster();
      if (!mounted) return;
      final riders = ((data?['riders'] as List?) ?? const <dynamic>[])
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .where((r) => (r['id'] as num?)?.toInt() != null)
          .toList();
      if (riders.isEmpty) {
        AppToast.show(context, 'No other active riders are available to take this trip right now.');
        return;
      }

      final target = await showModalBottomSheet<Map<String, dynamic>>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        builder: (ctx) {
          return SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + MediaQuery.of(ctx).viewPadding.bottom),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.line, borderRadius: BorderRadius.circular(4)))),
                  const SizedBox(height: 16),
                  Row(children: [
                    Container(
                      width: 42, height: 42,
                      decoration: BoxDecoration(color: AppColors.forest.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
                      child: const Icon(Icons.swap_horiz_rounded, color: AppColors.forest),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Transfer ride', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: -0.2)),
                      SizedBox(height: 2),
                      Text('Hand this trip to another active rider.', style: TextStyle(fontSize: 12.5, color: AppColors.muted)),
                    ])),
                    IconButton(onPressed: () => Navigator.of(ctx).pop(), icon: const Icon(Icons.close)),
                  ]),
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: AppColors.canvas, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.line)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(ref, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
                      const SizedBox(height: 4),
                      Text(pickup, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, color: AppColors.muted)),
                      if (status.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text('Status: $status', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.forest)),
                      ],
                    ]),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: const Color(0xFFFFF7E8), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFF1D39A))),
                    child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Icon(Icons.info_outline, size: 18, color: Color(0xFF8A5A00)),
                      SizedBox(width: 8),
                      Expanded(child: Text('Only transfer if you cannot complete this ride. The selected rider gets the trip, waybill, and responsibility immediately.', style: TextStyle(fontSize: 12, height: 1.35, color: Color(0xFF5F4308)))),
                    ]),
                  ),
                  const SizedBox(height: 14),
                  const Text('Choose a rider', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.38),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: riders.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) {
                        final r = riders[i];
                        final name = '${r['full_name'] ?? r['phone'] ?? 'Rider'}';
                        final vehicle = '${r['vehicle'] ?? ''}'.trim();
                        final phone = '${r['phone'] ?? ''}'.trim();
                        return InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () => Navigator.of(ctx).pop(r),
                          child: Ink(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: AppColors.line),
                              color: Colors.white,
                            ),
                            child: Row(children: [
                              CircleAvatar(
                                radius: 20,
                                backgroundColor: AppColors.forest.withValues(alpha: 0.1),
                                child: Text(name.isNotEmpty ? name[0].toUpperCase() : 'R', style: const TextStyle(color: AppColors.forest, fontWeight: FontWeight.w900)),
                              ),
                              const SizedBox(width: 12),
                              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                                const SizedBox(height: 2),
                                Text([if (vehicle.isNotEmpty) vehicle, if (phone.isNotEmpty) phone].join(' · '),
                                    style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                              ])),
                              const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: AppColors.muted),
                            ]),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
      if (target == null || !mounted) return;

      final toRiderId = (target['id'] as num?)?.toInt() ?? 0;
      final targetName = '${target['full_name'] ?? target['phone'] ?? 'this rider'}';
      if (toRiderId <= 0) return;

      final confirmed = await showConfirmSheet(
        context,
        title: 'Confirm transfer',
        message: 'Transfer $ref to $targetName?\n\nThey will receive the trip immediately, including the waybill and responsibility for the next steps.',
        confirmLabel: 'Transfer ride',
        icon: Icons.swap_horiz_rounded,
      );
      if (confirmed != true || !mounted) return;

      final res = await DropOffApi.transferJob(ref, toRiderId);
      if (!mounted) return;
      if (res.ok) {
        AppToast.show(context, '$ref transferred to $targetName.');
        Navigator.of(context).pop();
        _load();
      } else {
        final detail = res.body['detail'] ?? res.body['error'] ?? res.error ?? 'Try again.';
        AppToast.error(context, 'Could not transfer this ride. $detail');
      }
    } finally {
      if (mounted) setState(() => _busyRef = null);
    }
  }

  Future<void> _loadShifts() async {
    final data = await DropOffApi.riderShifts();
    if (!mounted) return;
    setState(() {
      _shifts = data;
      final raw = ((data?['shifts'] as List?) ?? const <dynamic>[])
          .whereType<String>()
          .toList();
      if (raw.isNotEmpty) _selectedShifts = raw.toSet();
    });
  }

  Future<void> _setShift(bool on, [StateSetter? setSheetState]) async {
    if (!mounted || _shiftBusy) return;
    void sync(VoidCallback fn) {
      if (mounted) setState(fn);
      setSheetState?.call(() {});
    }
    sync(() => _shiftBusy = true);
    bool accepted = _shifts?['terms_accepted'] == true;
    if (on && !accepted) {
      final ok = await showAppSheet<bool>(
        context,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.line, borderRadius: BorderRadius.circular(4)))),
          const SizedBox(height: 16),
          const Row(children: [
            Icon(Icons.schedule_outlined, color: AppColors.forest),
            SizedBox(width: 10),
            Expanded(child: Text('Sweep shift terms', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20))),
          ]),
          const SizedBox(height: 12),
          const Text(
            'By going ON SHIFT you agree to work the three pickup windows: 05:30–07:30 (06:00), 10:00–11:30 and 14:00–15:30 CAT. '
            'The next sweep’s orders (06:00 / 10:00 / 14:00) may be claimed at any time, even off shift; collection starts at 05:30 for the 06:00 sweep, or at 10:00 / 14:00. '
            'DropOff assignments stop outside these windows, when you switch OFF SHIFT, or between shifts — so you are free to do other rides then. '
            'You agree to meet the daily target of 30 parcels, or the monthly target across the month if the daily target is missed; pay and bonuses follow the payroll rules. '
            'Hand over every item only against the correct proof (code or photo). Keep location sharing on while on shift.',
            style: TextStyle(fontSize: 12.5, height: 1.45, color: AppColors.ink),
          ),
          const SizedBox(height: 20),
          Row(children: [
            Expanded(child: OutlinedButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel'))),
            const SizedBox(width: 10),
            Expanded(child: FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('I agree'))),
          ]),
        ]),
      );
      if (ok != true) {
        sync(() => _shiftBusy = false);
        return;
      }
      accepted = true;
    }
    final res = await DropOffApi.setRiderShifts(
      onShift: on,
      shifts: _selectedShifts.toList(),
      termsAccepted: accepted,
    );
    if (!mounted) return;
    sync(() => _shiftBusy = false);
    if (res.ok) {
      await _loadShifts();
      setSheetState?.call(() {});
      if (!mounted) return;
      AppToast.show(context, on ? 'You are ON SHIFT — DropOff jobs will flow in your sweeps.' : 'You are OFF SHIFT — other ride work is unrestricted.');
    } else {
      AppToast.show(context, 'Could not update shift. Check your connection and try again.');
    }
  }

  /// Compact App Bar control: status dot + ON/OFF. Full controls open in a
  /// bottom sheet — no vertical space is taken from the stats card.
  Widget _shiftPill() {
    final on = _shifts?['on_shift'] == true;
    final active = _shifts?['active_shift'] as String?;
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.white,
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
          builder: (sheetCtx) => StatefulBuilder(
            builder: (sheetCtx, setSheetState) => Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, MediaQuery.of(sheetCtx).viewInsets.bottom + 20),
              child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(color: AppColors.line, borderRadius: BorderRadius.circular(4))),
                Row(children: [
                  const Icon(Icons.schedule, color: AppColors.forest),
                  const SizedBox(width: 8),
                  const Expanded(child: Text('Sweep shifts', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17))),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(sheetCtx).pop()),
                ]),
                const SizedBox(height: 8),
                _shiftCard(setSheetState: setSheetState),
              ])),
            ),
          ),
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: on ? AppColors.forest.withValues(alpha: 0.10) : AppColors.line.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: on ? AppColors.forest.withValues(alpha: 0.35) : AppColors.line),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.circle, size: 8, color: on ? AppColors.success : AppColors.muted),
            const SizedBox(width: 4),
            Text(
              on ? (active != null ? 'ON $active' : 'ON') : 'OFF',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w900,
                color: on ? AppColors.forest : AppColors.muted,
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _shiftCard({StateSetter? setSheetState}) {
    final data = _shifts;
    final on = data?['on_shift'] == true;
    final active = data?['active_shift'] as String?;
    return Card(
      color: on ? AppColors.forest.withValues(alpha: 0.08) : AppColors.line.withValues(alpha: 0.12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.schedule, size: 18, color: on ? AppColors.forest : AppColors.muted),
            const SizedBox(width: 8),
            const Expanded(child: Text('Sweep shifts', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14))),
            if (active != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: AppColors.forest, borderRadius: BorderRadius.circular(12)),
                child: Text('ACTIVE · ${_shiftLabels[active] ?? active}',
                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900)),
              ),
          ]),
          const SizedBox(height: 6),
          const Text('Pickup windows (CAT). 06:00 opens at 05:30. Between them you are free to do other rides.',
              style: TextStyle(fontSize: 11, color: AppColors.muted)),
          const SizedBox(height: 8),
          Wrap(spacing: 6, children: [
            for (final entry in _shiftLabels.entries)
              FilterChip(
                label: Text(entry.value, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
                selected: _selectedShifts.contains(entry.key),
                onSelected: _shiftBusy ? null : (v) {
                  setState(() {
                    if (v) { _selectedShifts.add(entry.key); } else { _selectedShifts.remove(entry.key); }
                  });
                  setSheetState?.call(() {});
                },
              ),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: _shiftBusy ? null : () => _setShift(!on, setSheetState),
                icon: _shiftBusy
                    ? const AppLogoSpinner(size: 15)
                    : Icon(on ? Icons.pause_circle_outline : Icons.play_circle_outline),
                label: Text(_shiftBusy ? 'Saving' : (on ? 'Go off shift' : 'Go on shift')),
              ),
            ),
          ]),
          if (data == null)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text('Shift settings unavailable offline — showing your last known choice.',
                  style: TextStyle(fontSize: 10.5, color: AppColors.muted)),
            ),
        ]),
      ),
    );
  }

  /// RING + WAKE (owner 2026-11-20): when NEW jobs appear in the queue,
  /// vibrate the phone and keep the screen awake so the rider sees a new
  /// order even with the phone idle — the worker's FCM push is the loudest
  /// alert, but the queue screen catching one alerts the rider immediately.
  Future<void> _triggerSos() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Send SOS?'),
        content: const Text(
          'This alerts every other DropOff rider with your location and asks for help. '
          'Only use in a real emergency.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Send SOS'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final pos = _riderPos;
    final res = await DropOffApi.riderSos(
      lat: pos?.latitude,
      lng: pos?.longitude,
    );
    if (!mounted) return;
    if (res.ok) {
      AppToast.show(context, 'SOS sent to ${res.body['alerted'] ?? 'all'} riders. Help is on the way.');
    } else {
      AppToast.error(context, 'Could not send SOS - check your connection and try again.');
    }
  }

  Future<void> _ringForNewJobs(dynamic batches) async {
    if (!mounted) return;
    final refs = <String>{};
    for (final b in (batches as List?) ?? const <dynamic>[]) {
      for (final s in ((b as Map<String, dynamic>)['stops'] as List?) ?? const <dynamic>[]) {
        refs.add('${(s as Map)['ref'] ?? ''}');
      }
    }
    refs.remove('');
    final newRefs = refs.where((r) => !_alarmSeenRefs.contains(r)).toList();
    _alarmSeenRefs.addAll(refs);
    // Cold start: adopt the current queue silently; only genuinely NEW refs ring.
    if (!_alarmPrimed) {
      _alarmPrimed = true;
      return;
    }
    if (newRefs.isEmpty) return;
    final navigator = Navigator.of(context);
    HapticFeedback.heavyImpact();
    final first = newRefs.first;
    Map<String, dynamic>? detail;
    for (final b in batches ?? const <dynamic>[]) {
      for (final s in ((b as Map<String, dynamic>)['stops'] as List?) ?? const <dynamic>[]) {
        if ('${(s as Map)['ref'] ?? ''}' == first) {
          detail = Map<String, dynamic>.from(s);
          break;
        }
      }
    }
    unawaited(OrderAlert.start(
      ref: first,
      title: 'New delivery assigned',
      body: 'Job $first — ${detail?['pickup_address'] ?? 'open your Task Queue'}',
      address: '${detail?['pickup_address'] ?? ''}',
      eta: '${detail?['eta_minutes'] ?? ''}',
      fee: '${detail?['rider_fee_zmw'] ?? ''}',
    ));
    await WakelockPlus.enable();
    Future<void>.delayed(_alarmWindow, () async => await WakelockPlus.disable());
    if (_alertRef == first) return;
    _alertRef = first;
    await navigator.push(MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => IncomingOrderScreen(jobRef: first, detail: detail),
    ));
    _alertRef = null;
  }

  /// Leftovers after automated dispatch. Refreshed with the queue — a claim by
  /// another rider removes the card here too (server-side exclusivity).
  Future<void> _loadAvailable() async {
    final data = await DropOffApi.riderAvailable();
    if (!mounted) return;
    setState(() {
      _available = ((data?['jobs'] as List?) ?? const []).cast<Map<String, dynamic>>();
      _availableHint = data?['hint'] as String?;
    });
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
      AppToast.error(context, 'This item is waiting for the sender\'s prepayment.');
      return;
    }
    AppToast.error(context, switch (res.error) { 'at_capacity' => 'You are at capacity - finish a stop first.', 'payment_required' => 'Prepayment is still pending for this job.', _ => 'Could not claim this job - check your connection.' });
  }

  /// Auto-name a depot dropoff point (Waze-style growing location): reverse
  /// geocode the rider's current position and save it as a shared community
  /// POI so every rider in the city sees it on the map.
  Future<String?> _autoNameDepotPoi(String ref) async {
    try {
      final pos = _riderPos;
      if (pos == null) return null;
      var name = await MapServices.reverse(LatLng(pos.latitude, pos.longitude));
      if (name == null || name.trim().isEmpty) {
        // Manual fallback: ask the rider to name the dropoff point.
        if (!mounted) return null;
        name = await showDialog<String>(
          context: context,
          builder: (ctx) {
            final ctrl = TextEditingController();
            return AlertDialog(
              title: const Text('Name this dropoff point?'),
              content: TextField(
                controller: ctrl,
                decoration: const InputDecoration(
                  hintText: 'e.g. Kabwata Market, Mercury Kabulonga',
                  border: OutlineInputBorder(),
                ),
                autofocus: true,
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Skip')),
                FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('Save')),
              ],
            );
          },
        );
        if (name == null || name.trim().isEmpty) return null;
      }
      const city = 'Lusaka';
      await DropOffApi.saveCommunityPoi(
        name: name,
        city: city,
        lat: pos.latitude,
        lng: pos.longitude,
      );
      return name;
    } catch (_) {
      // Best-effort: never fail the depot drop because of POI naming.
      return null;
    }
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
      // Re-entrant on resume: cancel the old stream first so fixes to GPS
      // permission actually take effect and we never double-subscribe.
      await _posSub?.cancel();
      _posSub = null;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        if (!mounted) return;
        setState(() => _gpsIssue = 'permission');
        return;
      }
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (!mounted) return;
        setState(() => _gpsIssue = 'service');
        return;
      }
      if (mounted && _gpsIssue != null) setState(() => _gpsIssue = null);
      _posSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 12),
      ).listen(_onPosition);
      // Prime an immediate ping so a rider who just granted permission is
      // dispatchable right away instead of waiting for the first movement.
      try {
        final cur = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
        );
        if (mounted) _onPosition(cur);
      } catch (_) { /* stream will deliver the next fix */ }
    } catch (_) {
      // Arrival detection is a bonus — the rider can always tap arrived, but
      // surface a recoverable banner rather than failing silently.
      if (mounted) setState(() => _gpsIssue = 'service');
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
  // photograph every item exactly once; depot drops need the depot's own
  // receipt photos; door deliveries (last-mile/collection jobs only) require
  // the recipient's 4-digit DropOff code.

  /// CAMERA-ONLY capture for pickup item photos (owner directive
  /// 2026-11-17: "no repeat capture" — a gallery pick could re-file an old
  /// photo, so collection evidence is captured live, one photo per picked-up item).
  Future<String?> _captureParcelPhoto() async {
    try {
      final picked = await ImagePicker().pickImage(source: ImageSource.camera, maxWidth: 1600, imageQuality: 82);
      if (picked == null || !mounted) return null;
      final bytes = await picked.readAsBytes();
      DateTime? capturedAt;
      try { capturedAt = await picked.lastModified(); } catch (_) {}
      if (!mounted) return null;
      final res = await ProofUploadOverlay.run(
        context,
        title: 'Securing item photo',
        task: DropOffApi.uploadImage(bytes, picked.name.isNotEmpty ? picked.name : 'pickup.jpg', kind: 'kyc', capturedAt: capturedAt),
      );
      if (!mounted) return null;
      if (!res.ok) {
        AppToast.show(context, 'Photo upload failed. Check your connection and try the capture again.');
        return null;
      }
      final url = '${res.body['url'] ?? ''}'.trim();
      if (url.isEmpty) {
        AppToast.show(context, 'Photo upload failed. Check your connection and try the capture again.');
        return null;
      }
      return url;
    } catch (_) {
      if (mounted) AppToast.show(context, 'Could not capture the item photo. Check camera permission and try again.');
      return null;
    }
  }

  Future<String?> _pickPodPhoto() async {
    // CAMERA-ONLY (owner audit 2026-11-21): handover and depot-receipt proof
    // must be captured live. A gallery pick could re-file an old photo, which
    // is exactly what the pickup evidence policy forbids.
    try {
      final picked = await ImagePicker().pickImage(source: ImageSource.camera, maxWidth: 1600, imageQuality: 82);
      if (picked == null || !mounted) return null;
      final bytes = await picked.readAsBytes();
      DateTime? capturedAt;
      try { capturedAt = await picked.lastModified(); } catch (_) {}
      if (!mounted) return null;
      final res = await ProofUploadOverlay.run(
        context,
        title: 'Securing proof photo',
        task: DropOffApi.uploadImage(bytes, picked.name.isNotEmpty ? picked.name : 'proof.jpg', kind: 'kyc', capturedAt: capturedAt),
      );
      if (!mounted) return null;
      if (!res.ok) {
        AppToast.show(context, 'Proof photo did not upload - check your connection and retake it.');
        return null;
      }
      final url = '${res.body['url'] ?? ''}'.trim();
      if (url.isEmpty) {
        AppToast.show(context, 'Proof photo did not upload - check your connection and retake it.');
        return null;
      }
      return url;
    } catch (_) {
      if (mounted) AppToast.show(context, 'Could not capture the proof photo. Check camera permission and try again.');
      return null;
    }
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
    final kind = '${s['kind'] ?? ''}';
    final isDepotAction = kind == 'depot_drop' || kind == 'depot_drop_group';
    final picked = isDepotAction ? true : _picked('${s['status'] ?? ''}');
    // COLLECTION jobs run DEPOT → RECIPIENT (the reverse of a drop-off). The
    // first leg is the courier counter where the item is already waiting;
    // only after the pickup does the rider head to the recipient's door.
    final isCollection = '${s['service'] ?? ''}' == 'collection';
    // A DELIVERY stop (standard last-mile OR collection handover) goes to the
    // recipient's door. Its saved pickup_lat/lng belong to the SENDER, never
    // the door — leave them null so the typed dest_address is geocoded.
    final isDelivery = !isDepotAction && kind == 'delivery';
    final double? lat;
    final double? lng;
    if (isDelivery) {
      lat = null;
      lng = null;
    } else if (picked) {
      lat = isCollection ? null : (s['depot_lat'] as num?)?.toDouble() ?? (s['lat'] as num?)?.toDouble();
      lng = isCollection ? null : (s['depot_lng'] as num?)?.toDouble() ?? (s['lng'] as num?)?.toDouble();
    } else {
      lat = (s['pickup_lat'] as num?)?.toDouble() ?? (s['lat'] as num?)?.toDouble();
      lng = (s['pickup_lng'] as num?)?.toDouble() ?? (s['lng'] as num?)?.toDouble();
    }
    final addr = '${s['address'] ?? ''}'.trim();
    // "To Platinum" / "To Icypeed" (owner 2026-11-18): the depot leg is named
    // by the DEPOT, not a generic "depot" — stop rows carry `depot` now.
    final depotName = '${s['depot'] ?? s['courier'] ?? 'DropOff'}'.trim();
    final senderName = '${s['seller'] ?? ''}'.trim();
    final label = isDelivery
        ? 'Deliver to ${'${s['recipient'] ?? 'recipient'}'}'
        : isCollection
            ? (picked
                ? 'Deliver to ${'${s['recipient'] ?? 'recipient'}'}'
                : '$depotName depot — collect the item')
            : (picked
                ? '$depotName depot'
                : (senderName.isNotEmpty ? '$senderName — $addr' : '${s['ref'] ?? 'Stop'} — $addr').trim());
    // Whole-job context on the map (owner 2026-11-18 "fix the rider map just
    // like the sender map tracking"): heading to the sender shows the depot
    // pin too, heading to the depot shows the sender's stop too.
    //
    // COLLECTION (owner directive 2026-11-20: "on collection the depot pin
    // remove it, only when handover"): the depot is the item's ORIGIN, not
    // a place to navigate to — no depot context pin is drawn on a collection
    // at any stage. The only pin is the leg destination (depot counter first,
    // recipient door at handover).
    final otherLat = isCollection
        ? null
        : isDelivery
            ? (s['depot_lat'] as num?)?.toDouble()
            : (picked
                ? (s['pickup_lat'] as num?)?.toDouble() ?? (s['lat'] as num?)?.toDouble()
                : (s['depot_lat'] as num?)?.toDouble());
    final otherLng = isCollection
        ? null
        : isDelivery
            ? (s['depot_lng'] as num?)?.toDouble()
            : (picked
                ? (s['pickup_lng'] as num?)?.toDouble() ?? (s['lng'] as num?)?.toDouble()
                : (s['depot_lng'] as num?)?.toDouble());
    if (lat != null && lng != null) {
      // Re-bind to non-null finals: Dart cannot promote a nullable local that
      // was assigned in branches once it is captured by this builder closure.
      final dLat = lat, dLng = lng;
      Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => InAppNavigatorScreen(
          destLat: dLat,
          destLng: dLng,
          label: label,
          destIsDepot: isDelivery ? false : isCollection ? !picked : picked,
          otherLat: otherLat,
          otherLng: otherLng,
          otherIsDepot: isDelivery ? true : isCollection ? picked : !picked,
          vehicleClass: '${s['vehicle_class'] ?? 'motorcycle'}',
        ),
      ));
      return;
    }
    // No pin on the booking — geocode the typed address OURSELVES and keep
    // the rider inside the DropOff navigator.
    final doorAddr = '${s['dest_address'] ?? ''}'.trim();
    final doorCity = '${s['dest_city'] ?? ''}'.trim();
    final query = isDelivery
        ? '$doorAddr${doorCity.isNotEmpty ? ', $doorCity' : ''}'.trim()
        : isCollection
            ? (picked
                ? (doorAddr.isEmpty
                    ? '$depotName depot ${s['from_city'] ?? ''}'.trim()
                    : doorAddr)
                : '$depotName depot ${s['from_city'] ?? ''}'.trim())
            : (picked
                ? '$depotName depot ${s['from_city'] ?? ''}'.trim()
                : '$addr${'${s['from_city'] ?? ''}'.trim().isNotEmpty ? ', ${s['from_city']}' : ''}'.trim());
    // The destination city is ALWAYS known from the booking, so even a total
    // geocoder outage can open the in-app navigator at a clearly-labelled
    // approximate point. Never dead-end on a toast (owner 2026-11-23).
    final targetCity = isDelivery
        ? doorCity
        : isCollection
            ? (picked ? doorCity : '${s['from_city'] ?? ''}'.trim())
            : '${s['from_city'] ?? ''}'.trim();
    final anchor = cityCoords[targetCity.toLowerCase()] ??
        cityCoords['lusaka'] ?? (-15.4255, 28.2805);
    void openApprox() {
      if (!mounted) return;
      Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => InAppNavigatorScreen(
          destLat: anchor.$1, destLng: anchor.$2,
          label: label,
          destIsDepot: isDelivery ? false : isCollection ? !picked : picked,
          approximateLocation: true,
          otherLat: otherLat, otherLng: otherLng,
          otherIsDepot: isDelivery ? true : isCollection ? picked : !picked,
          vehicleClass: '${s['vehicle_class'] ?? 'motorcycle'}',
        ),
      ));
    }
    if (query.isEmpty) {
      _snack('No street address on the booking — opening $targetCity centre as an approximate point.');
      openApprox();
      return;
    }
    // Toast wording (owner 2026-11-18): say WHAT is being located and that the
    // DropOff map is doing it — a raw geocoder query reads like an error.
    _snack(isDelivery || (isCollection && picked)
        ? 'Finding the recipient door on the DropOff map…'
        : isCollection
            ? 'Finding the $depotName depot on the DropOff map…'
            : picked
                ? 'Finding the $depotName depot on the DropOff map…'
                : 'Finding the pickup point on the DropOff map…');
    final hits = await MapServices.search(query);
    if (!mounted) return;
    if (hits.isNotEmpty) {
      final hit = hits.first;
      Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => InAppNavigatorScreen(
          destLat: hit.point.latitude,
          destLng: hit.point.longitude,
          label: label,
          destIsDepot: isDelivery ? false : isCollection ? !picked : picked,
          otherLat: otherLat,
          otherLng: otherLng,
          otherIsDepot: isDelivery ? true : isCollection ? picked : !picked,
          vehicleClass: '${s['vehicle_class'] ?? 'motorcycle'}',
        ),
      ));
      return;
    }
    // Collection rescue: before pickup the destination really IS the depot,
    // so its own pin is a safe fallback when the name geocode misses. After
    // pickup the destination is the recipient's door — the depot pin must
    // never be offered as the handover destination (owner 2026-11-20).
    final fbLatD = isCollection && !picked ? (s['depot_lat'] as num?)?.toDouble() : null;
    final fbLngD = isCollection && !picked ? (s['depot_lng'] as num?)?.toDouble() : null;
    if (isCollection && fbLatD != null && fbLngD != null && (fbLatD.abs() + fbLngD.abs()) > 0) {
      Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => InAppNavigatorScreen(
          destLat: fbLatD, destLng: fbLngD, label: label,
          destIsDepot: true, otherLat: null, otherLng: null, otherIsDepot: false,
          vehicleClass: '${s['vehicle_class'] ?? 'motorcycle'}',
        ),
      ));
      return;
    }
    // Geocoder missed (or Photon was unreachable). Try a CITY-ONLY query once
    // more, then fall back to the known city centre — still inside DropOff's
    // map, with an honest "approximate" badge. Never leave the rider staring
    // at a toast with no map (owner 2026-11-23).
    if (targetCity.isNotEmpty && targetCity.toLowerCase() != query.toLowerCase()) {
      final cityHits = await MapServices.search(targetCity);
      if (!mounted) return;
      if (cityHits.isNotEmpty) {
        final hit = cityHits.first;
        Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => InAppNavigatorScreen(
            destLat: hit.point.latitude, destLng: hit.point.longitude,
            label: label, approximateLocation: true,
            destIsDepot: isDelivery ? false : isCollection ? !picked : picked,
            otherLat: otherLat, otherLng: otherLng,
            otherIsDepot: isDelivery ? true : isCollection ? picked : !picked,
            vehicleClass: '${s['vehicle_class'] ?? 'motorcycle'}',
          ),
        ));
        return;
      }
    }
    _snack('Exact pin unavailable — opening $targetCity centre as an approximate point.');
    openApprox();
  }

  /// Full-screen proof-of-payment receipt — the rider shows this at the
  /// courier counter to collect the goods. Pinch to zoom, tap to close.
  void _showCollectionReceipt(String url, {String ref = ''}) {
    if (url.isEmpty) return;
    // Absolute paths (/media/...) get the API host; already-absolute URLs are
    // used as-is so a CDN/legacy receipt never becomes "host/media/https://…".
    final uri = url.startsWith('http') ? url : '${DropOffApi.baseUrl}$url';
    Navigator.of(context).push<void>(MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          // Bounded + two lines: the old single-line title was clipped to
          // "Receipt - show at the depot cou..." on narrow phones.
          title: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width - 110),
            child: const Text(
              'Receipt — show at the depot counter',
              maxLines: 2,
              softWrap: true,
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, height: 1.2),
            ),
          ),
          // Screenshots are blocked app-wide; sharing is an explicit file
          // export instead (owner 2026-11-23).
          actions: [
            IconButton(
              tooltip: 'Download / share receipt',
              icon: const Icon(Icons.ios_share),
              onPressed: () => ReceiptViewer.share(context, uri, ref),
            ),
          ],
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: FilledButton.icon(
              onPressed: () => ReceiptViewer.share(context, uri, ref),
              icon: const Icon(Icons.ios_share, size: 17),
              label: const Text('Download & share receipt'),
            ),
          ),
        ),
        body: InteractiveViewer(
          maxScale: 5,
          child: Center(
            child: Image.network(
              uri,
              headers: DropOffApi.authHeaders,
              fit: BoxFit.contain,
              loadingBuilder: (_, child, progress) =>
                  progress == null ? child : const AppLogoSpinner(size: 34, color: Colors.white),
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
    final kind = '${s['kind'] ?? ''}';
    final refs = ((s['refs'] as List?) ?? [ref]).map((e) => '$e').where((e) => e.isNotEmpty).toList();
    if (kind == 'depot_drop' || kind == 'depot_drop_group') {
      await _depotDropGroupSheet(s, refs);
      return;
    }
    final lastMile = (s['last_mile'] as num?)?.toInt() ?? 0;
    final parcels = (s['parcels'] as num?)?.toInt() ?? 1;
    // A collection runs DEPOT → RECIPIENT and a delivery stop always ends at
    // the door. Their `last_mile` field may still be 0, so never show them a
    // second "drop at the depot" step — that dead-ended the handover.
    final doorHandover = lastMile == 1 || kind == 'delivery' || '${s['service'] ?? ''}' == 'collection';
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
                    ? const AppLogoSpinner(size: 18)
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
              // over. Then the rider photographs every picked-up item.
              if ('${s['service'] ?? ''}' == 'collection' && '${s['collection_receipt_url'] ?? ''}'.isNotEmpty) ...[
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: OutlinedButton.icon(
                    onPressed: () => _showCollectionReceipt('${s['collection_receipt_url']}', ref: '${s['ref'] ?? ''}'),
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
                        ? 'Show the payment receipt, then photograph every picked-up item ($parcels)'
                        : 'Sender\'s 4-digit code + one camera photo per picked-up item ($parcels)',
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
              if (!doorHandover)
                step(
                  done: dropped,
                  unlocked: picked,
                  icon: Icons.inventory_2_outlined,
                  title: 'Dropped at the depot branch',
                  subtitle: dropped ? 'Filed' : !picked ? 'Locked - pick up first' : 'Item photos + every depot receipt and amount',
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
              if (doorHandover)
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
              if (!doorHandover)
                const Padding(padding: EdgeInsets.fromLTRB(14, 2, 14, 0), child: Text(
                  'The courier carries your items the rest of the way from the depot.',
                  style: TextStyle(fontSize: 11, color: AppColors.muted, height: 1.35))),
              const Divider(height: 16),
              // ORDER WAYBILL (owner 2026-11-18): the rider's read-only copy of
              // the full order sheet — contacts, both addresses, depot,
              // items — no money fields. Available any time on this stop.
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
              // TRANSFER (owner 2026-11-21): hand this stop to another rider
              // before pickup. The worker updates every rider-facing surface.
              if (!dropped && st != 'ready_for_collection')
                ListTile(
                  enabled: _busyRef == null,
                  leading: const Icon(Icons.swap_horiz_outlined, color: AppColors.forest),
                  title: const Text('Transfer this ride',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                  subtitle: const Text('Hand this trip to another active rider',
                      style: TextStyle(fontSize: 12)),
                  onTap: () => _transferStop(s),
                ),
              // RESEND (owner 2026-11-18): the sender's booking SMS may never
              // have landed — without the 4-digit code the pickup can never be
              // verified. One tap re-fires a FRESH code to both phones.
              if (!picked && !isCollection)
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
    final word = words.isEmpty ? 'item' : words.first.toLowerCase();
    return '${kind[0].toUpperCase()}${kind.substring(1).toLowerCase()} — $word';
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
    // LOCK THE WHOLE STEP (owner audit 2026-11-21): _busyRef was only ever
    // cleared, never set, so the spinners and enabled checks were dead and a
    // double-tap could re-file a step. The sheet handler clears it on return.
    setState(() => _busyRef = ref);
    final parcels = (s['parcels'] as num?)?.toInt() ?? 1;
    final senderName = '${s['seller'] ?? ''}'.trim();
    final senderPhone = '${s['seller_phone'] ?? ''}'.trim();
    // COLLECTIONS (owner audit 2026-11-21): the parcel is already at the
    // depot. No sender and NO sender pickup PIN exist — the worker only mints
    // a door code for collections. Demanding a 4-digit sender code here was
    // a hard dead end at the depot counter.
    final isCollection = '${s['service'] ?? ''}' == 'collection';
    final otpCtrl = TextEditingController();
    final photos = <String>[];
    String? inlineError;
    String? lastErrCode; // the rejected-code errors unlock the resend helper
    bool resending = false;
    bool submitting = false;
    // Verify the PIN SERVER-SIDE as the code is completed. Only a real match
    // ticks the checklist and unlocks photo capture (owner 2026-11-23).
    var pinState = isCollection ? _PinCheck.notNeeded : _PinCheck.idle;
    Timer? pinDebounce;
    final res = await showModalBottomSheet<ApiResponse>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (dctx) => StatefulBuilder(
        builder: (dctx, setDialog) {
          final photoDone = photos.length >= parcels;
          final pinDone = pinState == _PinCheck.ok || pinState == _PinCheck.notNeeded;

          Future<void> verifyPin(String code) async {
            if (code.length != 4) {
              setDialog(() => pinState = _PinCheck.idle);
              return;
            }
            setDialog(() => pinState = _PinCheck.checking);
            final r = await DropOffApi.verifyPin(ref, code, 'pickup');
            if (!dctx.mounted) return;
            if (r.ok) {
              setDialog(() => pinState = r.body['needed'] == true ? _PinCheck.ok : _PinCheck.notNeeded);
              return;
            }
            final err = r.error ?? '';
            final detail = (r.body['detail'] as String?)?.trim() ?? '';
            setDialog(() {
              switch (err) {
                case 'not_needed':
                  // Job already moved past pickup or no code was ever minted.
                  pinState = _PinCheck.notNeeded;
                  lastErrCode = err;
                  inlineError = null;
                case 'network_error' || 'offline_demo_mode':
                  // NEVER call an unverifiable code "verified" — leave it
                  // unchecked and ask for a retry (owner 2026-11-23).
                  pinState = _PinCheck.idle;
                  inlineError = 'Could not reach DropOff to check the code. Try again.';
                case 'otp_locked':
                  pinState = _PinCheck.locked;
                  lastErrCode = err;
                  inlineError = detail.isNotEmpty ? detail : 'Too many wrong codes — contact DropOff support.';
                default:
                  pinState = _PinCheck.wrong;
                  lastErrCode = err;
                  inlineError = detail.isNotEmpty ? detail : 'That code did not match — ask the sender to read their SMS again.';
              }
            });
          }

          return SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + MediaQuery.of(dctx).viewInsets.bottom),
              child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.line, borderRadius: BorderRadius.circular(4)))),
                  const SizedBox(height: 14),
                  Row(children: [
                    Container(
                      width: 44, height: 44,
                      decoration: BoxDecoration(color: AppColors.forest.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                      child: Icon(isCollection ? Icons.warehouse_outlined : Icons.inventory_2_outlined, color: AppColors.forest),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(_handoverTitle(s, isCollection ? 'COLLECT' : 'PICKUP'), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 22, letterSpacing: -0.2)),
                      Text(isCollection ? 'Collect at the depot counter' : 'Confirm sender PIN and capture proof', style: const TextStyle(fontSize: 12.5, color: AppColors.muted)),
                    ])),
                  ]),
                  const SizedBox(height: 14),
                  _sheetChecklist([
                    _SheetCheck(
                      label: isCollection ? 'Depot collection' : 'Sender PIN verified',
                      done: pinDone,
                      detail: isCollection
                          ? 'No sender PIN needed at depot counter'
                          : switch (pinState) {
                              _PinCheck.ok => 'Code matched on DropOff server',
                              _PinCheck.notNeeded => 'No PIN required for this booking',
                              _PinCheck.checking => 'Checking code with DropOff…',
                              _PinCheck.wrong => 'Code did not match — ask the sender again',
                              _PinCheck.locked => 'Too many wrong codes — contact support',
                              _ => 'Ask ${senderName.isEmpty ? 'the sender' : senderName} for the 4-digit code',
                            }),
                    _SheetCheck(label: 'Item photos captured', done: photoDone, detail: '${photos.length}/$parcels photo${parcels == 1 ? '' : 's'}'),
                  ]),
                  const SizedBox(height: 14),
                  if (isCollection)
                    _sheetInfoCard(icon: Icons.receipt_long_outlined, title: 'Collection check', message: 'Show the sender\'s payment receipt, then photograph every item you pick up before leaving the counter.')
                  else ...[
                    _sheetSection('Sender PIN'),
                    const SizedBox(height: 8),
                    Text('Get the 4-digit PICKUP PIN from: ${senderName.isEmpty ? 'the sender' : senderName}${senderPhone.isNotEmpty ? ' · $senderPhone' : ''}',
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: AppColors.forest, height: 1.35)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: otpCtrl,
                      keyboardType: TextInputType.number,
                      maxLength: 4,
                      autofocus: true,
                      onChanged: (v) {
                        pinDebounce?.cancel();
                        final code = v.trim();
                        if (code.length != 4) {
                          setDialog(() => pinState = _PinCheck.idle);
                          return;
                        }
                        pinDebounce = Timer(const Duration(milliseconds: 350), () => unawaited(verifyPin(code)));
                      },
                      decoration: InputDecoration(
                        counterText: '',
                        labelText: '4-digit pickup code (from the SENDER)',
                        border: const OutlineInputBorder(),
                        suffixIcon: switch (pinState) {
                          _PinCheck.checking => const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))),
                          _PinCheck.ok => const Icon(Icons.verified, color: AppColors.forest),
                          _PinCheck.wrong || _PinCheck.locked => const Icon(Icons.error_outline, color: AppColors.danger),
                          _ => null,
                        },
                      ),
                    ),
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerRight,
                      child: OutlinedButton.icon(
                        onPressed: pinState == _PinCheck.checking || otpCtrl.text.trim().length != 4
                            ? null
                            : () {
                                pinDebounce?.cancel();
                                unawaited(verifyPin(otpCtrl.text.trim()));
                              },
                        icon: const Icon(Icons.verified_user_outlined, size: 15),
                        label: const Text('Verify code with DropOff'),
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  _sheetSection('Proof photos'),
                  const SizedBox(height: 6),
                  Text('Photograph each of the $parcels item${parcels == 1 ? '' : 's'} once (camera only, time-stamped).',
                      style: const TextStyle(fontSize: 12.5, color: AppColors.muted, height: 1.35)),
                  const SizedBox(height: 8),
                  if (photos.isNotEmpty)
                    SizedBox(
                      height: 84,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: photos.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (_, i) => GestureDetector(
                          onTap: () => ReceiptViewer.show(context, path: photos[i], title: 'Item photo ${i + 1}', shareTooltip: 'Download / share photo', shareLabel: 'Download & share photo'),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: ColoredBox(color: AppColors.line.withValues(alpha: 0.18), child: AuthedImage(photos[i], fit: BoxFit.contain, width: 84, height: 84)),
                          ),
                        ),
                      ),
                    ),
                  if (photos.length < parcels)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.camera_alt_outlined, size: 18),
                        label: Text('Capture item ${photos.length + 1} of $parcels'),
                        // PIN first, THEN capture (owner 2026-11-23): no photo
                        // until the server says the sender's code matched.
                        onPressed: submitting || !pinDone ? null : () async {
                          final url = await _captureParcelPhoto();
                          if (url != null) setDialog(() { photos.add(url); inlineError = null; });
                        },
                      ),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Row(children: [
                        const Icon(Icons.check_circle, size: 16, color: AppColors.forest),
                        const SizedBox(width: 6),
                        Expanded(child: Text('All $parcels picked-up items photographed — locked.', style: const TextStyle(fontSize: 12, color: AppColors.forest, fontWeight: FontWeight.w700))),
                      ]),
                    ),
                  if (inlineError != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: AppColors.danger.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.danger.withValues(alpha: 0.2))),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(inlineError!, style: const TextStyle(fontSize: 12.5, color: AppColors.danger, height: 1.35, fontWeight: FontWeight.w600)),
                        if (!isCollection && !resending && (lastErrCode == 'otp_required' || lastErrCode == 'otp_locked'))
                          TextButton.icon(
                            icon: const Icon(Icons.sms_outlined, size: 16),
                            label: const Text('Sender never got the SMS? Resend a fresh code', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                            onPressed: () async {
                              setDialog(() => resending = true);
                              final msg = await _resendPinCode(ref);
                              if (!dctx.mounted) return;
                              setDialog(() { resending = false; inlineError = msg; });
                            },
                          ),
                        if (resending) const Padding(padding: EdgeInsets.only(top: 4), child: AppLogoSpinner(size: 16)),
                      ]),
                    ),
                  ],
                  const SizedBox(height: 20),
                  Row(children: [
                    Expanded(child: OutlinedButton(onPressed: submitting ? null : () => Navigator.pop(dctx, null), child: const Text('Cancel'))),
                    const SizedBox(width: 10),
                    Expanded(child: FilledButton(
                      onPressed: submitting ? null : () async {
                        final code = otpCtrl.text.trim();
                        if (!isCollection && !pinDone) {
                          setDialog(() => inlineError = pinState == _PinCheck.checking
                              ? 'Still checking the sender\'s code with DropOff…'
                              : 'Enter the sender\'s 4-digit pickup code — it must match before pickup.');
                          return;
                        }
                        if (photos.length < parcels) {
                          setDialog(() => inlineError = 'Photograph each picked-up item once — ${parcels - photos.length} more photo${parcels - photos.length == 1 ? '' : 's'} to take.');
                          return;
                        }
                        submitting = true;
                        setDialog(() {});
                        final r = await DropOffApi.jobEvent(
                          jobRef: ref, status: 'picked_up',
                          otp: isCollection || code.length != 4 ? null : code,
                          photoUrl: photos.first, stage: 'pickup',
                          parcelPhotos: photos,
                          lat: _riderPos?.latitude, lng: _riderPos?.longitude,
                        );
                        if (!dctx.mounted) return;
                        if (r.ok || r.error == 'already_picked_up') {
                          Navigator.pop(dctx, r.ok ? r : const ApiResponse(ok: true));
                          return;
                        }
                        submitting = false;
                        final err = r.error ?? '';
                        final detail = (r.body['detail'] as String?) ?? '';
                        await StepSounds.stepError();
                        setDialog(() {
                          inlineError = switch (err) {
                            'otp_required' => 'Code rejected. ${detail.isEmpty ? 'The code is in the sender\'s booking SMS.' : detail}',
                            'otp_locked' => 'Too many wrong codes — DropOff support has been notified.',
                            'photo_required' => detail.isEmpty ? 'Photograph every picked-up item before filing.' : detail,
                            'photo_locked' => 'Pickup photo already on file for $ref — the evidence is locked. Contact DropOff support for a correction.',
                            _ => 'Could not file the pickup. Check your connection and try again.',
                          };
                          lastErrCode = err;
                        });
                      },
                      child: submitting ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Confirm pickup'),
                    )),
                  ]),
                ]),
              ),
            ),
          );
        },
      ),
    );
    if (res == null) return null;
    if (res.ok) {
      await _snack('$ref - picked up');
      await StepSounds.stepDone(); // step-complete chime (owner request 2026-11-20)
      AnalyticsService.instance.track(feature: 'rider', action: 'picked_up', context: 'sender_stop');
      _load();
    }
    return res;
  }

  /// Depot drop with the counter-receipt kit (owner directive 2026-11-12):
  /// photograph EVERY item in the batch, and file EVERY depot receipt the
  /// depot wrote — each photographed, each with the EXACT amount written on
  /// it. A submitted receipt is a single, exact, photographed document, never
  /// a rider-computed sum; the SERVER totals the receipts. The rider fronts
  /// the fare with their own money; DropOff reimburses it fee-free the moment
  /// the sender pays.
  Future<void> _depotDropGroupSheet(Map<String, dynamic> s, List<String> refs) async {
    final depotName = '${s['depot'] ?? s['courier'] ?? 'depot'}'.trim();
    final items = ((s['items'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final done = <String>{
      for (final it in items)
        if (['delivered', 'at_depot'].contains('${it['status'] ?? ''}')) '${it['ref'] ?? ''}'
    }..remove('');
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: StatefulBuilder(builder: (ctx, setSheet) {
          final remaining = refs.where((r) => !done.contains(r)).toList();
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Depot drop — $depotName', style: AppType.subhead),
              const SizedBox(height: 6),
              Text(
                remaining.isEmpty
                    ? 'All items for this depot have been filed.'
                    : 'Drop each order at this depot. File proof for one order at a time — no interleaving between depots.',
                style: const TextStyle(fontSize: 12.5, color: AppColors.muted, height: 1.35),
              ),
              const SizedBox(height: 12),
              ...refs.map((r) {
                final it = items.cast<Map<String, dynamic>?>().firstWhere((e) => '${e?['ref'] ?? ''}' == r, orElse: () => null);
                final isDone = done.contains(r) || ['delivered', 'at_depot'].contains('${it?['status'] ?? ''}');
                final busy = _busyRef == r;
                final label = '${it?['seller'] ?? ''}'.trim().isNotEmpty ? '$r · ${it?['seller']}' : r;
                final detail = '${it?['description'] ?? ''}'.trim();
                // Stacked layout, never a ListTile: a trailing button inside a
                // ListTile competes with the title for width and can crush the
                // label into a vertical one-character-per-line ribbon on small
                // phones. Text owns full width; the button gets its own row.
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                  decoration: BoxDecoration(
                    color: AppColors.line.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.line),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Icon(isDone ? Icons.check_circle : Icons.inventory_2_outlined, size: 20, color: isDone ? AppColors.forest : AppColors.muted),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            softWrap: false,
                            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: isDone ? AppColors.muted : AppColors.ink)),
                      ),
                    ]),
                    const SizedBox(height: 4),
                    Text(
                      isDone ? 'Depot drop filed' : (detail.isNotEmpty ? detail : 'File parcel photo and depot receipt'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11.5, color: AppColors.muted, height: 1.35),
                    ),
                    const SizedBox(height: 10),
                    if (busy)
                      const Center(child: AppLogoSpinner(size: 18))
                    else if (isDone)
                      const Row(children: [
                        Icon(Icons.lock, size: 14, color: AppColors.muted),
                        SizedBox(width: 6),
                        Text('Filed — locked', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.muted)),
                      ])
                    else
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: _busyRef != null ? null : () async {
                            final res = await _depotDropWithReceipt(r);
                            if (!mounted) return;
                            setState(() => _busyRef = null);
                            if (res != null && res.ok) {
                              setSheet(() => done.add(r));
                              _load();
                            }
                          },
                          child: const Text('File drop', maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis),
                        ),
                      ),
                  ]),
                );
              }),
              if (remaining.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: SizedBox(width: double.infinity, child: FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Done'))),
                ),
            ]),
          );
        }),
      ),
    );
  }

  Future<ApiResponse?> _depotDropWithReceipt(String ref) async {
    if (_busyRef != null) return null;
    if (!mounted) return null;
    setState(() => _busyRef = ref); // one step at a time — see _pickUpFromSender
    final parcelPhotos = <String>[]; // batch: one or more item photos
    final branchCtrl = TextEditingController();
    // Each depot receipt: its own amount field + its own photo. A batch may
    // be split across receipts by the depot — file them all, one by one.
    final receipts = <_ReceiptEntry>[];
    bool filing = false;
    // Money attestation (owner 2026-11-23): the figure the rider types is the
    // EXACT figure the sender is charged. Filing requires an explicit promise
    // that every amount was copied from the photographed depot receipt.
    bool amountCopiedFromReceipt = false;
    String? filedSummary;
    // The SENDER's booking photo travels with the stop (owner directive
    // 2026-11-17): the rider sees the parcel they are collecting next to the
    // one they just photographed, so swaps are caught at the drop, not at
    // delivery. Riders are authorized on /jobs/:ref/evidence.
    final evData = await DropOffApi.jobEvidence(ref);
    final evMap = (evData?['evidence'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
    if (!mounted) return null;
    final sellerPhoto = '${evMap['booking_photo'] ?? ''}';
    final res = await showModalBottomSheet<ApiResponse>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) {
          final parsedAmounts = receipts
              .map((e) => double.tryParse(e.amountCtrl.text.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0)
              .toList();
          final receiptsReady = receipts.isNotEmpty &&
              receipts.every((e) => e.url != null) &&
              parsedAmounts.every((a) => a > 0 && a <= 20000);
          final filedTotal = parsedAmounts.fold<double>(0, (sum, a) => sum + a);
          return SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
              child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.line, borderRadius: BorderRadius.circular(4)))),
                  const SizedBox(height: 14),
                  Row(children: [
                    Container(width: 44, height: 44, decoration: BoxDecoration(color: AppColors.forest.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.storefront_outlined, color: AppColors.forest)),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Depot drop — $ref', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 22, letterSpacing: -0.2)),
                      const Text('Capture item proof and every depot receipt before filing.', style: TextStyle(fontSize: 12.5, color: AppColors.muted)),
                    ])),
                    const HelpIconButton(topic: HelpTopic.depotReceipts),
                  ]),
                  const SizedBox(height: 14),
                  _sheetChecklist([
                    _SheetCheck(label: 'Item photos', done: parcelPhotos.isNotEmpty, detail: parcelPhotos.isEmpty ? 'At least one item photo required' : '${parcelPhotos.length} item photo${parcelPhotos.length == 1 ? '' : 's'} captured'),
                    _SheetCheck(label: 'Depot receipts', done: receiptsReady, detail: receipts.isEmpty ? 'Add each receipt with photo and exact amount' : '${receipts.length} receipt${receipts.length == 1 ? '' : 's'} added'),
                    _SheetCheck(label: 'Branch name', done: branchCtrl.text.trim().isNotEmpty, detail: branchCtrl.text.trim().isEmpty ? 'Optional, but helpful for tracking' : branchCtrl.text.trim()),
                  ]),
                  const SizedBox(height: 14),
                  if (sellerPhoto.isNotEmpty) ...[
                    _sheetSection('Sender booking photo'),
                    const SizedBox(height: 6),
                    ClipRRect(borderRadius: BorderRadius.circular(12), child: ColoredBox(color: AppColors.line.withValues(alpha: 0.18), child: AuthedImage(sellerPhoto, fit: BoxFit.contain, width: double.infinity, height: 140))),
                    const SizedBox(height: 4),
                    const Text('Compare this with the item photos before filing the drop.', style: TextStyle(fontSize: 11.5, color: AppColors.muted, height: 1.35)),
                    const SizedBox(height: 14),
                  ],
                  _sheetSection('Item photos (${parcelPhotos.length})'),
                  const SizedBox(height: 6),
                  if (parcelPhotos.isNotEmpty)
                    SizedBox(
                      height: 96,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: parcelPhotos.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (_, i) => PhotoPreview(
                          pathOrUrl: parcelPhotos[i],
                          size: 96,
                          label: 'ITEM ${i + 1} · TAP TO VIEW',
                          // Tapping the photo opens it — it NEVER deletes.
                          onTap: () => ReceiptViewer.show(context,
                              path: parcelPhotos[i], title: 'Item ${i + 1} proof photo'),
                          onRemove: () => setDialog(() => parcelPhotos.removeAt(i)),
                        ),
                      ),
                    ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.camera_alt_outlined, size: 18),
                    label: Text(parcelPhotos.isEmpty ? 'Capture first item (required)' : 'Capture next item'),
                    onPressed: () async { final url = await _pickPodPhoto(); if (url != null) setDialog(() => parcelPhotos.add(url)); },
                  ),
                  const SizedBox(height: 14),
                  _sheetSection('Depot branch'),
                  const SizedBox(height: 6),
                  TextField(
                    controller: branchCtrl,
                    textInputAction: TextInputAction.next,
                    onChanged: (_) => setDialog(() {}),
                    decoration: const InputDecoration(hintText: 'e.g. Platinum — Kabwata', prefixIcon: Icon(Icons.storefront_outlined), border: OutlineInputBorder(), isDense: true),
                  ),
                  const SizedBox(height: 4),
                  const Text('Optional — the branch the item landed at.', style: TextStyle(fontSize: 11.5, color: AppColors.muted, height: 1.35)),
                  const SizedBox(height: 14),
                  _sheetSection('Depot receipts (${receipts.length})'),
                  const SizedBox(height: 6),
                  // EXACT AMOUNT RULE (owner 2026-11-23): this is money the
                  // sender pays. The app cannot read the printed figure for the
                  // rider, so make the rule unmissable at the point of entry.
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF1D2),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0x66B3261E)),
                    ),
                    child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Icon(Icons.report_problem_outlined, size: 18, color: Color(0xFF7B5710)),
                      SizedBox(width: 8),
                      Expanded(child: Text(
                        'Type ONLY the amount printed on the depot receipt. Never guess, round up, or add your own fee — the sender is charged exactly what you enter, so a wrong figure means a wrong payment.',
                        style: TextStyle(fontSize: 11.5, color: Color(0xFF4A3400), height: 1.4, fontWeight: FontWeight.w600),
                      )),
                    ]),
                  ),
                  const SizedBox(height: 8),
                  for (var i = 0; i < receipts.length; i++) _receiptEntryTile(setDialog, receipts, i),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.receipt_long_outlined, size: 18),
                    label: Text(receipts.isEmpty ? 'Add depot receipt (required)' : 'Add another receipt'),
                    onPressed: () => setDialog(() => receipts.add(_ReceiptEntry())),
                  ),
                  const SizedBox(height: 6),
                  const Text('Photos unlock when the sender pays, and you are reimbursed.', style: AppType.caption),
                  if (receiptsReady) ...[
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppColors.forest.withValues(alpha: 0.07),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'Total the sender will be asked for: K${filedTotal.toStringAsFixed(2)} (filed receipt${receipts.length == 1 ? '' : 's'}) + the DropOff processing fee. Check every figure against its receipt photo before filing.',
                        style: const TextStyle(fontSize: 11.5, color: AppColors.ink, height: 1.4, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    value: amountCopiedFromReceipt,
                    onChanged: filing ? null : (v) => setDialog(() => amountCopiedFromReceipt = v ?? false),
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: const Text('I copied the exact amount printed on every depot receipt',
                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: AppColors.ink)),
                    subtitle: const Text('No estimates, no rounding, no added fees — I checked each figure against its receipt photo.',
                        style: TextStyle(fontSize: 11, color: AppColors.muted, height: 1.35)),
                  ),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(child: OutlinedButton(onPressed: filing ? null : () => Navigator.pop(ctx, null), child: const Text('Cancel'))),
                    const SizedBox(width: 10),
                    Expanded(child: FilledButton(
                      onPressed: filing || !amountCopiedFromReceipt ? null : () async {
                        if (parcelPhotos.isEmpty) { _snack('At least one item photo is required.'); return; }
                        if (receipts.isEmpty) { _snack('Add the depot receipt — photo + the exact amount written on it.'); return; }
                        var total = 0.0;
                        for (var i = 0; i < receipts.length; i++) {
                          final r = receipts[i];
                          if (r.url == null) { _snack('Receipt ${i + 1} needs its photo.'); return; }
                          final amt = double.tryParse(r.amountCtrl.text.replaceAll(RegExp(r'[^0-9.]'), ''));
                          if (amt == null || amt <= 0) {
                            _snack('Receipt ${i + 1}: enter the exact amount printed on the receipt — not a guess.');
                            return;
                          }
                          if (amt > 20000) {
                            _snack('Receipt ${i + 1}: that amount is too high. Re-read the printed figure before filing.');
                            return;
                          }
                          total += amt;
                        }
                        if (!amountCopiedFromReceipt) {
                          _snack('Confirm you copied the exact printed amounts before filing.');
                          return;
                        }
                        filedSummary = 'K${total.toStringAsFixed(2)}';
                        final branch = branchCtrl.text.trim();
                        setDialog(() => filing = true);
                        final r = await DropOffApi.jobEvent(
                          jobRef: ref, status: 'delivered',
                          photoUrl: parcelPhotos.first, stage: 'delivery',
                          parcelPhotos: parcelPhotos,
                          branch: branch.isEmpty ? null : branch,
                          receipts: [for (final e in receipts) {'amount_zmw': double.parse(e.amountCtrl.text.replaceAll(RegExp(r'[^0-9.]'), '')), 'url': e.url}],
                          receiptAmountConfirmed: amountCopiedFromReceipt,
                        );
                        if (!ctx.mounted) return;
                        Navigator.pop(ctx, r);
                      },
                      child: filing ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Confirm depot drop'),
                    )),
                  ]),
                ]),
              ),
            ),
          );
        },
      ),
    );
    if (!mounted) return null;
    if (res == null) return null; // cancelled
    if (res.ok) {
      setState(() => _busyRef = null);
      await _snack('$ref - dropped at depot. Sender will be asked for $filedSummary on the filed receipt - check it matches the photo.');
      await StepSounds.stepDone(); // step-complete chime (owner request 2026-11-20)
      AnalyticsService.instance.track(feature: 'rider', action: 'delivered', context: 'depot_stop');
      // Auto-name this dropoff point (Waze-style growing location): reverse
      // geocode the rider's position and save it as a shared community POI.
      final savedName = await _autoNameDepotPoi(ref);
      if (mounted && savedName != null && savedName.isNotEmpty) {
        AppToast.show(context, 'Dropoff point saved as "$savedName" on the map.');
      }
      // Best-effort: compare seller's booking photo vs this drop photo.
      final chk = await DropOffApi.parcelCheck(ref);
      if (!mounted) return res;
      if (chk.ok) {
        final verdict = chk.body['same_parcel'] ?? 'uncertain';
        final flagged = chk.body['flagged'] == true;
        await _snack(flagged || verdict != 'yes'
            ? '$ref photo check inconclusive — DropOff support will review'
            : '$ref photo check passed');
      } else {
        // AI check is best-effort; a slow/unavailable vision model must not
        // confuse a rider who just filed the drop correctly.
        await _snack('$ref drop filed. Photo check unavailable — DropOff will review the photos.');
      }
      _load();
      return res;
    }
    final err = res.error ?? '';
    final detail = (res.body['detail'] as String?) ?? '';
    setState(() => _busyRef = null);
    await StepSounds.stepError(); // rejected-step tone (owner request 2026-11-20)
    await _snack(switch (err) {
      'receipt_required' => detail.isEmpty ? 'Every depot receipt needs its photo and exact amount.' : detail,
      'photo_required' => detail.isEmpty ? 'A parcel photo is required.' : detail,
      'two_photos_required' => detail.isEmpty ? 'Parcel photos and receipt photos must be separate images.' : detail,
      'photo_locked' => detail.isEmpty ? 'That proof photo is already filed — pull to refresh; contact support if the task stays open.' : detail,
      'counter_receipt_locked' => detail.isEmpty ? 'The depot receipt is already paid and locked — contact support.' : detail,
      _ => 'Drop not filed - check your connection and retry.',
    });
    return res;
  }

  Widget _sheetSection(String title) => Text(title.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 0.4, color: AppColors.muted));

  Widget _sheetInfoCard({required IconData icon, required String title, required String message}) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: AppColors.forest.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.forest.withValues(alpha: 0.12))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 18, color: AppColors.forest),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
            const SizedBox(height: 2),
            Text(message, style: const TextStyle(fontSize: 12.5, height: 1.35, color: AppColors.ink)),
          ])),
        ]),
      );

  Widget _sheetChecklist(List<_SheetCheck> items) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: AppColors.canvas, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.line)),
        child: Column(children: [
          for (var i = 0; i < items.length; i++) ...[
            Row(children: [
              Icon(items[i].done ? Icons.check_circle : Icons.radio_button_unchecked, size: 18, color: items[i].done ? AppColors.forest : AppColors.muted),
              const SizedBox(width: 8),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(items[i].label, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: items[i].done ? AppColors.ink : AppColors.muted)),
                Text(items[i].detail, style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
              ])),
            ]),
            if (i != items.length - 1) const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Divider(height: 1)),
          ],
        ]),
      );

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
          decoration: InputDecoration(
            labelText: 'Amount printed on receipt ${i + 1} (K)',
            prefixText: 'K ',
            helperText: 'Copy the printed figure exactly — not an estimate',
            helperMaxLines: 1,
            isDense: true,
            border: const OutlineInputBorder(),
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
    setState(() => _busyRef = ref); // one step at a time — see _pickUpFromSender
    final recName = '${s['recipient'] ?? ''}'.trim();
    final recPhone = '${s['recipient_phone'] ?? ''}'.trim();
    final otpCtrl = TextEditingController();
    String? podUrl;
    bool submitting = false;
    // Ask the server whether THIS job has a door code at all (same-city jobs
    // often don't). With no code, the proof photo is the only requirement.
    var doorNeedsPin = true;
    try {
      final pre = await DropOffApi.verifyPin(ref, '', 'door');
      if (pre.ok) doorNeedsPin = pre.body['needed'] == true;
    } catch (_) { /* final confirm still verifies server-side */ }
    if (!mounted) return null;
    var pinState = doorNeedsPin ? _PinCheck.idle : _PinCheck.notNeeded;
    Timer? pinDebounce;
    String? pinError;
    final res = await showModalBottomSheet<ApiResponse>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) {
          final hasPhoto = podUrl != null;
          final pinDone = pinState == _PinCheck.ok || pinState == _PinCheck.notNeeded;

          Future<void> verifyPin(String code) async {
            if (code.length != 4) {
              setDialog(() => pinState = _PinCheck.idle);
              return;
            }
            setDialog(() => pinState = _PinCheck.checking);
            final r = await DropOffApi.verifyPin(ref, code, 'door');
            if (!ctx.mounted) return;
            if (r.ok) {
              setDialog(() {
                pinState = r.body['needed'] == true ? _PinCheck.ok : _PinCheck.notNeeded;
                pinError = null;
              });
              return;
            }
            final err = r.error ?? '';
            final detail = (r.body['detail'] as String?)?.trim() ?? '';
            setDialog(() {
              switch (err) {
                case 'not_needed':
                  pinState = _PinCheck.notNeeded;
                  pinError = null;
                case 'network_error' || 'offline_demo_mode':
                  pinState = _PinCheck.idle;
                  pinError = 'Could not reach DropOff to check the code. Try again.';
                case 'otp_locked':
                  pinState = _PinCheck.locked;
                  pinError = detail.isNotEmpty ? detail : 'Too many wrong codes — contact DropOff support.';
                default:
                  pinState = _PinCheck.wrong;
                  pinError = detail.isNotEmpty ? detail : 'That door code did not match — ask the recipient to check it.';
              }
            });
          }

          return SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
              child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.line, borderRadius: BorderRadius.circular(4)))),
                  const SizedBox(height: 14),
                  Row(children: [
                    Container(width: 44, height: 44, decoration: BoxDecoration(color: AppColors.forest.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.handshake_outlined, color: AppColors.forest)),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(_handoverTitle(s, '${s['service'] ?? ''}' == 'collection' ? 'COLLECTION' : 'HANDOVER'), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 22, letterSpacing: -0.2)),
                      Text(recName.isEmpty ? 'Confirm recipient handover' : 'Hand over to $recName', style: const TextStyle(fontSize: 12.5, color: AppColors.muted)),
                    ])),
                  ]),
                  const SizedBox(height: 14),
                  _sheetChecklist([
                    _SheetCheck(label: 'Recipient identified', done: true, detail: recName.isEmpty ? 'Recipient at delivery point' : '$recName${recPhone.isNotEmpty ? ' · $recPhone' : ''}'),
                    _SheetCheck(
                      label: 'Door PIN/code',
                      done: pinDone,
                      detail: switch (pinState) {
                        _PinCheck.ok => 'Code matched on DropOff server',
                        _PinCheck.notNeeded => 'No door PIN for this booking — photo proof',
                        _PinCheck.checking => 'Checking code with DropOff…',
                        _PinCheck.wrong => 'Code did not match — ask the recipient again',
                        _PinCheck.locked => 'Too many wrong codes — contact support',
                        _ => doorNeedsPin ? 'Ask the recipient for their 4-digit code' : 'Optional in Lusaka; required when the recipient has a code',
                      }),
                    _SheetCheck(label: 'Proof photo', done: hasPhoto, detail: hasPhoto ? 'Photo attached' : 'Required camera photo of handover'),
                  ]),
                  const SizedBox(height: 14),
                  _sheetInfoCard(icon: Icons.info_outline, title: 'Handover rule', message: 'Intercity items need the recipient’s 4-digit SMS code. Lusaka items may be confirmed with a proof photo; if the recipient set a door PIN, enter it here.'),
                  const SizedBox(height: 14),
                  _sheetSection('Door PIN / code'),
                  const SizedBox(height: 6),
                  TextField(
                    controller: otpCtrl,
                    keyboardType: TextInputType.number,
                    maxLength: 4,
                    onChanged: (v) {
                      pinDebounce?.cancel();
                      final code = v.trim();
                      if (code.length != 4) {
                        setDialog(() => pinState = _PinCheck.idle);
                        return;
                      }
                      pinDebounce = Timer(const Duration(milliseconds: 350), () => unawaited(verifyPin(code)));
                    },
                    decoration: InputDecoration(
                      counterText: '',
                      labelText: '4-digit door PIN / code (if the recipient has one)',
                      border: const OutlineInputBorder(),
                      errorText: pinError,
                      suffixIcon: switch (pinState) {
                        _PinCheck.checking => const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))),
                        _PinCheck.ok || _PinCheck.notNeeded => const Icon(Icons.verified, color: AppColors.forest),
                        _PinCheck.wrong || _PinCheck.locked => const Icon(Icons.error_outline, color: AppColors.danger),
                        _ => null,
                      },
                    ),
                  ),
                  if (!doorNeedsPin && pinState != _PinCheck.notNeeded)
                    TextButton(
                      onPressed: () => setDialog(() => pinState = _PinCheck.notNeeded),
                      child: const Text('No door PIN for this item — continue with photo proof'),
                    ),
                  const SizedBox(height: 14),
                  _sheetSection('Proof photo'),
                  const SizedBox(height: 6),
                  OutlinedButton.icon(
                    icon: Icon(hasPhoto ? Icons.check_circle : Icons.camera_alt_outlined, size: 18),
                    label: Text(hasPhoto ? 'Proof photo attached ✓' : 'Add proof photo (required)'),
                    // Verify the code BEFORE the proof capture step (owner
                    // 2026-11-23): a 4-digit entry alone never unlocks it.
                    onPressed: submitting || !pinDone ? null : () async {
                      setDialog(() => podUrl = null);
                      final url = await _pickPodPhoto();
                      setDialog(() => podUrl = url);
                    },
                  ),
                  if (podUrl != null) ...[
                    const SizedBox(height: 8),
                    Row(children: [
                      PhotoPreview(
                        pathOrUrl: podUrl!,
                        label: 'PROOF · TAP TO VIEW',
                        size: 96,
                        onTap: () => ReceiptViewer.show(context, path: podUrl!, title: 'Handover proof'),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(child: Text('Check this is the item you handed over before you confirm.', style: AppType.caption)),
                    ]),
                  ],
                  const SizedBox(height: 20),
                  Row(children: [
                    Expanded(child: OutlinedButton(onPressed: submitting ? null : () => Navigator.pop(ctx, null), child: const Text('Cancel'))),
                    const SizedBox(width: 10),
                    Expanded(child: FilledButton(
                      onPressed: submitting ? null : () async {
                        final code = otpCtrl.text.trim();
                        if (!pinDone) {
                          _snack(pinState == _PinCheck.checking
                              ? 'Still checking the door code with DropOff…'
                              : 'Confirm the door PIN with DropOff before handover.');
                          return;
                        }
                        if (podUrl == null) { _snack('Attach the camera photo of the handover to confirm.'); return; }
                        setDialog(() => submitting = true);
                        final r = await DropOffApi.jobEvent(jobRef: ref, status: 'delivered', otp: code.length == 4 ? code : null, photoUrl: podUrl, stage: 'delivery');
                        if (!ctx.mounted) return;
                        if (r.ok || r.error == 'already_delivered') { Navigator.pop(ctx, r.ok ? r : const ApiResponse(ok: true)); return; }
                        setDialog(() => submitting = false);
                        _snack(r.error == 'photo_required' ? 'Attach the camera photo of the handover to confirm.' : 'Handover not filed - check your connection and retry.');
                      },
                      child: submitting ? const AppLogoSpinner(size: 18, color: Colors.white) : const Text('Confirm handover'),
                    )),
                  ]),
                ]),
              ),
            ),
          );
        },
      ),
    );
    if (!mounted) return null;
    if (res == null) return null; // cancelled
    if (res.ok) {
      await _snack('$ref - handover complete ✓');
      await StepSounds.stepDone(); // step-complete chime (owner request 2026-11-20)
      _load();
      return res;
    }
    // Server-side OTP errors map to rider-readable guidance.
    final err = res.error ?? '';
    final detail = (res.body['detail'] as String?) ?? '';
    await StepSounds.stepError(); // rejected-step tone (owner request 2026-11-20)
    await _snack(switch (err) {
      'otp_required' => 'Code rejected. ${detail.isEmpty ? 'Ask the recipient to re-check their SMS.' : detail}',
      'otp_locked' => 'Too many wrong codes — support has been notified.',
      _ => 'Handover not filed - check your connection and retry.',
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
          const Text('Unassigned jobs - first to claim takes them.', style: TextStyle(fontSize: 11, color: AppColors.muted)),
          if (_availableHint != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(_availableHint!, style: const TextStyle(fontSize: 11, color: AppColors.forest, fontWeight: FontWeight.w700)),
            ),
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
                  Text('${j['sender_name'] ?? ''} → ${j['dest_city'] ?? ''} · ${j['parcels'] ?? 1} items · ${j['pickup_window'] ?? ''}',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10.5, color: AppColors.muted)),
                  if ('${j['needs_car']}' == '1')
                    const Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: Text('Sender prefers a CAR — a car rider is free to claim',
                          style: TextStyle(fontSize: 10, color: AppColors.forest, fontWeight: FontWeight.w800)),
                    ),
                ])),
                const SizedBox(width: 8),
                FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size(72, 36)),
                  onPressed: _claimingRef != null ? null : () => _claim(j),
                  child: _claimingRef == '${j['ref']}'
                      ? const AppLogoSpinner(size: 16)
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
        appBar: AppBar(
          title: const Text(
            'Task Queue',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
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
        title: const Text(
          'Task Queue',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          // Compact shift switch — full controls live in a bottom sheet so
          // the Task Queue body (and the stats card) never gets pushed down.
          _shiftPill(),
          IconButton(
            tooltip: 'Job history',
            icon: const Icon(Icons.history_rounded),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const RiderHistoryScreen())),
          ),
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
                    headers: DropOffApi.authHeaders, // /media is auth-gated — without this the avatar never loads
                    width: 28, height: 28, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const Icon(Icons.account_circle)))
                : Icon(store.email != null ? Icons.account_circle : Icons.account_circle_outlined),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AccountScreen())),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _triggerSos,
        backgroundColor: AppColors.danger,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.sos_rounded),
        label: const Text('SOS', style: TextStyle(fontWeight: FontWeight.w900)),
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
        // RECOVERY BANNERS (owner audit 2026-11-21): both of these used to fail
        // silently and leave the rider with no orders and no way to fix it.
        if (store.linked && !store.shareLocationOn)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            color: AppColors.amber.withValues(alpha: 0.24),
            child: Row(children: [
              const Icon(Icons.location_off, size: 16, color: AppColors.ink),
              const SizedBox(width: 8),
              const Expanded(child: Text('Location sharing is off - new jobs cannot reach you.',
                  style: TextStyle(fontSize: 11.5, color: AppColors.ink, fontWeight: FontWeight.w700))),
              TextButton(onPressed: () => store.setShareLocationOn(true), child: const Text('Turn on sharing')),
            ]),
          ),
        if (store.linked && _gpsIssue != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            color: AppColors.danger.withValues(alpha: 0.12),
            child: Row(children: [
              const Icon(Icons.gps_off, size: 16, color: AppColors.danger),
              const SizedBox(width: 8),
              Expanded(child: Text(_gpsIssue == 'service'
                  ? 'Location services are off - arrival alerts and availability are paused.'
                  : 'Location permission was denied - arrival alerts and availability are paused.',
                  style: const TextStyle(fontSize: 11.5, color: AppColors.ink, fontWeight: FontWeight.w700))),
              TextButton(
                onPressed: () => _gpsIssue == 'service'
                    ? Geolocator.openLocationSettings()
                    : Geolocator.openAppSettings(),
                child: const Text('Open settings'),
              ),
            ]),
          ),
        // NEW-ORDER ALERTS (owner 2026-11-23): on Android 13+ notifications are
        // OFF by default. With permission denied, FCM tokens still register but
        // every "new order" push vanishes silently — the rider waits forever.
        if (PushService.supportsPush && !PushService.notificationsEnabled)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            color: AppColors.danger.withValues(alpha: 0.12),
            child: Row(children: [
              const Icon(Icons.notifications_off_outlined, size: 16, color: AppColors.danger),
              const SizedBox(width: 8),
              const Expanded(child: Text('New-order alerts are off — you will not hear when a job arrives.',
                  style: TextStyle(fontSize: 11.5, color: AppColors.ink, fontWeight: FontWeight.w700))),
              TextButton(
                onPressed: () async {
                  await PushService.openNotificationSettings();
                  if (!mounted) return;
                  await PushService.refreshPermission();
                  if (mounted) setState(() {});
                },
                child: const Text('Turn on'),
              ),
            ]),
          ),
        Expanded(
          child: _loading
          ? const Center(child: AppLogoSpinner(size: 26))
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
                                  'New jobs appear here automatically. Pull down to refresh.',
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
        // radar reads as searching the whole city for an item signal.
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
                // no white corners/patches around the pin + item mark.
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
    final items = (s['parcels'] as num?)?.toInt() ?? 0;
  
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
            Expanded(
              child: Text('$items items · updated $_statsSynced',
                  maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10.5, color: Colors.white.withValues(alpha: 0.6), fontWeight: FontWeight.w600)),
            ),
          ]),
          const SizedBox(height: 4),
          // Salary note on its own full-width line (owner bug 2026-11-20: it
          // sat in the header Row and overlapped the card's right edge).
          Row(children: [
            const Icon(Icons.badge_outlined, size: 12, color: Colors.white70),
            const SizedBox(width: 6),
            Expanded(
              child: Text('Pay: monthly and weekly salary - see your agreement',
                  maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: Colors.white.withValues(alpha: 0.7))),
            ),
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
    final progress = daily > 0 ? (today / daily).clamp(0.0, 1.0) : 0.0;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.flag_outlined, size: 13, color: AppColors.amber),
          const SizedBox(width: 6),
          Expanded(child: Text('TODAY $today/$daily  ·  MONTH $month/$pace',
              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800))),
          const Text('Daily progress',
              style: TextStyle(color: AppColors.amber, fontSize: 11, fontWeight: FontWeight.w900)),
        ]),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(value: progress, minHeight: 5,
              backgroundColor: Colors.white24, color: AppColors.amber),
        ),
        const SizedBox(height: 4),
        Text(behind > 0
            ? '$behind behind pace - hit the daily target first.'
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
        final pickedCount = stops.where((s) {
          final k = '${s['kind'] ?? ''}';
          if (k == 'depot_drop' || k == 'depot_drop_group') return '${s['status'] ?? ''}' == 'delivered';
          return _picked('${s['status'] ?? ''}');
        }).length;
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
              Text('TOTAL ITEMS TO PICK UP: ${b['total_parcels']}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
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
                  const Text('Stops left to file',
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
    final kind = '${s['kind'] ?? ''}';
    final isDepotAction = kind == 'depot_drop' || kind == 'depot_drop_group';
    // A DELIVERY stop stays open until the handover is FILED. Before this fix
    // `done` was just `picked`, so every last-mile/collection stop became a
    // locked, unclickable ✓ the moment the item was picked up — even though
    // the door step had not been filed. That is why a live order sat on the
    // queue with no way to tick it.
    final isDelivery = !isDepotAction && kind == 'delivery';
    final status = '${s['status'] ?? ''}';
    final picked = isDepotAction ? false : _picked(status);
    final done = isDepotAction
        ? status == 'delivered'
        : isDelivery
            ? ['delivered', 'ready_for_collection'].contains(status)
            : picked;
    final arrived = !done && !isDepotAction && _arrivedRefs.contains(ref);
    final depotName = '${s['depot'] ?? s['courier'] ?? 'depot'}'.trim();
    final refs = ((s['refs'] as List?) ?? [ref]).map((e) => '$e').where((e) => e.isNotEmpty).toList();
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
                    color: done ? AppColors.muted : AppColors.ink)),
            const SizedBox(height: 2),
            Text(
              isDepotAction
                  ? (() {
                      final items = ((s['items'] as List?) ?? const []).cast<Map<String, dynamic>>();
                      final doneCount = items.where((i) => ['delivered', 'at_depot'].contains('${i['status'] ?? ''}')).length;
                      if (done) return '✓ dropped at $depotName';
                      if (items.isNotEmpty) return 'Drop ${s['parcels'] ?? refs.length} item(s) at $depotName · $doneCount/${items.length} filed';
                      return 'Drop ${s['parcels'] ?? refs.length} item(s) at $depotName · ${refs.length} order(s)';
                    })()
                  : isDelivery
                      ? (done
                          ? '✓ delivered to ${'${s['recipient'] ?? 'recipient'}'}'
                          : arrived
                              ? 'ARRIVED — tap ✓ to file the door handover'
                              : 'Tap ✓ to file the door handover to ${'${s['recipient'] ?? 'recipient'}'}')
                      : picked
                          ? '✓ picked — drop at the $depotName depot'
                          : arrived
                              ? ('${s['service'] ?? ''}' == 'collection'
                                  ? 'ARRIVED at the depot — tap ✓ to collect the parcel'
                                  : 'ARRIVED — tap ✓ to file the pickup')
                              : '${'${s['service'] ?? ''}' == 'collection' ? 'Recipient' : 'Sender'}: ${s['seller']} · ${s['depot'] ?? 'depot'} · ${s['parcels']} items',
              style: TextStyle(color: done ? AppColors.forest : arrived ? AppColors.ink : AppColors.muted,
                  fontSize: 11.5, fontWeight: done || arrived ? FontWeight.w800 : FontWeight.w400),
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
          isDelivery
              ? 'To ${'${s['recipient'] ?? 'Recipient'}'}'
              : (picked || isDepotAction)
                  ? ('${s['service'] ?? ''}' == 'collection'
                      ? 'To ${'${s['recipient'] ?? 'recipient'}'}'
                      : 'To ${_depotShort(s)}')
                  : ('${s['service'] ?? ''}' == 'collection'
                      ? 'To ${_depotShort(s)}'
                      : 'To ${'${s['seller'] ?? 'Recipient'}'.trim().isEmpty ? 'Recipient' : '${s['seller']}'.trim()}'),
          isDelivery
              ? 'Navigate to the recipient door in the DropOff map'
              : (picked || isDepotAction) && '${s['service'] ?? ''}' != 'collection'
                  ? 'Navigate to the ${s['depot'] ?? s['courier'] ?? 'depot'} depot in the DropOff map'
                  : 'Navigate to the handover in the DropOff map',
          (isDelivery || picked || isDepotAction) ? AppColors.forest : AppColors.forestLight,
          Icons.navigation_rounded,
          () => _navigateToStop(s),
        ),
        IconButton(
          tooltip: 'Update stop',
          visualDensity: VisualDensity.compact,
          icon: _busyRef == ref
              ? const AppLogoSpinner(size: 18)
              : Icon(done ? Icons.check_circle : Icons.check_circle_outline, color: AppColors.forest),
          onPressed: done ? null : () => _advanceStop(s),
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
      '· ~${_routeDuration(b['minutes_on_road'])} route',
    ];
    return parts.join(' · ');
  }

  /// Human route time — "45 min" / "1 h 20 min", never a bare "1034 min"
  /// (owner audit 2026-11-20).
  String _routeDuration(dynamic raw) {
    final mins = (raw as num?)?.toInt() ?? 0;
    if (mins <= 0) return '—';
    if (mins < 60) return '$mins min';
    final h = mins ~/ 60, m = mins % 60;
    return m == 0 ? '$h h' : '$h h $m min';
  }
}

class _SheetCheck {
  final String label;
  final bool done;
  final String detail;
  const _SheetCheck({required this.label, required this.done, required this.detail});
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
/// addresses, depot/branch, items, window) with every money field stripped
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
      final wb = data?['waybill'] as Map<String, dynamic>?;
      // Older workers returned the value at the top level, not inside waybill.
      if (wb != null && wb['declared_value_zmw'] == null && data?['declared_value_zmw'] != null) {
        _wb = Map<String, dynamic>.from(wb)..['declared_value_zmw'] = data!['declared_value_zmw'];
      } else {
        _wb = wb;
      }
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

  /// Screenshots are blocked app-wide, so the waybill is shared explicitly
  /// as text (money fields are already stripped by the worker).
  void _shareWaybill() {
    final wb = _wb;
    if (wb == null) return;
    String val(String key) => '${wb[key] ?? ''}'.trim();
    final lines = <String>[
      'DropOff order ${widget.ref}',
      if (val('sender_name').isNotEmpty) 'Sender: ${val('sender_name')} · ${val('sender_phone')}',
      if (val('recipient_name').isNotEmpty) 'Recipient: ${val('recipient_name')} · ${val('recipient_phone')}',
      if (val('pickup_address').isNotEmpty) 'Pickup: ${val('pickup_address')}',
      if (val('dest_address').isNotEmpty) 'Deliver: ${val('dest_address')}',
      if (val('depot').isNotEmpty) 'Depot: ${val('depot')}',
      if (val('branch').isNotEmpty) 'Branch: ${val('branch')}',
      if (val('description').isNotEmpty) 'Item: ${val('description')}',
      if (val('pickup_window').isNotEmpty) 'Window: ${val('pickup_window')}',
    ];
    unawaited(Share.share(lines.join('\n'), subject: 'DropOff order ${widget.ref}'));
  }

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
            IconButton(
              tooltip: 'Share waybill details',
              icon: const Icon(Icons.ios_share, size: 19, color: AppColors.forest),
              onPressed: _wb == null ? null : _shareWaybill,
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
                          child: Center(child: AppLogoSpinner(size: 26)),
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
            const Text('The courier carries your items the rest of the way from the depot.',
                style: TextStyle(fontSize: 11, color: AppColors.muted, height: 1.4)),
          ],
        ]),
        _section('ITEM', [
          _row('Items', '${w['parcels'] ?? 1}'),
          _row('Contents', '${w['description'] ?? ''}'),
          _row('Size', '${w['weight_class'] ?? ''}'),
          // Declared item VALUE (owner request): needed at the depot counter.
          // No fees, rates or rider payouts are ever shown on this sheet.
          _row(
            'Package value',
            ((w['declared_value_zmw'] as num?)?.toDouble() ?? 0) > 0
                ? 'K${(w['declared_value_zmw'] as num).toDouble().toStringAsFixed(2)}'
                : 'Not declared by the sender',
          ),
        ]),
        const Divider(height: 12),
        Text('Depot fare is paid at the counter — DropOff never collects partner money.',
            style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600, height: 1.4)),
      ]),
    );
  }
}
