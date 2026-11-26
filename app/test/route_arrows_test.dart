import 'package:dropoff/data/route_arrows.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

/// Direction chevrons on the route line (owner 2026-11-26: "add an arrow on the
/// map routing to show the rider"). These pin the three things that make the
/// arrows trustworthy: they sit ON the route, they point ALONG the direction of
/// travel, and they never decorate a route that is not really a road route.
void main() {
  // A ~2.2 km eastbound run through Lusaka, split into three segments.
  const start = LatLng(-15.4167, 28.2833);
  const mid1 = LatLng(-15.4167, 28.2933);
  const mid2 = LatLng(-15.4167, 28.3033);
  const end = LatLng(-15.4167, 28.3133);
  const eastbound = [start, mid1, mid2, end];

  test('an eastbound route gets arrows pointing east', () {
    final arrows = routeArrowSpecs(eastbound);
    expect(arrows, isNotEmpty);
    for (final a in arrows) {
      // Eastbound bearing is ~90 degrees (latlong2 may return 89.9x).
      expect(a.bearingDeg, closeTo(90, 1.0));
      // Every arrow sits on the horizontal line of the route.
      expect(a.point.latitude, closeTo(start.latitude, 1e-6));
      expect(a.point.longitude, inInclusiveRange(start.longitude, end.longitude));
    }
  });

  test('a reversed route flips every arrow', () {
    final forward = routeArrowSpecs(eastbound);
    final backward = routeArrowSpecs(eastbound.reversed.toList());
    expect(forward.length, backward.length);
    for (final a in backward) {
      expect(a.bearingDeg, closeTo(270, 1.0));
    }
  });

  test('arrows are ordered along the route and never duplicated', () {
    final arrows = routeArrowSpecs(eastbound);
    final lngs = arrows.map((a) => a.point.longitude).toList();
    final sorted = [...lngs]..sort();
    expect(lngs, sorted, reason: 'arrows must follow the direction of travel');
    expect(lngs.toSet().length, lngs.length, reason: 'no two arrows on one spot');
  });

  test('longer routes get more arrows but never more than the cap', () {
    final shortRoute = routeArrowSpecs([start, const LatLng(-15.4167, 28.2873)]);
    expect(shortRoute, isEmpty, reason: 'fewer than 3 points is not a polyline');

    final many = routeArrowSpecs(eastbound, maxArrows: 2);
    expect(many.length, lessThanOrEqualTo(2));

    // A 60 km route should hit the ceiling, not grow without bound.
    final long = routeArrowSpecs(const [
      LatLng(-15.4167, 28.2833),
      LatLng(-15.4167, 28.5833),
      LatLng(-15.4167, 28.8833),
    ]);
    expect(long.length, 6);
  });

  test('a straight-line fallback or a very short hop gets no arrows', () {
    expect(routeArrowSpecs(eastbound, straightLine: true), isEmpty);
    // ~110 m: too short to decorate.
    expect(routeArrowSpecs(const [
      LatLng(-15.4167, 28.2833),
      LatLng(-15.4167, 28.2843),
      LatLng(-15.4167, 28.2853),
    ]), isEmpty);
    expect(routeArrowSpecs(const []), isEmpty);
  });
}
