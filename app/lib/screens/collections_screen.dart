import '../ui/app_toast.dart';
import 'package:flutter/material.dart';

import '../data/catalog.dart';
import '../data/dropoff_api.dart';
import '../data/analytics_service.dart';
import '../main.dart';
import '../ui/app_theme.dart';
import '../widgets/common.dart';
import 'account_screen.dart';
import 'booking_screen.dart';

/// Collect a parcel from a courier's point in Lusaka and deliver it to the
/// recipient's door. No counter fare and no branch picking â€” the parcel is
/// already at the courier depot; a DropOff rider runs the last mile.
class CollectionsScreen extends StatefulWidget {
  const CollectionsScreen({super.key});

  @override
  State<CollectionsScreen> createState() => _CollectionsScreenState();
}

class _CollectionsScreenState extends State<CollectionsScreen> {
  String _courierId = 'icypeed';
  final _point = TextEditingController();
  final _recipientName = TextEditingController();
  final _recipientPhone = TextEditingController();
  final _address = TextEditingController();
  final _description = TextEditingController();
  final _senderName = TextEditingController();
  final _promoCode = TextEditingController();
  String _window = '10:00';
  final String _payment = 'Mobile money';
  String _vehicleClass = 'motorcycle';
  int _parcels = 1;
  bool _saving = false;
  bool _aiBusy = false;

