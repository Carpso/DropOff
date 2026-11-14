/// App-side feature usage / click analytics.
///
/// Events are buffered locally (SharedPreferences outbox) and flushed to
/// POST /analytics/ingest in the background — the app never blocks on the
/// network, and events survive a restart. Call [AnalyticsService.track] from
/// any screen/widget to log a screen view, button tap or form submit.
///
/// Example:
///   AnalyticsService.instance.track(
///     feature: 'booking', action: 'submit',
///     context: 'booking_step_3',
///     meta: {'parcels': 2, 'vehicle_class': 'motorcycle', 'last_mile': true},
///   );
library analytics_service;

import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../data/dropoff_api.dart';

class AnalyticsService {
  AnalyticsService._();
  static final AnalyticsService instance = AnalyticsService._();

  static const _outboxKey = 'dropoff_analytics_outbox_v1';
  static const int _flushThreshold = 10; // flush automatically when N pending
  static const Duration _flushInterval = Duration(minutes: 5);

  final List<Map<String, dynamic>> _pending = [];
  final Set<String> _viewedScreens = {}; // dedupe screen views per session
  bool _ready = false;
  bool _flushing = false;
  DateTime? _lastFlush;

  /// Call once from main() before runApp.
  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_outboxKey);
      if (raw != null) {
        final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
        _pending.addAll(list.take(200)); // cap stored backlog
      }
    } catch (_) {
      // best-effort; start empty
    }
    _ready = true;
    _scheduleTimerInternal();
    // Ship any backlog from the previous session immediately.
    if (_pending.isNotEmpty) unawaited(flush());
  }

  void _scheduleTimerInternal() {
    // HOLD FIX: this used to be an empty no-op AND flush only happened at 10
    // pending events (or 5-minute maybeFlush, which nothing ever called), so
    // most screen views sat in the outbox forever and the KPI looked empty.
    // Now the outbox ships every few minutes while the app is alive, and the
    // 10-event threshold still triggers an early flush.
    Timer.periodic(_flushInterval, (_) => maybeFlush());
  }

  /// Log a feature usage / click event.
  ///
  /// [feature] e.g. 'booking', 'collections', 'pack_codes', 'admin_users',
  /// 'rider_verification', 'fraud', 'sms_broadcast', 'branches', 'track',
  /// 'rating', 'subscriptions', 'admin_analytics'.
  /// [action] e.g. 'view', 'tap', 'submit', 'approve', 'reject', 'redeem',
  /// 'generate', 'clear', 'confirm', 'broadcast', 'pay', 'rate', 'share'.
  /// [context] the screen/page (e.g. 'home', 'booking_step_3', 'admin_console').
  /// [meta] free-form JSON-safe extras (parcels, tier, amount, ref, etc.).
  void track({
    required String feature,
    required String action,
    String context = '',
    Map<String, dynamic>? meta,
  }) {
    if (!_ready) return;
    _pending.add({
      'feature': feature,
      'action': action,
      'context': context,
      'meta': meta,
      'ts': DateTime.now().toUtc().toIso8601String(),
    });
    if (_pending.length >= _flushThreshold) {
      unawaited(flush());
    } else {
      unawaited(_persist());
    }
  }

  /// Log a screen view once per screen per app session (safe to call from
  /// build() of StatelessWidget screens — repeats are ignored).
  void trackScreenView(String screen) {
    if (!_ready) return;
    if (_viewedScreens.add(screen)) {
      track(feature: 'screen', action: 'view', context: screen);
    }
  }

  /// Push all pending events to the server. Safe to call repeatedly; in-flight
  /// flushes are deduplicated. Best-effort: failures leave events in the
  /// outbox for the next attempt.
  Future<void> flush() async {
    if (!_ready || _flushing || _pending.isEmpty) return;
    _flushing = true;
    try {
      final batch = List<Map<String, dynamic>>.from(_pending);
      final res = await DropOffApi.post('/analytics/ingest', {'events': batch});
      if (res.ok) {
        _pending.clear();
        await _persist();
        _lastFlush = DateTime.now();
      }
      // On failure (network / 5xx) keep events in _pending for retry.
    } catch (_) {
      // swallow — retry next flush
    } finally {
      _flushing = false;
    }
  }

  /// Maybe flush if the interval has elapsed. Call from AppStore / resume.
  Future<void> maybeFlush() async {
    if (!_ready) return;
    final now = DateTime.now();
    if (_lastFlush == null ||
        now.difference(_lastFlush!) > _flushInterval) {
      await flush();
    } else {
      await _persist();
    }
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_outboxKey, jsonEncode(_pending));
    } catch (_) {
      // best-effort
    }
  }

  int get pendingCount => _pending.length;
}
