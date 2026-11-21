import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../data/dropoff_api.dart';
import '../data/map_services.dart';
import '../ui/app_theme.dart';
import '../widgets/rider_map.dart';

/// Sender-side live rider screen: the DropOff map (Protomaps Zambia/Zimbabwe/Malawi/Mozambique on our R2), fresh fix every 12 s while open, road-following route line when OSRM answers.
class RiderMapScreen extends StatefulWidget {
  final String jobRef;
  const RiderMapScreen({super.key, required this.jobRef});

  @override
  State<RiderMapScreen> createState() => _RiderMapScreenState();
}

class _RiderMapScreenState extends State<RiderMapScreen> {
  Map<String, dynamic>? _live;
  String _error = '';
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 12), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    final live = await DropOffApi.liveLocation(widget.jobRef);
    if (!mounted) return;
    setState(() {
      _live = live;
      _error = live == null ? 'No live connection — rider fix may be stale.' : '';
    });
    await _maybeRoute();
  }

  LatLng? get _pickup =>
      (_live?['pickup_lat'] != null && _live?['pickup_lng'] != null)
          ? LatLng((_live!['pickup_lat'] as num).toDouble(), (_live!['pickup_lng'] as num).toDouble())
          : null;

  LatLng? get _rider =>
      (_live?['lat'] != null && _live?['lng'] != null)
          ? LatLng((_live!['lat'] as num).toDouble(), (_live!['lng'] as num).toDouble())
          : null;

  /// END of the visible leg: the courier's depot branch (real coordinates the
  /// live API now serves — jobs carry no destination GPS). Shown as the
  /// warehouse pin so the tracking map reads start → rider → end (owner
  /// 2026-11-18: "show start and end of route to pick up and drop off").
  ///
  /// COLLECTIONS ARE REVERSED (owner directive 2026-11-20: "on collection the
  /// depot pin remove it"): the parcel is already at the depot, so the depot
  /// is the START, never the destination. No warehouse pin is drawn — the
  /// route ends at the recipient's handover.
  /// </summary>
  LatLng? get _depot {
    if ('${_live?['service'] ?? ''}' == 'collection') return null;
    return (_live?['depot_lat'] != null && _live?['depot_lng'] != null)
        ? LatLng((_live!['depot_lat'] as num).toDouble(), (_live!['depot_lng'] as num).toDouble())
        : null;
  }

  RouteResult? _route;
  LatLng? _routeOrigin;

  /// Road-following rider→pickup route (OSRM). Refetched when the rider
  /// moves >150 m so the line tracks the drive, not a stale snapshot.
  Future<void> _maybeRoute() async {
    final me = _rider, dest = _pickup;
    if (me == null || dest == null) return;
    if (_route != null && _routeOrigin != null &&
        const Distance().as(LengthUnit.Meter, _routeOrigin!, me) < 150) {
      return;
    }
    final route = await MapServices.route(me, dest);
    if (!mounted) return;
    setState(() {
      _route = route;
      _routeOrigin = me;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text('Rider live', style: TextStyle(fontWeight: FontWeight.w900)),
        actions: [IconButton(tooltip: 'Refresh', icon: const Icon(Icons.refresh), onPressed: _refresh)],
      ),
      body: Column(children: [
        Expanded(child: Stack(children: [
          RiderMap(
            pickup: _pickup,
            rider: _rider,
            depot: _depot,
            route: _route?.points ??
                ((_rider != null && _pickup != null) ? [_rider!, _pickup!] : null),
            routeIsStraightLine: _route == null,
            vehicleClass: '${_live?['vehicle_class'] ?? 'motorcycle'}',
          ),
          if (_live == null || _live!['lat'] == null)
            Positioned(
              left: 12, right: 12, bottom: 12,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(12)),
                child: const Text(
                  'Rider has not shared a fix yet (or GPS is denied). Check again in a minute — the map fills in as soon as they ping.',
                  style: TextStyle(color: Colors.white, fontSize: 12, height: 1.4),
                ),
              ),
            ),
        ])),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(
                _rider != null
                    ? 'Last fix: ${_live?['seen_at'] ?? 'just now'}'
                    : 'Waiting for rider…',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
              ),
              if (_error.isNotEmpty) Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(_error, style: const TextStyle(color: AppColors.muted, fontSize: 11)),
              ),
              const SizedBox(height: 8),
              const Text(
                'This is the DropOff live map. The rider pin refreshes every 12 seconds while this screen is open.',
                style: TextStyle(color: AppColors.muted, fontSize: 11.5, height: 1.4),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}
