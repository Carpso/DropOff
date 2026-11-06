import 'dart:async';

import 'package:flutter/material.dart';

import 'screens/app_shell.dart';
import 'screens/bookings_screen.dart';
import 'state/app_store.dart';
import 'data/dropoff_api.dart';
import 'data/analytics_service.dart';
import 'ui/app_theme.dart';
import 'data/push_service.dart';
import 'widgets/common.dart';

/// Root navigator so push-notification taps can open Bookings from anywhere.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = AppStore();
  // Initialize analytics outbox (offline-first) on a background future so the
  // splash screen shows immediately; events are flushed with the booking
  // outbox and on a timer.
  final initFuture = Future.wait([store.initialize(), AnalyticsService.instance.init()]);
  PushService.init();
  PushService.onNotificationTap.stream.listen((jobRef) {
    final ctx = navigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) return;
    Navigator.of(ctx).push(MaterialPageRoute<void>(builder: (_) => const BookingsScreen()));
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
        child: MaterialApp(
          navigatorKey: navigatorKey,
          title: 'DropOff Zambia',
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(),
          home: _SplashScreen(store: store, initFuture: initFuture),
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

  @override
  Widget build(BuildContext context) {
    if (widget.store.ready) {
      return const AppShell();
    }
    return Scaffold(
      backgroundColor: AppColors.forest,
      body: Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const DropOffLogo(size: 46),
          const SizedBox(height: 16),
          const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3, color: AppColors.amber)),
          const SizedBox(height: 12),
          const Text('DropOff', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: -0.7)),
        ]),
      ),
    );
  }
}
