// DropOff smart saved-place map pin (owner 2026-11-21).
// A branded teardrop with the actual app logo on the pinhead — built from
// existing assets so it ships without any new image dependency.

import 'package:flutter/material.dart';

import 'app_theme.dart';

class SavedPlacePin extends StatelessWidget {
  final String label;
  final bool selected;
  final bool frequent;
  final VoidCallback? onTap;

  const SavedPlacePin({
    super.key,
    required this.label,
    this.selected = false,
    this.frequent = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final pin = Stack(
      alignment: Alignment.topCenter,
      children: [
        // Amber rim then forest body — a layered teardrop reads as bevel/3D.
        const Icon(Icons.place_rounded, size: 50, color: AppColors.amber),
        const Padding(
          padding: EdgeInsets.only(top: 2),
          child: Icon(Icons.place_rounded, size: 46, color: AppColors.forest),
        ),
        Positioned(
          top: 10,
          child: Container(
            width: 22,
            height: 22,
            padding: const EdgeInsets.all(2),
            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
            child: Image.asset('assets/brand/dropoff_logo.png', fit: BoxFit.contain),
          ),
        ),
        if (frequent)
          const Positioned(
            right: 6,
            top: 6,
            child: Icon(Icons.star_rounded, size: 16, color: AppColors.amber),
          ),
      ],
    );
    return Semantics(
      label: 'Saved place: $label',
      child: GestureDetector(
        onTap: onTap,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (selected)
            Container(
              margin: const EdgeInsets.only(bottom: 2),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.forest.withValues(alpha: 0.4)),
              ),
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.ink)),
            ),
          pin,
        ]),
      ),
    );
  }
}