  /// AI tidy-up of a free-text address (best-effort; never blocks).
  Future<void> _aiTidy(TextEditingController ctl) async {
    final text = ctl.text.trim();
    if (text.length < 5) return _message('Type the address first, then tap AI.');
    setState(() => _aiBusy = true);
    final res = await DropOffApi.aiAddress(text);
    if (!mounted) return;
    setState(() => _aiBusy = false);
    final parsed = res.body['parsed'];
    if (!res.ok || parsed is! Map) return _message('AI is unavailable right now - your address is unchanged.');
    final parts = [parsed['street'], parsed['area'], parsed['landmark']]
        .map((e) => '${e ?? ''}'.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (parts.isNotEmpty) ctl.text = parts.join(', ');
    _message('AI tidied the address - check it before booking.');
  }

  static const Map<String, String> _windows = {
    '06:00': '6:00 â€“ 7:30 AM',
    '10:00': '10:00 â€“ 11:30 AM',
    '14:00': '2:00 â€“ 3:30 PM',
  };
  static const Map<String, String> _cutoffs = {'06:00': '05:30', '10:00': '09:30', '14:00': '13:30'};
  static const Map<String, int> _maxParcels = {'motorcycle': 3, 'car': 6, 'van': 10, 'truck': 15};
  static const Map<String, String> _vehicleLabels = {'motorcycle': 'Motorcycle', 'car': 'Car', 'van': 'Van', 'truck': 'Truck (large cargo)'};

  @override
  void dispose() {
    for (final c in [_point, _recipientName, _recipientPhone, _address, _description, _senderName, _promoCode]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    AnalyticsService.instance.track(
      feature: 'collections', action: 'view', context: 'collections_form',
    );
  }

  bool _slotClosed(String key) {
    final parts = _cutoffs[key]!.split(':');
    final now = TimeOfDay.now();
    return now.hour * 60 + now.minute > int.parse(parts[0]) * 60 + int.parse(parts[1]);
  }

  Future<void> _submit() async {
    final store = AppScope.of(context);
    if (!_point.text.trim().isNotEmpty) {
      return _message('Enter the courier point where the parcel is waiting.');
    }
    if (_recipientName.text.trim().length < 2) return _message('Enter the recipient name.');
    if (!RegExp(r'^(?:\+?260|0)?[79][567]\d{7}$').hasMatch(_recipientPhone.text.replaceAll(RegExp(r'[\s-]'), ''))) {
      return _message('Use a valid Zambian recipient number, e.g. 0961234567.');
    }
    if (_address.text.trim().length < 4) return _message('Enter the door address for delivery.');
    // Plan code entry: pre-redeem before the collection so the plan covers the
    // rider fee for this booking without a separate step.
    final promo = _promoCode.text.trim().toUpperCase();
    if (promo.isNotEmpty) {
      try {
        final red = await DropOffApi.redeemPackCode(promo);
        if (!red.ok) {
          _message('Plan code not recognised â€” continuing as pay-as-you-go.');
        }
      } catch (_) { /* best-effort */ }
    }
    setState(() => _saving = true);
    final res = await DropOffApi.createCollection(
      courierId: courierServerIdOf(_courierId),
      point: _point.text.trim(),
      recipientName: _recipientName.text.trim(),
      recipientPhone: _recipientPhone.text.trim(),
      destAddress: _address.text.trim(),
      pickupWindow: _window,
      senderName: _senderName.text.trim().isEmpty ? null : _senderName.text.trim(),
      description: _description.text.trim().isEmpty ? null : _description.text.trim(),
      parcels: _parcels,
      vehicleClass: _vehicleClass,
      payMethod: 'mobile_money',
    );
    if (!mounted) return;
    if (!res.ok) {
      setState(() => _saving = false);
      return _message('Could not book the collection (${res.error}). Try again.');
    }
    final ref = '${res.body['ref'] ?? ''}';
    final due = ((res.body['total_zmw'] as num?) ?? 0).toDouble();
    if (!mounted) return;
    setState(() => _saving = false);
    if (_payment == 'Mobile money' && DropOffApi.enabled && store.linked && due > 0) {
      _message('Collection $ref saved. Approve the momo prompt for K${due.toStringAsFixed(2)}.');
      final pay = await DropOffApi.pay(jobRef: ref, phone: store.linkedPhone ?? _recipientPhone.text, idempotencyKey: 'pay-$ref');
      if (!mounted) return;
      if (pay.ok) {
        final paymentId = '${pay.body['payment_id']}';
        var status = 'pending';
        for (var attempt = 0; attempt < 20 && status == 'pending'; attempt++) {
          await Future<void>.delayed(const Duration(seconds: 2));
          status = await DropOffApi.paymentStatus(paymentId) ?? 'pending';
        }
        if (!mounted) return;
        _message(switch (status) {
          'success' => 'Paid â€” a rider will collect from $_courierId point.',
          'failed' => 'The mobile-money prompt was rejected â€” check your momo balance and try again, or contact DropOff support.',
          _ => 'Payment still pending â€” the rider sweep confirms when your money lands.',
        });
      }
    } else {
      _message(due > 0
          ? 'Collection $ref booked â€” approve the prepayment prompt sent to this number.'
          : 'Collection $ref booked â€” your plan covers the DropOff leg.');
    }
    if (!mounted) return;
    Navigator.of(context).pop();
    AnalyticsService.instance.track(
      feature: 'collections', action: 'submit', context: 'collections_form',
      meta: {
        'parcels': _parcels,
        'vehicle_class': _vehicleClass,
        'pay_method': _payment,
        'courier_id': _courierId,
      },
    );
  }

  void _message(String text) => AppToast.show(context, text);

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    if (!store.linked) {
      return Scaffold(
        appBar: AppBar(title: const Text('Book a collection', style: TextStyle(fontWeight: FontWeight.w900))),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.lock_outline, size: 44, color: AppColors.muted),
              const SizedBox(height: 16),
              const Text('Sign up to book a collection', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900), textAlign: TextAlign.center),
              const SizedBox(height: 8),
              const Text('Collect a parcel from a courier point and we deliver it to the door.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted, height: 1.45)),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AccountScreen())),
                icon: const Icon(Icons.person_add_alt_1),
                label: const Text('Sign up / Sign in'),
              ),
            ]),
          ),
        ),
      );
    }
    final courier = couriers.firstWhere((c) => c.id == _courierId, orElse: () => couriers.first);
    final points = courier.branchesNear('Lusaka').map((b) => b.name).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Book a collection', style: TextStyle(fontWeight: FontWeight.w900))),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 24), children: [
        const Text('Where is the parcel waiting?', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: -0.4)),
        const SizedBox(height: 4),
        const Text('Your parcel already arrived at the courier in Lusaka. A rider picks it up and brings it to your recipientâ€™s door.', style: TextStyle(color: AppColors.muted, fontSize: 12.5, height: 1.4)),
        const SizedBox(height: 16),
        const Text('Courier', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        for (final c in couriers)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: InkWell(
              borderRadius: BorderRadius.circular(15),
              onTap: () => setState(() => _courierId = c.id),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _courierId == c.id ? const Color(0xFFE9F0EB) : Colors.white,
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: _courierId == c.id ? AppColors.forest : AppColors.line, width: _courierId == c.id ? 1.5 : 1),
                ),
                child: Row(children: [
                  CourierAvatar(courier: c, size: 38),
                  const SizedBox(width: 10),
                  Expanded(child: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5))),
                  Icon(_courierId == c.id ? Icons.check_circle : Icons.circle_outlined, color: _courierId == c.id ? AppColors.forest : AppColors.line),
                ]),
              ),
            ),
          ),
        const SizedBox(height: 8),
        TextField(
          controller: _point,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            labelText: 'Collection point',
            hintText: points.isEmpty ? 'e.g. Longacres counter' : points.first,
            prefixIcon: const Icon(Icons.location_on_outlined),
            helperText: points.isEmpty ? 'Ask the courier which counter holds it.' : 'Popular: ${points.take(2).join(' Â· ')}',
            suffixIcon: TextButton(onPressed: _aiBusy ? null : () => _aiTidy(_point), child: _aiBusy ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('AI tidy')),
          ),
        ),
        const SizedBox(height: 20),
        const Text('Deliver to', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
        const SizedBox(height: 10),
        TextField(controller: _recipientName, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Recipient name', prefixIcon: Icon(Icons.person_pin_circle_outlined))),
        const SizedBox(height: 10),
        TextField(controller: _recipientPhone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Recipient mobile number', hintText: '0961234567', prefixIcon: Icon(Icons.phone_outlined))),
        const SizedBox(height: 10),
        TextField(controller: _address, minLines: 2, maxLines: 3, textCapitalization: TextCapitalization.sentences, decoration: InputDecoration(labelText: 'Door address', hintText: 'e.g. 12 Kabwata Site, near the shops', prefixIcon: const Icon(Icons.house_outlined), alignLabelWithHint: true, suffixIcon: TextButton(onPressed: _aiBusy ? null : () => _aiTidy(_address), child: _aiBusy ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('AI tidy')))),
        const SizedBox(height: 10),
        TextField(controller: _description, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(labelText: 'Parcel contents (optional)', hintText: 'e.g. One carton of shoes', prefixIcon: Icon(Icons.inventory_2_outlined))),
        const SizedBox(height: 10),
        TextField(controller: _senderName, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Your name (optional)', prefixIcon: Icon(Icons.person_outline))),
        const SizedBox(height: 16),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: DropdownButtonFormField<String>(
            initialValue: _vehicleClass,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Vehicle', prefixIcon: Icon(Icons.directions)),
            items: _vehicleLabels.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value, maxLines: 1, overflow: TextOverflow.ellipsis))).toList(),
            onChanged: (v) { if (v != null) { _vehicleClass = v; if (_parcels > _maxParcels[v]!) _parcels = _maxParcels[v]!; setState(() {}); } },
          )),
          const SizedBox(width: 12),
          Expanded(child: DropdownButtonFormField<int>(
            initialValue: _parcels.clamp(1, _maxParcels[_vehicleClass]!),
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Parcels', prefixIcon: Icon(Icons.inventory)),
            items: List.generate(_maxParcels[_vehicleClass]!, (i) => i + 1).map((i) => DropdownMenuItem(value: i, child: Text('$i', maxLines: 1))).toList(),
            onChanged: (v) { if (v != null) setState(() => _parcels = v); },
          )),
        ]),
        const SizedBox(height: 18),
        const Text('Collection window', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        for (final entry in _windows.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: InkWell(
              borderRadius: BorderRadius.circular(13),
              onTap: () {
                if (_slotClosed(entry.key)) return _message('${entry.value} closed â€” the counter canâ€™t hand over in time. Pick another window.');
                setState(() => _window = entry.key);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
                decoration: BoxDecoration(
                  color: _window == entry.key ? const Color(0xFFE9F0EB) : Colors.white,
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(color: _window == entry.key ? AppColors.forest : AppColors.line, width: _window == entry.key ? 1.5 : 1),
                ),
                child: Row(children: [
                  Icon(_slotClosed(entry.key) ? Icons.lock_outline : Icons.schedule_rounded, size: 18, color: AppColors.muted),
                  const SizedBox(width: 10),
                  Expanded(child: Text(_slotClosed(entry.key) ? '${entry.value} â€” closed' : entry.value, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: _slotClosed(entry.key) ? AppColors.muted : AppColors.ink))),
                  if (_window == entry.key && !_slotClosed(entry.key)) const Icon(Icons.check_circle, size: 18, color: AppColors.forest),
                ]),
              ),
            ),
          ),
        // Next-day sweep: always open, for when every today window has closed.
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: InkWell(
            borderRadius: BorderRadius.circular(13),
            onTap: () => setState(() => _window = 'tomorrow:06:00'),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
              decoration: BoxDecoration(
                color: _window == 'tomorrow:06:00' ? const Color(0xFFE9F0EB) : Colors.white,
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: _window == 'tomorrow:06:00' ? AppColors.forest : AppColors.line, width: _window == 'tomorrow:06:00' ? 1.5 : 1),
              ),
              child: Row(children: [
                const Icon(Icons.event_repeat_rounded, size: 18, color: AppColors.muted),
                const SizedBox(width: 10),
                Expanded(child: Text('Tomorrow 6:00 â€“ 7:30 AM', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: _window == 'tomorrow:06:00' ? AppColors.forest : AppColors.ink))),
                if (_window == 'tomorrow:06:00') const Icon(Icons.check_circle, size: 18, color: AppColors.forest),
              ]),
            ),
          ),
        ),
        const SizedBox(height: 10),
        const Text('Subscription code', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        TextField(
          controller: _promoCode,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
            labelText: 'Plan / promo code (optional)',
            hintText: 'e.g. DROP-XXXX-XXXX (activates your pack on this number before you pay the rider)',
            prefixIcon: Icon(Icons.redeem_rounded),
          ),
        ),
        const SizedBox(height: 10),
        const Text('Payment', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Builder(builder: (context) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              color: AppColors.forest.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.forest.withValues(alpha: 0.35)),
            ),
            child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.phone_android, color: AppColors.forest, size: 18),
                SizedBox(width: 8),
                Expanded(child: Text('Mobile money â€” prepayment at booking', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13))),
              ]),
              SizedBox(height: 3),
              Text('Approve the momo prompt on this number and a rider collects for you; no cash, riders never handle the money.',
                  style: TextStyle(color: AppColors.muted, fontSize: 11.5, height: 1.4)),
            ]),
          );
        }),
        const SizedBox(height: 6),
        const Text('Rider fee from K45 Â· processing fee added. The courierâ€™s own charges are paid to them directly â€” we only run the local collection.', style: TextStyle(color: AppColors.muted, fontSize: 11.5, height: 1.4)),
        const SizedBox(height: 18),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: _saving
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Book collection'),
        ),
      ]),
    );
  }
}
