import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_map_tiles/vector_map_tiles.dart';
import 'package:vector_map_tiles_pmtiles/vector_map_tiles_pmtiles.dart';

/// A plain rectangle in degrees — south/west/north/east.
class MapBounds {
  const MapBounds({
    required this.south,
    required this.west,
    required this.north,
    required this.east,
  });

  final double south;
  final double west;
  final double north;
  final double east;
}

/// Serves the regional archive everywhere, and swaps to a high-detail CITY
/// archive for tiles inside [cityBounds] at street zooms.
///
/// Why this exists (owner 2026-11-22): the regional Zambia/Zimbabwe/Malawi/
/// Mozambique archive stops at z15 and is generalised — street level in Lusaka
/// read thin. The same R2 bucket already carries `tiles/lusaka-z0-16.pmtiles`
/// (the archive churchonapp_flutter uses), so we draw its z13–z16 tiles inside
/// the Lusaka rectangle and keep the regional file for everything else.
///
/// Both archives are Protomaps basemaps tiles with the same schema, so the
/// single theme draws them identically. A missing city tile always falls back
/// to the regional archive rather than leaving a hole in the map.
class CityFirstTileProvider extends VectorTileProvider {
  CityFirstTileProvider({
    required this.regional,
    required this.city,
    required this.cityBounds,
    this.cityFromZoom = 13,
  });

  final VectorTileProvider regional;
  final VectorTileProvider city;
  final MapBounds cityBounds;

  /// First zoom at which the city archive takes over inside its rectangle.
  final int cityFromZoom;

  @override
  TileProviderType get type => regional.type;

  @override
  int get minimumZoom => regional.minimumZoom;

  /// The city archive reaches z16, the regional one z15 — so Lusaka can be
  /// zoomed one step closer than the rest of the country.
  @override
  int get maximumZoom => math.max(regional.maximumZoom, city.maximumZoom);

  @override
  TileOffset get tileOffset => TileOffset.DEFAULT;

  /// Slippy tile ranges that cover [cityBounds] at zoom [z].
  bool _coversCity(TileIdentity tile) {
    final n = 1 << tile.z;
    int lonToX(double lon) => ((lon + 180.0) / 360.0 * n).floor();
    int latToY(double lat) {
      final rad = lat * math.pi / 180.0;
      final y = (1.0 - math.log(math.tan(rad) + 1.0 / math.cos(rad)) / math.pi) / 2.0;
      return (y * n).floor();
    }

    final x0 = lonToX(cityBounds.west);
    final x1 = lonToX(cityBounds.east);
    // North has the smaller y; clamp so the check stays valid at any zoom.
    final y0 = latToY(cityBounds.north).clamp(0, n - 1);
    final y1 = latToY(cityBounds.south).clamp(0, n - 1);
    return tile.x >= x0 && tile.x <= x1 && tile.y >= y0 && tile.y <= y1;
  }

  @override
  Future<Uint8List> provide(TileIdentity tile) async {
    if (tile.z >= cityFromZoom && _coversCity(tile)) {
      try {
        return await city.provide(tile);
      } on ProviderException {
        // City archive has no tile here (or the range request failed) — the
        // regional archive is always the safety net.
      }
    }
    return regional.provide(tile);
  }
}
