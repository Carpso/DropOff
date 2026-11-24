import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import 'dropoff_api.dart';

/// One routing/search service for everything drawn on the DropOff map.
///
/// Routing: DropOff Worker `/maps/route` — open-source OSRM served from
/// infra/router (or any ORS key set server-side). Road-following routes
/// arrive cached and signed-in-only; when unreachable, the caller draws a
/// clearly-labelled straight line — NEVER a fake road. See
/// infra/router/README.md for the one-time self-host setup.
///
/// Search: Photon (photon.komoot.io) — free OSM geocoder with a location
/// bias, built for type-ahead. Zambia coverage via OSM; no key.

class RouteStep {
  final String instruction;
  final double distanceMetres;

  /// Maneuver point [lat,lng] from the routing engine. Voice cues are spoken
  /// from the rider's live GPS distance to THIS point — not from a timed list.
  final LatLng? location;

  const RouteStep(this.instruction, this.distanceMetres, {this.location});
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
  static const _photonBase = 'https://photon.komoot.io/api/';
  static const Duration _timeout = Duration(seconds: 8);

  /// Routing order: DropOff Worker proxy (OSRM self-host / ORS key server-side,
  /// cached) → null (caller draws a labelled straight line). Riders always get
  /// *some* direction; quality upgrades when the owner hosts the router.
  static Future<RouteResult?> route(LatLng from, LatLng to) async {
    return _routeViaWorker(from, to);
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
          .map((s) {
            final lat = (s['lat'] as num?)?.toDouble();
            final lng = (s['lng'] as num?)?.toDouble();
            return RouteStep(
              '${s['instruction'] ?? ''}',
              (s['distance_m'] as num?)?.toDouble() ?? 0,
              location: lat != null && lng != null ? LatLng(lat, lng) : null,
            );
          })
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

  /// LUSAKA LOCK (owner directive 2026-11-17: the app once suggested a pickup
  /// outside Lusaka): every geocode result is filtered to this Lusaka metro
  /// box AND the Zambia country code. Photon's lat/lon is only a soft bias;
  /// the bbox parameter plus this client-side check make the lock hard.
  static const double _lusakaMinLon = 28.05, _lusakaMinLat = -15.62;
  static const double _lusakaMaxLon = 28.55, _lusakaMaxLat = -15.18;

  static bool _inLusaka(double lat, double lon) =>
      lat >= _lusakaMinLat && lat <= _lusakaMaxLat && lon >= _lusakaMinLon && lon <= _lusakaMaxLon;

  /// Type-ahead place search, HARD-LOCKED to Lusaka.
  static Future<List<MapSearchResult>> search(String query, {LatLng? bias}) async {
    final q = query.trim();
    if (q.length < 3) return const [];
    try {
      final b = bias ?? const LatLng(-15.4167, 28.2833); // Lusaka
      final url = Uri.parse(
          '$_photonBase?q=${Uri.encodeQueryComponent(q)}&lat=${b.latitude}&lon=${b.longitude}'
          '&bbox=$_lusakaMinLon,$_lusakaMinLat,$_lusakaMaxLon,$_lusakaMaxLat&limit=20&lang=en');
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
        final lat = (coords[1] as num).toDouble();
        final lon = (coords[0] as num).toDouble();
        // HARD LUSAKA LOCK — outside the box or outside Zambia: never shown.
        if (!_inLusaka(lat, lon)) continue;
        final country = '${p['countrycode'] ?? p['country'] ?? ''}'.trim().toLowerCase();
        if (country.isNotEmpty && country != 'zm' && country != 'zambia') continue;
        final name = '${p['name'] ?? ''}'.trim();
        final city = '${p['city'] ?? p['town'] ?? p['village'] ?? ''}'.trim();
        final label = [if (name.isNotEmpty) name, if (city.isNotEmpty && city != name) city].join(', ');
        if (label.isEmpty) continue;
        if (!seen.add(label.toLowerCase())) continue;
        out.add(MapSearchResult(label, LatLng(lat, lon)));
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  /// Reverse geocode a coordinate to a place name (Photon). Returns null if
  /// no name is available. Best-effort; never throws.
  static Future<String?> reverse(LatLng point) async {
    try {
      final url = Uri.parse(
          'https://photon.komoot.io/reverse?lat=${point.latitude}&lon=${point.longitude}&lang=en');
      final res = await http.get(url).timeout(_timeout);
      if (res.statusCode != 200) return null;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final features = (data['features'] as List?) ?? const [];
      if (features.isEmpty) return null;
      final p = (features.first as Map<String, dynamic>)['properties'] as Map<String, dynamic>? ?? const {};
      final name = '${p['name'] ?? ''}'.trim();
      final city = '${p['city'] ?? p['town'] ?? p['village'] ?? ''}'.trim();
      if (name.isEmpty) return null;
      if (city.isNotEmpty && city != name) return '$name, $city';
      return name;
    } catch (_) {
      return null;
    }
  }
}
