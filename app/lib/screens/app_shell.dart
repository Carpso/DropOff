import 'package:flutter/material.dart';

import '../main.dart';
import 'bookings_screen.dart';
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
    // Team = riders/drivers/ops console. Only staff (admin/ops) see it —
    // ordinary sellers and recipients never get the fleet tools or the
    // driver-economics card.
    final screens = <Widget>[
      HomeScreen(onOpenCouriers: () => goTo(1), onOpenBookings: () => goTo(2)),
      const CouriersScreen(),
      const BookingsScreen(),
      if (store.isStaff) const OperationsScreen(),
    ];
    final destinations = <NavigationDestination>[
      const NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
      const NavigationDestination(icon: Icon(Icons.local_shipping_outlined), selectedIcon: Icon(Icons.local_shipping), label: 'Couriers'),
      const NavigationDestination(icon: Icon(Icons.inventory_2_outlined), selectedIcon: Icon(Icons.inventory_2), label: 'Bookings'),
      if (store.isStaff)
        const NavigationDestination(icon: Icon(Icons.groups_outlined), selectedIcon: Icon(Icons.groups), label: 'Team'),
    ];
    final safeIndex = _index < screens.length ? _index : 0;
    return Scaffold(
      body: IndexedStack(index: safeIndex, children: screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: safeIndex,
        onDestinationSelected: goTo,
        destinations: destinations,
      ),
    );
  }
}
