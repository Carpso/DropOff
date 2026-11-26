import 'package:flutter/material.dart';

import 'app_theme.dart';

/// The map's copyright stamp (owner 2026-11-26): a circled (c) beside the
/// DropOff name, then the map-data credit. It reads as OUR map, not a stock
/// tile widget, and it is the single place the OpenStreetMap attribution is
/// rendered - keep it on every map surface.
///
/// Layout note (AGENTS.md invariants): the row is short and every text child
/// is intrinsic-width, so it cannot collapse into vertical text; the whole
/// stamp is wrapped by the caller in a [Positioned] with a bounded parent.
class MapCreditStamp extends StatelessWidget {
  const MapCreditStamp({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 4, 9, 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.93),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.forest.withValues(alpha: 0.28)),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 3, offset: Offset(0, 1))],
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        // Circled (c).
        Container(
          width: 14,
          height: 14,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.forest, width: 1.2),
          ),
          child: const Text(
            'C',
            style: TextStyle(fontSize: 8, height: 1, fontWeight: FontWeight.w900, color: AppColors.forest),
          ),
        ),
        const SizedBox(width: 4),
        const Text(
          'DropOff',
          style: TextStyle(
            fontSize: 9.5,
            height: 1.1,
            fontWeight: FontWeight.w900,
            color: AppColors.forest,
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(width: 5),
        Container(width: 1, height: 9, color: AppColors.forest.withValues(alpha: 0.25)),
        const SizedBox(width: 5),
        // Bounded + ellipsis: the credit can never push the pill past a 320 px
        // map edge (owner layout invariant). ConstrainedBox (not Flexible)
        // keeps the pill intrinsic-width instead of stretching it full width.
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 186),
          child: const Text(
            'map data \u00A9 OpenStreetMap contributors',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 8, height: 1.1, color: AppColors.muted, fontWeight: FontWeight.w600),
          ),
        ),
      ]),
    );
  }
}
