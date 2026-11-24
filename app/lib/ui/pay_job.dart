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
///   status — 'success' | 'failed' | 'pending' (Lipila's verdict on the prompt)
///            or 'error:<reason>' when the prompt could not be started at all
///   failReason — the telco's own failure message when status == 'failed'
///            (e.g. "User wallet does not have enough money to cover the
///            payable amount."). Owner directive 2026-11-17: the payer must
///            see WHY a prompt failed, not a generic rejection.
class PayJob {
  PayJob._();

  static Future<({String status, String? failReason})> startAndPoll({required String jobRef, required String phone}) async {
    final res = await DropOffApi.pay(
      jobRef: jobRef,
      phone: phone,
      // A fresh key per attempt: re-sending is the whole point of the retry
      // path (the booking is held until one prompt lands).
      idempotencyKey: 'pay-$jobRef-${DateTime.now().millisecondsSinceEpoch}',
    );
    if (!res.ok) return (status: 'error:${res.error ?? 'network'}', failReason: null);
    final paymentId = '${res.body['payment_id']}';
    var status = 'pending';
    String? failReason;
    // Fast phase: catches the common approve-right-away case.
    for (var attempt = 0; attempt < 20 && status == 'pending'; attempt++) {
      await Future<void>.delayed(const Duration(seconds: 2));
      final st = await DropOffApi.paymentStatus(paymentId);
      status = st.$1 ?? 'pending';
      failReason = st.$2;
    }
    // Slow tail: the phone may still be showing the prompt — keep watching.
    for (var attempt = 0; attempt < 6 && status == 'pending'; attempt++) {
      await Future<void>.delayed(const Duration(seconds: 5));
      final st = await DropOffApi.paymentStatus(paymentId);
      status = st.$1 ?? 'pending';
      failReason = st.$2;
    }
    if (status == 'failed') {
      // Safety recheck: provider/webhook status can lag behind a debit.
      await Future<void>.delayed(const Duration(seconds: 3));
      final recheck = await DropOffApi.paymentStatus(paymentId);
      status = recheck.$1 ?? status;
      failReason = recheck.$2 ?? failReason;
    }
    return (status: status, failReason: failReason);
  }
}
