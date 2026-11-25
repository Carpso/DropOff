import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:dropoff/data/map_theme_layers.dart';

void main() {
  test('bundled light-v4 theme decodes into concrete Map<String, Object> layers', () {
    final decoded = decodeMapTheme(File('assets/map/theme-light-v4.json').readAsStringSync());
    final layers = protomapsLayers(decoded);

    expect(layers, isNotEmpty);
    for (final layer in layers) {
      expect(layer, isA<Map<String, Object>>());
      // The old `.cast<Map<String, Object>>()` view only threw when a value
      // was READ (inside ThemeReader), which is why the banner looked like a
      // network/basemap failure. Touch every value so that regression fails
      // here instead of on a rider's phone.
      for (final entry in layer.entries) {
        expect(entry.value, isA<Object>());
      }
    }
  });

  test('a decoded Map<String, dynamic> layer is copied, not lazily cast', () {
    final decoded = decodeMapTheme(
      '{"glyphs":"g","sprite":"s","layers":[{"id":"roads","type":"line","paint":{"line-color":"#fff"},"minzoom":0}]}',
    );
    final layers = protomapsLayers(decoded);

    expect(layers, hasLength(1));
    expect(layers.single['id'], 'roads');
    expect(layers.single['minzoom'], 0);
    expect(layers.single['paint'], isA<Object>());
  });

  test('a malformed theme fails loudly instead of hanging on a blank map', () {
    expect(() => decodeMapTheme('[]'), throwsA(isA<FormatException>()));
    expect(() => protomapsLayers(<String, dynamic>{}), throwsA(isA<FormatException>()));
  });
}
