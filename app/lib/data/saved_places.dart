import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'dropoff_api.dart';

/// Auto-growing place book (owner 2026-11-18): every place used in the map
/// navigator, every pickup address used for a booking and every pinned GPS
/// location is remembered here automatically — locally for offline use AND on
/// the server against the signed-in phone, so the collection grows across
/// devices and can populate the in-app map.
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
        usedAt: (j['usedAt'] as num?)?.toInt() ??
            (j['used_at'] != null
                ? DateTime.tryParse('${j['used_at']}Z')?.millisecondsSinceEpoch ?? 0
                : 0),
      );
}

class SavedPlaces {
  static const _key = 'dropoff_saved_places_v1';
  static const _cap = 60;
  static List<SavedPlace> _cache = const [];

  static Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode(_cache.map((p) => p.toJson()).toList()));
    } catch (_) {}
  }

  static Future<List<SavedPlace>> load() async {
    if (_cache.isEmpty) {
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
    }
    // Merge the server copy when signed in — the address book follows the
    // account, not just this phone.
    if (DropOffApi.token != null) {
      try {
        final data = await DropOffApi.savedPlaces();
        final rows = (data?['places'] as List?) ?? const [];
        final merged = <String, SavedPlace>{
          for (final p in _cache) p.label.toLowerCase(): p,
        };
        for (final r in rows) {
          final sp = SavedPlace.fromJson(r as Map<String, dynamic>);
          if (sp.label.isNotEmpty) {
            final existing = merged[sp.label.toLowerCase()];
            // Never let a pinless server row erase a good local pin (or vice
            // versa) — a saved place without coordinates is search-only.
            final hasPin = sp.lat != null && sp.lng != null;
            final keepExisting = existing != null && existing.lat != null && existing.lng != null && !hasPin;
            merged[sp.label.toLowerCase()] = keepExisting ? existing : sp;
          }
        }
        _cache = merged.values.toList()
          ..sort((a, b) => b.usedAt.compareTo(a.usedAt));
        await _persist();
      } catch (_) {
        // offline: the local mirror is still authoritative enough
      }
    }
    // An email address is not a place — the owner's email was accidentally
    // saved as a location during testing (owner 2026-11-23). Drop any such
    // entry from every device, local and server-merged.
    _cache = _cache.where((p) => !p.label.contains('@')).toList();
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
      final existing = places.where((p) => p.label.toLowerCase() == text.toLowerCase()).firstOrNull;
      final keepLat = lat ?? existing?.lat;
      final keepLng = lng ?? existing?.lng;
      kept.insert(0, SavedPlace(text, lat: keepLat, lng: keepLng, usedAt: DateTime.now().millisecondsSinceEpoch));
      _cache = kept.take(_cap).toList();
      await _persist();
      // Server write is best-effort; the local book is already updated.
      if (DropOffApi.token != null) {
        unawaited(DropOffApi.rememberPlace(text, lat: lat, lng: lng));
      }
    } catch (_) {
      // best-effort: the app keeps working without the address book
    }
  }
}
