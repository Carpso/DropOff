import 'dart:convert';

/// Decode the bundled Protomaps light-v4 layers into the exact type
/// `ProtomapsThemes.build()` requires (`List<Map<String, Object>>`).
///
/// `jsonDecode()` produces `Map<String, dynamic>` for every layer. The old
/// `(decoded['layers'] as List).cast<Map<String, Object>>()` is a LAZY cast
/// view: it does not throw at the cast site, it throws later when the theme
/// reader reads an element —
///   type '_Map<String, dynamic>' is not a subtype of the type
///   'Map<String, Object>' in type cast
/// — which killed the whole basemap and produced the permanent
/// "Basemap offline - your position and route still show" banner whose Retry
/// button could never succeed (it rebuilt the same broken theme every time).
///
/// Build real `Map<String, Object>` instances instead. Null values are dropped
/// because `Object` is non-nullable; a null style key is never meaningful.
List<Map<String, Object>> protomapsLayers(Map<String, dynamic> decoded) {
  final rawLayers = decoded['layers'];
  if (rawLayers is! List) {
    throw const FormatException('map theme has no layers list');
  }
  final layers = <Map<String, Object>>[];
  for (final item in rawLayers) {
    if (item is! Map) continue;
    final layer = <String, Object>{};
    for (final entry in item.entries) {
      final value = entry.value;
      if (value == null) continue;
      layer[entry.key.toString()] = value as Object;
    }
    layers.add(layer);
  }
  return layers;
}

/// Convenience for reading the bundled theme asset in one step.
Map<String, dynamic> decodeMapTheme(String raw) {
  final decoded = jsonDecode(raw);
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('map theme must be a JSON object');
  }
  return decoded;
}
