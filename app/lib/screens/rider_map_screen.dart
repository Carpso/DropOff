import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../data/dropoff_api.dart';
import '../data/freshness.dart';
import '../data/map_services.dart';
import '../ui/app_theme.dart';
import '../widgets/rider_map.dart';

/// Sender-side live rider screen: the DropOff map (Protomaps Zambia/Zimbabwe/Malawi/Mozambique on our R2), fresh fix every 12 s while open, road-following route line when OSRM answers.
class RiderMapScreen extends StatefulWidget {
  final String jobRef;

  /// Optional synthetic payload for the admin self-test — no polling, no API.
  final Map<String, dynamic>? preview;

  const RiderMapScreen({super.key, required this.jobRef, this.preview});

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
    if (widget.preview != null) {
      _live = widget.preview;
    } else {
      _refresh();
      _timer = Timer.periodic(const Duration(seconds: 12), (_) => _refresh());
    }
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

  /// END of the CURRENT leg, chosen by the server's tracking stage:
  /// before pickup it is the sender's door; after pickup it is the courier
  /// depot; a collection heads to the recipient's door (no GPS pin).
  LatLng? get _activeDest {
    final lat = _live?['dest_lat'];
    final lng = _live?['dest_lng'];
    if (lat != null && lng != null) {
      return LatLng((lat as num).toDouble(), (lng as num).toDouble());
    }
    return _pickup;
  }

  LatLng? get _depot {
    // Only draw the warehouse pin when it is actually the active destination.
    if ('${_live?['stage']?['destination'] ?? ''}' != 'depot') return null;
    return (_live?['depot_lat'] != null && _live?['depot_lng'] != null)
        ? LatLng((_live!['depot_lat'] as num).toDouble(), (_live!['depot_lng'] as num).toDouble())
        : _activeDest;
  }

  Map<String, dynamic>? get _stage => _live?['stage'] as Map<String, dynamic>?;
  String get _stageLabel => '${_stage?['label'] ?? 'On the move'}';
  bool get _ended => _live?['ended'] == true || _stage?['live'] == false;
  bool get _stale => _live?['stale'] == true || isStaleFix(_live?['seen_at']);

  RouteResult? _route;
  LatLng? _routeOrigin;

  /// Road-following rider→pickup route (OSRM). Refetched when the rider
  /// moves >150 m so the line tracks the drive, not a stale snapshot.
  bool _routeLoading = false;

