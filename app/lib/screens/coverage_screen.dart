import 'package:flutter/material.dart';

import '../data/catalog.dart';
import '../ui/app_theme.dart';
import '../widgets/common.dart';

/// Live depot coverage: which cities DropOff can book today vs what is launching.
/// Helps sellers outside Lusaka know expectations up front.
class CoverageScreen extends StatelessWidget {
  const CoverageScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final platinum = couriers.firstWhere((c) => c.id == 'platinum');
    final coveredCities = platinum.branches.map((b) => b.city.toLowerCase()).toSet();
    final coming = cities.where((c) => !coveredCities.contains(c.trim().toLowerCase())).toList();
    final covered = platinum.branches.map((b) => b.city).toSet().toList()..sort();
    return Scaffold(
      appBar: AppBar(title: const Text('Depot coverage', style: TextStyle(fontWeight: FontWeight.w900))),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        const Text('DropOff launches courier-handover pickups Lusaka first, then Copperbelt and Southern. Outside these cities we still book today — quote at the counter.',
            style: TextStyle(color: AppColors.muted, height: 1.4)),
        const SizedBox(height: 20),
        const SectionTitle('Covered today'),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final city in covered) Chip(label: Text(city, style: const TextStyle(fontWeight: FontWeight.w700)), backgroundColor: AppColors.forest.withValues(alpha: 0.12), side: BorderSide(color: AppColors.forest.withValues(alpha: 0.3))),
        ]),
        const SizedBox(height: 22),
        const SectionTitle('Coming soon'),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final city in coming) Chip(label: Text(city, style: const TextStyle(color: AppColors.muted)), backgroundColor: AppColors.line.withValues(alpha: 0.3), side: const BorderSide(color: AppColors.line)),
        ]),
        const SizedBox(height: 20),
        const Text('Outside covered cities: the DropOff rider delivers to any courier counter, but the fare is quoted at the counter and confirmation may be manual.',
            style: TextStyle(color: AppColors.muted, fontSize: 11.5, height: 1.4)),
      ]),
    );
  }
}
