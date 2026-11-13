// :Godfrey Moses Kalambo:Carpso Solutions:0968551110.
import 'dart:async';

import '../data/dropoff_api.dart';

/// Shared pay-and-poll used by every "pay for this booking" surface (the
/// booking-flow screen, the success/held screen and the bookings list).
///
/// Sends a Lipila mobile-money prompt for [jobRef] and polls
/// GET /payments/:id/status until it settles (20 × 2 s ≈ 40 s).
///
/// Returns:
///   'success' | 'failed' | 'pending'  — Lipila's verdict on the prompt
///   'error:<reason>'                   — the prompt could not be started at all
class PayJob {
  PayJob._();

  static Future<String> startAndPoll({required String jobRef, required String phone}) async {
    final res = await DropOffApi.pay(
      jobRef: jobRef,
      phone: phone,
      // A fresh key per attempt: re-sending is the whole point of the retry
      // path (the booking is held until one prompt lands).
      idempotencyKey: 'pay-$jobRef-${DateTime.now().millisecondsSinceEpoch}',
    );
    if (!res.ok) return 'error:${res.error ?? 'network'}';
    final paymentId = '${res.body['payment_id']}';
    var status = 'pending';
    for (var attempt = 0; attempt < 20 && status == 'pending'; attempt++) {
      await Future<void>.delayed(const Duration(seconds: 2));
      status = await DropOffApi.paymentStatus(paymentId) ?? 'pending';
    }
    return status;
  }
}
