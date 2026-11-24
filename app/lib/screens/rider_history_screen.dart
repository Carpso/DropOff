import 'package:flutter/material.dart';

import '../data/dropoff_api.dart';
import '../ui/app_spinner.dart';
import '../ui/app_theme.dart';

class RiderHistoryScreen extends StatefulWidget {
  const RiderHistoryScreen({super.key});

  @override
  State<RiderHistoryScreen> createState() => _RiderHistoryScreenState();
}

class _RiderHistoryScreenState extends State<RiderHistoryScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _jobs = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final data = await DropOffApi.riderHistory(limit: 100);
      final rows = ((data?['jobs'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList();
      if (!mounted) return;
      setState(() { _jobs = rows; _loading = false; });
    } catch (_) {
      if (!mounted) return;
      setState(() { _loading = false; _error = 'Could not load job history. Check your connection and try again.'; });
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'delivered':
      case 'ready_for_collection':
        return AppColors.forest;
      case 'canceled':
      case 'cancelled':
      case 'deleted':
        return AppColors.danger;
      default:
        return AppColors.muted;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'delivered':
        return 'Delivered';
      case 'ready_for_collection':
        return 'Ready for collection';
      case 'canceled':
      case 'cancelled':
        return 'Canceled';
      case 'deleted':
        return 'Deleted';
      default:
        return status.isEmpty ? 'Unknown' : status;
    }
  }

  String _fmtDate(dynamic raw) {
    final s = raw?.toString() ?? '';
    final dt = DateTime.tryParse(s.endsWith('Z') ? s : '${s}Z');
    if (dt == null) return s;
    final cat = dt.toUtc().add(const Duration(hours: 2));
    String two(int n) => n.toString().padLeft(2, '0');
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${two(cat.day)} ${months[cat.month - 1]} ${cat.year}, ${two(cat.hour)}:${two(cat.minute)} CAT';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Job history', style: TextStyle(fontWeight: FontWeight.w900)),
      ),
      body: _loading
          ? const Center(child: AppLogoSpinner())
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted)),
                  const SizedBox(height: 12),
                  FilledButton(onPressed: _load, child: const Text('Retry')),
                ])))
              : _jobs.isEmpty
                  ? const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('No completed jobs yet. Your delivered and closed jobs will appear here.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted))))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: _jobs.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (_, i) {
                          final j = _jobs[i];
                          final status = '${j['status'] ?? ''}';
                          final ref = '${j['ref'] ?? ''}';
                          final pickup = '${j['pickup_address'] ?? ''}';
                          final dest = '${j['dest_address'] ?? j['dest_city'] ?? ''}';
                          final recipient = '${j['recipient_name'] ?? ''}';
                          final parcels = j['parcels'];
                          final createdAt = _fmtDate(j['created_at']);
                          final courier = '${j['courier_name'] ?? j['depot_name'] ?? ''}'.trim();
                          return Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: AppColors.line),
                            ),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Row(children: [
                                Expanded(child: Text(ref, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13))),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(color: _statusColor(status).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(999)),
                                  child: Text(_statusLabel(status), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _statusColor(status))),
                                ),
                              ]),
                              const SizedBox(height: 6),
                              Text(createdAt, style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
                              if (recipient.isNotEmpty) ...[const SizedBox(height: 6), Text('Recipient: $recipient', style: const TextStyle(fontSize: 12.5))],
                              if (pickup.isNotEmpty) ...[const SizedBox(height: 4), Text('Pickup: $pickup', style: const TextStyle(fontSize: 12.5, color: AppColors.muted))],
                              if (dest.isNotEmpty) ...[const SizedBox(height: 2), Text('Destination: $dest', style: const TextStyle(fontSize: 12.5, color: AppColors.muted))],
                              if (courier.isNotEmpty || parcels != null) ...[
                                const SizedBox(height: 6),
                                Text([if (courier.isNotEmpty) courier, if (parcels != null) '$parcels item${'$parcels' == '1' ? '' : 's'}'].join(' • '), style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
                              ],
                            ]),
                          );
                        },
                      ),
                    ),
    );
  }
}