import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Where an offline basemap download stands.
enum OfflineMapState { unknown, notDownloaded, downloading, ready, failed }

/// Snapshot of the offline basemap for the UI (map chrome + Account).
@immutable
class OfflineMapStatus {
  const OfflineMapStatus({
    this.state = OfflineMapState.unknown,
    this.bytes = 0,
    this.progress = 0,
    this.message,
  });

  final OfflineMapState state;
  final int bytes;

  /// 0..1 while [state] is [OfflineMapState.downloading].
  final double progress;

  /// Plain-language note for the sheet (never a raw exception).
  final String? message;

  bool get isReady => state == OfflineMapState.ready;
  bool get isBusy => state == OfflineMapState.downloading;

  /// Human size, e.g. `28 MB`. Empty until the size is known.
  String get sizeLabel {
    if (bytes <= 0) return '';
    if (bytes >= 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }

  OfflineMapStatus copyWith({
    OfflineMapState? state,
    int? bytes,
    double? progress,
    String? message,
    bool clearMessage = false,
  }) =>
      OfflineMapStatus(
        state: state ?? this.state,
        bytes: bytes ?? this.bytes,
        progress: progress ?? this.progress,
        message: clearMessage ? null : (message ?? this.message),
      );
}

/// Offline-by-default map tile cache (owner 2026-11-24, "billion-dollar map";
/// download manager added 2026-11-26).
///
/// Mapbox/Google download the city archive on first run and serve it from
/// disk forever after. We do the same for the Lusaka archive so a rider in
/// Lusaka never depends on a live Range request for the basemap — the single
/// biggest cause of the "plain map" symptom on weak mobile data.
///
/// The cache is best-effort: a failed download leaves the HTTP URL in place
/// (the existing range/full-download fallbacks still work) and retries on the
/// next map open. Riders can also manage it explicitly from the map chrome
/// and Account: download, see progress, delete to free space.
class MapTileCache {
  MapTileCache._();

  static const String _lusakaUrl =
      'https://pub-f3c14b5846eb4de487b036d5a6d6a760.r2.dev/tiles/lusaka-z0-16.pmtiles';
  static const String _fileName = 'lusaka-z0-16.pmtiles';

  /// Anything smaller than this is a truncated/placeholder file, not a map.
  static const int minimumBytes = 1000000;

  static File? _cachedFile;
  static bool _downloading = false;

  /// Live status for widgets (map banner, offline map sheet, Account tile).
  static final ValueNotifier<OfflineMapStatus> status =
      ValueNotifier<OfflineMapStatus>(const OfflineMapStatus());

  /// Returns a `file://` URI when the archive is on disk, otherwise the
  /// original HTTP URL (so the map still works online). Triggers a background
  /// download the first time it is missing.
  static Future<Uri> lusakaArchiveUri() async {
    final file = await _cachedFileOnDisk();
    if (file != null) {
      _setStatus(OfflineMapStatus(
        state: OfflineMapState.ready,
        bytes: await file.length(),
        progress: 1,
      ));
      return Uri.file(file.path);
    }
    // Kick off a background download; don't block the map on it.
    unawaited(download());
    return Uri.parse(_lusakaUrl);
  }

  static Future<File?> _cachedFileOnDisk() async {
    if (_cachedFile != null) {
      try {
        if (await _cachedFile!.exists() && await _cachedFile!.length() >= minimumBytes) {
          return _cachedFile;
        }
      } catch (_) {
        _cachedFile = null;
      }
    }
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/map_tiles/$_fileName');
      if (await file.exists() && await file.length() >= minimumBytes) {
        _cachedFile = file;
        return file;
      }
    } catch (_) {}
    return null;
  }

  static void _setStatus(OfflineMapStatus next) {
    status.value = next;
  }

