import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'l10n/app_localizations.dart';
import 'data/catalog.dart' as cat;
import 'screens/couriers_screen.dart';
import 'screens/track_screen.dart';
import 'screens/waybill_screen.dart';
import 'screens/account_screen.dart';
import 'screens/booking_screen.dart';
import 'screens/chat_screen.dart';
import 'package:app_links/app_links.dart';
import 'screens/app_shell.dart';
import 'screens/bookings_screen.dart';
import 'screens/lock_screen.dart';
import 'state/app_store.dart';
import 'data/dropoff_api.dart';
import 'data/analytics_service.dart';
import 'ui/app_theme.dart';
import 'data/push_service.dart';
import 'services/device_lock.dart';
import 'widgets/common.dart';

/// Root navigator so push-notification taps and deep links can open the right screen from anywhere.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// Handle `dropoff.app/...` deep links coming from the OS (URI stream from app_links
/// or `getInitialLink()` on a cold start). Known paths are routed; unknown are shell.
void _handleDeepLink(AppStore store, Uri uri) {
  final ctx = navigatorKey.currentContext;
  if (ctx == null) return;
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
  // /promo/:ref, /promo?code=..., /r/:code — referral prefill/claim
  if (seg.length >= 2 && (seg[0] == 'promo' || seg[0] == 'r')) {
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
  // /auth/link?k=...&t=... — open account screen
  if (seg.length >= 2 && seg[0] == 'auth' && seg[1] == 'link') {
    Navigator.of(ctx).push(MaterialPageRoute<void>(builder: (_) => const AccountScreen()));
    return;
  }
  // Fallback: shell
  Navigator.of(ctx).push(MaterialPageRoute<void>(builder: (_) => const AppShell()));
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = AppStore();
  // Initialize analytics outbox (offline-first) on a background future so the
  // splash screen shows immediately; events are flushed with the booking
  // outbox and on a timer.
  final initFuture = Future.wait([store.initialize(), AnalyticsService.instance.init()]);
  PushService.init();
  PushService.onPayloadTap.stream.listen((data) {
    final ctx = navigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) return;
    final jobRef = data?['job_ref']?.toString();
    final kind = '${data?['kind'] ?? ''}'.toLowerCase();
    AnalyticsService.instance.track(feature: 'push', action: 'tap', context: kind.isEmpty ? 'unknown' : kind);

    Widget? routeTo;
    if (kind == 'chat' || kind.startsWith('chat')) {
      routeTo = jobRef != null && jobRef.isNotEmpty ? ChatScreen.job(jobRef) : const ChatScreen.supportThread();
    } else if (kind == 'support_reply' || kind == 'support') {
      routeTo = const ChatScreen.supportThread();
    } else if (kind == 'job_assigned' || kind == 'rider_assigned' || kind == 'deposit_paid' || kind == 'pickup_reminder' || kind == 'job_delivered' || kind == 'payment_received') {
      if (jobRef != null && jobRef.isNotEmpty) {
        final match = store.bookings.where((b) => b.serverRef == jobRef).firstOrNull;
        routeTo = match != null
            ? BookingDetailScreen(bookingId: match.id)
            : const BookingsScreen();
      } else {
        routeTo = const BookingsScreen();
      }
    } else if (kind == 'plan_renewed' || kind == 'subscription_active' || kind == 'promo_issued' || kind == 'marketing') {
      routeTo = const AccountScreen(focusPlans: true);
    } else if (kind.contains('security') || kind.contains('fraud') || kind.contains('alert')) {
      routeTo = const AccountScreen();
    }

    if (routeTo != null) {
      Navigator.of(ctx).push(MaterialPageRoute<void>(builder: (_) => routeTo!));
      return;
    }
    Navigator.of(ctx).push(MaterialPageRoute<void>(builder: (_) => const BookingsScreen()));
  });
  final appLinks = AppLinks();
  appLinks.uriLinkStream.listen((uri) => _handleDeepLink(store, uri));
  appLinks.getInitialLink().then((uri) {
    if (uri != null) _handleDeepLink(store, uri);
  });
  runApp(DropOffApp(store: store, navigatorKey: navigatorKey, initFuture: initFuture));
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
            onGenerateTitle: (ctx) => AppLocalizations.of(ctx).appTitle,
            debugShowCheckedModeBanner: false,
            theme: buildAppTheme(),
            locale: store.locale,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            // Universal text-scale clamp: wrap EVERY screen so a large system
            // font can never crush a row/card into a vertical letter-per-line
            // ribbon (Business "No plan yet", Parcels in flight, stats, …).
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

  @override
  void initState() {
    super.initState();
    widget.initFuture.whenComplete(() {
      if (!mounted) return;
      if (widget.store.linked && DropOffApi.token != null) {
        unawaited(PushService.register());
      }
      setState(() {});
    });
  }

  Future<void> _tryUnlock() async {
    if (_authing) return;
    setState(() { _authing = true; _lockError = null; });
    final ok = await DeviceLock.authenticate('Unlock DropOff');
    if (!mounted) return;
    setState(() { _authing = false; if (ok) { _unlocked = true; } else { _lockError = 'Not recognized — try again.'; } });
  }

  /// Password door: drop the session and fall through to the sign-in screen.
  Future<void> _usePassword() async {
    await widget.store.unlink();
    if (!mounted) return;
    // Unlink wipes credentials; _unlocked stays false so we still show the
    // gate momentarily — but linked==false now, so we drop straight into the
    // app with the sign-in door visible.
    setState(() => _unlocked = true);
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    if (store.ready) {
      if (store.biometricEnabled && store.linked && !_unlocked) {
        return BiometricLockScreen(onUnlock: _tryUnlock, onUsePassword: _usePassword, busy: _authing, error: _lockError);
      }
      return const AppShell();
    }
    return const Scaffold(
      backgroundColor: AppColors.forest,
      body: Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          DropOffLogo(size: 46),
          SizedBox(height: 16),
          SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3, color: AppColors.amber)),
          SizedBox(height: 12),
          Text('DropOff', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: -0.7)),
        ]),
      ),
    );
  }
}
