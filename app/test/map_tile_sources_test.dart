import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dropoff/data/map_tile_sources.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';

/// Records which archive answered each tile and can be told to miss.
class _FakeProvider extends VectorTileProvider {
  _FakeProvider(this.label, {this.maximum = 15, this.missing = false});

  final String label;
  final int maximum;
  final bool missing;
  final List<String> served = [];

  @override
  Future<Uint8List> provide(TileIdentity tile) async {
    if (missing) {
      throw ProviderException(
        message: 'Tile not found: $tile',
        retryable: Retryable.none,
        statusCode: 404,
      );
    }
    served.add('$label:${tile.key()}');
    return Uint8List.fromList([1]);
  }

  @override
  int get maximumZoom => maximum;

  @override
  int get minimumZoom => 0;

  @override
  TileOffset get tileOffset => TileOffset.DEFAULT;
}

/// The slippy tile containing (lat, lng) at [z].
TileIdentity tileFor(double lat, double lng, int z) {
  final n = 1 << z;
  final x = ((lng + 180.0) / 360.0 * n).floor();
  final rad = lat * math.pi / 180.0;
  final y = ((1.0 - math.log(math.tan(rad) + 1.0 / math.cos(rad)) / math.pi) / 2.0 * n).floor();
  return TileIdentity(z, x, y);
}

void main() {
  const lusaka = MapBounds(south: -15.78, west: 27.66, north: -15.02, east: 28.62);

  CityFirstTileProvider build(_FakeProvider regional, _FakeProvider city) =>
      CityFirstTileProvider(regional: regional, city: city, cityBounds: lusaka);

  test('Lusaka street-zoom tiles come from the city archive', () async {
    final regional = _FakeProvider('regional');
    final city = _FakeProvider('city', maximum: 16);
    final provider = build(regional, city);
    expect(provider.maximumZoom, 16);

    await provider.provide(tileFor(-15.4255, 28.2805, 16));
    expect(city.served.length, 1);
    expect(regional.served, isEmpty);
  });

  test('tiles outside Lusaka at the same zoom use the regional archive', () async {
    final regional = _FakeProvider('regional');
    final city = _FakeProvider('city', maximum: 16);

    await build(regional, city).provide(tileFor(-12.9587, 28.6366, 16)); // Ndola
    expect(regional.served.length, 1);
    expect(city.served, isEmpty);
  });

  test('low zooms always use the regional archive', () async {
    final regional = _FakeProvider('regional');
    final city = _FakeProvider('city', maximum: 16);

    await build(regional, city).provide(tileFor(-15.4255, 28.2805, 10));
    expect(regional.served.length, 1);
    expect(city.served, isEmpty);
  });

  test('a missing city tile falls back to the regional archive', () async {
    final regional = _FakeProvider('regional');
    final city = _FakeProvider('city', maximum: 16, missing: true);

    await build(regional, city).provide(tileFor(-15.4255, 28.2805, 15));
    expect(regional.served.length, 1);
  });
}
