import 'package:flutter/material.dart';

import 'app_theme.dart';

/// Shown on the map when the basemap could not open.
///
/// HARD RULE (owner 2026-11-26): this widget accepts NO error string. A rider
/// must never see internals such as
/// `region-zm-zw-mw-mz.pmtiles:timeoutexception after 0:00:08.000000:future not
/// completed`. Technical detail goes to CrashReporting/logs; the person holding
/// the phone gets calm, actionable copy. Keeping the parameter out of the API
/// makes a leak impossible.
class MapOfflineBanner extends StatelessWidget {
  const MapOfflineBanner({
    super.key,
    required this.onRetry,
    required this.onDownload,
  });

  final VoidCallback onRetry;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.97),
      borderRadius: BorderRadius.circular(12),
      elevation: 2,
      shadowColor: AppColors.forest.withValues(alpha: 0.25),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
        // Layout invariants: body copy sits on its own full-width line, the
        // CTA is full width, and no long string is a direct child of a Row.
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(children: [
              const Icon(Icons.explore_off_outlined, size: 17, color: AppColors.amber),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  'Map detail is offline',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: AppColors.ink),
                ),
              ),
              TextButton(
                onPressed: onRetry,
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, 30),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('Retry',
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800)),
              ),
            ]),
            const Text(
              'Your position, route and turn cues still work.',
              style: TextStyle(fontSize: 10.5, height: 1.3, color: AppColors.muted),
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onDownload,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.forest,
                  side: BorderSide(color: AppColors.forest.withValues(alpha: 0.45)),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                icon: const Icon(Icons.download_for_offline_rounded, size: 15),
                label: const Text(
                  'Save the map for offline',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
