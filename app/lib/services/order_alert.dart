import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'step_sounds.dart';

/// inDrive-style INCOMING ORDER alert (owner 2026-11-24).
///
/// A new delivery is the one alert that must behave like an incoming call:
///
///  * **Loops** an alarm ringtone and a vibration pattern until the rider
///    accepts, declines, opens the app, or 60 s pass (`OrderAlertService` on
///    Android, a haptic/sound loop elsewhere).
///  * Survives aggressive OEM battery managers because the Android side runs in
///    a **foreground service** with a partial wake lock — a single notification
///    chime is easy to miss on a moving bike.
///  * Carries **Accept / Decline** actions straight on the notification, so the
///    rider answers without hunting for the app.
///
/// Every path funnels into [onAction] with `{action: accept|decline|open,
/// ref: DRO-…}`, so the app performs the API call with the real session
/// (a killed app is relaunched by the notification action and replays the tap).
class OrderAlert {
  OrderAlert._();

  static const MethodChannel _channel =
      MethodChannel('zm.dropoff.dropoff/order_alert');

  static final StreamController<Map<String, dynamic>> _actions =
      StreamController<Map<String, dynamic>>.broadcast();

  /// Accept / Decline / Open taps, from the notification, the ring service or
  /// the system intent that relaunched the app.
  static Stream<Map<String, dynamic>> get onAction => _actions.stream;

  /// An action that arrived before any listener was attached (cold start).
  static Map<String, dynamic>? _pending;

  static bool _ringing = false;
  static bool get ringing => _ringing;

  static Timer? _fallbackTimer;
  static int _fallbackTicks = 0;
  static const int _fallbackMaxTicks = 60;

  static bool get _native => !kIsWeb && Platform.isAndroid;

  /// Wire the native channel and replay any tap that relaunched the app.
  static Future<void> init() async {
    if (!_native) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onOrderAction') {
        final raw = (call.arguments as Map?) ?? const {};
        final action = '${raw['action'] ?? ''}';
        final ref = '${raw['ref'] ?? ''}';
        if (action.isNotEmpty && ref.isNotEmpty) {
          handleAction({'action': action, 'ref': ref});
        }
      }
      return null;
    });
    final pending = await consumePendingAction();
    if (pending != null) handleAction(pending);
  }

  /// Entry point for every accept/decline/open source.
  static void handleAction(Map<String, dynamic> action) {
    final ref = '${action['ref'] ?? ''}';
    if (ref.isEmpty) return;
    _pending = action;
    unawaited(stop());
    if (!_actions.isClosed) _actions.add(action);
  }

  /// Takes (and clears) an action that arrived before Flutter was listening.
  static Map<String, dynamic>? takePending() {
    final p = _pending;
    _pending = null;
    return p;
  }

  /// Starts ringing for [ref]. Safe to call repeatedly — one ring per order.
  static Future<void> start({
    required String ref,
    String title = 'New delivery',
    String body = '',
    String address = '',
    String eta = '',
    String fee = '',
  }) async {
    if (ref.isEmpty) return;
    _ringing = true;
    if (_native) {
      try {
        await _channel.invokeMethod<void>('startRing', {
          'ref': ref,
          'title': title,
          'body': body,
          'address': address,
          'eta': eta,
          'fee': fee,
        });
        return; // the native foreground service is ringing
      } catch (_) {
        // Fall through to the in-app alarm loop.
      }
    }
    _startFallbackLoop();
  }

  /// Silences the alert (accepted, declined, opened, or timed out).
  static Future<void> stop() async {
    _ringing = false;
    _fallbackTimer?.cancel();
    _fallbackTimer = null;
    if (!_native) return;
    try {
      await _channel.invokeMethod<void>('stopRing');
    } catch (_) {}
  }

  /// Reads a tap captured by the native activity before the channel existed.
  static Future<Map<String, dynamic>?> consumePendingAction() async {
    if (!_native) return null;
    try {
      final raw = await _channel.invokeMethod<Map<Object?, Object?>>('pendingAction');
      if (raw == null) return null;
      final action = '${raw['action'] ?? ''}';
      final ref = '${raw['ref'] ?? ''}';
      if (action.isEmpty || ref.isEmpty) return null;
      return {'action': action, 'ref': ref};
    } catch (_) {
      return null;
    }
  }

  /* --------------------------- battery + health -------------------------- */

  /// False on Xiaomi/Oppo/Vivo/Samsung-style managers that can stop order
  /// pushes when the app is "optimised". Riders get an honest fix prompt.
  static Future<bool> batteryOptimizationsIgnored() async {
    if (!_native) return true;
    try {
      return await _channel.invokeMethod<bool>('batteryOptimizationsIgnored') ?? true;
    } catch (_) {
      return true;
    }
  }

  /// Opens the system exemption dialog. Never changes a setting silently.
  static Future<bool> requestIgnoreBatteryOptimizations() async {
    if (!_native) return false;
    try {
      return await _channel.invokeMethod<bool>('requestIgnoreBatteryOptimizations') ?? false;
    } catch (_) {
      return false;
    }
  }

  /* ------------------------------- fallback ------------------------------ */

  /// Platforms without the native service (iOS/web/desktop, or a device that
  /// refused the foreground service) still get an insistent alarm: haptics plus
  /// the order chime, repeating for the same 60 s window.
  static void _startFallbackLoop() {
    _fallbackTimer?.cancel();
    _fallbackTicks = 0;
    unawaited(StepSounds.orderAlert());
    _fallbackTimer = Timer.periodic(const Duration(milliseconds: 900), (t) {
      _fallbackTicks++;
      if (!_ringing || _fallbackTicks > _fallbackMaxTicks) {
        t.cancel();
        _fallbackTimer = null;
        return;
      }
      HapticFeedback.heavyImpact();
      if (_fallbackTicks % 2 == 0) unawaited(StepSounds.orderAlert());
    });
  }
}
