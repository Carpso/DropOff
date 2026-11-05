import 'dart:ui';

import 'package:flutter/material.dart';

/// Blur + giant diagonal SAMPLE stamp — privacy for all supplied sample receipts.
/// Real, per-order receipts (captured at drop-off) MUST be shown with
/// [blurAndStamp] = false.
class SampleStamp extends StatelessWidget {
  final Widget child;
  final bool blurAndStamp;

  const SampleStamp({super.key, required this.child, this.blurAndStamp = true});

  @override
  Widget build(BuildContext context) {
    if (!blurAndStamp) return child;
    return Stack(fit: StackFit.passthrough, children: [
      child,
      Positioned.fill(
        child: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
            child: Container(color: Colors.white.withValues(alpha: 0.12)),
          ),
        ),
      ),
      Positioned.fill(
        child: IgnorePointer(
          child: Center(
            child: Transform.rotate(
              angle: -0.32,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFFD33B2E), width: 5),
                  borderRadius: const BorderRadius.all(Radius.circular(6)),
                ),
                child: const Text(
                  'SAMPLE',
                  style: TextStyle(
                    color: Color(0xFFD33B2E),
                    fontSize: 44,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 8,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ]);
  }
}
