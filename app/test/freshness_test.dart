import 'package:dropoff/data/freshness.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 11, 28, 12, 0, 0);

  test('fresh fixes read naturally', () {
    expect(fixAgeLabel('2026-11-28 11:59:56', now: now), 'Just now');
    expect(fixAgeLabel('2026-11-28 11:59:48', now: now), '12s ago');
    expect(fixAgeLabel('2026-11-28 11:58:30', now: now), '1 min ago');
  });

  test('old fixes are explicitly stale, never presented as live', () {
    expect(fixAgeLabel('2026-11-28 11:57:00', now: now), 'Stale - 3 min ago');
    expect(isStaleFix('2026-11-28 11:57:00', now: now), isTrue);
    expect(isStaleFix('2026-11-28 11:59:48', now: now), isFalse);
  });

  test('missing or malformed fixes are stale', () {
    expect(fixAgeLabel('', now: now), 'No fix yet');
    expect(isStaleFix(null, now: now), isTrue);
    expect(isStaleFix('nonsense', now: now), isTrue);
  });
}