  Future<void> _maybeRoute() async {
    final me = _rider, dest = _ended ? null : _activeDest;
    if (me == null || dest == null || _routeLoading) return;
    if (_route != null && _routeOrigin != null &&
        const Distance().as(LengthUnit.Meter, _routeOrigin!, me) < 150) {
      return;
    }
    _routeLoading = true;
    final route = await MapServices.route(me, dest);
    _routeLoading = false;
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
        // Green heading, matching the in-app navigator (owner 2026-11-26).
        backgroundColor: AppColors.forest,
        surfaceTintColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Row(mainAxisSize: MainAxisSize.min, children: [
          const Text('Rider live', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Colors.white)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(color: AppColors.mint.withValues(alpha: 0.22), borderRadius: BorderRadius.circular(20)),
            child: Text(widget.preview != null ? 'DEMO' : 'LIVE',
                style: const TextStyle(color: AppColors.mint, fontSize: 9.5, fontWeight: FontWeight.w900, letterSpacing: 1)),
          ),
        ]),
        actions: [
          if (widget.preview == null)
            IconButton(tooltip: 'Refresh', icon: const Icon(Icons.refresh), onPressed: _refresh),
        ],
      ),
      body: Column(children: [
        Expanded(child: Stack(children: [
          RiderMap(
            pickup: _pickup,
            rider: _rider,
            depot: _depot,
            route: _route?.points ??
                ((_rider != null && _activeDest != null && !_ended) ? [_rider!, _activeDest!] : null),
            routeIsStraightLine: _route == null,
            vehicleClass: '${_live?['vehicle_class'] ?? 'motorcycle'}',
            // Names for labels on map markers (owner: map should show names,
            // not just icons).
            courierName: '${_live?['courier_name'] ?? ''}',
            depotName: '${_live?['depot_name'] ?? ''}',
            recipientName: '${_live?['recipient_name'] ?? ''}',
            senderName: '${_live?['sender_name'] ?? ''}',
            city: '${_live?['from_city'] ?? _live?['city'] ?? 'Lusaka'}',
          ),
          if (_ended)
            Positioned(
              left: 12, right: 12, bottom: 12,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: AppColors.forest.withValues(alpha: 0.92), borderRadius: BorderRadius.circular(12)),
                child: Text('${_live?['note'] ?? 'Tracking has ended.'}',
                    style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w700, height: 1.4)),
              ),
            )
          else if (_live == null || _live!['lat'] == null)
            Positioned(
              left: 12, right: 12, bottom: 12,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(12)),
                child: const Text(
                  'Waiting for the rider\'s live location. It will appear here as soon as their next GPS update arrives.',
                  style: TextStyle(color: Colors.white, fontSize: 12, height: 1.4),
                ),
              ),
            )
          else if (_stale)
            Positioned(
              left: 12, right: 12, bottom: 12,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: AppColors.amber.withValues(alpha: 0.95), borderRadius: BorderRadius.circular(12)),
                child: const Text(
                  'Last GPS fix is old — the rider may have moved since. Waiting for a fresh update.',
                  style: TextStyle(color: AppColors.ink, fontSize: 12, fontWeight: FontWeight.w700, height: 1.4),
                ),
              ),
            ),
        ])),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
            child: Card(
              margin: EdgeInsets.zero,
              clipBehavior: Clip.antiAlias,
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Container(
                  color: AppColors.forest,
                  padding: const EdgeInsets.fromLTRB(12, 7, 10, 7),
                  child: Row(children: [
                    Icon(_ended ? Icons.flag_circle : (_stale ? Icons.history_toggle_off : Icons.my_location),
                        color: AppColors.mint, size: 16),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(_ended ? 'JOURNEY COMPLETE' : 'RIDER LIVE',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w900, letterSpacing: 1.1)),
                    ),
                    Text(
                      _ended ? 'TRACKING ENDED' : _stale ? 'STALE FIX' : 'UPDATING · 12 s',
                      style: TextStyle(color: _stale ? AppColors.amber : AppColors.mint,
                          fontSize: 9.5, fontWeight: FontWeight.w900, letterSpacing: 0.4),
                    ),
                  ]),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      CircleAvatar(
                        radius: 18,
                        backgroundColor: AppColors.forest.withValues(alpha: 0.12),
                        child: Text(
                          '${_live?['rider_name'] ?? '?'}'.trim().isEmpty
                              ? '?'
                              : '${_live?['rider_name']}'.trim()[0].toUpperCase(),
                          style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.forest),
                        ),
                      ),
                      const SizedBox(width: 9),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(
                          '${_live?['rider_name'] ?? 'Your rider'}',
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: AppColors.forest),
                        ),
                        Text('${_live?['rider_vehicle'] ?? 'motorcycle'} · ${_live?['dest_label'] ?? ''}',
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11, color: AppColors.muted)),
                      ])),
                    ]),
                    const SizedBox(height: 8),
                    Text(_stageLabel,
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: AppColors.ink)),
                    const SizedBox(height: 3),
                    Row(children: [
                      const Icon(Icons.pin_drop_outlined, size: 14, color: AppColors.forestLight),
                      const SizedBox(width: 5),
                      Expanded(child: Text(_ended
                          ? '${_live?['note'] ?? 'Journey complete'}'
                          : 'Heading to ${_live?['dest_label'] ?? 'your stop'}',
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, color: AppColors.muted))),
                      if (_live?['eta_minutes'] != null && !_ended)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(color: AppColors.forest.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(20)),
                          child: Text('~${_live!['eta_minutes']} min',
                              style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900, color: AppColors.forest)),
                        ),
                    ]),
                    const SizedBox(height: 6),
                    Text(
                      _rider != null
                          ? 'Last fix ${fixAgeLabel(_live?['seen_at'])}${_stale ? ' — waiting for a fresh GPS update' : ''}'
                          : 'Waiting for your rider…',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                          color: _stale ? AppColors.danger : AppColors.muted),
                    ),
                    if (_error.isNotEmpty) Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(_error, style: const TextStyle(color: AppColors.muted, fontSize: 11.5)),
                    ),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}
