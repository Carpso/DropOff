// ─────────────────────────────────────────────────────────────────────
// DROPOFF — ownership stamp (do not remove)
// :Godfrey Moses Kalambo:Carpso Solutions:0968551110.
// © 2026 Godfrey Moses Kalambo · Carpso Solutions · Lusaka, Zambia.
// All rights reserved — unauthorised copying, resale or rebranding of
// this source code is prohibited.
// ─────────────────────────────────────────────────────────────────────
import 'dart:async';

import 'package:flutter/material.dart';

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
import 'services/device_lock.dart';
import 'widgets/common.dart';
import 'ui/app_spinner.dart';

/// Root navigator so push-notification taps and deep links can open the right screen from anywhere.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// Handle `dropoff.app/...` deep links coming from the OS (URI stream from app_links
/// or `getInitialLink()` on a cold start). Known paths are routed; unknown are shell.
void _handleDeepLink(AppStore store, Uri uri) {
  final ctx = navigatorKey.currentContext;
  if (ctx == null) return;
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
  CrashReporting.init();
  final store = AppStore();
  // Initialize analytics outbox (offline-first) on a background future so the
  // splash screen shows immediately; events are flushed with the booking
  // outbox and on a timer.
  final initFuture = Future.wait([store.initialize(), AnalyticsService.instance.init()]);
  PushService.init();
  void handleTap(Map<String, dynamic>? data) {
    // If the navigator isn't mounted yet (cold start), retry every 300 ms —
    // a tapped notification from a killed app must never be silently dropped.
    final ctx = navigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) {
      var tries = 0;
      Timer.periodic(const Duration(milliseconds: 300), (t) {
        tries++;
        final c = navigatorKey.currentContext;
        if (c != null && c.mounted) {
          t.cancel();
          handleTap(data);
        } else if (tries > 25) {
          t.cancel();
        }
      });
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
  }
  PushService.onPayloadTap.stream.listen(handleTap);
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
            scaffoldMessengerKey: scaffoldMessengerKey,
            title: 'DropOff',
            debugShowCheckedModeBanner: false,
            theme: buildAppTheme(),
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
  bool _reauth = false;
  bool _reauthBusy = false;
  String? _reauthError;
  final _emailCtor = TextEditingController();
  final _passwordCtor = TextEditingController();

  @override
  void initState() {
    super.initState();
    _emailCtor.text = widget.store.email ?? '';
    widget.initFuture.whenComplete(() {
      if (!mounted) return;
      if (widget.store.linked && DropOffApi.token != null) {
        unawaited(PushService.register());
      }
      setState(() {});
    });
  }

  @override
  void dispose() {
    _emailCtor.dispose();
    _passwordCtor.dispose();
    super.dispose();
  }

  Future<void> _tryUnlock() async {
    if (_authing) return;
    setState(() { _authing = true; _lockError = null; });
    final ok = await DeviceLock.authenticate('Unlock DropOff');
    if (!mounted) return;
    setState(() { _authing = false; if (ok) { _unlocked = true; } else { _lockError = 'Not recognized — try again.'; } });
  }

  /// Password door: verify password inline and unlock — the session is KEPT.
  Future<void> _usePassword() async {
    if (_reauth && _emailCtor.text.trim().isNotEmpty && _passwordCtor.text.length >= 8) {
      setState(() { _reauthBusy = true; _reauthError = null; });
      final ok = await widget.store.loginEmail(_emailCtor.text.trim(), _passwordCtor.text, remember: true);
      if (!mounted) return;
      if (ok) {
        _unlocked = true;
      } else {
        _reauthError = widget.store.lastAuthError ?? 'Wrong email or password — try again.';
      }
      setState(() { _reauthBusy = false; });
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
    return const Scaffold(
      backgroundColor: AppColors.forest,
      body: Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          DropOffLogo(size: 46),
          SizedBox(height: 16),
          AppLogoSpinner(size: 28, color: AppColors.amber),
          SizedBox(height: 12),
          Text('DropOff', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: -0.7)),
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
