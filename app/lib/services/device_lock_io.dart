// Mobile/desktop implementation of the biometric gate (dart:io platforms).
// Ignored on web - device_lock_stub.dart wins there via the conditional export.
import 'package:local_auth/local_auth.dart';

class DeviceLock {
  static Future<bool> get isAvailable async {
    try {
      final la = LocalAuthentication();
      if (!await la.isDeviceSupported()) return false;
      return await la.canCheckBiometrics;
    } catch (_) {
      return false;
    }
  }

  /// Prompts the device credential (fingerprint / face / PIN / pattern).
  /// biometricOnly:false so a failed sensor falls back to the PIN - nobody
  /// gets locked out of their own parcel app.
  static Future<bool> authenticate(String reason) async {
    try {
      final la = LocalAuthentication();
      return await la.authenticate(
        localizedReason: reason,
        biometricOnly: false,
        sensitiveTransaction: true,
        persistAcrossBackgrounding: true,
      );
    } catch (_) {
      return false;
    }
  }
}
