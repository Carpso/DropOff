import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_map_tiles/vector_map_tiles.dart';

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

/// Registry of high-detail city archives. A city becomes active the moment
/// its archive is uploaded to the R2 bucket under `tiles/<slug>-z0-16.pmtiles`
/// — no app code change needed beyond flipping `enabled` to true here (or,
/// better, the app probes the URL and enables itself).
///
/// HOW TO ADD A CITY (owner recipe, 2026-11-24):
///   1. Download the OSM extract for the country/region (Geofabrik
///      `zambia-latest.osm.pbf` covers all of Zambia).
///   2. Clip to the city bbox with osmium:
///        osmium extract -b <west>,<south>,<east>,<north> zambia-latest.osm.pbf -o city.osm.pbf
///   3. Generate PMTiles with planetiler (Docker, no Java needed):
///        docker run -v $PWD:/data ghcr.io/onthegomap/planetiler:latest \
///          --osm-path=/data/city.osm.pbf --output=/data/city-z0-16.pmtiles \
///          --maxzoom=16 --minzoom=0 --bounds=<west>,<south>,<east>,<north>
///   4. Upload to the R2 bucket:  rclone copy city-z0-16.pmtiles r2:dropoff-map-assets/tiles/
///   5. Flip `enabled: true` below (or let the app probe the URL).
/// City bboxes (south, west, north, east) in degrees.
class CityArchive {
  const CityArchive({
    required this.slug,
    required this.label,
    required this.bounds,
    required this.url,
    this.enabled = true,
    this.fromZoom = 13,
    this.maxZoom = 16,
  });
  final String slug;
  final String label;
  final MapBounds bounds;
  final String url;
  final bool enabled;
  final int fromZoom;
  final int maxZoom;
}

/// All known city archives. Lusaka is live; Ndola and Kitwe are ready to
/// activate once their PMTiles files are uploaded to R2.
const List<CityArchive> kCityArchives = [
  CityArchive(
    slug: 'lusaka',
    label: 'Lusaka',
    bounds: MapBounds(south: -15.78, west: 27.66, north: -15.02, east: 28.62),
    url: 'https://pub-f3c14b5846eb4de487b036d5a6d6a760.r2.dev/tiles/lusaka-z0-16.pmtiles',
    enabled: true,
  ),
  // TODO (owner): generate + upload, then set enabled: true
  // CityArchive(
  //   slug: 'ndola',
  //   label: 'Ndola',
  //   bounds: MapBounds(south: -13.05, west: 28.55, north: -12.90, east: 28.75),
  //   url: 'https://pub-f3c14b5846eb4de487b036d5a6d6a760.r2.dev/tiles/ndola-z0-16.pmtiles',
  //   enabled: false,
  // ),
  // CityArchive(
  //   slug: 'kitwe',
  //   label: 'Kitwe',
  //   bounds: MapBounds(south: -12.85, west: 28.15, north: -12.70, east: 28.30),
  //   url: 'https://pub-f3c14b5846eb4de487b036d5a6d6a760.r2.dev/tiles/kitwe-z0-16.pmtiles',
  //   enabled: false,
  // ),
];
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
    // OVERZOOM: outside Lusaka the regional archive stops at z15, but the
    // camera can reach 16.5 for the city. Asking regional for a z16 tile it
    // never contained left blank squares across the rest of Zambia. Serve the
    // nearest available parent tile instead — flutter_map scales it up, which
    // is far better than an empty map (owner onboarding audit 2026-11-23).
    if (tile.z > regional.maximumZoom) {
      final steps = tile.z - regional.maximumZoom;
      final parent = TileIdentity(
        regional.maximumZoom,
        tile.x >> steps,
        tile.y >> steps,
      );
      return regional.provide(parent);
    }
    return regional.provide(tile);
  }
}
