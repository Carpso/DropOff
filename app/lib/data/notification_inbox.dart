import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// In-app notification centre (owner 2026-11-25/26).
///
/// EVERY notification for the signed-in user lands here — foreground pushes,
/// background pushes, cold-start taps, order alarm answers and locally raised
/// prompts (counter fare, security). The system curtain still fires, but the
/// bell is the complete, reviewable history for every role: rider, sender,
/// recipient, partner and staff.
class NotificationInbox {
  NotificationInbox._();

  static const _key = 'notification_inbox_v1';
  static const _max = 80;
  static final List<Map<String, dynamic>> _items = [];
  static final ValueNotifier<int> unread = ValueNotifier<int>(0);
  static Future<void>? _initFuture;

  static List<Map<String, dynamic>> get items => List.unmodifiable(_items);

  /// Idempotent: callers in both isolates can use this freely. Every [add]
  /// waits for it so a push arriving during startup cannot be overwritten.
  static Future<void> init() => _initFuture ??= _initialize();

  static Future<void> _initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          final rows = decoded.whereType<Map>()
              .map((m) => Map<String, dynamic>.from(m))
              .where((m) => m['kind'] != null || m['title'] != null || m['job_ref'] != null)
              .toList();
          _items
            ..clear()
            ..addAll(rows.take(_max));
          _recount();
        }
      }
    } catch (_) {}
  }

  /// Same update re-delivered by FCM, a local notification and a tap must show
  /// ONCE. The fingerprint prefers the provider message id, then falls back to
  /// the event identity within a short window.
  static String _fingerprint(Map<String, dynamic> data) => [
        data['message_id'] ?? data['id'] ?? '',
        data['kind'] ?? '',
        data['job_ref'] ?? '',
        data['order_action'] ?? '',
        data['title'] ?? '',
        data['body'] ?? '',
      ].join('|');

  static Future<void> add(Map<String, dynamic> data) async {
    await init();
    final entry = Map<String, dynamic>.from(data);
    final now = DateTime.now();
    entry['received_at'] = now.toIso8601String();
    entry['read'] = false;
    final fp = _fingerprint(entry);
    final duplicate = _items.any((e) {
      if (_fingerprint(e) != fp) return false;
      final at = DateTime.tryParse('${e['received_at'] ?? ''}');
      return at != null && now.difference(at).inMinutes < 5;
    });
    if (duplicate) return;
    _items.insert(0, entry);
    if (_items.length > _max) _items.removeRange(_max, _items.length);
    _recount();
    await _persist();
  }

  /// Shortcut for notifications raised inside the app (no push involved).
  static Future<void> addLocal({
    required String title,
    required String body,
    required String kind,
    String? jobRef,
    Map<String, dynamic> extra = const {},
  }) =>
      add({
        ...extra,
        'kind': kind,
        'title': title,
        'body': body,
        if (jobRef != null) 'job_ref': jobRef,
        'local': true,
      });

  static Future<void> markAllRead() async {
    await init();
    for (final e in _items) {
      e['read'] = true;
    }
    _recount();
    await _persist();
  }

  static Future<void> clear() async {
    await init();
    _items.clear();
    _recount();
    await _persist();
  }

  static void _recount() {
    unread.value = _items.where((e) => e['read'] != true).length;
  }

  static Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode(_items));
    } catch (_) {}
  }
}
