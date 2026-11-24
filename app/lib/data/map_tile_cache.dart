import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Offline-by-default map tile cache (owner 2026-11-24, "billion-dollar map").
///
/// Mapbox/Google download the city archive on first run and serve it from
/// disk forever after. We do the same for the Lusaka archive so a rider in
/// Lusaka never depends on a live Range request for the basemap — the single
/// biggest cause of the "plain map" symptom on weak mobile data.
///
/// The cache is best-effort: a failed download leaves the HTTP URL in place
/// (the existing range/full-download fallbacks still work) and retries on the
/// next map open.
class MapTileCache {
  MapTileCache._();

  static const String _lusakaUrl =
      'https://pub-f3c14b5846eb4de487b036d5a6d6a760.r2.dev/tiles/lusaka-z0-16.pmtiles';
  static const String _fileName = 'lusaka-z0-16.pmtiles';

  static File? _cachedFile;
  static bool _downloading = false;

  /// Returns a `file://` URI when the archive is on disk, otherwise the
  /// original HTTP URL (so the map still works online). Triggers a background
  /// download the first time it is missing.
  static Future<Uri> lusakaArchiveUri() async {
    if (_cachedFile != null && await _cachedFile!.exists()) {
      return Uri.file(_cachedFile!.path);
    }
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/map_tiles/$_fileName');
      if (await file.exists() && await file.length() > 1000000) {
        _cachedFile = file;
        return Uri.file(file.path);
      }
      // Kick off a background download; don't block the map on it.
      unawaited(_download(file));
    } catch (_) {}
    return Uri.parse(_lusakaUrl);
  }

  static Future<void> _download(File target) async {
    if (_downloading) return;
    _downloading = true;
    try {
      await target.parent.create(recursive: true);
      final tmp = File('${target.path}.part');
      final res = await http.get(Uri.parse(_lusakaUrl));
      if (res.statusCode == 200 && res.bodyBytes.length > 1000000) {
        await tmp.writeAsBytes(res.bodyBytes, flush: true);
        if (await target.exists()) await target.delete();
        await tmp.rename(target.path);
        _cachedFile = target;
      } else {
        try {
          await tmp.delete();
        } catch (_) {}
      }
    } catch (_) {
      // Best-effort only — the HTTP fallback keeps the map working.
    } finally {
      _downloading = false;
    }
  }

  /// Persist already-downloaded bytes so the next run is offline-by-default.
  static Future<void> persistBytes(List<int> bytes) async {
    if (bytes.length < 1000000) return;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/map_tiles/$_fileName');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes, flush: true);
      _cachedFile = file;
    } catch (_) {}
  }

  /// Force a re-download (e.g. after a corrupt file). Used by the Retry
  /// button on the "Basemap offline" banner.
  static Future<void> invalidate() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/map_tiles/$_fileName');
      if (await file.exists()) await file.delete();
      _cachedFile = null;
    } catch (_) {}
  }
}
