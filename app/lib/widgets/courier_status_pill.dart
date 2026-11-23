import 'package:flutter/material.dart';

import '../ui/app_theme.dart';

/// Honest partnership status for EVERY listed courier.
///
/// DropOff lists operators so routing, fare checks and collections work before
/// a commercial agreement exists. Showing this plainly avoids implying a
/// partnership that hasn't been signed, and gives staff a ready-made opening
/// when volumes justify outreach (owner 2026-11-23).
class CourierStatusPill extends StatelessWidget {
  const CourierStatusPill({super.key, required this.partnered, this.compact = false});

  /// True only when the courier has a signed-in partner account in D1.
  final bool partnered;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final label = partnered ? 'Partner depot' : (compact ? 'Listed' : 'Listed · partnership pending');
    final tip = partnered
        ? 'This depot has an active DropOff partner account and confirms its own prices and handovers.'
        : 'Listed for routing and fare checks so the app works in this city. Not yet a DropOff partner — we engage depots once delivery volume is confirmed.';
    return Tooltip(
      message: tip,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 9, vertical: compact ? 3 : 4),
        decoration: BoxDecoration(
          color: partnered ? AppColors.forest.withValues(alpha: 0.10) : AppColors.amber.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: partnered ? AppColors.forest.withValues(alpha: 0.3) : AppColors.amber.withValues(alpha: 0.45)),
        ),
        child: Text(label, style: TextStyle(
          fontSize: compact ? 9.5 : 10.5,
          fontWeight: FontWeight.w900,
          color: partnered ? AppColors.forest : const Color(0xFF7B5710),
        )),
      ),
    );
  }
}
