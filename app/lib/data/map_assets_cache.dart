import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:pmtiles/pmtiles.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';
import 'package:vector_map_tiles_pmtiles/vector_map_tiles_pmtiles.dart';

import 'map_theme_layers.dart';
import 'map_tile_cache.dart';
import 'map_tile_sources.dart';
import '../services/crash_reporting.dart';

/// The one basemap for the whole app process (owner 2026-11-26: "downloaded
/// map still reloads on every ride").
///
/// Before this cache every [RiderMap] mount — every route open, every screen
/// switch — opened both PMTiles archives again, re-parsed the theme, and could
/// even start another 30 MB download. Now the heavy work happens at most once
/// per process, is warmed at splash, and every later map is instant.
class MapAssetsBundle {
  const MapAssetsBundle(this.provider, this.theme, this.error);

  final VectorTileProvider? provider;
  final dynamic theme;
  final String? error;

  bool get hasBasemap => provider != null && theme != null;
}

/// Our R2 bucket URLs and the Lusaka rectangle (south, west, north, east).
const String kRegionalTileUrl =
    'https://pub-f3c14b5846eb4de487b036d5a6d6a760.r2.dev/region-zm-zw-mw-mz.pmtiles';
const String kLusakaTileUrl =
    'https://pub-f3c14b5846eb4de487b036d5a6d6a760.r2.dev/tiles/lusaka-z0-16.pmtiles';
const MapBounds kLusakaBounds =
    MapBounds(south: -15.78, west: 27.66, north: -15.02, east: 28.62);
const String kAltAssetsBase =
    'https://pub-d23651cb1a9d491f998c73094d54f379.r2.dev';

class MapAssetsCache {
  MapAssetsCache._();

  static Future<MapAssetsBundle>? _future;

  /// Same future for every caller — a second map never reopens the archive.
  static Future<MapAssetsBundle> load() => _future ??= _open();

  /// Start opening the basemap at splash so a new order's route is ready by
  /// the time the rider accepts it. Never blocks the UI.
  static void warm() {
    unawaited(load());
  }

  /// Drop the memoised assets (used by Retry after a genuine failure).
  static void invalidate() => _future = null;

  /// Force a fresh open, e.g. after a corrupt downloaded archive was removed.
  static Future<MapAssetsBundle> reload() {
    _future = null;
    return load();
  }

  static Future<MapAssetsBundle> _open() async {
    String? error;

    Future<VectorTileProvider?> openOne(String url, Duration timeout) async {
      for (var attempt = 0; attempt < 2; attempt++) {
        try {
          return await PmTilesVectorTileProvider.fromSource(url).timeout(timeout);
        } catch (e) {
          debugPrint('RiderMap could not open $url (attempt ${attempt + 1}): $e');
          error = '${error ?? ''} ${Uri.parse(url).pathSegments.last}: $e';
          if (attempt == 0) await Future<void>.delayed(const Duration(milliseconds: 250));
        }
      }
      return null;
    }

    Future<VectorTileProvider?> openWithFallback(List<String> urls, Duration timeout) async {
      for (final url in urls) {
        final p = await openOne(url, timeout);
        if (p != null) return p;
      }
      return null;
    }

    final regionalUrls = <String>[kRegionalTileUrl, '$kAltAssetsBase/region-zm-zw-mw-mz.pmtiles'];
    final lusakaUrls = <String>[kLusakaTileUrl, '$kAltAssetsBase/tiles/lusaka-z0-16.pmtiles'];

    Future<VectorTileProvider?> openLusakaFast() async {
      // 1. A previously downloaded archive is the fastest path: local file,
      //    no Range request, no network.
      try {
        final cached = await MapTileCache.lusakaArchiveUri();
        if (cached.scheme == 'file') {
          final p = await PmTilesVectorTileProvider.fromSource(cached.toString())
              .timeout(const Duration(seconds: 8));
          debugPrint('RiderMap: Lusaka from disk cache ($cached)');
          return p;
        }
      } catch (e) {
        debugPrint('RiderMap: cached Lusaka open failed: $e');
      }
      // 2. Range-open reads only the PMTiles header (a few KB) — fast even on
      //    mobile data. Persist a full copy in the background for next time;
      //    never block the rider on a 30 MB download here.
      final ranged = await openWithFallback(lusakaUrls, const Duration(seconds: 8));
      if (ranged != null) {
        unawaited(MapTileCache.download());
        return ranged;
      }
      // 3. Last resort: full download, but bounded — a failed/stripped Range
      //    response must not leave the map spinning forever.
      for (final url in lusakaUrls) {
        try {
          final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 25));
          if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) {
            final archive = await PmTilesArchive.fromBytes(res.bodyBytes);
            unawaited(MapTileCache.persistBytes(res.bodyBytes));
            return PmTilesVectorTileProvider.fromArchive(archive);
          }
        } catch (e) {
          debugPrint('RiderMap: Lusaka full download failed for $url: $e');
        }
      }
      return null;
    }

    final opened = await Future.wait([
      openWithFallback(regionalUrls, const Duration(seconds: 8)),
      openLusakaFast(),
    ]);
    final regional = opened[0];
    final lusaka = opened[1];
    VectorTileProvider? provider;
    if (regional != null && lusaka != null) {
      provider = CityFirstTileProvider(
        regional: regional,
        city: lusaka,
        cityBounds: kLusakaBounds,
      );
    } else {
      provider = lusaka ?? regional;
    }
    if (provider != null) error = null;

    dynamic theme;
    try {
      final raw = await rootBundle.loadString('assets/map/theme-light-v4.json');
      final decoded = decodeMapTheme(raw);
      theme = ProtomapsThemes(
        glyphs: decoded['glyphs'] as String,
        sprites: decoded['sprite'] as String,
      ).build(protomapsLayers(decoded));
    } catch (e) {
      error = '${error ?? ''} theme: $e';
      debugPrint('RiderMap theme load failed: $e');
    }
    if (error != null) {
      CrashReporting.reportCaught('RiderMap basemap degraded', error);
    }
    return MapAssetsBundle(provider, theme, error);
  }
}
