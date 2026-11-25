import 'package:flutter/material.dart';

import '../data/dropoff_api.dart';
import '../screens/rider_queue_screen.dart' show OrderWaybillSheet;
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
      case 'rejected_at_depot':
        return AppColors.amber;
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
      case 'rejected_at_depot':
        return 'Rejected at depot';
      default:
        return status.replaceAll('_', ' ');
    }
  }

  String _dateKey(String? iso) {
    if (iso == null || iso.isEmpty) return 'Unknown date';
    final d = DateTime.tryParse(iso.replaceFirst(' ', 'T'));
    if (d == null) return iso.substring(0, 10);
    final now = DateTime.now();
    if (d.year == now.year && d.month == now.month && d.day == now.day) return 'Today';
    final yest = now.subtract(const Duration(days: 1));
    if (d.year == yest.year && d.month == yest.month && d.day == yest.day) return 'Yesterday';
    return '${d.day} ${_months[d.month - 1]} ${d.year}';
  }

  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  String _time(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    final d = DateTime.tryParse(iso.replaceFirst(' ', 'T'));
    if (d == null) return '';
    return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  Map<String, List<Map<String, dynamic>>> _grouped() {
    final out = <String, List<Map<String, dynamic>>>{};
    for (final j in _jobs) {
      final key = _dateKey(j['created_at']?.toString());
      out.putIfAbsent(key, () => []).add(j);
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Job history', style: TextStyle(fontWeight: FontWeight.w900)),
        actions: [
          IconButton(tooltip: 'Refresh', icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: AppLogoSpinner(size: 32))
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)))
              : _jobs.isEmpty
                  ? const Center(child: Text('No completed jobs yet.', style: TextStyle(color: AppColors.muted)))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.all(12),
                        children: [
                          for (final entry in _grouped().entries) ...[
                            Padding(
                              padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
                              child: Text(entry.key, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: AppColors.muted, letterSpacing: 0.5)),
                            ),
                            ...entry.value.map((j) {
                              final ref = '${j['ref'] ?? ''}';
                              final status = '${j['status'] ?? ''}';
                              final city = '${j['dest_city'] ?? j['from_city'] ?? ''}';
                              final courier = '${j['courier_name'] ?? j['depot_name'] ?? ''}';
                              return Card(
                                margin: const EdgeInsets.only(bottom: 8),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(12),
                                  onTap: () => _openDetail(j),
                                  child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 42,
                                          height: 42,
                                          decoration: BoxDecoration(
                                            color: _statusColor(status).withValues(alpha: 0.12),
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: Icon(Icons.inventory_2_outlined, color: _statusColor(status), size: 20),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(ref, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
                                              const SizedBox(height: 2),
                                              Text('${j['description'] ?? 'Parcel'}${city.isNotEmpty ? ' · $city' : ''}',
                                                  maxLines: 1, overflow: TextOverflow.ellipsis,
                                                  style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                                              if (courier.isNotEmpty)
                                                Text(courier, style: const TextStyle(fontSize: 11, color: AppColors.muted)),
                                            ],
                                          ),
                                        ),
                                        Column(
                                          crossAxisAlignment: CrossAxisAlignment.end,
                                          children: [
                                            Text(_time(j['created_at']?.toString()), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.muted)),
                                            const SizedBox(height: 4),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                              decoration: BoxDecoration(
                                                color: _statusColor(status).withValues(alpha: 0.12),
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                              child: Text(_statusLabel(status), style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: _statusColor(status))),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(width: 4),
                                        const Icon(Icons.chevron_right_rounded, color: AppColors.muted, size: 18),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            }),
                          ],
                        ],
                      ),
                    ),
    );
  }

  void _openDetail(Map<String, dynamic> j) {
    final ref = '${j['ref'] ?? ''}';
    if (ref.isEmpty) return;
    // Open the order waybill sheet (read-only) for this job.
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => OrderWaybillSheet(ref: ref),
    );
  }
}
