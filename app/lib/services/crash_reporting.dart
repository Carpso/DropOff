import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:http/http.dart' as http;

import '../data/dropoff_api.dart';

/// Production crash visibility — free, in our own D1, no third-party account.
///
/// Captures every unhandled Flutter/Dart error (framework + synchronous) and
/// posts a compact report to the Worker (`POST /client/error`). The worker
/// dedupes by device+message+stack fingerprint per hour, stores at most 2000
/// chars of stack, and the admin console shows the tally per 24h.
///
/// Wired at startup: [CrashReporting.init] is called before runApp in main.dart.
class CrashReporting {
  static const String _appVersion = '0.5.34+44';
  static bool _initialised = false;

  static void init() {
    if (_initialised) return;
    _initialised = true;

    FlutterError.onError = (details) {
      // Preserve default logging so errors still surface in debug builds.
      FlutterError.presentError(details);
      _report(_describeFlutterError(details), details.stack);
    };

    PlatformDispatcher.instance.onError = (error, stack) {
      _report(error.toString(), stack);
      return true; // stop red-screens crashing the process on release builds
    };
  }

  static String _describeFlutterError(FlutterErrorDetails details) {
    final exception = details.exception;
    final library = details.library == null ? '' : ' [${details.library}]';
    return '${exception.runtimeType}$library: $exception';
  }

  static Future<void> _report(String message, StackTrace? stack) async {
    if (!DropOffApi.enabled) return; // offline demo mode — nothing to report
    try {
      final platform = Platform.isAndroid
          ? 'android'
          : Platform.isIOS
              ? 'ios'
              : Platform.isWindows
                  ? 'windows'
                  : Platform.isLinux
                      ? 'linux'
                      : 'other';
      final stackText = stack?.toString() ?? '';
      final headers = <String, String>{
        'Content-Type': 'application/json',
        if (DropOffApi.apiKey.isNotEmpty) 'X-Api-Key': DropOffApi.apiKey,
        if (DropOffApi.token != null) 'Authorization': 'Bearer ${DropOffApi.token}',
        if (DropOffApi.deviceId.isNotEmpty) 'X-Device-Id': DropOffApi.deviceId,
      };
      await http
          .post(
            Uri.parse('${DropOffApi.baseUrl}/client/error'),
            headers: headers,
            body: jsonEncode({
              'message': message.length > 240 ? message.substring(0, 240) : message,
              'stack': stackText.length > 2000 ? stackText.substring(0, 2000) : stackText,
              'platform': platform,
              'app_version': _appVersion,
              'device_id': DropOffApi.deviceId.isEmpty ? 'unknown' : DropOffApi.deviceId,
            }),
          )
          .timeout(const Duration(seconds: 6));
    } catch (_) {
      // crash reporting must never crash the app
    }
  }
}
