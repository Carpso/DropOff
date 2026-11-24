import 'dart:async';

import 'package:flutter/material.dart';

import '../data/dropoff_api.dart';
import '../main.dart';
import '../services/order_alert.dart';
import '../ui/app_spinner.dart';
import '../ui/app_theme.dart';
import '../ui/app_toast.dart';

/// Full-screen INCOMING ORDER (owner 2026-11-24, inDrive parity).
///
/// Shown over everything — including the lock screen when Android allows the
/// full-screen intent — with two big, unmissable actions: ACCEPT and DECLINE.
/// The order rings until the rider answers, and silences itself after the
/// countdown so a phone left on a table does not scream forever.
class IncomingOrderScreen extends StatefulWidget {
  const IncomingOrderScreen({super.key, required this.jobRef, this.detail});

  final String jobRef;
  final Map<String, dynamic>? detail;

  @override
  State<IncomingOrderScreen> createState() => _IncomingOrderScreenState();
}

class _IncomingOrderScreenState extends State<IncomingOrderScreen> {
  static const Duration _window = Duration(seconds: 45);

  late final DateTime _deadline = DateTime.now().add(_window);
  Timer? _ticker;
  bool _expired = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (DateTime.now().isAfter(_deadline)) {
        _ticker?.cancel();
        unawaited(OrderAlert.stop());
        if (!_expired) setState(() => _expired = true);
        return;
      }
      setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    unawaited(OrderAlert.stop());
    super.dispose();
  }

  int get _secondsLeft {
    final s = _deadline.difference(DateTime.now()).inSeconds;
    return s < 0 ? 0 : s;
  }

  String _read(List<String> keys) {
    for (final k in keys) {
      final v = widget.detail?[k];
      if (v != null && '$v'.trim().isNotEmpty) return '$v'.trim();
    }
    return '';
  }

  Future<void> _accept() async {
    if (_busy) return;
    setState(() => _busy = true);
    await OrderAlert.stop();
    final res = await DropOffApi.acceptJob(widget.jobRef);
    if (!mounted) return;
    if (res.ok) {
      await AppScope.of(context).syncJobsFromServer();
      if (!mounted) return;
      Navigator.of(context).maybePop();
      AppToast.show(context, 'Order ${widget.jobRef} accepted — it is in your Task Queue.');
      return;
    }
    setState(() => _busy = false);
    if (res.error == 'not_your_job' || res.error == 'not_found') {
      Navigator.of(context).maybePop();
      AppToast.show(context, 'This order moved to another rider.');
      return;
    }
    AppToast.error(context, res.error == 'rider_required'
        ? 'Sign in again as a rider to accept orders.'
        : 'Could not accept — check your connection and try again.');
  }

  Future<void> _decline() async {
    if (_busy) return;
    setState(() => _busy = true);
    await OrderAlert.stop();
    final res = await DropOffApi.declineJob(widget.jobRef);
    if (!mounted) return;
    if (res.ok) {
      await AppScope.of(context).syncJobsFromServer();
      if (!mounted) return;
      Navigator.of(context).maybePop();
      AppToast.show(context, 'Declined — ${widget.jobRef} went back to the order board.');
      return;
    }
    setState(() => _busy = false);
    AppToast.error(context, res.error == 'already_started'
        ? 'You already started this delivery — open your Task Queue.'
        : 'Could not decline — check your connection and try again.');
  }

  void _openQueue() {
    unawaited(OrderAlert.stop());
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final address = _read(['pickup_address', 'pickup', 'address']);
    final city = _read(['dest_city', 'to_city', 'destination']);
    final parcels = _read(['parcels', 'items']);
    final eta = _read(['eta_minutes', 'eta']);
    final fee = _read(['fee', 'rider_fee_zmw']);
    final service = _read(['service']).toLowerCase();
    final isCollection = service == 'collection';

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFF0B1F14),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: AppColors.amber,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(Icons.delivery_dining_rounded,
                          color: Color(0xFF0B1F14), size: 26),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('DROPOFF',
                              style: TextStyle(
                                  color: Colors.white, fontWeight: FontWeight.w900,
                                  letterSpacing: 2, fontSize: 13)),
                          Text(_expired ? 'Order alert silenced' : 'New delivery — live now',
                              style: const TextStyle(color: Color(0xCCFFFFFF), fontSize: 12.5)),
                        ],
                      ),
                    ),
                    if (!_expired)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          color: const Color(0x22FFFFFF),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0x44FFFFFF)),
                        ),
                        child: Text('${_secondsLeft}s',
                            style: const TextStyle(
                                color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14)),
                      ),
                  ],
                ),
                const SizedBox(height: 22),
                Expanded(
                  child: SingleChildScrollView(
                    child: Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(22),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(isCollection ? 'Collection from the depot' : 'Pickup',
                              style: const TextStyle(
                                  fontSize: 11, fontWeight: FontWeight.w800,
                                  color: AppColors.muted, letterSpacing: 1.1)),
                          const SizedBox(height: 6),
                          Text(
                            address.isNotEmpty
                                ? address
                                : isCollection
                                    ? 'Depot counter — show the sender\'s receipt'
                                    : 'Open your Task Queue for the address',
                            softWrap: true,
                            style: const TextStyle(
                                fontSize: 19, height: 1.25, fontWeight: FontWeight.w900,
                                color: Color(0xFF11261B)),
                          ),
                          if (city.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text('Deliver to $city',
                                style: const TextStyle(fontSize: 13, color: AppColors.muted)),
                          ],
                          const SizedBox(height: 16),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _pill(Icons.inventory_2_outlined,
                                  parcels.isNotEmpty ? '$parcels item(s)' : 'Item'),
                              if (eta.isNotEmpty) _pill(Icons.schedule, '$eta min to pickup'),
                              if (fee.isNotEmpty) _pill(Icons.payments_outlined, 'Fee $fee'),
                              _pill(Icons.confirmation_number_outlined, widget.jobRef),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppColors.canvas,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Text(
                              'Accepting confirms you are taking this order now. '
                              'Declining returns it to the order board for another rider.',
                              softWrap: true,
                              style: TextStyle(fontSize: 12, height: 1.35, color: Color(0xFF3A4A42)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                if (_expired)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 10),
                    child: Text(
                      'The alarm stopped, but the order is still on your Task Queue.',
                      softWrap: true,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0xCCFFFFFF), fontSize: 12),
                    ),
                  ),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _busy ? null : _decline,
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(58),
                          side: const BorderSide(color: Color(0xFFFF8A80), width: 1.6),
                          foregroundColor: const Color(0xFFFF8A80),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        child: _busy
                            ? const AppLogoSpinner(size: 20)
                            : const Text('Decline',
                                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: FilledButton(
                        onPressed: _busy ? null : _accept,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(58),
                          backgroundColor: AppColors.success,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        child: _busy
                            ? const AppLogoSpinner(size: 20)
                            : const Text('ACCEPT ORDER',
                                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15.5)),
                      ),
                    ),
                  ],
                ),
                TextButton(
                  onPressed: _busy ? null : _openQueue,
                  child: const Text('Open Task Queue instead',
                      style: TextStyle(color: Color(0xCCFFFFFF), fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _pill(IconData icon, String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F2),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: AppColors.forest),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 220),
              child: Text(label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w700, color: Color(0xFF11261B))),
            ),
          ],
        ),
      );
}
