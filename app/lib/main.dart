// ─────────────────────────────────────────────────────────────────────
// ignore_for_file: prefer_const_constructors, prefer_const_literals_to_create_immutables
// DROPOFF — ownership stamp (do not remove)
// :Godfrey Moses Kalambo:Carpso Solutions:0968551110.
// © 2026 Godfrey Moses Kalambo · Carpso Solutions · Lusaka, Zambia.
// All rights reserved — unauthorised copying, resale or rebranding of
// this source code is prohibited.
// ─────────────────────────────────────────────────────────────────────
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'ui/keys.dart';
import 'data/catalog.dart' as cat;
import 'screens/couriers_screen.dart';
import 'screens/track_screen.dart';
import 'screens/waybill_screen.dart';
import 'screens/account_screen.dart';
import 'screens/booking_screen.dart';
import 'screens/tickets_screen.dart';
import 'package:app_links/app_links.dart';
import 'screens/app_shell.dart';
import 'screens/in_app_navigator_screen.dart';
import 'screens/bookings_screen.dart';
import 'screens/lock_screen.dart';
import 'state/app_store.dart';
import 'data/dropoff_api.dart';
import 'data/analytics_service.dart';
import 'services/crash_reporting.dart';
import 'ui/app_theme.dart';
import 'data/push_service.dart';
import 'data/notification_inbox.dart';
import 'services/order_alert.dart';
import 'screens/incoming_order_screen.dart';
import 'ui/app_toast.dart';

import 'services/device_lock.dart';

import 'ui/app_spinner.dart';
import 'ui/in_app_browser.dart';


/// Root navigator so push-notification taps and deep links can open the right screen from anywhere.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// COLD START + BIOMETRIC GATE (owner audit 2026-11-21): a push or SMS link
// tapped before `initFuture` completes, or while the lock screen is showing,
// used to be dropped — or, worse, pushed ABOVE the lock screen and expose
// parcel/ticket content. All navigations now queue here and replay only once
// the store is loaded AND the app is unlocked.
bool _appReady = false;
bool _appUnlocked = false;
AppStore? _rootStore;
bool _isLocked() => _rootStore != null &&
    _rootStore!.ready &&
    _rootStore!.biometricEnabled &&
    _rootStore!.linked &&
    !_appUnlocked;
final List<VoidCallback> _deferredNavigations = <VoidCallback>[];
int _flushTries = 0;

void _flushDeferred() {
  if (!_appReady || _isLocked()) return;
  final ctx = navigatorKey.currentContext;
  if (ctx == null || !ctx.mounted) {
    if (_flushTries++ < 60) Timer(const Duration(milliseconds: 250), _flushDeferred);
    return;
  }
  _flushTries = 0;
  final pending = List<VoidCallback>.from(_deferredNavigations);
  _deferredNavigations.clear();
  for (final action in pending) {
    action();
  }
}

void _runWhenReady(VoidCallback action) {
  final ctx = navigatorKey.currentContext;
  if (_appReady && !_isLocked() && ctx != null && ctx.mounted) {
    action();
    return;
  }
  _deferredNavigations.add(action);
}

/// Handle `dropoff.carpsosolutions.store/...` deep links coming from the OS (URI stream from app_links
/// or `getInitialLink()` on a cold start). Known paths are routed; unknown are shell.
void _handleDeepLink(AppStore store, Uri uri) =>
    _runWhenReady(() => _performDeepLink(store, uri));

