import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// In-app notification center (owner 2026-11-25, "billion-dollar" UX).
///
/// Foreground pushes used to pop a banner that covered the screen. Now they
/// land in this inbox, reachable from the bell icon — the curtain (system)
/// notification still fires, so the rider is never interrupted mid-task but
/// can review everything later.
class NotificationInbox {
  NotificationInbox._();

  static const _key = 'notification_inbox_v1';
  static const _max = 50;
  static final List<Map<String, dynamic>> _items = [];
  static final ValueNotifier<int> unread = ValueNotifier<int>(0);

  static List<Map<String, dynamic>> get items => List.unmodifiable(_items);

  static Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw != null && raw.isNotEmpty) {
        final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
        _items
          ..clear()
          ..addAll(list.take(_max));
        _recount();
      }
    } catch (_) {}
  }

  static Future<void> add(Map<String, dynamic> data) async {
    final entry = Map<String, dynamic>.from(data);
    entry['received_at'] = DateTime.now().toIso8601String();
    entry['read'] = false;
    _items.insert(0, entry);
    if (_items.length > _max) _items.removeRange(_max, _items.length);
    _recount();
    await _persist();
  }

  static Future<void> markAllRead() async {
    for (final e in _items) {
      e['read'] = true;
    }
    _recount();
    await _persist();
  }

  static Future<void> clear() async {
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
