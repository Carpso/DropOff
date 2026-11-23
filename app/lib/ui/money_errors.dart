import '../data/dropoff_api.dart';

/// Shared money-path error copy. Every failure that reaches the user
/// distinguishes server-side truth from a real network outage — never a bare
/// "network error" for a provider rejection (Lipila, bank, our worker).
String moneyErrorText(ApiResponse r, String fallback) {
  final err = r.error ?? '';
  final detail = r.body['detail']?.toString() ?? '';
  if (err == 'network_error') return 'Mobile-money service unreachable right now — check your connection and retry.';
  if (err == 'lipila_init_failed') {
    final tail = detail.length > 90 ? '${detail.substring(0, 90)}…' : detail;
    return 'Lipila rejected the prompt${tail.isEmpty ? '' : ' ($tail)'} — verify your momo balance has the funds, then tap Pay now again. The plan did not start.';
  }
  if (err == 'payment_already_pending') return 'A prompt is already waiting on your phone — approve it first.';
  if (err == 'too_many_requests') return 'Too many attempts — wait a minute and try again.';
  if (err == 'identity_required' || err == 'unauthorized') return 'Sign in first — your plan is tied to your phone.';
  if (err == 'no_subscription' || err == 'choose_a_plan') return 'Choose a plan first, then tap Start.';
  if (err.startsWith('http_')) return 'Payment provider returned an error — try again in a moment.';
  if (err.isEmpty) return fallback;
  return fallback;
}

/// Courier-bill (depot counter fare) errors. These used to be flattened into
/// one "check your connection and balance" toast, which blamed the sender for
/// provider outages, wrong-account jobs and stale receipts alike (owner bug
/// 2026-11-23, booking DRO-261121-3ME9J). Every branch here is either the
/// server's own plain-language detail or a next step the sender can take.
String counterFareErrorText(ApiResponse r) {
  final err = r.error ?? '';
  final detail = r.body['detail']?.toString().trim() ?? '';
  final tail = detail.isEmpty ? '' : ' (${detail.length > 80 ? '${detail.substring(0, 80)}…' : detail})';
  if (err == 'counter_fare_already_paid') return 'This courier bill is already paid — the receipt is unlocked.';
  if (err == 'no_counter_receipt') return 'The depot receipt has not been filed yet — check again in a few minutes.';
  if (err == 'job not found') return 'This booking is still syncing — reopen it in a moment and try again.';
  if (err == 'forbidden') return 'This courier bill belongs to a different account — sign in with the sender number.';
  if (err == 'missing phone' || err == 'identity_required' || err == 'unauthorized') {
    return 'Sign in first to pay the courier bill.';
  }
  if (err == 'too_many_requests') return 'Too many attempts — wait a minute and try again.';
  if (err == 'network_error' || err == 'offline_demo_mode') {
    return 'The money service is unreachable right now — check your connection and try again.';
  }
  if (err == 'lipila_init_failed') {
    return 'The momo prompt could not be started$tail — no money was taken. Try again in a moment.';
  }
  if (err.startsWith('http_')) return 'The payment service returned an error — no money was taken. Try again in a moment.';
  if (detail.isNotEmpty) return detail;
  return 'Could not start the courier payment — no money was taken. Try again in a moment.';
}