void _performDeepLink(AppStore store, Uri uri) {
  final ctx = navigatorKey.currentContext;
  if (ctx == null || !ctx.mounted) return;
  if (uri.scheme == 'geo') {
    // Another app asked Android to navigate here — answer with OUR map.
    final bits = uri.path.split(',');
    final lat = double.tryParse(bits.isNotEmpty ? bits[0] : '');
    final lng = double.tryParse(bits.length > 1 ? bits[1] : '');
    if (lat != null && lng != null) {
      Navigator.of(ctx).push(MaterialPageRoute<void>(builder: (_) => InAppNavigatorScreen(
        destLat: lat, destLng: lng, label: uri.queryParameters['q'] ?? 'Destination',
      )));
    }
    return;
  }
  // dropoff://track/TOKEN has "track" as the HOST, not a path segment.
  if (uri.scheme == 'dropoff') {
    final token = uri.host == 'track'
        ? (uri.pathSegments.isNotEmpty ? uri.pathSegments.first : '')
        : (uri.queryParameters['token'] ?? uri.pathSegments.firstOrNull ?? '');
    if (token.isNotEmpty) {
      final ctx = navigatorKey.currentContext;
      if (ctx != null && ctx.mounted) {
        Navigator.of(ctx).push(MaterialPageRoute<void>(builder: (_) => TrackScreen(initialToken: token)));
      }
      return;
    }
  }
  final seg = uri.pathSegments;
  AnalyticsService.instance.track(feature: 'deeplink', action: 'open', context: uri.path, meta: {'query': uri.queryParameters});
  if (seg.isEmpty) return;
  // /track/:token and  /t/:token (short)
  if (seg.length >= 2 && (seg[0] == 'track' || seg[0] == 't')) {
    Navigator.of(ctx).push(MaterialPageRoute<void>(builder: (_) => TrackScreen(initialToken: seg[1])));
    return;
  }
  // /bookings/:ref[/rate]
  if (seg.length >= 2 && seg[0] == 'bookings') {
    final ref = seg[1];
    final match = store.bookings.where((b) => b.serverRef == ref).firstOrNull;
    if (match != null) {
      Navigator.of(ctx).push(MaterialPageRoute<void>(builder: (_) => BookingDetailScreen(bookingId: match.id)));
      return;
    }
    Navigator.of(ctx).push(MaterialPageRoute<void>(builder: (_) => const BookingsScreen()));
    return;
  }
  // /rate/:ref
  if (seg.length >= 2 && seg[0] == 'rate') {
    final ref = seg[1];
    final match = store.bookings.where((b) => b.serverRef == ref).firstOrNull;
    if (match != null) {
      Navigator.of(ctx).push(MaterialPageRoute<void>(builder: (_) => BookingDetailScreen(bookingId: match.id)));
      return;
    }
    Navigator.of(ctx).push(MaterialPageRoute<void>(builder: (_) => const BookingsScreen()));
    return;
  }
  // /waybill/:ref
  if (seg.length >= 2 && seg[0] == 'waybill') {
    final ref = seg[1];
    final match = store.bookings.where((b) => b.serverRef == ref).firstOrNull;
    if (match != null) {
      Navigator.of(ctx).push(MaterialPageRoute<void>(builder: (_) => WaybillScreen(bookingId: match.id)));
      return;
    }
    Navigator.of(ctx).push(MaterialPageRoute<void>(builder: (_) => const BookingsScreen()));
    return;
  }
  // /r/:code — a REFERRAL claim, never a promo code.
  if (seg.length >= 2 && seg[0] == 'r') {
    final code = seg[1].trim().toUpperCase();
    AnalyticsService.instance.track(feature: 'deeplink', action: 'open_referral', context: code);
    AccountScreen.prefillReferral = code;
    if (store.linked) {
      unawaited(DropOffApi.claimReferral(code).catchError((_) => const ApiResponse()));
    }
    Navigator.of(ctx).push(MaterialPageRoute<void>(builder: (_) => const AccountScreen()));
    return;
  }
  // /promo/:ref and /promo?code=... — real promo prefill at booking.
  if (seg.length >= 2 && seg[0] == 'promo') {
    final code = seg[1].trim().toUpperCase();
    AnalyticsService.instance.track(feature: 'deeplink', action: 'open_referral_or_promo', context: code);
    BookingScreen.prefill = {'promo_code': code};
    Navigator.of(ctx).push(MaterialPageRoute<void>(builder: (_) => const BookingScreen()));
    return;
  }
  if (seg.length == 1 && seg[0] == 'promo') {
    final code = (uri.queryParameters['code'] ?? '').trim().toUpperCase();
    if (code.isNotEmpty) {
      AnalyticsService.instance.track(feature: 'deeplink', action: 'open_promo', context: code);
      BookingScreen.prefill = {'promo_code': code};
      Navigator.of(ctx).push(MaterialPageRoute<void>(builder: (_) => const BookingScreen()));
      return;
    }
  }
  // /plans?focus=gold
  if (seg.isNotEmpty && seg[0] == 'plans') {
    Navigator.of(ctx).push(MaterialPageRoute<void>(builder: (_) => const AccountScreen(focusPlans: true)));
    return;
  }
  // /couriers/:id
  if (seg.length >= 2 && seg[0] == 'couriers') {
    final courier = cat.courierById(seg[1]);
    Navigator.of(ctx).push(MaterialPageRoute<void>(builder: (_) => CourierDetailScreen(courier: courier)));
    return;
  }
  // /auth/link?k=...&t=... — MUST be consumed by the Worker's verify/reset
  // pages. Android App Links claim /auth, so opening Account here killed the
  // single-use token and left email unverified / password unchanged.
  if (seg.length >= 2 && seg[0] == 'auth' && seg[1] == 'link') {
    unawaited(openInApp(uri.toString()));
    return;
  }
  // Fallback: shell
  Navigator.of(ctx).push(MaterialPageRoute<void>(builder: (_) => const AppShell()));
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Never show Flutter's red debug screen to a user. A bad server row or a
  // render error becomes a calm, branded recovery screen (owner 2026-11-23).
  ErrorWidget.builder = (details) => Directionality(
        textDirection: TextDirection.ltr,
        child: Material(
          color: AppColors.canvas,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.error_outline, size: 44, color: AppColors.amber),
                const SizedBox(height: 14),
                const Text('Something went wrong', textAlign: TextAlign.center,
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 19, color: AppColors.ink)),
                const SizedBox(height: 8),
                const Text('Close and reopen DropOff — your bookings and data are safe.',
                    textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted, fontSize: 13)),
              ]),
            ),
          ),
        ),
      );
  // Block OS screenshots / recordings of OTPs, waybills, customer addresses
  // and finance data. All sharing exports a real file via the OS share sheet,
  // which is separate system UI and keeps working (owner 2026-11-23).
  // Screen protection is intentionally not blanket-enabled so users can share
  // receipts/support screenshots. Use ScreenPrivacy.enableProtection() on
  // sensitive flows only if needed.
  // ANDROID 15+ EDGE-TO-EDGE (Play advisory on release 84): use the modern
  // inset-based mode instead of the deprecated setSystemUiVisibility flags.
  // Flutter then reports status/nav bar insets through MediaQuery, and every
  // screen's SafeArea / AppBar / NavigationBar applies them.
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    systemNavigationBarIconBrightness: Brightness.dark,
  ));
  CrashReporting.init();
  final store = AppStore();
  _rootStore = store;
  // Initialize analytics outbox (offline-first) on a background future so the
  // splash screen shows immediately; events are flushed with the booking
  // outbox and on a timer.
  final initFuture = Future.wait([store.initialize(), AnalyticsService.instance.init()]);
  // Push setup runs in parallel (the OS permission dialog must not block the
  // splash), but PushService.register() awaits its completion before sending
  // the token to the server, so a cold-start rider is never left unregistered.
  PushService.init();
  // inDrive-style order alerts: channel wiring + replay of an Accept/Decline
  // tap that relaunched the app while it was closed (owner 2026-11-24).
  OrderAlert.init();
  // Notification center (owner 2026-11-25): foreground pushes land here instead
  // of an auto-popping banner; reachable from the bell icon.
  NotificationInbox.init();
  void handleTap(Map<String, dynamic>? data) {
    // Cold start / lock screen: queue the tap instead of dropping it or
    // navigating above the biometric gate.
    _runWhenReady(() => _performTap(store, data));
  }
  PushService.onPayloadTap.stream.listen(handleTap);
  final appLinks = AppLinks();
  appLinks.uriLinkStream.listen((uri) => _handleDeepLink(store, uri));
  appLinks.getInitialLink().then((uri) {
    if (uri != null) _handleDeepLink(store, uri);
  });
  runApp(DropOffApp(store: store, navigatorKey: navigatorKey, initFuture: initFuture));
  // Replay any deep link / push that arrived before the store finished loading.
  unawaited(initFuture.whenComplete(() {
    _appReady = true;
    _flushDeferred();
  }));
}

