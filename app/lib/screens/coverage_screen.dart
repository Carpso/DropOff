import 'package:flutter/material.dart';

import '../data/catalog.dart';
import '../ui/app_theme.dart';

/// Live depot coverage: which cities DropOff can book today vs what is launching.
class CoverageScreen extends StatelessWidget {
  const CoverageScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final platinum = couriers.firstWhere((c) => c.id == 'platinum');
    final coveredCities = platinum.branches.map((b) => b.city.toLowerCase()).toSet();
    final coming = cities.where((c) => !coveredCities.contains(c.trim().toLowerCase())).toList();
    final covered = platinum.branches.map((b) => b.city).toSet().toList()..sort();
    return Scaffold(
      appBar: AppBar(title: const Text('Coverage', style: TextStyle(fontWeight: FontWeight.w900))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [AppColors.forest, Color(0xFF1B5A48)], begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('DROP OFF COVERAGE', style: TextStyle(color: Color(0xFFDCE9E3), fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.1)),
              const SizedBox(height: 8),
              const Text('Lusaka live now.\nMore cities opening up.', style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900, height: 1.1, letterSpacing: -0.5)),
              const SizedBox(height: 10),
              Text('Courier handover pickups are live in Lusaka. Outside covered cities, you can still book — the depot fare is quoted at the counter.',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.88), height: 1.45)),
            ]),
          ),
          const SizedBox(height: 22),
          _sectionHeader('Live today', '${covered.length} cities', AppColors.success),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final city in covered)
              _cityChip(city, live: true),
          ]),
          const SizedBox(height: 24),
          _sectionHeader('Expanding next', '${coming.length} cities', AppColors.amber),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final city in coming)
              _cityChip(city, live: false),
          ]),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: AppColors.canvas, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.line)),
            child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.info_outline, color: AppColors.forest),
              SizedBox(width: 10),
              Expanded(child: Text('Need a city not listed as live yet? You can still create a booking. DropOff will take the item to the courier counter, and the counter fare is quoted at the counter.', style: TextStyle(height: 1.45, fontSize: 13, color: AppColors.ink))),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title, String subtitle, Color color) => Row(
        children: [
          Expanded(child: Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: -0.2))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
            child: Text(subtitle, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: color)),
          ),
        ],
      );

  Widget _cityChip(String city, {required bool live}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: live ? AppColors.forest.withValues(alpha: 0.08) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: live ? AppColors.forest.withValues(alpha: 0.2) : AppColors.line),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(live ? Icons.check_circle : Icons.schedule_rounded, size: 15, color: live ? AppColors.success : AppColors.muted),
          const SizedBox(width: 6),
          Text(city, style: TextStyle(fontWeight: FontWeight.w700, color: live ? AppColors.ink : AppColors.muted)),
        ]),
      );
}
