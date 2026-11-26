import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart' as permission_handler;

import 'dropoff_api.dart';
import 'notification_inbox.dart';
import '../services/order_alert.dart';

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
  /// Completes when Firebase/permission/channel setup finishes (success or
  /// failure). [register] waits on it instead of racing a cold start, without
  /// holding the splash screen hostage to the OS permission dialog.
  static final Completer<void> _initDone = Completer<void>();
  static bool _localReady = false;
  static bool _permissionGranted = false;
  static bool _tokenRefreshBound = false;

  /// True when Android actually allows notifications. Riders need this to be
  /// visible: a denied POST_NOTIFICATIONS (Android 13+) makes every FCM send
  /// silently vanish even though the token is registered server-side.
  static bool get notificationsEnabled => _permissionGranted;

  /// Web/Windows have no Android notification channel to configure.
  static bool get supportsPush => !kIsWeb && !Platform.isWindows;

  static bool _granted(AuthorizationStatus status) =>
      status == AuthorizationStatus.authorized || status == AuthorizationStatus.provisional;

  /// Re-read the OS setting (e.g. the rider just changed it in Settings).
  static Future<bool> refreshPermission() async {
    if (kIsWeb || Platform.isWindows) return true;
    try {
      final settings = await _fcm.getNotificationSettings();
      _permissionGranted = _granted(settings.authorizationStatus);
    } catch (_) {}
    return _permissionGranted;
  }

  /// Android 13+ will not re-prompt after the rider tapped "Don't allow" —
  /// the only recovery is the system settings screen.
  static Future<void> openNotificationSettings() async {
    if (kIsWeb || Platform.isWindows) return;
    await permission_handler.openAppSettings();
  }

  /// Emits the tapped-notification payload so main.dart can route by kind.
  static final StreamController<Map<String, dynamic>?> onPayloadTap = StreamController.broadcast();

  /// Every message received while the app is in the foreground. Used to show
  /// an in-app prompt for a newly-filed depot counter fare even when the
  /// sender is on another tab (owner 2026-11-23).
  static final StreamController<Map<String, dynamic>> onForegroundMessage =
      StreamController<Map<String, dynamic>>.broadcast();

  /// Backwards-compatible stream: only the `job_ref` (when the payload carries
  /// one). New code should prefer [onPayloadTap].
  static final Stream<String?> onNotificationTap =
      onPayloadTap.stream.map((m) => _str(m?['job_ref'])).asBroadcastStream();

  static String? _str(Object? v) => v == null ? null : '$v';

  static Future<void> init() async {
    if (_ready) return _initDone.future;
    _ready = true;
    try {
      if (kIsWeb || Platform.isWindows) return;

      await Firebase.initializeApp();
      final permission = await _fcm.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );
      _permissionGranted = _granted(permission.authorizationStatus);

      final androidImpl =
          _local.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await _prepareChannels(androidImpl);
      await _ensureLocalInitialized();

      FirebaseMessaging.onBackgroundMessage(_backgroundHandler);
      FirebaseMessaging.onMessage.listen(_onForegroundMessage);
      FirebaseMessaging.onMessageOpenedApp.listen((m) => onPayloadTap.add(
            Map<String, dynamic>.from(m.data).cast<String, dynamic>(),
          ));

      _enabled = true;
    } catch (_) {
      // Firebase not configured for this build — push stays off, app still runs.
    } finally {
      if (!_initDone.isCompleted) _initDone.complete();
    }
  }

  static const List<AndroidNotificationChannel> _channels = [
    // The alarm channel: max importance, sound + vibration, and a best-effort
    // Do Not Disturb bypass. A new order is the only alert allowed to wake a
    // rider's locked phone.
    AndroidNotificationChannel('dropoff_orders', 'DropOff — New orders',
        description: 'A new delivery is waiting — opens straight to your Task Queue.',
        importance: Importance.max, bypassDnd: true),
    AndroidNotificationChannel('dropoff_jobs', 'DropOff — Parcels & riders',
        description: 'Booking, dispatch, rider assignment and delivery updates.',
        importance: Importance.high),
    AndroidNotificationChannel('dropoff_chat', 'DropOff — Support tickets',
        description: 'Replies to your support tickets and DropOff updates.',
        importance: Importance.high),
    AndroidNotificationChannel('dropoff_payments', 'DropOff — Payments',
        description: 'Payment receipts and plan renewals.',
        importance: Importance.high),
    AndroidNotificationChannel('dropoff_marketing', 'DropOff — Offers',
        description: 'Occasional offers and updates from DropOff. You control these.',
        importance: Importance.defaultImportance),
    AndroidNotificationChannel('dropoff_alerts', 'DropOff — Account & security',
        description: 'New device, intrusion and account alerts.',
        importance: Importance.max),
  ];

  /// Channels must be created in the FOREGROUND (Android suppresses the first
  /// notification if a channel is first created from a background isolate).
  static Future<void> _prepareChannels(AndroidFlutterLocalNotificationsPlugin? android) async {
    if (android == null) return;
    for (final channel in _channels) {
      await android.createNotificationChannel(channel);
    }
    // Importance/sound/vibration are IMMUTABLE once Android has created a
    // channel. Older builds may have left `dropoff_orders` at a quiet level,
    // which is why riders heard nothing — rebuild only drifted channels.
    try {
      final existing = await android.getNotificationChannels();
      for (final channel in existing ?? const <AndroidNotificationChannel>[]) {
        AndroidNotificationChannel? wanted;
        for (final c in _channels) {
          if (c.id == channel.id) { wanted = c; break; }
        }
        if (wanted != null && channel.importance != wanted.importance) {
          await android.deleteNotificationChannel(channelId: channel.id);
          await android.createNotificationChannel(wanted);
        }
      }
    } catch (_) { /* best effort: the channels above already exist */ }
  }

  /// Dart isolates do not share memory: the background FCM handler has its own
  /// [FlutterLocalNotificationsPlugin] instance and must initialize it before
  /// calling `show`. This used to be foreground-only, so background order
  /// alerts were silently swallowed by a try/catch.
  static Future<void> _ensureLocalInitialized() async {
    if (_localReady) return;
    _localReady = true;
    await _local.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@drawable/ic_stat_dropoff'),
      ),
      onDidReceiveNotificationResponse: (details) {
        final payload = details.payload?.isNotEmpty == true
            ? _decodePayload(details.payload!)
            : <String, dynamic>{};
        // Accept / Decline tapped on an incoming-order notification: relay the
        // action so main.dart performs the API call with the signed-in session.
        final actionId = details.actionId;
        if (actionId != null && actionId.isNotEmpty) payload['order_action'] = actionId;
        onPayloadTap.add(payload.isEmpty ? null : payload);
      },
    );
    // Background isolates must also have channels; otherwise data-only order
    // alerts are dropped silently on Android 8+.
    final android = _local.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await _prepareChannels(android);
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
      await _ensureLocalInitialized();
      // An order is the one alert that must ring and wake the phone. Try to
      // start the native looping alarm from the background isolate too (it
      // works when the app was merely backgrounded); the FCM system
      // notification above covers the killed/force-stopped case.
      // Record EVERY push in the bell, including ones delivered while the app
      // was in the background/killed. Dedupe keeps the FCM + local pair to one
      // entry, and the main isolate reads this from SharedPreferences on open.
      final data = Map<String, dynamic>.from(message.data);
      final kind = _kindOf(data);
      await NotificationInbox.add({
        ...data,
        'kind': kind,
        'title': message.notification?.title ?? _str(data['title']) ?? _titleFor(data),
        'body': message.notification?.body ?? _str(data['body']) ?? '',
        'from_background': true,
      });
      final isOrder = kind.contains('assign') || kind == 'new_order' ||
          kind == 'trip_transferred' || kind == 'claim_available' || kind == 'sos';
      if (isOrder) {
        unawaited(OrderAlert.start(
          ref: _str(data['job_ref']) ?? '',
          title: message.notification?.title ?? _str(data['title']) ?? 'New delivery',
          body: message.notification?.body ?? _str(data['body']) ?? '',
          address: _str(data['pickup_address']) ?? '',
          eta: _str(data['eta_minutes']) ?? '',
          fee: _str(data['fee']) ?? '',
        ));
      }
      if (message.notification == null) {
        // Data-only fallback: this local notification carries the full-screen
        // intent that wakes the screen like an incoming call.
        await _show(data, message.notification?.title, message.notification?.body);
      }
    } catch (_) {}
  }

  static void _onForegroundMessage(RemoteMessage message) {
    final title = message.notification?.title ?? _str(message.data['title']);
    final body = message.notification?.body ?? _str(message.data['body']);
    final kind = _kindOf(message.data);
    final isOrderAlert = kind.contains('assign') || kind == 'new_order' ||
        kind == 'trip_transferred' || kind == 'claim_available' || kind == 'sos';
    // Foreground order alerts are handled entirely by the native OrderAlert
    // service (looping ring + notification with Accept/Decline actions). Posting
    // a second notification here would double up the curtain and the full-screen
    // intent — InDrive/Yango show ONE alert, not two.
    if (!isOrderAlert) {
      _show(message.data, title, body);
    } else {
      // Start the looping ring; the native service posts the alert notification.
      unawaited(OrderAlert.start(
        ref: _str(message.data['job_ref']) ?? '',
        title: title ?? 'New delivery',
        body: body ?? '',
        address: _str(message.data['pickup_address']) ?? _str(message.data['address']) ?? '',
        eta: _str(message.data['eta_minutes']) ?? '',
        fee: _str(message.data['fee']) ?? '',
      ));
    }
    onForegroundMessage.add({
      ...Map<String, dynamic>.from(message.data),
      if (title != null) 'title': title,
      if (body != null) 'body': body,
    });
  }

  /// Category of a notification; used to pick channel, icon accent and sound.
  static String _kindOf(Map<String, dynamic> data) => '${data['kind'] ?? ''}'.toLowerCase();

  static AndroidNotificationChannel _channelFor(String kind) {
    // A new order must RING like an incoming call — max importance channel,
    // full-screen intent and heads-up. Everything else keeps the quiet channels.
    if (kind.contains('assign') || kind == 'claim_available' || kind == 'new_order' || kind == 'trip_transferred') {
      return const AndroidNotificationChannel('dropoff_orders', 'DropOff — New orders',
          description: 'A new delivery is waiting — opens straight to your Task Queue.',
          importance: Importance.max, bypassDnd: true);
    }
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
    // Data-only order alerts carry the display text in `data` (the worker
    // cannot rely on `message.notification` for the alarm path).
    final rawTitle = title ?? _str(data['title']) ?? _titleFor(data);
    final kind = _kindOf(data);
    final channel = _channelFor(kind);
    final isOrderAlert = channel.id == 'dropoff_orders';
    // Premium heads-up copy (owner 2026-11-25): a flagship-grade call-screen
    // feel, never a raw system-looking string. Pickup details stay in the
    // expanded body so the rider can decide without unlocking.
    final t = isOrderAlert
        ? 'DropOff · New order ready'
        : (rawTitle.toLowerCase().startsWith('dropoff') ? rawTitle : 'DropOff · $rawTitle');
    final rawBody = body ?? _str(data['body']) ?? '';
    final b = isOrderAlert
        ? 'A pickup is waiting. Accept to claim it. $rawBody'.trim()
        : rawBody;
    final android = AndroidNotificationDetails(
      channel.id,
      channel.name,
      channelDescription: channel.description,
      importance: channel.importance,
      priority: isOrderAlert
          ? Priority.max
          : (channel.importance == Importance.defaultImportance ? Priority.defaultPriority : Priority.high),
      playSound: true,
      enableVibration: true,
      audioAttributesUsage: isOrderAlert ? AudioAttributesUsage.alarm : AudioAttributesUsage.notification,
      largeIcon: const DrawableResourceAndroidBitmap('@drawable/ic_notification_large'),
      icon: '@drawable/ic_stat_dropoff',
      ticker: t,
      category: (isOrderAlert || kind.contains('job') || kind.contains('assign') || kind.contains('status'))
          ? AndroidNotificationCategory.alarm
          : AndroidNotificationCategory.message,
      fullScreenIntent: isOrderAlert || kind.contains('job') || kind.contains('assign'),
      visibility: NotificationVisibility.public,
      autoCancel: true,
      // ANSWER FROM THE SHADE (owner 2026-11-24, inDrive parity): a rider must
      // not have to unlock, find the app and open the queue to answer an order.
      // Both actions relaunch DropOff, which performs the call with the real
      // session (the tap is replayed through `order_action`).
      actions: isOrderAlert
          ? const <AndroidNotificationAction>[
              AndroidNotificationAction('accept', 'Accept',
                  showsUserInterface: true, cancelNotification: true),
              AndroidNotificationAction('decline', 'Decline',
                  showsUserInterface: true, cancelNotification: true),
            ]
          : null,
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
        'plan_renewed' => 'Plan renewed — items unlocked',
        'subscription_active' => 'Plan activated',
        'marketing' => 'DropOff',
        'promo_issued' => 'Your promo reward is ready',
        'chat' => 'New message',
        'support_reply' => 'DropOff support replied',
        'security_alert' => 'DropOff security alert',
        'sos' => 'SOS - rider needs help',
        'push_test' => 'DropOff — push test',
        _ => 'DropOff',
      };

  /// Registers this device's FCM token under the signed-in user's phone. Call
  /// after every successful sign-in / link.
  static Future<void> register() async {
    // A cold-start sign-in can reach here before init() has finished the OS
    // permission/channel work. Wait for it instead of silently skipping the
    // token registration (the bug that left riders with no pushes at all).
    await _initDone.future;
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
      if (!_tokenRefreshBound) {
        _tokenRefreshBound = true;
        // ignore: deprecated_member_use
        _fcm.onTokenRefresh.listen((newToken) async {
          if (newToken.isEmpty || DropOffApi.token == null) return;
          await DropOffApi.post('/push/register', {'token': newToken, 'platform': defaultTargetPlatform.name});
        });
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