/// Resolve a notification tap to a screen. Runs only after the store is ready
/// and the biometric lock is cleared (see [_runWhenReady]).
void _performTap(AppStore store, Map<String, dynamic>? data) {
  final ctx = navigatorKey.currentContext;
  if (ctx == null || !ctx.mounted) return;
  // Accept / Decline tapped on an incoming-order notification (owner
  // 2026-11-24). Answered with the signed-in session, then the queue refreshes.
  final orderAction = '${data?['order_action'] ?? ''}'.toLowerCase();
  if (orderAction.isNotEmpty) {
    _performOrderAction(store, '${data?['job_ref'] ?? data?['ref'] ?? ''}', orderAction);
    return;
  }
  final jobRef = data?['job_ref']?.toString();
  final kind = '${data?['kind'] ?? ''}'.toLowerCase();
  AnalyticsService.instance.track(feature: 'push', action: 'tap', context: kind.isEmpty ? 'unknown' : kind);

  Widget? routeTo;
  if (kind == 'chat' || kind.startsWith('chat')) {
    routeTo = const TicketsScreen();
  } else if (kind == 'support_reply' || kind == 'support' || kind == 'ticket') {
    routeTo = const TicketsScreen();
  } else if (kind == 'counter_fare_due' || kind == 'counter_fare_paid') {
    // ALWAYS land on Bookings: that screen runs the "courier receipt locked /
    // Pay now" prompt on entry. BookingDetail has no such prompt, which is why
    // a rider filing the fare produced no visible ask (owner 2026-11-23).
    routeTo = const BookingsScreen();
  } else if (kind == 'job_assigned' || kind == 'rider_assigned' || kind == 'trip_transferred' || kind == 'deposit_paid' || kind == 'pickup_reminder' || kind == 'job_delivered' || kind == 'payment_received') {
    // RIDER ROUTING (owner audit 2026-11-21): these pushes are for the rider's
    // job — a sender Bookings screen is useless to them. AppShell index 0 IS
    // the rider's Task Queue, so opening the shell lands on the right screen.
    if (store.isRider) {
      routeTo = const AppShell();
    } else if (jobRef != null && jobRef.isNotEmpty) {
      final match = store.bookings.where((b) => b.serverRef == jobRef).firstOrNull;
      routeTo = match != null ? BookingDetailScreen(bookingId: match.id) : const BookingsScreen();
    } else {
      routeTo = const BookingsScreen();
    }
  } else if (kind == 'plan_renewed' || kind == 'subscription_active' || kind == 'promo_issued' || kind == 'marketing') {
    routeTo = const AccountScreen(focusPlans: true);
  } else if (kind.contains('security') || kind.contains('fraud') || kind.contains('alert')) {
    routeTo = const AccountScreen();
  }

  routeTo ??= store.isRider ? const AppShell() : const BookingsScreen();
  Navigator.of(ctx).push(MaterialPageRoute<void>(builder: (_) => routeTo!));
}

