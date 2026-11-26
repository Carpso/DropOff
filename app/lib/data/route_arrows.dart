import 'package:latlong2/latlong.dart';

/// One direction chevron placed on a route line.
class RouteArrowSpec {
  const RouteArrowSpec({required this.point, required this.bearingDeg});

  /// Where the chevron sits on the polyline.
  final LatLng point;

  /// Compass bearing (0-360, clockwise from north) of the road segment under
  /// the chevron - the direction the rider is travelling.
  final double bearingDeg;
}

/// Places direction chevrons along [route] so the green line reads as
/// "travelling THIS way" instead of a static stroke (owner 2026-11-26).
///
/// Rules:
/// - a straight-line fallback is never decorated (it is not a road route),
/// - routes shorter than [minRouteMeters] get no arrows (they would clutter),
/// - the count scales with distance and never exceeds [maxArrows],
/// - every arrow sits ON the polyline and points along its segment.
List<RouteArrowSpec> routeArrowSpecs(
  List<LatLng> route, {
  bool straightLine = false,
  int maxArrows = 6,
  double minRouteMeters = 220,
}) {
  if (straightLine || route.length < 3 || maxArrows <= 0) return const [];
  const d = Distance();
  var total = 0.0;
  for (var i = 0; i < route.length - 1; i++) {
    total += d.as(LengthUnit.Meter, route[i], route[i + 1]);
  }
  if (total < minRouteMeters) return const [];

  final wanted = total > 7000 ? 6 : total > 4000 ? 5 : total > 2000 ? 4 : total > 900 ? 3 : 2;
  final count = wanted > maxArrows ? maxArrows : wanted;
  final step = total / (count + 1);

  final out = <RouteArrowSpec>[];
  var travelled = 0.0;
  var nextAt = step;
  for (var i = 0; i < route.length - 1 && out.length < count; i++) {
    final a = route[i];
    final b = route[i + 1];
    final seg = d.as(LengthUnit.Meter, a, b);
    if (seg <= 0) continue;
    while (nextAt <= travelled + seg && out.length < count) {
      final t = ((nextAt - travelled) / seg).clamp(0.0, 1.0);
      final raw = d.bearing(a, b);
      out.add(RouteArrowSpec(
        point: LatLng(
          a.latitude + (b.latitude - a.latitude) * t,
          a.longitude + (b.longitude - a.longitude) * t,
        ),
        // latlong2 returns -180..180; normalise to a 0..360 compass bearing so
        // the contract is unambiguous for the marker rotation.
        bearingDeg: raw < 0 ? raw + 360 : raw,
      ));
      nextAt += step;
    }
    travelled += seg;
  }
  return out;
}
