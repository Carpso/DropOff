import 'package:flutter/material.dart';

import 'app_spinner.dart';
import 'app_theme.dart';

/// Premium "we're securing your proof" state shown while a camera photo is
/// stamped with the DropOff/CAT mark and uploaded. Blocking, branded, and
/// impossible to mistake for a frozen screen (owner 2026-11-23).
class ProofUploadOverlay {
  const ProofUploadOverlay._();

  /// Runs [task] with the overlay visible and always removes it afterwards,
  /// including on error.
  static Future<T> run<T>(
    BuildContext context, {
    required String title,
    String subtitle = 'Adding the DropOff time stamp and uploading securely…',
    required Future<T> task,
  }) async {
    final overlay = Overlay.of(context, rootOverlay: true);
    final entry = OverlayEntry(builder: (_) => _ProofUploadView(title: title, subtitle: subtitle));
    overlay.insert(entry);
    try {
      return await task;
    } finally {
      entry.remove();
    }
  }
}

class _ProofUploadView extends StatefulWidget {
  const _ProofUploadView({required this.title, required this.subtitle});
  final String title;
  final String subtitle;

  @override
  State<_ProofUploadView> createState() => _ProofUploadViewState();
}

class _ProofUploadViewState extends State<_ProofUploadView> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Positioned.fill(
      child: Material(
        color: const Color(0xBB0B2A22),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: size.width - 48),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 28),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.24), blurRadius: 28, offset: const Offset(0, 10))],
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                AnimatedBuilder(
                  animation: _pulse,
                  builder: (_, child) => Transform.scale(
                    scale: 0.94 + (_pulse.value * 0.08),
                    child: child,
                  ),
                  child: Container(
                    width: 88,
                    height: 88,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(colors: [Color(0xFFE8F2EC), Color(0xFFD6E7DC)]),
                    ),
                    alignment: Alignment.center,
                    child: const AppLogoSpinner(size: 52),
                  ),
                ),
                const SizedBox(height: 20),
                Text(widget.title, textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17, color: AppColors.ink)),
                const SizedBox(height: 8),
                Text(widget.subtitle, textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12.5, color: AppColors.muted, height: 1.4)),
                const SizedBox(height: 20),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: const SizedBox(
                    height: 3,
                    child: LinearProgressIndicator(
                      backgroundColor: Color(0xFFE4EDE8),
                      valueColor: AlwaysStoppedAnimation<Color>(AppColors.amber),
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