/// Details of the last order push per ref, so Accept/Decline tapped straight
/// from the notification still shows the real pickup address and fee.
final Map<String, Map<String, dynamic>> _orderDetails = {};

/// Answers an incoming order (accept / decline / open). Runs only after the
/// store is ready and the biometric lock is cleared, so the API call always
/// carries the signed-in rider's session.
void _performOrderAction(AppStore store, String rawRef, String action) {
  if (!store.isRider) return;
  final ref = rawRef.trim();
  final ctx = navigatorKey.currentContext;
  if (ref.isEmpty) {
    if (ctx != null && ctx.mounted) {
      Navigator.of(ctx).push(MaterialPageRoute<void>(builder: (_) => const AppShell()));
    }
    return;
  }
  if (action == 'open') {
    unawaited(OrderAlert.stop());
    if (ctx != null && ctx.mounted) {
      Navigator.of(ctx).push(MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => IncomingOrderScreen(jobRef: ref, detail: _orderDetails[ref]),
      ));
    }
    return;
  }
  unawaited(() async {
    final res = action == 'decline'
        ? await DropOffApi.declineJob(ref)
        : await DropOffApi.acceptJob(ref);
    await store.syncJobsFromServer();
    final c = navigatorKey.currentContext;
    if (c == null || !c.mounted) return;
    AppToast.show(c, res.ok
        ? (action == 'decline'
            ? 'Declined $ref — it went back to the order board.'
            : 'Order $ref accepted — it is in your Task Queue.')
        : 'Could not answer $ref — open your Task Queue.');
  }());
}

class AppScope extends InheritedNotifier<AppStore> {
  const AppScope({super.key, required AppStore store, required super.child}) : super(notifier: store);

  static AppStore of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;
}

class DropOffApp extends StatelessWidget {
  final AppStore store;
  final GlobalKey<NavigatorState> navigatorKey;
  final Future<void> initFuture;
  const DropOffApp({super.key, required this.store, required this.navigatorKey, required this.initFuture});

