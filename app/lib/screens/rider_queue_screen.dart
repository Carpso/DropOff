import 'package:flutter/material.dart';

import '../data/dropoff_api.dart';
import '../main.dart';
import '../ui/app_theme.dart';

/// The rider's day as slot-batched task queues:
///   BATCH: 10:00 AM SLOT · TOTAL PARCELS: 6 · DESTINATION: Mercury — Kabulonga
///   1. 10:05 · 14 Reedbuck Rd (Beauty Hub) — 2 parcels ...
/// plus the target branch drop-off time. Stop order is a nearest-neighbour
/// chain from the rider's last known position; ETAs assume 22 km/h + 4 min
/// per stop. Refresh pulls the latest assignments.
class RiderQueueScreen extends StatefulWidget {
  const RiderQueueScreen({super.key, this.phone});

  final String? phone;

  @override
  State<RiderQueueScreen> createState() => _RiderQueueScreenState();
}

class _RiderQueueScreenState extends State<RiderQueueScreen> {
  Map<String, dynamic>? _data;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await DropOffApi.riderQueue(widget.phone);
    if (!mounted) return;
    setState(() { _data = data; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    // Fleet view is staff-only (Team tab + this gate). The server also
    // validates the phone belongs to an active rider — a seller whose phone
    // is not a rider row gets an empty queue, never someone else's stops.
    final store = AppScope.of(context);
    if (!store.linked) {
      return Scaffold(
        appBar: AppBar(title: const Text('Task queue', style: TextStyle(fontWeight: FontWeight.w900))),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.lock_outline, size: 44, color: AppColors.muted),
              SizedBox(height: 16),
              Text('Sign in for the task queue', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900), textAlign: TextAlign.center),
              SizedBox(height: 8),
              Text('Link this device to a rider account to see slot-batched pickup runs.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted, height: 1.45)),
            ]),
          ),
        ),
      );
    }
    final batches = ((_data?['batches'] as List?) ?? const []).cast<Map<String, dynamic>>();
    return Scaffold(
      appBar: AppBar(title: const Text('Task queue', style: TextStyle(fontWeight: FontWeight.w900))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _loading ? null : _load,
        icon: const Icon(Icons.refresh),
        label: const Text('Refresh'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : batches.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text('No pick-ups assigned yet.\nNew bookings drop into your queue automatically.',
                        textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted, height: 1.5)),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 90),
                  itemCount: batches.length,
                  itemBuilder: (context, i) => _batchCard(batches[i]),
                ),
    );
  }

  Widget _batchCard(Map<String, dynamic> b) {
    final dest = b['destination'] as Map<String, dynamic>?;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            color: AppColors.forest,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${b['label']}', style: const TextStyle(color: AppColors.amber, fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 0.8)),
              const SizedBox(height: 5),
              Text('TOTAL PARCELS TO PICK UP: ${b['total_parcels']}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14)),
              if (dest != null)
                Text('DESTINATION: ${dest['courier']} — ${dest['branch']}',
                    style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (final s in ((b['stops'] as List?) ?? const []).cast<Map<String, dynamic>>())
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${s['n']}.', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12.5, color: AppColors.forest)),
                    const SizedBox(width: 8),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${s['time']} — ${s['address']}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                      const SizedBox(height: 2),
                      Text('Seller: ${s['seller']} · ${s['parcels']} parcel${s['parcels'] == 1 ? '' : 's'} · ${s['status']}'.replaceAll('_', ' '),
                          style: const TextStyle(color: AppColors.muted, fontSize: 11.5)),
                    ])),
                  ]),
                ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: AppColors.line.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(10)),
                child: Row(children: [
                  const Icon(Icons.flag_outlined, size: 16, color: AppColors.forest),
                  const SizedBox(width: 8),
                  Expanded(child: Text(
                    'Target branch drop-off: before ${b['target_dropoff']} · ~${b['minutes_on_road']} min on the road',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: AppColors.forest),
                  )),
                ]),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
