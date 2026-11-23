import 'package:dropoff/screens/in_app_navigator_screen.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_test/flutter_test.dart';

/// Owner 2026-11-23: the navigator title must say where the rider is headed,
/// and that suffix must CHANGE as she approaches / arrives / re-routes.
void main() {
  const dest = LatLng(-15.3875, 28.3228); // Lusaka

  test('names the current destination with an arrow', () {
    expect(navigatorTitleSuffix('Platinum depot', null, dest), '→ Platinum depot');
  });

  test('strips a leading Deliver to so the suffix reads naturally', () {
    expect(navigatorTitleSuffix('Deliver to Chanda', null, dest), '→ Chanda');
  });

  test('changes to ahead and then arrived as the rider closes in', () {
    final me = LatLng(dest.latitude + 0.0005, dest.longitude); // ~55 m
    expect(navigatorTitleSuffix('Kabwata', me, dest), '≈ Kabwata ahead');
    final atDoor = LatLng(dest.latitude + 0.0001, dest.longitude); // ~11 m
    expect(navigatorTitleSuffix('Kabwata', atDoor, dest), '✓ Arrived at Kabwata');
  });

  test('re-routing to a saved place changes the suffix immediately', () {
    expect(navigatorTitleSuffix('Platinum depot', null, dest), '→ Platinum depot');
    expect(navigatorTitleSuffix('Home', null, dest), '→ Home');
  });

  test('empty label is honest instead of blank', () {
    expect(navigatorTitleSuffix('', null, dest), '→ your next stop');
  });
}