  @override
  Widget build(BuildContext context) => AppScope(
        store: store,
        child: AnimatedBuilder(
          animation: store,
          builder: (context, _) => MaterialApp(
            navigatorKey: navigatorKey,
            scaffoldMessengerKey: scaffoldMessengerKey,
            title: 'DropOff',
            debugShowCheckedModeBanner: false,
            theme: buildAppTheme(),
            // Universal text-scale clamp: wrap EVERY screen so a large system
            // font can never crush a row/card into a vertical letter-per-line
            // ribbon (Business "No plan yet", Items in flight, stats, …).
            // Never shrink below the system size; never grow past 1.30x.
            builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    textScaler: MediaQuery.textScalerOf(context).clamp(
                      minScaleFactor: 1.0,
                      maxScaleFactor: 1.30,
                    ),
                  ),
                  child: child!,
                ),
            home: _SplashScreen(store: store, initFuture: initFuture),
          ),
        ),
      );
}

/// Splash screen shown while the store initializes on cold start. Once
//! initialized, the app shell is shown and push registration completes.
class _SplashScreen extends StatefulWidget {
  final AppStore store;
  final Future<void> initFuture;
  const _SplashScreen({required this.store, required this.initFuture});

  @override
  State<_SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<_SplashScreen> {
  bool _unlocked = false;
  bool _authing = false;
  String? _lockError;
  bool _reauth = false;
  bool _reauthBusy = false;
  String? _reauthError;
  final _emailCtor = TextEditingController();
  final _passwordCtor = TextEditingController();

  StreamSubscription<Map<String, dynamic>>? _pushSub;
  StreamSubscription<Map<String, dynamic>>? _orderActionSub;
  String? _incomingOrderRef;
  OverlayEntry? _pushBannerEntry;
  Timer? _pushBannerTimer;

  @override
  void initState() {
    super.initState();
    _emailCtor.text = widget.store.email ?? '';
    widget.initFuture.whenComplete(() {
      if (!mounted) return;
      if (widget.store.linked && DropOffApi.token != null) {
        unawaited(PushService.register());
        // Cold start with a fare filed while the app was closed: surface the
        // prompt instead of waiting for the sender to open Bookings herself.
        unawaited(DropOffApi.counterFareStatus().then((data) {
          if (data?['due'] == true) _showCounterFarePrompt();
        }));
      }
      setState(() {});
    });
    // Foreground push: show an in-app heads-up banner and handle urgent flows.
    _pushSub = PushService.onForegroundMessage.stream.listen((data) {
      final kind = '${data['kind'] ?? ''}';
      final isOrder = kind.contains('assign') || kind == 'new_order' ||
          kind == 'trip_transferred' || kind == 'claim_available' || kind == 'sos';
      if (isOrder) {
        final ref = '${data['job_ref'] ?? ''}';
        if (ref.isNotEmpty) _orderDetails[ref] = Map<String, dynamic>.from(data);
        // inDrive parity (owner 2026-11-24): a rider sees the full-screen
        // Accept / Decline card, not a small banner.
        if (widget.store.isRider) {
          _openIncomingOrder(data);
          unawaited(NotificationInbox.add(data));
          return;
        }
      }
      if (kind == 'counter_fare_due') _showCounterFarePrompt();
      unawaited(NotificationInbox.add(data));
    });
    // Accept / Decline answered from the ring service or a notification action.
    _orderActionSub = OrderAlert.onAction.listen((action) {
      _runWhenReady(() => _performOrderAction(
            widget.store,
            '${action['ref'] ?? ''}',
            '${action['action'] ?? ''}'.toLowerCase(),
          ));
    });
    final pendingAction = OrderAlert.takePending();
    if (pendingAction != null) {
      unawaited(widget.initFuture.whenComplete(() {
        _runWhenReady(() => _performOrderAction(
              widget.store,
              '${pendingAction['ref'] ?? ''}',
              '${pendingAction['action'] ?? ''}'.toLowerCase(),
            ));
      }));
    }
  }

  /// Full-screen incoming-order card + looping alarm for a rider.
  void _openIncomingOrder(Map<String, dynamic> data) {
    final ref = '${data['job_ref'] ?? ''}';
    if (ref.isEmpty || _incomingOrderRef == ref) return;
    _incomingOrderRef = ref;
    unawaited(OrderAlert.start(
      ref: ref,
      title: (data['title'] ?? 'New delivery').toString(),
      body: (data['body'] ?? '').toString(),
      address: '${data['pickup_address'] ?? data['address'] ?? ''}',
      eta: '${data['eta_minutes'] ?? ''}',
      fee: '${data['fee'] ?? ''}',
    ));
    _runWhenReady(() {
      if (!mounted) return;
      Navigator.of(context).push(MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => IncomingOrderScreen(jobRef: ref, detail: data),
      )).whenComplete(() => _incomingOrderRef = null);
    });
  }

