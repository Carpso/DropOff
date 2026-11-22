import 'dart:async';

import 'package:flutter/material.dart';

import '../main.dart';
import 'bookings_screen.dart';
import 'business_screen.dart';
import 'couriers_screen.dart';
import 'home_screen.dart';
import 'operations_screen.dart';
import 'rider_queue_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  void goTo(int index) {
    final store = AppScope.of(context);
    // Bookings is a persistent tab — re-sync on every switch so collections
    // and standing orders appear without an app restart.
    if (index == 2) store.syncJobsFromServer();
    // Keep the identity fresh on EVERY tab (profile photo, name, role). The
    // avatars in the Task Queue and Home read this store; a photo changed on
    // another device or by support must show without tapping a profile picture.
    if (store.linked) unawaited(store.refreshRole(force: true));
    setState(() => _index = index);
  }

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    // RIDER LANDING (owner directive 2026-11-17): a rider's FIRST screen is
    // the Task queue — their slot-batched pickups are the whole job. The
    // queue replaces Home as the first tab; Business never shows for riders.
    final showBusiness = store.linked && !store.isRider;
    final screens = <Widget>[
      if (store.isRider) RiderQueueScreen(phone: store.linkedPhone) else HomeScreen(onOpenCouriers: () => goTo(1), onOpenBookings: () => goTo(2)),
      const CouriersScreen(),
      const BookingsScreen(),
      if (showBusiness) const BusinessScreen(),
      if (store.isTeam) const OperationsScreen(),
    ];
    final destinations = <NavigationDestination>[
      if (store.isRider)
        const NavigationDestination(icon: Icon(Icons.fact_check_outlined), selectedIcon: Icon(Icons.fact_check), label: 'Task Queue')
      else
        const NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
      const NavigationDestination(icon: Icon(Icons.local_shipping_outlined), selectedIcon: Icon(Icons.local_shipping), label: 'Couriers'),
      const NavigationDestination(icon: Icon(Icons.inventory_2_outlined), selectedIcon: Icon(Icons.inventory_2), label: 'Bookings'),
      if (showBusiness)
        const NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'Business'),
      if (store.isTeam)
        const NavigationDestination(icon: Icon(Icons.groups_outlined), selectedIcon: Icon(Icons.groups), label: 'Team'),
    ];
    final safeIndex = _index < screens.length ? _index : 0;
    return Scaffold(
      // IndexedStack gives its children LOOSE constraints — a Scaffold/ListView
      // child then shrinks to its content and the canvas background shows as a
      // grey band below the last card ("grey area on bottom scroll"). Wrapping
      // each tab in SizedBox.expand gives it tight constraints so the list
      // always fills the viewport (owner bug 2026-11-20).
      body: IndexedStack(index: safeIndex, children: [
        // White behind EVERY tab: a short list must never show the canvas
        // grey band below its last card (owner bug 2026-11-20).
        for (final screen in screens)
          SizedBox.expand(child: ColoredBox(color: Colors.white, child: screen)),
      ]),
      // Universal text-scale clamp: EVERY screen in the app lives below this
      // clamp (MaterialApp.builder), so rows can't crush into a vertical
      // ribbon on large-font phones (the "Business tab text reading down",
      // "Items in flight", KPI tiles, plan cards, …). max 1.30x.
      bottomNavigationBar: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.30,
        child: NavigationBar(
          labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
          selectedIndex: safeIndex,
          onDestinationSelected: goTo,
          height: 64,
          destinations: destinations,
        ),
      ),
    );
  }
}
