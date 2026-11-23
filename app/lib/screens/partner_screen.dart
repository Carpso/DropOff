import 'dart:async';

import 'package:flutter/material.dart';

import '../data/dropoff_api.dart';
import '../main.dart';
import '../ui/app_spinner.dart';
import '../ui/app_theme.dart';
import '../ui/app_toast.dart';
import '../widgets/common.dart';
import '../widgets/courier_logo.dart';
import '../widgets/courier_status_pill.dart';

/// Courier depot partner desk. Backed by `/partner/me|quotes|rides` — the
/// account is pinned server-side to its own courier, so a partner can only see
/// and confirm their own depot's work (owner 2026-11-23).
class PartnerScreen extends StatefulWidget {
  const PartnerScreen({super.key});

  @override
  State<PartnerScreen> createState() => _PartnerScreenState();
}

class _PartnerScreenState extends State<PartnerScreen> {
  Map<String, dynamic>? _me;
  List<Map<String, dynamic>> _quotes = const [];
  List<Map<String, dynamic>> _rides = const [];
  bool _loading = true;
  String? _error;
  Timer? _timer;
  final Set<String> _confirming = {};

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _load(silent: true));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent && mounted) setState(() { _loading = true; _error = null; });
    try {
      final results = await Future.wait([
        DropOffApi.partnerMe(),
        DropOffApi.partnerQuotes(),
        DropOffApi.partnerRides(),
      ]);
      if (!mounted) return;
      setState(() {
        _me = results[0];
        _quotes = ((results[1]?['quotes'] as List?) ?? const [])
            .whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
        _rides = ((results[2]?['jobs'] as List?) ?? const [])
            .whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() { _loading = false; if (!silent) _error = 'Could not reach DropOff. Pull to retry.'; });
    }
  }

  Future<void> _confirm(Map<String, dynamic> ride) async {
    final ref = '${ride['ref'] ?? ''}';
    if (ref.isEmpty || _confirming.contains(ref)) return;
    setState(() => _confirming.add(ref));
    final res = await DropOffApi.partnerConfirmRide(ref);
    if (!mounted) return;
    setState(() => _confirming.remove(ref));
    AppToast.show(context, res.ok
        ? '$ref confirmed — the rider and DropOff can see it now.'
        : 'Could not confirm $ref. Check your connection and try again.');
    if (res.ok) unawaited(_load(silent: true));
  }

  @override
  Widget build(BuildContext context) {
    final courier = (_me?['courier'] as Map?)?.cast<String, dynamic>() ?? const {};
    final name = '${courier['name'] ?? AppScope.of(context).fullName ?? 'Your depot'}';
    final depot = '${courier['depot_name'] ?? ''}';
    final city = '${courier['city'] ?? ''}';
    final pending = _rides.where((r) => '${r['status']}' != 'delivered' && '${r['status']}' != 'canceled').length;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text('Partner desk', style: TextStyle(fontWeight: FontWeight.w900)),
        actions: [
          IconButton(tooltip: 'Refresh', onPressed: () => _load(),
              icon: _loading ? const AppLogoSpinner(size: 16) : const Icon(Icons.refresh)),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _load(silent: true),
        child: _loading
            ? const Center(child: AppLogoSpinner(size: 28))
            : ListView(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 32),
                children: [
                  if (_error != null)
                    Padding(padding: const EdgeInsets.only(bottom: 12), child: TextButton.icon(
                      onPressed: () => _load(), icon: const Icon(Icons.refresh),
                      label: Text('$_error Tap to retry.'))),
                  Card(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: Padding(padding: const EdgeInsets.all(18), child: Row(children: [
                      CourierLogo(name: name, size: 52),
                      const SizedBox(width: 14),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(name, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 3),
                        Text([depot, city].where((s) => s.isNotEmpty).join(' · '),
                            style: const TextStyle(color: AppColors.muted, fontSize: 12),
                            maxLines: 2, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 6),
                        const CourierStatusPill(partnered: true),
                      ])),
                    ])),
                  ),
                  const SizedBox(height: 14),
                  Row(children: [
                    Expanded(child: _kpi('${_quotes.length}', 'Prices on file')),
                    const SizedBox(width: 10),
                    Expanded(child: _kpi('${_rides.length}', 'Rides this month')),
                    const SizedBox(width: 10),
                    Expanded(child: _kpi('$pending', 'Awaiting handover')),
                  ]),
                  const SizedBox(height: 20),
                  const SectionTitle('Rides handed to your depot'),
                  const SizedBox(height: 8),
                  if (_rides.isEmpty)
                    const EmptyState(title: 'No rides yet',
                        message: 'Parcels booked to your depot will appear here automatically.')
                  else
                    for (final r in _rides) Card(
                      child: Padding(padding: const EdgeInsets.fromLTRB(14, 12, 14, 10), child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Expanded(child: Text('${r['ref']}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13))),
                            Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(color: AppColors.forest.withValues(alpha: 0.09), borderRadius: BorderRadius.circular(14)),
                              child: Text('K${(r['counter_price_zmw'] as num?)?.toStringAsFixed(2) ?? 'counter'}',
                                  style: const TextStyle(color: AppColors.forest, fontWeight: FontWeight.w800, fontSize: 11))),
                          ]),
                          const SizedBox(height: 4),
                          Text('${r['recipient_name'] ?? 'Recipient'} → ${r['dest_city'] ?? '—'} · ${r['status'] ?? ''}',
                              style: const TextStyle(color: AppColors.muted, fontSize: 11.5)),
                          Align(alignment: Alignment.centerRight, child: TextButton.icon(
                            onPressed: _confirming.contains('${r['ref']}') ? null : () => _confirm(r),
                            icon: const Icon(Icons.check_circle_outline, size: 16),
                            label: Text(_confirming.contains('${r['ref']}') ? 'Confirming…' : 'Confirm handover'),
                          )),
                        ])),
                    ),
                  const SizedBox(height: 20),
                  const SectionTitle('Your counter prices'),
                  const SizedBox(height: 8),
                  if (_quotes.isEmpty)
                    const EmptyState(title: 'No prices on file',
                        message: 'Confirm a route price in the web partner console; it will appear here for senders.')
                  else
                    for (final q in _quotes) ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.local_shipping_outlined, color: AppColors.forest),
                      title: Text('${q['from_city']} → ${q['to_city']}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                      subtitle: Text('${q['weight_class']} · ${q['service']}', style: const TextStyle(fontSize: 11.5)),
                      trailing: Text('K${(q['counter_price_zmw'] as num?)?.toStringAsFixed(2) ?? '—'}',
                          style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.forest)),
                    ),
                ],
              ),
      ),
    );
  }

  Widget _kpi(String value, String label) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: AppColors.canvas, borderRadius: BorderRadius.circular(14)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20, color: AppColors.forest),
              maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 10.5),
              maxLines: 2, overflow: TextOverflow.ellipsis),
        ]),
      );
}
