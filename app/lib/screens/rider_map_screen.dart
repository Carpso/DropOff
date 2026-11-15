import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../data/dropoff_api.dart';
import '../ui/app_theme.dart';
import '../ui/in_app_browser.dart';
import '../widgets/rider_map.dart';

/// Sender-side live rider screen: PMTiles Zambia map, fresh fix every 12s while open.
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
  }

  LatLng? get _pickup =>
      (_live?['pickup_lat'] != null && _live?['pickup_lng'] != null)
          ? LatLng((_live!['pickup_lat'] as num).toDouble(), (_live!['pickup_lng'] as num).toDouble())
          : null;

  LatLng? get _rider =>
      (_live?['lat'] != null && _live?['lng'] != null)
          ? LatLng((_live!['lat'] as num).toDouble(), (_live!['lng'] as num).toDouble())
          : null;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.canvas,
        elevation: 0,
        title: const Text('Rider live', style: TextStyle(fontWeight: FontWeight.w900)),
        actions: [IconButton(tooltip: 'Refresh', icon: const Icon(Icons.refresh), onPressed: _refresh)],
      ),
      body: Column(children: [
        Expanded(child: Stack(children: [
          RiderMap(pickup: _pickup, rider: _rider, depot: RiderMap.chibolya),
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
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    icon: const Icon(Icons.navigation_rounded),
                    label: const Text('Navigate to route', maxLines: 1, overflow: TextOverflow.ellipsis),
                    onPressed: _rider == null
                        ? null
                        : () => openInApp('https://waze.com/ul?ll=${_rider!.latitude},${_rider!.longitude}&navigate=yes'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    icon: const Icon(Icons.map_outlined),
                    label: const Text('Google Maps', maxLines: 1, overflow: TextOverflow.ellipsis),
                    onPressed: _rider == null
                        ? null
                        : () => openInApp(_live?['maps_link'] as String? ?? 'https://maps.google.com/?q=${_rider!.latitude},${_rider!.longitude}'),
                  ),
                ),
              ]),
            ]),
          ),
        ),
      ]),
    );
  }
}
