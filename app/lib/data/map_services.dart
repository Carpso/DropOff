import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import 'dropoff_api.dart';

/// One routing/search service for everything drawn on the DropOff map.
///
/// Routing: public OSRM demo server (router.project-osrm.org) — free, no
/// key, fair-use limits. Self-hosting OSRM is the production answer and
/// stays on the roadmap; until then callers fall back to a straight line
/// (clearly labelled "as the crow flies") so the app NEVER shows a false
/// road-following line.
///
/// Search: Photon (photon.komoot.io) — free OSM geocoder with a location
/// bias, built for type-ahead. Zambia coverage via OSM; no key.

class RouteStep {
  final String instruction;
  final double distanceMetres;
  const RouteStep(this.instruction, this.distanceMetres);
}

class RouteResult {
  final List<LatLng> points;
  final double distanceMetres;
  final double durationSeconds;
  final List<RouteStep> steps;
  final bool fromRoutingEngine;
  const RouteResult({
    required this.points,
    required this.distanceMetres,
    required this.durationSeconds,
    required this.steps,
    this.fromRoutingEngine = true,
  });

  /// Straight-line fallback when OSRM is unreachable — never shown as a road.
  factory RouteResult.straightLine(LatLng from, LatLng to) {
    final metres = const Distance().as(LengthUnit.Meter, from, to);
    return RouteResult(
      points: [from, to],
      distanceMetres: metres,
      durationSeconds: metres / 1000 / 25 * 3600,
      steps: const [],
      fromRoutingEngine: false,
    );
  }

  String get distanceLabel =>
      distanceMetres < 1000 ? '${distanceMetres.round()} m' : '${(distanceMetres / 1000).toStringAsFixed(1)} km';

  String get durationLabel {
    final minutes = (durationSeconds / 60).round();
    if (minutes < 60) return '~$minutes min';
    final h = minutes ~/ 60, m = minutes % 60;
    return '~${h}h ${m.toString().padLeft(2, '0')}m';
  }
}

class MapSearchResult {
  final String label;
  final LatLng point;
  const MapSearchResult(this.label, this.point);
}

class MapServices {
  static const _osrmBase = 'https://router.project-osrm.org/route/v1/driving/';
  static const _photonBase = 'https://photon.komoot.io/api/';
  static const Duration _timeout = Duration(seconds: 8);

  /// Routing order: DropOff Worker proxy (ORS key server-side, cached) →
  /// public OSRM demo (evaluation-grade, works at launch volume) → null
  /// (caller draws a labelled straight line). Riders always get *some*
  /// directions; quality upgrades with one server-side secret.
  static Future<RouteResult?> route(LatLng from, LatLng to) async {
    final viaWorker = await _routeViaWorker(from, to);
    if (viaWorker != null) return viaWorker;
    try {
      final url = Uri.parse(
          '$_osrmBase${from.longitude},${from.latitude};${to.longitude},${to.latitude}'
          '?overview=full&geometries=geojson&steps=true&continue_straight=true');
      final res = await http.get(url).timeout(_timeout);
      if (res.statusCode != 200) return null;
      final data = jsonDecode(res.body);
      final list = (data as Map<String, dynamic>)['routes'] as List?;
      if (list == null || list.isEmpty) return null;
      final r = list.first as Map<String, dynamic>;
      final coords = ((r['geometry'] as Map)['coordinates'] as List)
          .map((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()))
          .toList();
      if (coords.length < 2) return null;
      final steps = <RouteStep>[];
      for (final leg in ((r['legs'] as List?) ?? const [])) {
        for (final s in ((leg['steps'] as List?) ?? const [])) {
          final step = s as Map<String, dynamic>;
          final man = (step['maneuver'] as Map?) ?? const {};
          steps.add(RouteStep(
            _instruction(
              '${man['type'] ?? ''}',
              '${man['modifier'] ?? ''}',
              '${step['name'] ?? ''}',
            ),
            (step['distance'] as num?)?.toDouble() ?? 0,
          ));
        }
      }
      return RouteResult(
        points: coords,
        distanceMetres: (r['distance'] as num?)?.toDouble() ?? 0,
        durationSeconds: (r['duration'] as num?)?.toDouble() ?? 0,
        steps: steps,
      );
    } catch (_) {
      return null;
    }
  }

