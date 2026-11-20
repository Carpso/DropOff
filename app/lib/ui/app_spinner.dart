// DropOff branded progress spinner (owner directive 2026-11-20).
//
// EVERY loader in the app — button, card or full page — is the DropOff app
// logo inside the progress ring, never a bare Material spinner. The logo is
// cropped to a circle (BoxFit.cover) so the amber pin fills the middle of the
// ring instead of a square image floating on white. Const-constructible, so it
// drops into `const` widget trees.

import 'package:flutter/material.dart';

import 'app_theme.dart';

class AppLogoSpinner extends StatelessWidget {
  /// Outer ring diameter. Button loaders use 12–22; page loaders 26–40.
  final double size;

  /// Ring colour. Defaults to DropOff forest; pass [Colors.white] on a dark
  /// filled button so the spinner stays visible.
  final Color? color;

  const AppLogoSpinner({super.key, this.size = 18, this.color});

  @override
  Widget build(BuildContext context) {
    final ring = color ?? AppColors.forest;
    // The logo is ALWAYS present, even in a 12 px button loader — the owner
    // asked for the app logo inside every spinner, no exceptions.
    final logoSize = (size * 0.64).clamp(8.0, 48.0).toDouble();
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: size,
            height: size,
            child: CircularProgressIndicator(
              strokeWidth: (size * 0.12).clamp(1.4, 4.0),
              color: ring,
              backgroundColor: ring.withValues(alpha: 0.16),
            ),
          ),
          Container(
            width: logoSize,
            height: logoSize,
            decoration: BoxDecoration(color: ring, shape: BoxShape.circle),
            clipBehavior: Clip.antiAlias,
            child: Image.asset(
              'assets/brand/dropoff_logo.png',
              fit: BoxFit.cover,
              filterQuality: FilterQuality.medium,
            ),
          ),
        ],
      ),
    );
  }
}
