// :Godfrey Moses Kalambo:Carpso Solutions:0968551110.
import 'dart:async';

import '../data/dropoff_api.dart';

/// Shared pay-and-poll used by every "pay for this booking" surface (the
/// booking-flow screen, the success/held screen and the bookings list).
///
/// Sends a Lipila mobile-money prompt for [jobRef] and polls
/// GET /payments/:id/status until it settles — a fast phase (20 × 2 s ≈ 40 s)
/// then a slower tail (6 × 5 s ≈ 30 s), ~70 s in total. The telco prompt
/// screen can sit far longer than 40 s before the user confirms (owner:
/// the first-fired prompt "flashed very quickly"), so giving up early was
/// losing payments the user had actually approved.
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
    // Fast phase: catches the common approve-right-away case.
    for (var attempt = 0; attempt < 20 && status == 'pending'; attempt++) {
      await Future<void>.delayed(const Duration(seconds: 2));
      status = await DropOffApi.paymentStatus(paymentId) ?? 'pending';
    }
    // Slow tail: the phone may still be showing the prompt — keep watching.
    for (var attempt = 0; attempt < 6 && status == 'pending'; attempt++) {
      await Future<void>.delayed(const Duration(seconds: 5));
      status = await DropOffApi.paymentStatus(paymentId) ?? 'pending';
    }
    return status;
  }
}