  /// Road route via OUR worker — the ORS API key never ships in the binary,
  /// and identical coordinate pairs are cached server-side.
  static Future<RouteResult?> _routeViaWorker(LatLng from, LatLng to) async {
    if (!DropOffApi.enabled || DropOffApi.token == null) return null;
    try {
      final f = '${from.longitude.toStringAsFixed(5)},${from.latitude.toStringAsFixed(5)}';
      final t = '${to.longitude.toStringAsFixed(5)},${to.latitude.toStringAsFixed(5)}';
      final res = await http.get(
        Uri.parse('${DropOffApi.baseUrl}/maps/route?from=$f&to=$t'),
        headers: {
          'Content-Type': 'application/json',
          if (DropOffApi.apiKey.isNotEmpty) 'X-Api-Key': DropOffApi.apiKey,
          'Authorization': 'Bearer ${DropOffApi.token}',
          if (DropOffApi.deviceId.isNotEmpty) 'X-Device-Id': DropOffApi.deviceId,
        },
      ).timeout(_timeout);
      if (res.statusCode != 200) return null; // 503 not configured / 502 upstream — fall back to OSRM demo
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final pts = ((data['points'] as List?) ?? const [])
          .map((p) => LatLng((p[0] as num).toDouble(), (p[1] as num).toDouble()))
          .toList();
      if (pts.length < 2) return null;
      final steps = ((data['steps'] as List?) ?? const [])
          .map((s) => RouteStep('${s['instruction'] ?? ''}', (s['distance_m'] as num?)?.toDouble() ?? 0))
          .where((s) => s.instruction.isNotEmpty)
          .toList();
      return RouteResult(
        points: pts,
        distanceMetres: (data['distance_m'] as num?)?.toDouble() ?? 0,
        durationSeconds: (data['duration_s'] as num?)?.toDouble() ?? 0,
        steps: steps,
      );
    } catch (_) {
      return null;
    }
  }

  /// Type-ahead place search, biased to our operating region (Lusaka).
  static Future<List<MapSearchResult>> search(String query, {LatLng? bias}) async {
    final q = query.trim();
    if (q.length < 3) return const [];
    try {
      final b = bias ?? const LatLng(-15.4167, 28.2833); // Lusaka
      final url = Uri.parse(
          '$_photonBase?q=${Uri.encodeQueryComponent(q)}&lat=${b.latitude}&lon=${b.longitude}&limit=6&lang=en');
      final res = await http.get(url).timeout(_timeout);
      if (res.statusCode != 200) return const [];
      final data = jsonDecode(res.body);
      final features = (data as Map<String, dynamic>)['features'] as List? ?? const [];
      final seen = <String>{};
      final out = <MapSearchResult>[];
      for (final f in features) {
        final p = (f as Map<String, dynamic>)['properties'] as Map<String, dynamic>? ?? const {};
        final coords = ((f['geometry'] as Map?)?['coordinates'] as List?) ?? const [];
        if (coords.length < 2) continue;
        final name = '${p['name'] ?? ''}'.trim();
        final city = '${p['city'] ?? p['town'] ?? p['village'] ?? ''}'.trim();
        final label = [if (name.isNotEmpty) name, if (city.isNotEmpty && city != name) city].join(', ');
        if (label.isEmpty) continue;
        if (!seen.add(label.toLowerCase())) continue;
        out.add(MapSearchResult(label, LatLng((coords[1] as num).toDouble(), (coords[0] as num).toDouble())));
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  static String _instruction(String type, String modifier, String street) {
    final dir = switch (modifier) {
      'left' => 'left',
      'right' => 'right',
      'slight left' => 'slightly left',
      'slight right' => 'slightly right',
      'sharp left' => 'sharp left',
      'sharp right' => 'sharp right',
      'straight' => 'straight',
      'uturn' => 'U-turn',
      _ => '',
    };
    final onto = street.isEmpty ? '' : ' onto $street';
    switch (type) {
      case 'depart':
        return 'Head out';
      case 'arrive':
        return 'Arrive at the destination';
      case 'turn':
        return dir.isEmpty ? 'Make the turn$onto' : 'Turn $dir$onto';
      case 'end of road':
        return dir.isEmpty ? 'Turn at the end of the road$onto' : 'Turn $dir at the end of the road$onto';
      case 'fork':
        return dir.isEmpty ? 'Keep at the fork$onto' : 'Bear $dir at the fork$onto';
      case 'merge':
        return 'Merge$onto';
      case 'ramp':
        return 'Take the ramp$onto';
      case 'on ramp':
        return 'Take the on-ramp$onto';
      case 'off ramp':
        return 'Take the exit$onto';
      case 'new name':
        return 'Continue${onto.isEmpty ? '' : onto}';
      case 'continue':
        return 'Continue straight$onto';
      case 'roundabout':
      case 'rotary':
        final exit = modifier.isEmpty ? '' : ' (exit $modifier)';
        return 'Enter the roundabout$exit$onto';
      case 'exit roundabout':
        return 'Exit the roundabout$onto';
      case 'roundabout turn':
        return dir.isEmpty ? 'Turn at the roundabout$onto' : 'Take the $dir exit at the roundabout$onto';
      case 'notification':
        return 'Continue$onto';
      default:
        return dir.isEmpty ? 'Continue$onto' : 'Turn $dir$onto';
    }
  }
}
