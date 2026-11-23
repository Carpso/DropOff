import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Screenshot / screen-record protection.
///
/// Android only: sets FLAG_SECURE on the activity window, so the OS blocks
/// screenshots and recording of OTPs, waybills, customer addresses and admin
/// finance screens. This does NOT affect the OS share sheet or sharing a file
/// with Share.shareXFiles — every share path in DropOff exports a real image or
/// document rather than capturing the screen (owner 2026-11-23).
class ScreenPrivacy {
  const ScreenPrivacy._();

  static const MethodChannel _channel = MethodChannel('zm.dropoff.dropoff/screen_privacy');

  /// Call once at startup. No-op on web/desktop (flag is Android-specific).
  static Future<void> enableProtection() async {
    if (kIsWeb) return;
    try {
      await _channel.invokeMethod<bool>('setSecure', {'enabled': true});
    } on MissingPluginException {
      debugPrint('ScreenPrivacy: native channel not available');
    } catch (e) {
      debugPrint('ScreenPrivacy: could not enable protection: $e');
    }
  }
}
