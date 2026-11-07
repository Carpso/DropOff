import 'package:flutter/material.dart';

import '../main.dart';
import 'bookings_screen.dart';
import 'business_screen.dart';
import 'couriers_screen.dart';
import 'home_screen.dart';
import 'operations_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  void goTo(int index) => setState(() => _index = index);

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    // Tabs: everyone gets Home/Couriers/Bookings. Signed-in sellers also get
    // the Business dashboard. Staff (admin/ops) add Team; riders get Team as
    // their personal rider view instead of Business.
    final showBusiness = store.linked && !store.isRider;
    final screens = <Widget>[
      HomeScreen(onOpenCouriers: () => goTo(1), onOpenBookings: () => goTo(2)),
      const CouriersScreen(),
      const BookingsScreen(),
      if (showBusiness) const BusinessScreen(),
      if (store.isTeam) const OperationsScreen(),
    ];
    final destinations = <NavigationDestination>[
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
      body: IndexedStack(index: safeIndex, children: screens),
      // Universal text-scale clamp: EVERY screen in the app lives below this
      // clamp (MaterialApp.builder), so rows can't crush into a vertical
      // ribbon on large-font phones (the "Business tab text reading down",
      // "Parcels in flight", KPI tiles, plan cards, …). max 1.30x.
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