  DateTime? _lastCounterFarePromptAt;
  void _showCounterFarePrompt() {
    final now = DateTime.now();
    if (_lastCounterFarePromptAt != null && now.difference(_lastCounterFarePromptAt!) < const Duration(minutes: 2)) return;
    _lastCounterFarePromptAt = now;
    _runWhenReady(() async {
      final due = await DropOffApi.counterFareStatus();
      if (due?['due'] == true) {
        if (mounted) _performTap(widget.store, {'kind': 'counter_fare_due'});
      } else {
        await widget.store.syncJobsFromServer();
      }
    });
  }

  void _showForegroundPushBanner(Map<String, dynamic> data) {
    final overlay = navigatorKey.currentState?.overlay;
    if (overlay == null) return;
    _pushBannerTimer?.cancel();
    _pushBannerEntry?.remove();
    _pushBannerEntry = null;

    final title = (data['title'] ?? 'DropOff').toString();
    final body = (data['body'] ?? '').toString();
    final kind = '${data['kind'] ?? ''}'.toLowerCase();
    final isOrder = kind.contains('assign') || kind.contains('new_order') || kind == 'trip_transferred' || kind == 'claim_available';

    final entry = OverlayEntry(builder: (ctx) {
      final top = MediaQuery.of(ctx).padding.top + 8;
      return Positioned(
        top: top,
        left: 12,
        right: 12,
        child: Material(
          color: Colors.transparent,
          child: Dismissible(
            key: ValueKey('push-${data['kind'] ?? 'k'}-${data['job_ref'] ?? ''}-${data['message_id'] ?? DateTime.now().millisecondsSinceEpoch}'),
            direction: DismissDirection.up,
            onDismissed: (_) {
              _pushBannerTimer?.cancel();
              _pushBannerEntry?.remove();
              _pushBannerEntry = null;
            },
            child: GestureDetector(
              onTap: () {
                _pushBannerTimer?.cancel();
                _pushBannerEntry?.remove();
                _pushBannerEntry = null;
                _runWhenReady(() => _performTap(widget.store, data));
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: isOrder ? const Color(0xFF0F2A1D) : const Color(0xFF14213D),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 18, offset: Offset(0, 8))],
                  border: Border.all(color: isOrder ? const Color(0xFFF2C94C) : Colors.white24),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: isOrder ? const Color(0xFFF2C94C) : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(isOrder ? Icons.delivery_dining_rounded : Icons.notifications_active_rounded,
                          color: const Color(0xFF0F2A1D), size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13.5)),
                          if (body.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(body, maxLines: 2, overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Color(0xE6FFFFFF), fontSize: 12.5, height: 1.3)),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.chevron_right_rounded, color: Colors.white70),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    });

    _pushBannerEntry = entry;
    overlay.insert(entry);
    _pushBannerTimer = Timer(const Duration(seconds: 5), () {
      _pushBannerEntry?.remove();
      _pushBannerEntry = null;
    });
  }

  @override
  void dispose() {
    _pushBannerTimer?.cancel();
    _pushBannerEntry?.remove();
    _pushSub?.cancel();
    _orderActionSub?.cancel();
    _emailCtor.dispose();
    _passwordCtor.dispose();
    super.dispose();
  }

  Future<void> _tryUnlock() async {
    if (_authing) return;
    setState(() { _authing = true; _lockError = null; });
    final ok = await DeviceLock.authenticate('Unlock DropOff');
    if (!mounted) return;
    setState(() { _authing = false; if (ok) { _unlocked = true; _appUnlocked = true; } else { _lockError = 'Not recognized — try again.'; } });
    if (ok) _flushDeferred();
  }

  /// Password door: verify password inline and unlock — the session is KEPT.
  Future<void> _usePassword() async {
    if (_reauth && _emailCtor.text.trim().isNotEmpty && _passwordCtor.text.length >= 8) {
      setState(() { _reauthBusy = true; _reauthError = null; });
      final ok = await widget.store.loginEmail(_emailCtor.text.trim(), _passwordCtor.text, remember: true);
      if (!mounted) return;
      if (ok) {
        _unlocked = true;
        _appUnlocked = true;
      } else {
        _reauthError = widget.store.lastAuthError ?? 'Wrong email or password — try again.';
      }
      setState(() { _reauthBusy = false; });
      if (ok) _flushDeferred();
      return;
    }
    setState(() {
      _reauth = true;
      _reauthError = null;
      _emailCtor.text = widget.store.email ?? '';
    });
  }

  /// Explicitly sign out — the only path that wipes the session.
  Future<void> _signOutInstead() async {
    await widget.store.unlink();
    if (!mounted) return;
    setState(() => _unlocked = true);
    _appUnlocked = true;
    _flushDeferred();
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    if (store.ready) {
      if (store.biometricEnabled && store.linked && !_unlocked) {
        if (_reauth) {
          return _PasswordReauthGate(
            emailCtor: _emailCtor,
            passwordCtor: _passwordCtor,
            busy: _reauthBusy,
            error: _reauthError,
            onSubmit: _usePassword,
            onBack: () => setState(() => _reauth = false),
            onSignOut: _signOutInstead,
          );
        }
        return BiometricLockScreen(onUnlock: _tryUnlock, onUsePassword: _usePassword, busy: _authing, error: _lockError);
      }
      return const AppShell();
    }
    return Scaffold(
      backgroundColor: AppColors.forest,
      body: Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          SizedBox(height: 8),
          AppLogoSpinner(size: 34, color: AppColors.amber),
          SizedBox(height: 14),
          Text('DropOff', style: TextStyle(color: Colors.white, fontSize: 42, fontWeight: FontWeight.w900, letterSpacing: -1.2)),
          const SizedBox(height: 8),
          Text('WE CARRY IT TO THE COURIER', style: TextStyle(color: AppColors.amber, fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 2.0)),
        ]),
      ),
    );
  }
}


