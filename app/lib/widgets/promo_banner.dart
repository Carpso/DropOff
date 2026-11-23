import 'package:flutter/material.dart';

import '../ui/app_theme.dart';

/// Amber retention/promo card used by the Business tab (and safe to reuse).
///
/// LAYOUT INVARIANT — DO NOT REGRESS (owner bug, vertical-text card):
///  * the icon sits in a FIXED-width rail and the title in an `Expanded`, so
///    neither can squeeze the other into a one-character column;
///  * the BODY is on its own FULL-WIDTH line below that Row — never inside it;
///  * the CTA is a full-width button on its own line;
///  * nothing here has a fixed height, so body copy can never be clipped.
/// See `test/promo_banner_test.dart` (320 px narrow-phone regression test).
class PromoBanner extends StatelessWidget {
  const PromoBanner({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    required this.cta,
    required this.onCta,
  });

  final IconData icon;
  final String title;
  final String body;
  final String cta;
  final VoidCallback onCta;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.amber.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.amber.withValues(alpha: 0.35)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: 36,
            height: 36,
            child: Icon(icon, size: 22, color: AppColors.amber),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              softWrap: true,
              textAlign: TextAlign.left,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13, height: 1.2),
            ),
          ),
        ]),
        const SizedBox(height: 6),
        // Full-width body: `Column` hands it the card's complete content width,
        // so it wraps by words. A `Row` here (or a fixed-height parent) is the
        // exact bug this widget was extracted to prevent.
        Text(body, softWrap: true, textAlign: TextAlign.left, style: AppType.caption.copyWith(height: 1.4)),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
            onPressed: onCta,
            child: Text(cta, maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis),
          ),
        ),
      ]),
    );
  }
}
