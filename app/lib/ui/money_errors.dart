import '../data/dropoff_api.dart';

/// Shared money-path error copy. Every failure that reaches the user
/// distinguishes server-side truth from a real network outage — never a bare
/// "network error" for a provider rejection (Lipila, bank, our worker).
String moneyErrorText(ApiResponse r, String fallback) {
  final err = r.error ?? '';
  final detail = r.body['detail']?.toString() ?? '';
  final rawLower = detail.toLowerCase();
  if (rawLower.contains('duplicate reference')) {
    return 'A payment prompt may already have been sent. Check your phone for the prompt before trying again. If no money was deducted and no prompt arrived, wait a moment and retry.';
  }
  if (err == 'network_error') return 'Mobile-money service unreachable right now — check your connection and retry.';
  if (err == 'lipila_init_failed' || err == 'lenco_init_failed') {
    final safe = _safeMoneyDetail(detail);
    return safe.isNotEmpty
        ? '$safe Check your phone for a prompt before retrying.'
        : 'The payment prompt could not be confirmed. Check your phone for a prompt before retrying. If no prompt arrived and no money was deducted, verify your balance and try again.';
  }
  if (err == 'payment_already_pending') return 'A prompt is already waiting on your phone — approve it first.';
  if (err == 'too_many_requests') return 'Too many attempts — wait a minute and try again.';
  if (err == 'identity_required' || err == 'unauthorized') return 'Sign in first — your plan is tied to your phone.';
  if (err == 'no_subscription' || err == 'choose_a_plan') return 'Choose a plan first, then tap Start.';
  if (err.startsWith('http_')) return 'Payment provider returned an error. Check your phone for a prompt before retrying. If no money was deducted, try again in a moment.';
  if (err.isEmpty) return fallback;
  return fallback;
}

/// Courier-bill (depot counter fare) errors. These used to be flattened into
/// one "check your connection and balance" toast, which blamed the sender for
/// provider outages, wrong-account jobs and stale receipts alike (owner bug
/// 2026-11-23, booking DRO-261121-3ME9J). Every branch here is either the
/// server's own plain-language detail or a next step the sender can take.
String _safeMoneyDetail(String raw) {
  final d = raw.trim();
  if (d.isEmpty) return '';
  final lower = d.toLowerCase();
  if (lower.contains('duplicate reference') || lower.contains('errorcode":"10"') || lower.contains('errorcode":"10"')) {
    return 'A payment prompt for this bill was already sent. Check your phone for the prompt; if none arrived, wait a moment and try again.';
  }
  // Never surface raw provider JSON/blobs to users.
  if (d.startsWith('{') || d.startsWith('[') || d.contains('"success":') || d.contains('"errorCode"')) {
    return 'The payment provider returned an unexpected response. Check your phone for a prompt before retrying.';
  }
  final clean = d.replaceAll(RegExp(r'\s+'), ' ');
  return clean.length > 120 ? '${clean.substring(0, 120)}…' : clean;
}

String counterFareErrorText(ApiResponse r) {
  final err = r.error ?? '';
  final detail = r.body['detail']?.toString().trim() ?? '';
  final rawLower = detail.toLowerCase();
  final safeDetail = _safeMoneyDetail(detail);
  if (err == 'counter_fare_already_paid') return 'This courier bill is already paid — the receipt is unlocked.';
  if (err == 'no_counter_receipt') return 'The depot receipt has not been filed yet — check again in a few minutes.';
  if (err == 'job not found') return 'This booking is still syncing — reopen it in a moment and try again.';
  if (err == 'forbidden') return 'This courier bill belongs to a different account — sign in with the sender number.';
  if (err == 'missing phone' || err == 'identity_required' || err == 'unauthorized') {
    return 'Sign in first to pay the courier bill.';
  }
  if (err == 'too_many_requests') return 'Too many attempts — wait a minute and try again.';
  if (rawLower.contains('duplicate reference')) {
    return 'A payment prompt for this bill may already have been sent. Check your phone for the prompt before trying again. If no money was deducted and no prompt arrived, wait a moment and retry.';
  }
  if (err == 'network_error' || err == 'offline_demo_mode') {
    return 'The money service is unreachable right now — check your connection and try again.';
  }
  if (err == 'lipila_init_failed' || err == 'lenco_init_failed') {
    if (rawLower.contains('insufficient') || rawLower.contains('balance')) {
      return 'Your mobile money wallet may not have enough balance for this prompt. Check your balance and any prompt on your phone before trying again.';
    }
    if (rawLower.contains('invalid') && rawLower.contains('phone')) {
      return 'The mobile money number on this account could not receive the prompt. Check your number and try again.';
    }
    return safeDetail.isNotEmpty
        ? '$safeDetail Check your phone for a prompt before retrying.'
        : 'We could not confirm the mobile money prompt right now. Check your phone for a prompt before retrying. If no prompt arrived and no money was deducted, check your signal and balance, then tap Try again.';
  }
  if (err.startsWith('http_')) return 'The payment service returned an error. Check your phone for a prompt before retrying. If no money was deducted, try again in a moment.';
  if (safeDetail.isNotEmpty) return safeDetail;
  return 'Could not start the courier payment. Check your phone for a prompt before retrying. If no money was deducted, try again in a moment.';
}
