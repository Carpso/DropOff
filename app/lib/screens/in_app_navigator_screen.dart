import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../ui/app_theme.dart';
import '../widgets/rider_map.dart';

/// In-app navigator — the answer to "the Waze links keep breaking". Opens our
/// own map centred on the stop, drops the rider's live GPS as the moving pin
/// and draws a straight route line with distance + rough city-pace ETA.
/// Turn-by-turn needs a routing engine (tracked); the pin, map and line are
/// fully in-app — no external navigation app, no dead deep-links.
class InAppNavigatorScreen extends StatefulWidget {
  final double destLat;
  final double destLng;
  final String label;

  const InAppNavigatorScreen({
    super.key,
    required this.destLat,
    required this.destLng,
    required this.label,
  });

  @override
  State<InAppNavigatorScreen> createState() => _InAppNavigatorScreenState();
}

class _InAppNavigatorScreenState extends State<InAppNavigatorScreen> {
  LatLng? _me;
  String _error = '';
  Timer? _timer;

  LatLng get _dest => LatLng(widget.destLat, widget.destLng);

  @override
  void initState() {
    super.initState();
    _fix();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => _fix());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _fix() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        if (mounted) setState(() => _error = 'Location denied — the pin shows the stop, but not your position. Enable Location for DropOff to see yourself on the map.');
        return;
      }
      final service = await Geolocator.isLocationServiceEnabled();
      if (!service) {
        if (mounted) setState(() => _error = 'Location is off on this phone — turn it on to see your position on the map.');
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      if (!mounted) return;
      setState(() {
        _me = LatLng(pos.latitude, pos.longitude);
        _error = '';
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not get your position — check Location and try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = _me;
    final metres = me == null ? null : const Distance().as(LengthUnit.Meter, me, _dest);
    final minutes = metres == null ? null : (metres / 1000 / 25 * 60).round();
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.canvas,
        elevation: 0,
        title: const Text('Navigate', style: TextStyle(fontWeight: FontWeight.w900)),
        actions: [IconButton(tooltip: 'Refresh', icon: const Icon(Icons.refresh), onPressed: _fix)],
      ),
      body: Column(children: [
        Expanded(
          child: RiderMap(
            pickup: _dest,
            rider: me,
            route: me == null ? null : [me, _dest],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(widget.label, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
              const SizedBox(height: 4),
              Text(
                metres == null
                    ? 'Stop pinned on the DropOff map.'
                    : '${(metres / 1000).toStringAsFixed(metres < 1000 ? 2 : 1)} km away · ~$minutes min at city pace (25 km/h).',
                style: const TextStyle(color: AppColors.ink, fontSize: 13, height: 1.4),
              ),
              if (_error.isNotEmpty) Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(_error, style: const TextStyle(color: AppColors.muted, fontSize: 11.5, height: 1.4)),
              ),
              const SizedBox(height: 6),
              const Text('The pin, map and route line are live inside DropOff. Turn-by-turn voice guidance is coming — it needs a routing engine, not another app store link.',
                  style: TextStyle(color: AppColors.muted, fontSize: 11, height: 1.35)),
            ]),
          ),
        ),
      ]),
    );
  }
}
