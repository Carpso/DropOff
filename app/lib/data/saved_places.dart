import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Auto-growing place book (owner 2026-11-18): every place used in the map
/// navigator, every pickup address used for a booking and every pinned GPS
/// location is remembered here automatically — the list grows with the user
/// instead of starting empty each time. Local-only, no account needed.
class SavedPlace {
  final String label;
  final double? lat;
  final double? lng;
  final int usedAt; // epoch millis, newest first

  const SavedPlace(this.label, {this.lat, this.lng, required this.usedAt});

  Map<String, dynamic> toJson() => {
        'label': label,
        'lat': lat,
        'lng': lng,
        'usedAt': usedAt,
      };

  factory SavedPlace.fromJson(Map<String, dynamic> j) => SavedPlace(
        '${j['label'] ?? ''}',
        lat: (j['lat'] as num?)?.toDouble(),
        lng: (j['lng'] as num?)?.toDouble(),
        usedAt: (j['usedAt'] as num?)?.toInt() ?? 0,
      );
}

class SavedPlaces {
  static const _key = 'dropoff_saved_places_v1';
  static const _cap = 60;
  static List<SavedPlace> _cache = const [];

  static Future<List<SavedPlace>> load() async {
    if (_cache.isNotEmpty) return _cache;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw != null && raw.isNotEmpty) {
        final rows = jsonDecode(raw) as List;
        _cache = rows
            .map((r) => SavedPlace.fromJson(r as Map<String, dynamic>))
            .where((p) => p.label.isNotEmpty)
            .toList();
      }
    } catch (_) {
      _cache = const [];
    }
    return _cache;
  }

  /// Remember a place (new or existing) and move it to the top. Never throws —
  /// saving must never block the booking or navigation flow.
  static Future<void> remember(String label, {double? lat, double? lng}) async {
    final text = label.trim();
    if (text.isEmpty) return;
    try {
      final places = await load();
      final kept = places.where((p) => p.label.toLowerCase() != text.toLowerCase()).toList();
      kept.insert(0, SavedPlace(text, lat: lat, lng: lng, usedAt: DateTime.now().millisecondsSinceEpoch));
      _cache = kept.take(_cap).toList();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode(_cache.map((p) => p.toJson()).toList()));
    } catch (_) {
      // best-effort: the app keeps working without the address book
    }
  }
}