/// Inline password re-auth — unlock the session with email + password.
/// NEVER unlinks on a wrong password; the session only dies via explicit sign-out.
class _PasswordReauthGate extends StatelessWidget {
  final TextEditingController emailCtor;
  final TextEditingController passwordCtor;
  final bool busy;
  final String? error;
  final VoidCallback onSubmit;
  final VoidCallback onBack;
  final VoidCallback onSignOut;
  const _PasswordReauthGate({
    required this.emailCtor,
    required this.passwordCtor,
    required this.busy,
    required this.error,
    required this.onSubmit,
    required this.onBack,
    required this.onSignOut,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.forest,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const SizedBox(height: 8),
              const Icon(Icons.lock_outline_rounded, size: 44, color: AppColors.amber),
              const SizedBox(height: 12),
              const Text('Unlock with password', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              const Text('Your session stays on this phone — proving it is you takes one email and password.', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFFC9D9D2), height: 1.4, fontSize: 13)),
              const SizedBox(height: 22),
              TextField(
                controller: emailCtor,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Email', filled: true, fillColor: Colors.white, border: OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: passwordCtor,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Password', filled: true, fillColor: Colors.white, border: OutlineInputBorder()),
                onSubmitted: (_) => onSubmit(),
              ),
              if (error != null) ...[
                const SizedBox(height: 10),
                Text(error!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.amber, fontSize: 12.5, fontWeight: FontWeight.w700, height: 1.35)),
              ],
              const SizedBox(height: 16),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: AppColors.amber, foregroundColor: AppColors.forest, minimumSize: const Size.fromHeight(52)),
                onPressed: busy ? null : onSubmit,
                icon: busy
                    ? const AppLogoSpinner(size: 18, color: AppColors.forest)
                    : const Icon(Icons.login_rounded),
                label: Text(busy ? 'Checking…' : 'Unlock', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
              ),
              const SizedBox(height: 8),
              TextButton(onPressed: onBack, child: const Text('Try biometrics instead', style: TextStyle(color: Color(0xFFC9D9D2)))),
              TextButton(onPressed: onSignOut, child: const Text('Not you? Sign out instead', style: TextStyle(color: Colors.white70, fontSize: 12))),
            ]),
          ),
        ),
      ),
    );
  }
}
