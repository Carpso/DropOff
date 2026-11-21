import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'dropoff_api.dart';

/// Firebase Cloud Messaging for DropOff — fully optional.
///
/// Channels (Android settings > Apps > DropOff > Notifications):
///   dropoff_jobs     — parcels & rider dispatch (heads-up)
///   dropoff_chat     — messages from riders/ops/support (heads-up)
///   dropoff_payments — payments & plan renewals (heads-up)
///   dropoff_marketing — DropOff promotions (silent-ish; user-controlled)
///   dropoff_alerts   — security/fraud alerts (silent, highest priority)
///
/// Every notification carries a `kind` in its payload. Tapping one routes to
/// the exact screen it came from — not a generic Bookings fallback.
class PushService {
  static final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  static final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();

  static bool _ready = false;
  static bool _enabled = false;

  /// Emits the tapped-notification payload so main.dart can route by kind.
  static final StreamController<Map<String, dynamic>?> onPayloadTap = StreamController.broadcast();

  /// Backwards-compatible stream: only the `job_ref` (when the payload carries
  /// one). New code should prefer [onPayloadTap].
  static final Stream<String?> onNotificationTap =
      onPayloadTap.stream.map((m) => _str(m?['job_ref'])).asBroadcastStream();

  static String? _str(Object? v) => v == null ? null : '$v';

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

      final androidImpl =
          _local.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      // Wipe stale generic channel from earlier builds so Android doesn't keep
      // the legacy importance/priority mix.
      await androidImpl?.createNotificationChannel(
        const AndroidNotificationChannel('dropoff_jobs', 'DropOff — Parcels & riders',
            description: 'Booking, dispatch, rider assignment and delivery updates.',
            importance: Importance.high));
      await androidImpl?.createNotificationChannel(
        const AndroidNotificationChannel('dropoff_chat', 'DropOff — Support tickets',
            description: 'Replies to your support tickets and DropOff updates.',
            importance: Importance.high));
      await androidImpl?.createNotificationChannel(
        const AndroidNotificationChannel('dropoff_payments', 'DropOff — Payments',
            description: 'Payment receipts and plan renewals.',
            importance: Importance.high));
      await androidImpl?.createNotificationChannel(
        const AndroidNotificationChannel('dropoff_marketing', 'DropOff — Offers',
            description: 'Occasional offers and updates from DropOff. You control these.',
            importance: Importance.defaultImportance));
      await androidImpl?.createNotificationChannel(
        const AndroidNotificationChannel('dropoff_alerts', 'DropOff — Account & security',
            description: 'New device, intrusion and account alerts.',
            importance: Importance.max));

