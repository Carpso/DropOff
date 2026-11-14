// :Godfrey Moses Kalambo:Carpso Solutions:0968551110.
import 'dart:math' as math;

import '../data/catalog.dart';

/// Tidy — the DropOff app AI. Works in two layers:
///  1. Server (`/ai/address`): LLM that normalises spelling, expands obvious
///     abbreviations, and snaps typos onto known Zambian zones — it inlines the
///     canonical list and never invents a street or town.
///  2. Local (this file): everything that needs NO network — zone matching to
///     real coordinates (feeds the fee-band lookup and the rider's ETA) and
///     plus-code detection, because Plus Codes resolve natively in Google Maps
///     (the courier industry's chosen "no address" standard).
///
/// Design constraint: Tidy NEVER guesses beyond what it can verify — the reply
/// is always captioned so the sender eyeballs it before booking.
class Tidy {
  Tidy._();

  /// Lusaka delivery districts with coordinates — used to pin a fuzzy sender
  /// address to a real spot (±1 km, enough for the Lusaka fee bands, NOT for
  /// turn-by-turn). Rows roughly ordered by delivery value.
  static const lusakaAreas = <TidyArea>[
    TidyArea('Kabwata', -15.3922, 28.3290),
    TidyArea('Kabulonga', -15.4216, 28.3223),
    TidyArea('Northmead', -15.4033, 28.3081),
    TidyArea('Rhodes Park', -15.4147, 28.2997),
    TidyArea('Roma', -15.3778, 28.3074),
    TidyArea('Woodlands', -15.4356, 28.3232),
    TidyArea('Avondale', -15.3716, 28.3097),
    TidyArea('Chalala', -15.3831, 28.3670),
    TidyArea('Garden', -15.3900, 28.3350),
    TidyArea('Kalingalinga', -15.4155, 28.3362),
    TidyArea('Mtendere', -15.4194, 28.3511),
    TidyArea('Kanyama', -15.4489, 28.2561),
    TidyArea('Libala', -15.4222, 28.3090),
    TidyArea('Thornpark', -15.4267, 28.2997),
    TidyArea('Chilenje', -15.4290, 28.2960),
    TidyArea('Matero', -15.3930, 28.2650),
    TidyArea('Chelstone', -15.3536, 28.4019),
    TidyArea('Chalimbana', -15.2736, 28.3561),
    TidyArea('Chibolya', -15.4250, 28.2830),
    TidyArea('Longacres', -15.4226, 28.3136),
    TidyArea('Chilanga', -15.5000, 28.1900),
  ];

  /// Pull an Open Location Code ("8FQ4+22 Lusaka") out of raw text.
  /// No decoder needed: Google Maps interprets the code natively, and we carry
  /// it through the address string so riders and the depot can navigate by it.
  static String? extractPlusCode(String text) {
    final m = RegExp(r'\b[23456789CFGHJMPQRVWX]{4}\+[23456789CFGHJMPQRVWX]{2,3}(?:\s?[A-Za-z][A-Za-z ]{0,20})?',
            caseSensitive: false)
        .firstMatch(text.toUpperCase());
    return m?.group(0)?.trim();
  }

  /// Best-effort pin for a messy address: known Zambian towns first (they are
  /// exact), then Lusaka districts (fuzzy, ±2 edits). Returns null on anything
  /// doubtful — we would rather NOT pin than pin wrongly.
  static TidyArea? matchZambianPlace(String text) {
    final q = _fold(text);
    if (q.isEmpty) return null;
    for (final e in cityCoords.entries) {
      if (q.contains(_fold(e.key))) return TidyArea(e.key, e.value.$1, e.value.$2);
    }
    var best = 999, bestIdx = -1;
    for (var i = 0; i < lusakaAreas.length; i++) {
      final d = _levenshtein(q, _fold(lusakaAreas[i].name));
      if (d < best) { best = d; bestIdx = i; }
    }
    if (bestIdx >= 0 && best <= 2) return lusakaAreas[bestIdx];
    // Token-level match: "near Kabvata Bread shop" → kabwata holds.
    for (var i = 0; i < lusakaAreas.length; i++) {
      final n = _fold(lusakaAreas[i].name);
      for (final tok in q.split(' ')) {
        if (tok.length >= 5 && _levenshtein(tok, n) <= 2) return lusakaAreas[i];
      }
    }
    return null;
  }

  /// A Tidy reply is always human-checked — this string goes under the input.
  static bool isZambiaTown(String? name) {
    final q = _fold(name ?? '');
    if (q.isEmpty) return false;
    for (final city in cities) {
      if (q.contains(_fold(city))) return true;
    }
    for (final a in lusakaAreas) {
      if (q.contains(_fold(a.name))) return true;
    }
    return false;
  }

  static String _fold(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static int _levenshtein(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;
    var prev = List<int>.generate(b.length + 1, (i) => i);
    for (var i = 1; i <= a.length; i++) {
      var cur = <int>[i];
      for (var j = 1; j <= b.length; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        cur.add(math.min(math.min(cur[j - 1] + 1, prev[j] + 1), prev[j - 1] + cost));
      }
      prev = cur;
    }
    return prev[b.length];
  }
}

/// One resolved place — name, coordinates, provenance (\"tidy\" vs guess).
class TidyArea {
  final String name;
  final double lat;
  final double lng;
  const TidyArea(this.name, this.lat, this.lng);
}
