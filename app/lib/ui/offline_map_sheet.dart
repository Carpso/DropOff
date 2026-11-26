import 'package:flutter/material.dart';

import '../data/map_tile_cache.dart';
import 'app_sheet.dart';
import 'app_theme.dart';

/// Opens the offline-map manager. Reachable from the map chrome (the download
/// badge) and from Account, so a rider can prepare the phone before going out
/// on a route with no signal.
Future<void> showOfflineMapSheet(BuildContext context) =>
    showAppSheet<void>(context, child: const OfflineMapSheet());

/// Offline basemap manager: download, live progress, delete.
///
/// Copy rules: plain language only. A failed download says what to do next
/// ("check your connection and try again") and never leaks a raw exception,
/// URL or `.pmtiles` file name at the rider.
class OfflineMapSheet extends StatefulWidget {
  const OfflineMapSheet({super.key});

  @override
  State<OfflineMapSheet> createState() => _OfflineMapSheetState();
}

class _OfflineMapSheetState extends State<OfflineMapSheet> {
  @override
  void initState() {
    super.initState();
    // Truth on open: the file may have been downloaded in a previous session.
    MapTileCache.refresh();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<OfflineMapStatus>(
      valueListenable: MapTileCache.status,
      builder: (context, status, _) {
        final ready = status.isReady;
        final busy = status.isBusy;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.line,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.forest.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.download_for_offline_rounded, color: AppColors.forest),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Offline map',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: -0.2),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            const Text(
              'Keep the streets on this phone so the map, your position and the route '
              'still work with no network. Only the map is downloaded.',
              style: TextStyle(fontSize: 13.5, height: 1.45, color: AppColors.muted),
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.canvas,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.forest.withValues(alpha: 0.18)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(children: [
                    const Expanded(
                      child: Text(
                        'Lusaka, Zambia',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.ink),
                      ),
                    ),
                    _statePill(status),
                  ]),
                  const SizedBox(height: 4),
                  Text(
                    _detailLine(status),
                    style: const TextStyle(fontSize: 12, height: 1.35, color: AppColors.muted),
                  ),
                  if (busy) ...[
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: status.progress > 0 ? status.progress : null,
                        minHeight: 6,
                        backgroundColor: AppColors.forest.withValues(alpha: 0.10),
                        valueColor: const AlwaysStoppedAnimation<Color>(AppColors.forest),
                      ),
                    ),
                  ],
                  if (status.message != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      status.message!,
                      style: const TextStyle(fontSize: 12, height: 1.35, color: AppColors.danger),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: busy ? null : () => _start(status),
                icon: Icon(ready ? Icons.refresh_rounded : Icons.download_rounded, size: 18),
                label: Text(busy
                    ? 'Downloading…'
                    : ready
                        ? 'Download again'
                        : 'Download for offline use'),
              ),
            ),
            if (ready) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: busy ? null : _delete,
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  label: const Text('Delete from this phone'),
                  style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
                ),
              ),
            ],
            const SizedBox(height: 6),
            const Text(
              'Tip: download while you are on Wi-Fi. The map keeps working when your data drops.',
              style: TextStyle(fontSize: 11.5, height: 1.4, color: AppColors.muted),
            ),
          ],
        );
      },
    );
  }

  String _detailLine(OfflineMapStatus status) {
    switch (status.state) {
      case OfflineMapState.ready:
        final size = status.sizeLabel;
        return size.isEmpty
            ? 'Saved on this phone. Works with no network.'
            : 'Saved on this phone · $size · works with no network.';
      case OfflineMapState.downloading:
        final pct = (status.progress * 100).clamp(0, 100).toStringAsFixed(0);
        final size = status.sizeLabel;
        return size.isEmpty
            ? 'Downloading… $pct%'
            : 'Downloading… $pct% of about $size';
      case OfflineMapState.failed:
        return 'Not saved yet.';
      case OfflineMapState.notDownloaded:
      case OfflineMapState.unknown:
        return 'About 30 MB once. Streets, places and addresses for the city.';
    }
  }

  Widget _statePill(OfflineMapStatus status) {
    late final String label;
    late final Color bg;
    late final Color fg;
    switch (status.state) {
      case OfflineMapState.ready:
        label = 'SAVED';
        bg = AppColors.forest.withValues(alpha: 0.12);
        fg = AppColors.forest;
      case OfflineMapState.downloading:
        label = 'DOWNLOADING';
        bg = AppColors.amber.withValues(alpha: 0.22);
        fg = AppColors.ink;
      case OfflineMapState.failed:
        label = 'RETRY';
        bg = AppColors.danger.withValues(alpha: 0.12);
        fg = AppColors.danger;
      case OfflineMapState.notDownloaded:
      case OfflineMapState.unknown:
        label = 'NOT SAVED';
        bg = AppColors.muted.withValues(alpha: 0.14);
        fg = AppColors.muted;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(
        label,
        style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w900, letterSpacing: 0.5, color: fg),
      ),
    );
  }

  Future<void> _start(OfflineMapStatus status) async {
    // Re-downloading over a saved copy must be an explicit choice.
    if (status.isReady) {
      final go = await showConfirmSheet(
        context,
        title: 'Download the map again?',
        message: 'The saved copy stays on the phone until the new download finishes. '
            'Do this on Wi-Fi to avoid using mobile data.',
        confirmLabel: 'Download again',
        icon: Icons.download_for_offline_rounded,
      );
      if (!go) return;
    }
    await MapTileCache.download(force: true);
  }

  Future<void> _delete() async {
    final go = await showConfirmSheet(
      context,
      title: 'Delete the offline map?',
      message: 'The map will need a connection again. Your bookings, routes and '
          'addresses are not affected.',
      confirmLabel: 'Delete',
      danger: true,
      icon: Icons.delete_outline_rounded,
    );
    if (!go) return;
    await MapTileCache.delete();
  }
}

/// Compact Account tile that shows the offline map state and opens the sheet.
class OfflineMapTile extends StatefulWidget {
  const OfflineMapTile({super.key});

  @override
  State<OfflineMapTile> createState() => _OfflineMapTileState();
}

class _OfflineMapTileState extends State<OfflineMapTile> {
  @override
  void initState() {
    super.initState();
    MapTileCache.refresh();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<OfflineMapStatus>(
      valueListenable: MapTileCache.status,
      builder: (context, status, _) {
        final size = status.sizeLabel;
        final subtitle = status.isBusy
            ? 'Downloading… ${(status.progress * 100).clamp(0, 100).toStringAsFixed(0)}%'
            : status.isReady
                ? (size.isEmpty ? 'Saved on this phone' : 'Saved on this phone · $size')
                : 'Not saved yet · works with no network';
        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.forest.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(11),
            ),
            child: const Icon(Icons.download_for_offline_rounded, size: 20, color: AppColors.forest),
          ),
          title: const Text('Offline map', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          subtitle: Text(subtitle, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
          trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
          onTap: () => showOfflineMapSheet(context),
        );
      },
    );
  }
}
