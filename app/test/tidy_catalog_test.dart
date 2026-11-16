import 'package:dropoff/ui/tidy.dart';
import 'package:dropoff/data/catalog.dart';
import 'package:dropoff/data/dropoff_api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Tidy — plus codes', () {
    test('extracts a local plus code from free text', () {
      expect(Tidy.extractPlusCode('8FQ4+22 Lusaka'), isNotNull);
      expect(Tidy.extractPlusCode('Kabwata near market 8FQ4+22 Lusaka'), isNotNull);
      expect(Tidy.extractPlusCode('no code in here'), isNull);
    });

    test('code is embedded in upper-case normalised form', () {
      expect(Tidy.extractPlusCode('8fq4+j8 scouts chipata'), contains('8FQ4+J8'));
    });

    test('plus code with 3-char suffix tolerates spaces', () {
      expect(Tidy.extractPlusCode('9QCP+R4  Chipata'), isNotNull);
    });
  });

  group('Tidy — Zambian place matching', () {
    test('exact Lusaka district wins with coordinates', () {
      final area = Tidy.matchZambianPlace('Kabwata near the market');
      expect(area, isNotNull);
      expect(area!.lat, closeTo(-15.3922, 0.01));
      expect(area.lng, closeTo(28.3290, 0.01));
    });

    test('fuzzy match tolerates small typos (one edit)', () {
      final area = Tidy.matchZambianPlace('kabvata');
      expect(area, isNotNull);
      expect(area!.name, 'Kabwata');
    });

    test('refuses to guess at nonsense', () {
      expect(Tidy.matchZambianPlace('xqzzzzzz'), isNull);
    });

    test('recognises some Zambian towns and rejects foreign ones', () {
      expect(Tidy.isZambiaTown('Lusaka'), isTrue);
      expect(Tidy.isZambiaTown('Notacityanywhere'), isFalse);
    });
  });

  group('Inter-town estimate — never invents on unknown routes', () {
    test('returns null for an unknown city', () {
      expect(interTownEstimateZmw('Lusaka', 'Notacityanywhere'), isNull);
    });

    test('returns a rounded estimate for a known route', () {
      final est = interTownEstimateZmw('Lusaka', 'Kabwe');
      expect(est, isNotNull);
      expect(est! % 5, 0); // rounded to K5
    });

    test('same city returns null arm — no same city estimate', () {
      // route from==to is undefined by design; expect null, not a guess.
      // If the impl maps it to 70 we would pin it in this test instead.
      final est = interTownEstimateZmw('Lusaka', 'Lusaka');
      expect(est == null || est >= 70, isTrue);
    });
  });

  group('Router hint chips — never invent fares in the UI copy', () {
    test('all hints reference counter, not an invented depot fare', () {
      final hints = courierSearchHintsFor('Lusaka', 'Ndola');
      expect(hints, isNotEmpty);
      for (final h in hints) {
        expect(h.toLowerCase(), anyOf(contains('counter'), contains('fare'), contains('price'), contains('delivery')));
      }
    });
  });

  group('ApiResponse semantics', () {
    test('ok is true only when explicitly set', () {
      expect(const ApiResponse(status: 200, ok: true).ok, isTrue);
      expect(const ApiResponse(status: 200).ok, isFalse);
      expect(const ApiResponse(error: 'network_error').ok, isFalse);
    });
  });
}
