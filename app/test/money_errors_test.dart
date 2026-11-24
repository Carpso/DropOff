import 'package:dropoff/data/dropoff_api.dart';
import 'package:dropoff/ui/money_errors.dart';
import 'package:flutter_test/flutter_test.dart';

/// Courier-bill error copy (owner bug 2026-11-23, DRO-261121-3ME9J). A provider
/// outage, a stale receipt and a wrong-account job must never all collapse into
/// "check your connection and balance".
void main() {
  group('counterFareErrorText', () {
    test('network outage says so plainly', () {
      final t = counterFareErrorText(const ApiResponse(error: 'network_error'));
      expect(t, contains('unreachable'));
      expect(t, contains('connection'));
    });

    test('provider rejection names Lipila and confirms no money was taken', () {
      final t = counterFareErrorText(const ApiResponse(
        status: 502,
        error: 'lipila_init_failed',
        body: {'detail': 'gateway timeout'},
      ));
      expect(t, contains('could not send the mobile money prompt'));
      expect(t, contains('gateway timeout'));
      expect(t.toLowerCase(), contains('no money was taken'));
      expect(t, contains('check your signal'));
    });

    test('stale receipt and wrong-account job get their own next steps', () {
      expect(counterFareErrorText(const ApiResponse(error: 'no_counter_receipt')), contains('not been filed'));
      expect(counterFareErrorText(const ApiResponse(error: 'forbidden')), contains('different account'));
      expect(counterFareErrorText(const ApiResponse(error: 'job not found')), contains('syncing'));
    });

    test('rate limiting and 5xx do not blame the sender', () {
      expect(counterFareErrorText(const ApiResponse(error: 'too_many_requests')), contains('wait a minute'));
      expect(counterFareErrorText(const ApiResponse(status: 503, error: 'http_503')), contains('payment service'));
    });

    test('always hides raw codes but keeps the server plain-language detail', () {
      final t = counterFareErrorText(const ApiResponse(status: 409, error: 'weird_code', body: {'detail': 'Receipt already settled.'}));
      expect(t, 'Receipt already settled.');
    });
  });
}
