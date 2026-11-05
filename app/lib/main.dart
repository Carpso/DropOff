import 'dart:async';

import 'package:flutter/material.dart';

import 'screens/app_shell.dart';
import 'screens/bookings_screen.dart';
import 'state/app_store.dart';
import 'data/dropoff_api.dart';
import 'ui/app_theme.dart';
import 'data/push_service.dart';

/// Root navigator so push-notification taps can open Bookings from anywhere.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = AppStore();
  await store.initialize();

  PushService.init();
  PushService.onNotificationTap.stream.listen((jobRef) {
    final ctx = navigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) return;
    Navigator.of(ctx).push(MaterialPageRoute<void>(builder: (_) => const BookingsScreen()));
  });
  if (store.linked && DropOffApi.token != null) {
    unawaited(PushService.register());
  }

  runApp(DropOffApp(store: store, navigatorKey: navigatorKey));
}

class AppScope extends InheritedNotifier<AppStore> {
  const AppScope({super.key, required AppStore store, required super.child}) : super(notifier: store);

  static AppStore of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;
}

class DropOffApp extends StatelessWidget {
  final AppStore store;
  final GlobalKey<NavigatorState> navigatorKey;
  const DropOffApp({super.key, required this.store, required this.navigatorKey});

  @override
  Widget build(BuildContext context) => AppScope(
        store: store,
        child: MaterialApp(
          navigatorKey: navigatorKey,
          title: 'DropOff Zambia',
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(),
          home: const AppShell(),
        ),
      );
}
