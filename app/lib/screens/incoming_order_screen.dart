import 'dart:async';

import 'package:flutter/material.dart';

import '../data/dropoff_api.dart';
import '../data/notification_inbox.dart';
import '../main.dart';
import 'app_shell.dart';
import '../services/order_alert.dart';
import '../ui/app_spinner.dart';
import '../ui/app_theme.dart';
import '../ui/app_toast.dart';
import '../widgets/rider_map.dart';
import 'package:latlong2/latlong.dart';

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
  Map<String, dynamic> _offer = const {};

  @override
  void initState() {
    super.initState();
    _loadOffer();
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

  /// The push payload can be missing (cold start / notification replay). The
  /// assigned rider always has a server-side offer with the real pin, so the
  /// card never opens without its map and details.
  Future<void> _loadOffer() async {
    try {
      final data = await DropOffApi.jobOffer(widget.jobRef);
      final offer = data?['offer'];
      if (mounted && offer is Map) {
        setState(() => _offer = Map<String, dynamic>.from(offer));
      }
    } catch (_) {
      // The pushed detail is still a usable fallback.
    }
  }

  double? _coord(List<String> keys) {
    for (final k in keys) {
      final v = _offer[k] ?? widget.detail?[k];
      if (v == null) continue;
      final d = double.tryParse('$v');
      if (d != null && d != 0) return d;
    }
    return null;
  }

  double? get _pickupLat => _coord(['pickup_lat', 'lat']);
  double? get _pickupLng => _coord(['pickup_lng', 'lng']);
  double? get _destLat => _coord(['depot_lat', 'dest_lat']);
  double? get _destLng => _coord(['depot_lng', 'dest_lng']);

  String _read(List<String> keys) {
    for (final k in keys) {
      final v = _offer[k] ?? widget.detail?[k];
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
      unawaited(NotificationInbox.addLocal(
        title: 'Order accepted',
        body: '${widget.jobRef} is in your Task Queue — head to the pickup.',
        kind: 'order_answer',
        jobRef: widget.jobRef,
      ));
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => const AppShell()),
        (route) => false,
      );
      AppToast.show(context, 'Order ${widget.jobRef} accepted — open your Task Queue.');
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
      unawaited(NotificationInbox.addLocal(
        title: 'Order declined',
        body: '${widget.jobRef} went back to the order board for another rider.',
        kind: 'order_answer',
        jobRef: widget.jobRef,
      ));
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => const AppShell()),
        (route) => false,
      );
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
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const AppShell()),
      (route) => false,
    );
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
    final sender = _read(['sender_name']);
    final fromCity = _read(['from_city']);
    final pickupWindow = _read(['pickup_window']);
    final declared = _read(['declared_value_zmw']);
    final vehicle = _read(['vehicle_class']);
    final depotName = _read(['depot_name']);
    final destAddress = _read(['dest_address', 'dest_address']);
    final promo = _read(['promo_code']);
    final promoOff = _read(['promo_discount_zmw']);
    final pickup = (_pickupLat != null && _pickupLng != null)
        ? LatLng(_pickupLat!, _pickupLng!)
        : null;
    final dest = (_destLat != null && _destLng != null)
        ? LatLng(_destLat!, _destLng!)
        : null;

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
                          if (pickup != null) ...[
                            const SizedBox(height: 12),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: SizedBox(
                                height: 150,
                                child: RiderMap(
                                  pickup: pickup,
                                  rider: null,
                                  depot: dest,
                                  pickupIsDepot: isCollection,
                                  depotName: depotName.isNotEmpty ? depotName : null,
                                  route: dest != null ? [pickup, dest] : null,
                                  routeIsStraightLine: true,
                                  city: fromCity.isNotEmpty ? fromCity : null,
                                ),
                              ),
                            ),
                            const Padding(
                              padding: EdgeInsets.only(top: 4),
                              child: Text('Map preview - open Task Queue for turn-by-turn navigation.',
                                  style: TextStyle(fontSize: 10.5, color: AppColors.muted)),
                            ),
                          ],
                          const SizedBox(height: 12),
                          // Everything the rider needs to judge the order,
                          // before accepting (no raw refs in place of copy).
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF6F8F5),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (sender.isNotEmpty)
                                  _detailLine('From', sender),
                                if (fromCity.isNotEmpty)
                                  _detailLine('Origin', fromCity),
                                if (destAddress.isNotEmpty)
                                  _detailLine('Destination', destAddress),
                                if (city.isNotEmpty)
                                  _detailLine('Drop-off city', city),
                                if (pickupWindow.isNotEmpty)
                                  _detailLine('Pickup window', pickupWindow),
                                if (vehicle.isNotEmpty)
                                  _detailLine('Vehicle', vehicle == 'car' ? 'Car' : 'Motorcycle'),
                                if (declared.isNotEmpty)
                                  _detailLine('Declared value', 'K$declared'),
                              ],
                            ),
                          ),
                          if (promo.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                              decoration: BoxDecoration(
                                color: AppColors.amberSoft,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                promoOff.isNotEmpty
                                    ? 'Promo $promo — sender saves K$promoOff. Your pay is unchanged.'
                                    : 'Promo $promo applied — your pay is unchanged.',
                                style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700,
                                    color: AppColors.ink),
                              ),
                            ),
                          ],
                          const SizedBox(height: 14),
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
                      'The alert has silenced — this order is still waiting in your Task Queue.',
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

  Widget _detailLine(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 92, child: Text(label,
              style: const TextStyle(fontSize: 11.5, color: AppColors.muted))),
          const SizedBox(width: 6),
          Expanded(child: Text(value, maxLines: 2, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700,
                  color: Color(0xFF11261B)))),
        ]),
      );

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
