// Web (and any platform without dart:io): biometrics are not offered.
// The conditional export in device_lock.dart swaps this in for browsers.
class DeviceLock {
  static Future<bool> get isAvailable async => false;

  static Future<bool> authenticate(String reason) async => false;
}