  /// Re-read the disk so the UI shows the truth (called when a sheet opens).
  static Future<OfflineMapStatus> refresh() async {
    if (_downloading) return status.value;
    final file = await _cachedFileOnDisk();
    if (file == null) {
      _setStatus(const OfflineMapStatus(state: OfflineMapState.notDownloaded));
    } else {
      _setStatus(OfflineMapStatus(
        state: OfflineMapState.ready,
        bytes: await file.length(),
        progress: 1,
      ));
    }
    return status.value;
  }

  /// Download the archive with real progress. Safe to call repeatedly: a
  /// second call while one is running just returns the current future.
  static Future<void> download({bool force = false}) async {
    if (_downloading) return;
    _downloading = true;
    File? target;
    File? tmp;
    try {
      final dir = await getApplicationDocumentsDirectory();
      target = File('${dir.path}/map_tiles/$_fileName');
      if (!force) {
        final existing = await _cachedFileOnDisk();
        if (existing != null) {
          _setStatus(OfflineMapStatus(
            state: OfflineMapState.ready,
            bytes: await existing.length(),
            progress: 1,
          ));
          return;
        }
      }
      await target.parent.create(recursive: true);
      _setStatus(const OfflineMapStatus(state: OfflineMapState.downloading, progress: 0));

      final client = http.Client();
      try {
        final req = http.Request('GET', Uri.parse(_lusakaUrl));
        final res = await client.send(req).timeout(const Duration(seconds: 30));
        if (res.statusCode != 200) {
          throw StateError('bad status ${res.statusCode}');
        }
        final total = res.contentLength ?? 0;
        final builder = BytesBuilder(copy: false);
        var received = 0;
        await for (final chunk in res.stream) {
          builder.add(chunk);
          received += chunk.length;
          _setStatus(OfflineMapStatus(
            state: OfflineMapState.downloading,
            bytes: total > 0 ? total : received,
            progress: total > 0 ? (received / total).clamp(0.0, 0.99) : 0,
          ));
        }
        final bytes = builder.takeBytes();
        if (bytes.length < minimumBytes) {
          throw StateError('truncated download (${bytes.length} bytes)');
        }
        tmp = File('${target.path}.part');
        await tmp.writeAsBytes(bytes, flush: true);
        if (await target.exists()) await target.delete();
        await tmp.rename(target.path);
        _cachedFile = target;
        _setStatus(OfflineMapStatus(
          state: OfflineMapState.ready,
          bytes: bytes.length,
          progress: 1,
        ));
        debugPrint('MapTileCache: Lusaka offline map ready (${bytes.length} bytes)');
      } finally {
        client.close();
      }
    } catch (e) {
      debugPrint('MapTileCache download failed: $e');
      try {
        if (tmp != null && await tmp.exists()) await tmp.delete();
      } catch (_) {}
      final kept = await _cachedFileOnDisk();
      if (kept != null) {
        // An older good copy survives a failed refresh — never downgrade it.
        _setStatus(OfflineMapStatus(
          state: OfflineMapState.ready,
          bytes: await kept.length(),
          progress: 1,
        ));
      } else {
        _setStatus(const OfflineMapStatus(
          state: OfflineMapState.failed,
          message: 'The map download did not finish. Check your connection and try again.',
        ));
      }
    } finally {
      _downloading = false;
    }
  }

  /// Persist already-downloaded bytes so the next run is offline-by-default.
  static Future<void> persistBytes(List<int> bytes) async {
    if (bytes.length < minimumBytes) return;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/map_tiles/$_fileName');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes, flush: true);
      _cachedFile = file;
      _setStatus(OfflineMapStatus(
        state: OfflineMapState.ready,
        bytes: bytes.length,
        progress: 1,
      ));
    } catch (_) {}
  }

  /// Remove the offline copy to free space. The map still works online.
  static Future<void> delete() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/map_tiles/$_fileName');
      if (await file.exists()) await file.delete();
      _cachedFile = null;
      _setStatus(const OfflineMapStatus(state: OfflineMapState.notDownloaded));
    } catch (_) {}
  }

  /// Force a re-download (e.g. after a corrupt file). Used by the Retry
  /// button on the "Basemap offline" banner.
  static Future<void> invalidate() async {
    await delete();
  }
}
