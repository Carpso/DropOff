import 'package:flutter/material.dart';

import '../ui/app_theme.dart';
import '../widgets/common.dart';

/// Full-screen device lock shown on cold start when "fingerprint / face
/// unlock" is on and a session exists. Unlocking restores the app instantly
/// (the session was already persisted) — no password re-typing.
class BiometricLockScreen extends StatelessWidget {
  const BiometricLockScreen({
    super.key,
    required this.onUnlock,
    required this.onUsePassword,
    this.busy = false,
    this.error,
  });

  /// Prompt the biometric.
  final VoidCallback onUnlock;

  /// Drop the session and show the password sign-in door.
  final VoidCallback onUsePassword;

  final bool busy;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.forest,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const DropOffLogo(size: 46),
              const SizedBox(height: 28),
              const Text('Unlock DropOff', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: -0.8)),
              const SizedBox(height: 6),
              const Text('Your session is on this phone — prove it is you.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFFC9D9D2), height: 1.4)),
              const SizedBox(height: 28),
              SizedBox(
                width: 132,
                height: 132,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    shape: const CircleBorder(),
                    backgroundColor: AppColors.amber,
                    foregroundColor: AppColors.forest,
                  ),
                  onPressed: busy ? null : onUnlock,
                  child: busy
                      ? const SizedBox(width: 40, height: 40, child: CircularProgressIndicator(strokeWidth: 3, color: AppColors.forest))
                      : const Icon(Icons.fingerprint, size: 64),
                ),
              ),
              const SizedBox(height: 26),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.amber, fontWeight: FontWeight.w800)),
                ),
              TextButton(
                onPressed: busy ? null : onUsePassword,
                child: const Text('Use my password instead',
                    style: TextStyle(color: Color(0xFFC9D9D2), fontWeight: FontWeight.w700)),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