      await _local.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@drawable/ic_stat_dropoff'),
        ),
        onDidReceiveNotificationResponse: (details) =>
            onPayloadTap.add(details.payload?.isNotEmpty == true ? _decodePayload(details.payload!) : null),
      );

      FirebaseMessaging.onBackgroundMessage(_backgroundHandler);
      FirebaseMessaging.onMessage.listen(_onForegroundMessage);
      FirebaseMessaging.onMessageOpenedApp.listen((m) => onPayloadTap.add(
            Map<String, dynamic>.from(m.data).cast<String, dynamic>(),
          ));

      _enabled = true;
    } catch (_) {
      // Firebase not configured for this build — push stays off, app still runs.
    }
  }

  static Map<String, dynamic> _decodePayload(String raw) {
    try {
      final decoded = raw.contains(':')
          ? Map<String, dynamic>.from(
              Map<String, dynamic>.fromEntries(raw.split(':').map((e) => e.split('=')).where((kv) => kv.length == 2)
                  .map((kv) => MapEntry(kv[0], kv[1]))),
            )
          : <String, dynamic>{};
      return decoded;
    } catch (_) {
      // Legacy raw job_ref payload — treat as {job_ref: raw}.
      return {'job_ref': raw};
    }
  }

  @pragma('vm:entry-point')
  static Future<void> _backgroundHandler(RemoteMessage message) async {
    try {
      await Firebase.initializeApp();
      _show(message.data, message.notification?.title, message.notification?.body);
    } catch (_) {}
  }

  static void _onForegroundMessage(RemoteMessage message) =>
      _show(message.data, message.notification?.title, message.notification?.body);

  /// Category of a notification; used to pick channel, icon accent and sound.
  static String _kindOf(Map<String, dynamic> data) => '${data['kind'] ?? ''}'.toLowerCase();

  static AndroidNotificationChannel _channelFor(String kind) {
    if (kind.startsWith('chat') || kind.contains('support')) {
      return const AndroidNotificationChannel('dropoff_chat', 'DropOff — Support tickets',
          description: 'Replies to your support tickets and DropOff updates.',
          importance: Importance.high);
    }
    if (kind.contains('payment') || kind.contains('deposit') || kind.contains('plan') || kind.contains('subscription')) {
      return const AndroidNotificationChannel('dropoff_payments', 'DropOff — Payments',
          description: 'Payment receipts and plan renewals.',
          importance: Importance.high);
    }
    if (kind.contains('marketing') || kind.contains('promo')) {
      return const AndroidNotificationChannel('dropoff_marketing', 'DropOff — Offers',
          description: 'Occasional offers and updates from DropOff. You control these.',
          importance: Importance.defaultImportance);
    }
    if (kind.contains('security') || kind.contains('alert') || kind.contains('fraud')) {
      return const AndroidNotificationChannel('dropoff_alerts', 'DropOff — Account & security',
          description: 'New device, intrusion and account alerts.',
          importance: Importance.max);
    }
    return const AndroidNotificationChannel('dropoff_jobs', 'DropOff — Parcels & riders',
        description: 'Booking, dispatch, rider assignment and delivery updates.',
        importance: Importance.max);
  }

  static Future<void> _show(Map<String, dynamic> data, String? title, String? body) async {
    // Brand in the shade: every notification reads "DropOff · …" even when the
    // worker sends a generic title (owner 2026-11-21).
    final rawTitle = title ?? _titleFor(data);
    final t = rawTitle.toLowerCase().startsWith('dropoff') ? rawTitle : 'DropOff · $rawTitle';
    final b = body ?? '';
    final kind = _kindOf(data);
    final channel = _channelFor(kind);
    final android = AndroidNotificationDetails(
      channel.id,
      channel.name,
      channelDescription: channel.description,
      importance: channel.importance,
      priority: (channel.importance == Importance.defaultImportance) ? Priority.defaultPriority : Priority.high,
      playSound: true,
      enableVibration: channel.importance != Importance.defaultImportance,
      largeIcon: const DrawableResourceAndroidBitmap('@mipmap/launcher_icon'),
      icon: '@drawable/ic_stat_dropoff',
      ticker: t,
      category: (kind.contains('job') || kind.contains('assign') || kind.contains('status'))
          ? AndroidNotificationCategory.alarm
          : AndroidNotificationCategory.message,
      fullScreenIntent: kind.contains('job') || kind.contains('assign'),
      visibility: NotificationVisibility.public,
      styleInformation: BigTextStyleInformation(b, contentTitle: t, htmlFormatBigText: false),
      groupKey: 'dropoff',
    );
    const darwin = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      sound: 'default',
    );
    await _local.show(
      // Stable-ish ID across duplicate messages (same kind + job) so the shade
      // doesn't stack duplicates; reflect an actual new message if the payload
      // carries a monotonically-increasing id (e.g. chat message id).
      id: (data['message_id'] as num?)?.toInt() ?? (kind.hashCode ^ (data['job_ref']?.hashCode ?? 0) ^ b.hashCode) & 0x7fffffff,
      title: t,
      body: b,
      notificationDetails: NotificationDetails(android: android, iOS: darwin),
      payload: _encodePayload({...data, 'title': t, 'body': b}),
    );
  }

  /// Compact k=v serialization for the tap payload (e.g. job_ref=DRO-1;kind=rider_assigned).
  static String _encodePayload(Map<String, dynamic> data) =>
      data.entries.where((e) => e.value != null && '${e.value}'.isNotEmpty)
          .map((e) => '${e.key}=${e.value}').join(':');

  static String _titleFor(Map<String, dynamic> data) => switch (_kindOf(data)) {
        'payment_received' => 'Payment received',
        'deposit_paid' => 'Prepayment received — rider dispatching',
        'rider_assigned' => 'Rider assigned',
        'job_assigned' => 'New delivery assigned',
        'job_delivered' => 'Delivered — rate your rider',
        'pickup_reminder' => 'Pickup time',
        'plan_renewed' => 'Plan renewed — parcels unlocked',
        'subscription_active' => 'Plan activated',
        'marketing' => 'DropOff',
        'promo_issued' => 'Your promo reward is ready',
        'chat' => 'New message',
        'support_reply' => 'DropOff support replied',
        'security_alert' => 'DropOff security alert',
        'push_test' => 'DropOff — push test',
        _ => 'DropOff',
      };

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
      // Also refresh on FCM's own token-refresh stream so the server always
      // holds the current token (older ones get 404/410 and are pruned server-side).
      // NOTE: onRegistered is firebase's FID — NOT the messaging token our
      // backend needs (it sends via FCM token). Deprecated but intentional.
      // ignore: deprecated_member_use
      _fcm.onTokenRefresh.listen((newToken) async {
        if (newToken.isEmpty || DropOffApi.token == null) return;
        await DropOffApi.post('/push/register', {'token': newToken, 'platform': defaultTargetPlatform.name});
      });
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
