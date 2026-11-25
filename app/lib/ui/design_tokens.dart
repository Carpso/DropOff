// DropOff design tokens (owner 2026-11-25, "billion-dollar" UI audit).
//
// Single source of truth for color, spacing, radius, typography and motion.
// Every screen should reference these instead of ad-hoc literals so the app
// feels consistent and premium. Values mirror AppColors/AppType where those
// already exist; this file is the canonical home going forward.

import 'package:flutter/material.dart';

/// Color tokens. Prefer these over raw Color(0x...) in new code.
class DColors {
  DColors._();
  static const forest = Color(0xFF0E3B32);
  static const forestLight = Color(0xFF1C6B87);
  static const amber = Color(0xFFF6B73C);
  static const amberSoft = Color(0xFFFFE9BE);
  static const canvas = Color(0xFFF5F5F0);
  static const surface = Colors.white;
  static const muted = Color(0xFF65736D);
  static const ink = Color(0xFF11261B);
  static const line = Color(0xFFDCE4DF);
  static const success = Color(0xFF2E7D32);
  static const danger = Color(0xFFB3261E);
  static const info = Color(0xFF1976D2);
  static const warning = Color(0xFF7B5710);
}

/// Spacing scale (4-based). Use instead of arbitrary values.
class DSpace {
  DSpace._();
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
}

/// Radius scale.
class DRadius {
  DRadius._();
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 20.0;
  static const full = 999.0;
}

/// Typography scale. Use AppText (below) instead of ad-hoc TextStyle.
class DText {
  DText._();
  static const display = TextStyle(fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: -0.6, height: 1.1);
  static const headline = TextStyle(fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: -0.3, height: 1.2);
  static const title = TextStyle(fontSize: 16, fontWeight: FontWeight.w800, height: 1.25);
  static const body = TextStyle(fontSize: 14, fontWeight: FontWeight.w500, height: 1.4);
  static const bodyBold = TextStyle(fontSize: 14, fontWeight: FontWeight.w700, height: 1.4);
  static const caption = TextStyle(fontSize: 12, fontWeight: FontWeight.w600, height: 1.35);
  static const overline = TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.1, height: 1.2);
}

/// Motion durations.
class DMotion {
  DMotion._();
  static const fast = Duration(milliseconds: 120);
  static const normal = Duration(milliseconds: 200);
  static const slow = Duration(milliseconds: 350);
}

/// Empty-state placeholder used by every list screen.
class DEmptyState extends StatelessWidget {
  const DEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
    this.actionLabel,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? action;
  final String? actionLabel;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: DColors.muted),
            const SizedBox(height: DSpace.lg),
            Text(title, style: DText.headline.copyWith(color: DColors.ink), textAlign: TextAlign.center),
            if (subtitle != null) ...[
              const SizedBox(height: DSpace.sm),
              Text(subtitle!, style: DText.body.copyWith(color: DColors.muted), textAlign: TextAlign.center),
            ],
            if (action != null && actionLabel != null) ...[
              const SizedBox(height: DSpace.xl),
              FilledButton.icon(
                onPressed: action,
                icon: const Icon(Icons.add_rounded),
                label: Text(actionLabel!),
                style: FilledButton.styleFrom(backgroundColor: DColors.forest),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Section header used to group content (sticky-friendly).
class DSectionHeader extends StatelessWidget {
  const DSectionHeader(this.title, {super.key, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(DSpace.lg, DSpace.xl, DSpace.lg, DSpace.sm),
      child: Row(
        children: [
          Text(title.toUpperCase(), style: DText.overline.copyWith(color: DColors.muted)),
          const Spacer(),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Standard card wrapper with consistent padding and radius.
class DCard extends StatelessWidget {
  const DCard({super.key, required this.child, this.padding = const EdgeInsets.all(DSpace.lg)});

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: DSpace.md),
      padding: padding,
      decoration: BoxDecoration(
        color: DColors.surface,
        borderRadius: BorderRadius.circular(DRadius.lg),
        border: Border.all(color: DColors.line),
        boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 8, offset: Offset(0, 2))],
      ),
      child: child,
    );
  }
}