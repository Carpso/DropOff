import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'dropoff_api.dart';

/// Firebase Cloud Messaging for DropOff — fully optional.
///
/// When no Firebase project config exists (web / builds without
/// google-services.json) every method silently no-ops, so the app still runs.
class PushService {
  static final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  static final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();

  static bool _ready = false;
  static bool _enabled = false;

  /// Emits the job ref carried by a tapped notification so main.dart can open
  /// the Bookings tab.
  static final StreamController<String?> onNotificationTap = StreamController.broadcast();

  /// Starts Firebase + local notifications. Safe to call any number of times;
  /// never throws.
  static Future<void> init() async {
    if (_ready) return;
    _ready = true;
    try {
      if (kIsWeb || Platform.isWindows) return;

      await Firebase.initializeApp();
      await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      const android = AndroidNotificationChannel(
        'dropoff_jobs',
        'DropOff parcels',
        description: 'Job status and payment updates.',
        importance: Importance.high,
      );
      final androidImpl =
          _local.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await androidImpl?.createNotificationChannel(android);

      await _local.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/launcher_icon'),
        ),
        onDidReceiveNotificationResponse: (details) =>
            onNotificationTap.add(details.payload),
      );

      FirebaseMessaging.onBackgroundMessage(_backgroundHandler);
      FirebaseMessaging.onMessage.listen(_onForegroundMessage);
      FirebaseMessaging.onMessageOpenedApp.listen((m) =>
          onNotificationTap.add(m.data['job_ref'] as String?));

      _enabled = true;
    } catch (_) {
      // Firebase not configured for this build — push stays off, app still runs.
    }
  }

  @pragma('vm:entry-point')
  static Future<void> _backgroundHandler(RemoteMessage message) async {
    try {
      await Firebase.initializeApp();
      _show(message.notification?.title ?? 'DropOff',
          message.notification?.body ?? '', message.data);
    } catch (_) {}
  }

  static void _onForegroundMessage(RemoteMessage message) =>
      _show(message.notification?.title ?? 'DropOff',
          message.notification?.body ?? '', message.data);

  static Future<void> _show(String title, String body, Map<String, dynamic> data) async {
    const android = AndroidNotificationDetails(
      'dropoff_jobs',
      'DropOff parcels',
      channelDescription: 'Job status and payment updates.',
      importance: Importance.high,
      priority: Priority.high,
    );
    const darwin = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      sound: 'default',
    );
    await _local.show(
      id: data.hashCode & 0x7fffffff,
      title: title,
      body: body,
      // ignore: prefer_const_constructors
      notificationDetails: NotificationDetails(android: android, iOS: darwin),
      payload: data['job_ref'] as String?,
    );
  }

  /// Registers this device's FCM token under the signed-in user's phone. Call
  /// after every successful sign-in / link.
  static Future<void> register() async {
    if (!_enabled) return;
    try {
      // ignore: deprecated_member_use
      final fcmToken = await _fcm.getToken();
      if (fcmToken == null || DropOffApi.token == null) return;
      final res = await DropOffApi.post('/push/register',
          {'token': fcmToken, 'platform': defaultTargetPlatform.name});
      if (!res.ok) {
        debugPrint('push register failed: ${res.error}');
      }
    } catch (_) {}
  }

  /// Deregisters this device (sign-out).
  static Future<void> unregister() async {
    if (!_enabled) return;
    try {
      // ignore: deprecated_member_use
      final fcmToken = await _fcm.getToken();
      if (fcmToken == null) return;
      await DropOffApi.delete('/push/register', body: {'token': fcmToken});
    } catch (_) {}
  }
}
