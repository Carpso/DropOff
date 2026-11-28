/// Plain-language age of a GPS fix — a rider pin must never look "live" when
/// the last fix is minutes old (owner tracking audit 2026-11-28).
String fixAgeLabel(Object? seenAt, {DateTime? now, int staleAfterSeconds = 120}) {
  final raw = '${seenAt ?? ''}'.trim();
  if (raw.isEmpty) return 'No fix yet';
  final dt = DateTime.tryParse(raw.replaceFirst(' ', 'T'));
  if (dt == null) return 'Last fix just now';
  final age = (now ?? DateTime.now()).difference(dt).inSeconds;
  if (age < 0) return 'Just now';
  if (age < 10) return 'Just now';
  if (age < 60) return '${age}s ago';
  final mins = age ~/ 60;
  if (mins < 60) {
    final prefix = age > staleAfterSeconds ? 'Stale - ' : '';
    return '$prefix$mins min ago';
  }
  final hours = mins ~/ 60;
  return 'Stale - ${hours}h${(mins % 60).toString().padLeft(2, '0')} ago';
}

/// True when the fix is old enough that the pin should be shown as stale.
bool isStaleFix(Object? seenAt, {DateTime? now, int staleAfterSeconds = 120}) {
  final raw = '${seenAt ?? ''}'.trim();
  if (raw.isEmpty) return true;
  final dt = DateTime.tryParse(raw.replaceFirst(' ', 'T'));
  if (dt == null) return true;
  return (now ?? DateTime.now()).difference(dt).inSeconds > staleAfterSeconds;
}
