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
  if (err.startsWith('http_')) return 'Payment provider returned an error ($err) — try again.';
  if (err.isEmpty) return fallback;
  return '$fallback ($err)';
}
