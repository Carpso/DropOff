import 'dart:async';

import '../ui/proof_upload_overlay.dart';
import '../ui/app_toast.dart';
import '../ui/receipt_viewer.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../data/catalog.dart';
import '../data/dropoff_api.dart';
import '../data/analytics_service.dart';
import '../main.dart';
import '../state/app_store.dart';
import '../ui/app_sheet.dart';
import '../ui/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/help_sheet.dart';
import 'account_screen.dart';
import '../ui/app_spinner.dart';
import '../services/step_sounds.dart';

/// Collect a parcel from a courier's point in Lusaka and deliver it to the
/// recipient's door. No counter fare and no branch picking — the parcel is
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
  final _declaredValue = TextEditingController();
  final _senderName = TextEditingController();
  final _promoCode = TextEditingController();
  String _window = '10:00';
  final String _payment = 'Mobile money';
  // Vehicle is SERVER-DECIDED from parcel size + this one preference.
  String get _vehicleClass => _size == 'large' ? 'car' : 'motorcycle';
  String _size = 'medium'; // drives the server's size-aware motorcycle cap
  int _parcels = 1;
  bool _saving = false;
  bool _aiBusy = false;
  // Retry state — set when the momo prompt fails so the form shows a Pay now button.
  String? _payRetryRef;
  double? _payRetryDue;
  // Proof-of-payment receipt the rider shows at the courier depot to collect
  // the goods. The rider later photographs the collected items at pickup.
  String? _receiptUrl;
  bool _receiptBusy = false;
  String? _pointError, _recipientNameError, _recipientPhoneError, _addressError, _declaredValueError;

  /// ✨ Tidy — normalises a free-text address (best-effort; never blocks).
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
    '06:00': '5:30 – 7:30 AM',
    '10:00': '10:00 – 11:30 AM',
    '14:00': '2:00 – 3:30 PM',
  };
  static const Map<String, String> _cutoffs = {'06:00': '05:30', '10:00': '09:30', '14:00': '13:30'};
  static const Map<String, int> _motorcycleParcelCap = {'small': 10, 'medium': 5, 'large': 1};
  static int _parcelCapFor(String vehicleClass, String size) =>
      vehicleClass == 'motorcycle' ? (_motorcycleParcelCap[size] ?? 5) : 9999;
  static const Map<String, String> _sizeLabels = {
    'small': 'Small (0–5kg)',
    'medium': 'Medium (5–15kg)',
    'large': 'Large (15kg+)',
  };

  @override
  void dispose() {
    for (final c in [_point, _recipientName, _recipientPhone, _address, _description, _declaredValue, _senderName, _promoCode]) {
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

  /// Capture the receipt proving the goods are paid for. The rider shows this
  /// full-screen at the depot counter before collecting the item. Offers
  /// Camera or Gallery — customers re-photograph the sender's receipt.
  Future<void> _pickReceipt() async {
    if (_receiptBusy) return;
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Receipt for the goods to collect', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
          const SizedBox(height: 4),
          const Text('Photograph the payment receipt from the sender — the rider shows it in full at the courier counter.', style: TextStyle(fontSize: 11.5, color: AppColors.muted, height: 1.35)),
          const SizedBox(height: 14),
          ...[
            (ImageSource.camera, const Icon(Icons.camera_alt_outlined), 'Camera'),
            (ImageSource.gallery, const Icon(Icons.photo_library_outlined), 'Gallery'),
          ].map((s) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            ListTile(
              leading: s.$2,
              title: Text(s.$3, style: const TextStyle(fontWeight: FontWeight.w800)),
              onTap: () => Navigator.of(context).pop(s.$1),
            ),
          ])),
          const SizedBox(height: 4),
          OutlinedButton(onPressed: () => Navigator.of(context).pop(null), child: const Text('Cancel')),
        ]),
      ),
    );
    if (source == null || !mounted) return;
    final picked = await ImagePicker().pickImage(source: source, maxWidth: 1600, imageQuality: 82);
    if (picked == null || !mounted) return;
    setState(() => _receiptBusy = true);
    final bytes = await picked.readAsBytes();
    DateTime? capturedAt;
    try { capturedAt = await picked.lastModified(); } catch (_) {}
    if (!mounted) return;
    final up = await ProofUploadOverlay.run(
      context,
      title: 'Securing payment receipt',
      task: DropOffApi.uploadImage(bytes, picked.name.isNotEmpty ? picked.name : 'receipt.jpg', kind: 'receipt', capturedAt: capturedAt),
    );
    if (!mounted) return;
    setState(() => _receiptBusy = false);
    if (!up.ok) return AppToast.error(context, 'Could not upload the receipt. Try again.');
    final url = '${up.body['url'] ?? ''}';
    if (url.isEmpty) return AppToast.error(context, 'The receipt upload returned no image. Try again.');
    setState(() => _receiptUrl = url);
    await StepSounds.stepDone(); // receipt step complete (owner request 2026-11-20)
    if (!mounted) return;
    AppToast.show(context, 'Receipt added — the rider will show it at the depot counter.');
  }

  Future<void> _submit() async {
    final store = AppScope.of(context);
    final serverCourierId = courierServerIdOf(_courierId);
    if (serverCourierId == null) {
      return _message('That courier is not available for collection yet — pick Platinum, Mercury, DHL, One World, Rovert, Icypeed or Falcon.');
    }
    final pointErr = !_point.text.trim().isNotEmpty ? 'Enter the courier point where the item is waiting.' : null;
    final recNameErr = _recipientName.text.trim().length < 2 ? 'Enter the recipient name.' : null;
    final recPhoneErr = !RegExp(r'^(?:\+?260|0)?(5[0-9]|7[0-9]|9[1-9])\d{7}$').hasMatch(_recipientPhone.text.replaceAll(RegExp(r'[\s-]'), '')) ? 'Enter a valid Zambian mobile number.' : null;
    final addrErr = _address.text.trim().length < 4 ? 'Enter the door address for delivery.' : null;
    final declaredValueZmw = double.tryParse(_declaredValue.text.replaceAll(RegExp(r'[^0-9.]'), ''));
    final valErr = (declaredValueZmw == null || declaredValueZmw <= 0) ? 'Enter the item value in ZMW.' : null;
    setState(() { _pointError = pointErr; _recipientNameError = recNameErr; _recipientPhoneError = recPhoneErr; _addressError = addrErr; _declaredValueError = valErr; });
    if ([pointErr, recNameErr, recPhoneErr, addrErr, valErr].any((e) => e != null)) {
      return _message('Check the highlighted fields before booking the collection.');
    }
    // Plan code entry: pre-redeem before the collection so the plan covers the
    // rider fee for this booking without a separate step.
    final promo = _promoCode.text.trim().toUpperCase();
    // FRIEND referral codes are PAYG promos for pickup/collection bookings.
    // Anything else is treated as a subscription pack code as before.
    final String? promoCode = promo.startsWith('FRIEND') ? promo : null;
    if (promo.isNotEmpty && promoCode == null) {
      try {
        final red = await DropOffApi.redeemPackCode(promo);
        if (!red.ok) {
          _message('Plan code not recognised — continuing as pay-as-you-go.');
        }
      } catch (_) { /* best-effort */ }
    }
    setState(() => _saving = true);
    final res = await DropOffApi.createCollection(
      courierId: serverCourierId,
      point: _point.text.trim(),
      recipientName: _recipientName.text.trim(),
      recipientPhone: _recipientPhone.text.trim(),
      destAddress: _address.text.trim(),
      pickupWindow: _window,
      senderName: _senderName.text.trim().isEmpty ? null : _senderName.text.trim(),
      description: _description.text.trim().isEmpty ? null : _description.text.trim(),
      parcels: _parcels,
      vehicleClass: _vehicleClass,
      promoCode: promoCode,
      payMethod: 'mobile_money',
      parcelSize: _size,
      collectionReceiptUrl: _receiptUrl,
      declaredValueZmw: declaredValueZmw,
    );
    if (!mounted) return;
    if (!res.ok) {
      setState(() => _saving = false);
      // An unpaid depot fare is a hard stop on new jobs. Offer the prompt here
      // so it is never a dead end (owner bug 2026-11-23).
      if (res.error == 'counter_fare_due') {
        // Verify before prompting — the fare may have just been waived by an
        // admin while this form was open (owner bug 2026-11-23).
        unawaited(store.counterFareStillDue().then((stillDue) async {
          if (!mounted) return;
          if (!stillDue) {
            _message('Your depot fare is cleared — tap Book collection again.');
            return;
          }
          _offerCounterFareSettlement(
            appStore: store,
            ref: '${res.body['due_ref'] ?? ''}',
            amount: ((res.body['due_amount_zmw'] as num?) ?? 0).toDouble(),
          );
        }));
        return;
      }
      final detail = res.body['detail'];
      return _message(detail is String && detail.isNotEmpty ? detail : 'Could not book the collection. Try again.');
    }
    final ref = '${res.body['ref'] ?? ''}';
    final due = ((res.body['total_zmw'] as num?) ?? 0).toDouble();
    final courierName = couriers.firstWhere((c) => c.id == _courierId, orElse: () => couriers.first).name;
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
          final st = await DropOffApi.paymentStatus(paymentId);
          status = st.$1 ?? 'pending';
        }
        if (!mounted) return;
        _message(switch (status) {
          'success' => 'Paid — a rider will collect from $courierName point.',
          'failed' => 'Payment failed — tap Pay now below to retry the prompt.',
          _ => 'Prompt still pending — approve it on your phone, or tap Pay now below.',
        });
        // A pending prompt is NORMAL — keep the retry control reachable and
        // stay on this screen instead of telling the rider to tap a button
        // that doesn't exist (owner audit 2026-11-21).
        if (status != 'success' && mounted) {
          setState(() { _payRetryRef = ref; _payRetryDue = due; });
        }
      } else {
        _message(due > 0
            ? 'Collection $ref booked — approve the prepayment prompt sent to this number.'
            : 'Collection $ref booked — your plan covers the DropOff leg.');
      }
    } else if (due <= 0) {
      _message('Collection $ref booked — your plan covers the DropOff leg.');
    } else {
      _message('Collection $ref booked — approve the prompt in your momo app.');
    }
    if (!mounted) return;
    // Only leave the screen when there is nothing left to pay.
    if (_payRetryRef == null) {
      AppScope.of(context).syncJobsFromServer();
      Navigator.of(context).pop();
    } else {
      AppScope.of(context).syncJobsFromServer();
    }
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

  /// Pay the depot counter fare that is blocking new jobs, right from the
  /// collection form. Keeps the form filled so she can retry immediately.
  void _offerCounterFareSettlement({
    required AppStore appStore,
    required String ref,
    required double amount,
  }) {
    if (ref.isEmpty) {
      _message('You still owe a depot counter fare — open Bookings, pay the receipt, then book again.');
      return;
    }
    showAppSheet<void>(context, child: Builder(builder: (ctx) {
      var busy = false;
      return StatefulBuilder(builder: (ctx, setSheetState) {
        Future<void> pay() async {
          setSheetState(() => busy = true);
          final result = await appStore.settleCounterFare(
            jobRef: ref,
            phone: appStore.linkedPhone,
          );
          if (!ctx.mounted) return;
          setSheetState(() => busy = false);
          if (result.isSuccess) {
            Navigator.pop(ctx);
            _message('Counter fare cleared — tap Book collection again.');
          } else {
            AppToast.show(ctx, result.message);
          }
        }

        return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(color: AppColors.amber.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.receipt_long_outlined, color: Color(0xFF7B5710)),
            ),
            const SizedBox(width: 12),
            const Expanded(child: Text('Settle your depot fare first', style: AppType.subhead)),
          ]),
          const SizedBox(height: 14),
          Text(
            amount > 0
                ? 'Your rider fronted K${amount.toStringAsFixed(2)} for the depot counter fare on $ref. Pay it now — one momo prompt — and you can book again right away.'
                : 'Your rider fronted the depot counter fare on $ref. Pay it now and you can book again right away.',
            style: const TextStyle(fontSize: 14, height: 1.45, color: AppColors.ink),
          ),
          const SizedBox(height: 18),
          SizedBox(width: double.infinity, child: FilledButton(
            onPressed: busy ? null : pay,
            child: busy
                ? const AppLogoSpinner(size: 18)
                : Text(amount > 0 ? 'Pay K${amount.toStringAsFixed(2)} now' : 'Pay the courier bill now'),
          )),
          const SizedBox(height: 6),
          SizedBox(width: double.infinity, child: OutlinedButton.icon(
            icon: const Icon(Icons.refresh, size: 15),
            onPressed: busy ? null : () async {
              setSheetState(() => busy = true);
              final cleared = !await appStore.counterFareStillDue();
              if (!ctx.mounted) return;
              setSheetState(() => busy = false);
              if (cleared) {
                Navigator.pop(ctx);
                _message('Fare already settled — tap Book collection again.');
              } else {
                AppToast.show(ctx, 'Still due on the server — pay when ready, or contact support if you already settled it.');
              }
            },
            label: const Text('Already paid — check again'),
          )),
          const SizedBox(height: 6),
          SizedBox(width: double.infinity, child: TextButton(
            onPressed: busy ? null : () => Navigator.pop(ctx),
            child: const Text('Not now'),
          )),
        ]);
      });
    }));
  }

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
              const Text('Collect an item from a courier point and deliver it to the door.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted, height: 1.45)),
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
      backgroundColor: Colors.white,
      appBar: AppBar(title: const Text('Book a collection', style: TextStyle(fontWeight: FontWeight.w900))),
      body: Column(children: [
        Expanded(child: RefreshIndicator(
        onRefresh: () async {
          await AppScope.of(context).syncJobsFromServer();
        },
        child: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 16), children: [
        const Text('Where are your items waiting?', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: -0.4)),
        const SizedBox(height: 4),
        const Text('Your items are already at the courier depot. A rider brings them to the recipient.', style: TextStyle(color: AppColors.ink, fontSize: 12.5, height: 1.4)),
        const SizedBox(height: 16),
        const Text('Courier', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Builder(builder: (context) {
          final availableCouriers = couriers.where((c) => !c.isClosedOnCat()).toList();
          if (availableCouriers.isEmpty) {
            return Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: AppColors.canvas, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.line)),
              child: const Row(children: [
                Icon(Icons.event_busy_outlined, color: AppColors.muted),
                SizedBox(width: 10),
                Expanded(child: Text('No depots are taking sweeps today. Please check back on the next open day.', style: TextStyle(fontSize: 12.5, height: 1.4, color: AppColors.muted))),
              ]),
            );
          }
          if (!availableCouriers.any((c) => c.id == _courierId)) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _courierId = availableCouriers.first.id);
            });
          }
          return Column(children: [
            for (final c in availableCouriers)
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
                      Expanded(child: Text(c.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5))),
                      Icon(_courierId == c.id ? Icons.check_circle : Icons.circle_outlined, color: _courierId == c.id ? AppColors.forest : AppColors.line),
                    ]),
                  ),
                ),
              ),
          ]);
        }),
        const SizedBox(height: 8),
        TextField(
          controller: _point,
          textCapitalization: TextCapitalization.words,
          onChanged: (_) { if (_pointError != null) setState(() => _pointError = null); },
          decoration: InputDecoration(
            labelText: 'Collection point',
            hintText: points.isEmpty ? 'e.g. Longacres counter' : points.first,
            prefixIcon: const Icon(Icons.location_on_outlined),
            helperText: points.isEmpty ? 'Ask the courier which counter holds it.' : 'Popular: ${points.take(2).join(' · ')}',
            errorText: _pointError,
            suffixIcon: TextButton(onPressed: _aiBusy ? null : () => _aiTidy(_point), child: _aiBusy ? const AppLogoSpinner(size: 14) : const Text('✨ Tidy')),
          ),
        ),
        const SizedBox(height: 20),
        const Text('Deliver to', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
        const SizedBox(height: 10),
        TextField(controller: _recipientName, textCapitalization: TextCapitalization.words, onChanged: (_) { if (_recipientNameError != null) setState(() => _recipientNameError = null); }, decoration: InputDecoration(labelText: 'Recipient name', errorText: _recipientNameError, prefixIcon: const Icon(Icons.person_pin_circle_outlined))),
        const SizedBox(height: 10),
        TextField(controller: _recipientPhone, keyboardType: TextInputType.phone, onChanged: (_) { if (_recipientPhoneError != null) setState(() => _recipientPhoneError = null); }, decoration: InputDecoration(labelText: 'Recipient mobile number', hintText: '0961234567', errorText: _recipientPhoneError, prefixIcon: const Icon(Icons.phone_outlined))),
        const SizedBox(height: 10),
        TextField(controller: _address, minLines: 2, maxLines: 3, textCapitalization: TextCapitalization.sentences, onChanged: (_) { if (_addressError != null) setState(() => _addressError = null); }, decoration: InputDecoration(labelText: 'Door address', hintText: 'e.g. 12 Kabwata Site, near the shops', prefixIcon: const Icon(Icons.house_outlined), alignLabelWithHint: true, errorText: _addressError, suffixIcon: TextButton(onPressed: _aiBusy ? null : () => _aiTidy(_address), child: _aiBusy ? const AppLogoSpinner(size: 14) : const Text('AI tidy')))),
        const SizedBox(height: 10),
        TextField(controller: _description, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(labelText: 'Parcel contents (optional)', hintText: 'e.g. One carton of shoes', prefixIcon: Icon(Icons.inventory_2_outlined))),
        const SizedBox(height: 10),
        TextField(
          controller: _declaredValue,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (_) { if (_declaredValueError != null) setState(() => _declaredValueError = null); },
          decoration: InputDecoration(
            labelText: 'Declared value (ZMW)',
            hintText: 'What the item is worth, e.g. 450',
            errorText: _declaredValueError,
            prefixIcon: const Icon(Icons.payments_outlined),
          ),
        ),
        const Padding(
          padding: EdgeInsets.only(top: 4, bottom: 2),
          child: Text('Required — recorded on the receipt and waybill for this collection.', style: TextStyle(fontSize: 12, color: AppColors.muted)),
        ),
        const SizedBox(height: 10),
        TextField(controller: _senderName, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Your name (optional)', prefixIcon: Icon(Icons.person_outline))),
        const SizedBox(height: 14),
        // COLLECTION RECEIPT (owner 2026-11-20): proof of payment for the goods
        // at the courier depot. The rider shows this in full screen at the
        // counter, then photographs the items they collect.
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _receiptUrl != null ? AppColors.amberSoft : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _receiptUrl != null ? AppColors.amber : AppColors.line),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.receipt_long_outlined,
                  color: _receiptUrl != null ? AppColors.forest : AppColors.muted),
              const SizedBox(width: 9),
              const Expanded(child: Text('Receipt for the goods to collect',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5))),
            ]),
            const SizedBox(height: 5),
            const Text('Photograph the payment receipt from the sender. The rider shows it at the counter before collecting your item.',
                style: TextStyle(fontSize: 11.5, color: AppColors.muted, height: 1.35)),
            const SizedBox(height: 10),
            if (_receiptUrl != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                // Tapping the preview OPENS it — it never deletes the receipt.
                child: GestureDetector(
                  onTap: () => ReceiptViewer.show(context,
                      path: _receiptUrl!, title: 'Collection receipt'),
                  // CONTAIN keeps the burned-in DropOff timestamp visible.
                  child: ColoredBox(
                    color: AppColors.line.withValues(alpha: 0.18),
                    child: AuthedImage(ReceiptViewer.resolve(_receiptUrl!),
                        height: 120, width: double.infinity, fit: BoxFit.contain),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Row(children: [
                Expanded(child: OutlinedButton.icon(
                  onPressed: () => ReceiptViewer.show(context,
                      path: _receiptUrl!, title: 'Collection receipt', ref: _receiptUrl!),
                  icon: const Icon(Icons.visibility_outlined, size: 15),
                  label: const Text('View full screen'),
                )),
                const SizedBox(width: 8),
                Expanded(child: OutlinedButton.icon(
                  onPressed: () => ReceiptViewer.share(context, _receiptUrl!, ''),
                  icon: const Icon(Icons.ios_share, size: 15),
                  label: const Text('Share receipt'),
                )),
              ]),
              const SizedBox(height: 8),
            ],
            OutlinedButton.icon(
              onPressed: _receiptBusy ? null : _pickReceipt,
              icon: _receiptBusy
                  ? const AppLogoSpinner(size: 16)
                  : Icon(_receiptUrl != null ? Icons.camera_alt : Icons.add_a_photo),
              label: Text(_receiptBusy
                  ? 'Uploading receipt…'
                  : _receiptUrl != null ? 'Retake receipt' : 'Add receipt photo'),
            ),
          ]),
        ),
        const SizedBox(height: 16),
        // VEHICLE IS SERVER-DECIDED: motorcycle by default, car automatically
        // for large or over-cap items. No vehicle question for the sender.
        _vehicleClass == 'motorcycle'
            ? DropdownButtonFormField<int>(
                initialValue: _parcels.clamp(1, _parcelCapFor(_vehicleClass, _size)),
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Parcels', prefixIcon: Icon(Icons.inventory)),
                items: List.generate(_parcelCapFor(_vehicleClass, _size), (i) => i + 1).map((i) => DropdownMenuItem(value: i, child: Text('$i'))).toList(),
                onChanged: (v) { if (v != null) setState(() => _parcels = v); },
              )
            // Cars, vans and trucks: no practical limit — type any number.
            : TextFormField(
                initialValue: '$_parcels',
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Parcels (no limit)', hintText: '1', prefixIcon: Icon(Icons.inventory)),
                onChanged: (v) {
                  final n = int.tryParse(v.replaceAll(RegExp(r'[^0-9]'), ''));
                  setState(() => _parcels = (n == null || n < 1) ? 1 : n);
                },
              ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: _size,
          decoration: const InputDecoration(labelText: 'Item size', prefixIcon: Icon(Icons.straighten_outlined)),
          items: _sizeLabels.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
          onChanged: (v) { if (v != null) { final cap = _parcelCapFor(_vehicleClass, v); setState(() { _size = v; if (_parcels > cap) _parcels = cap; }); } },
        ),
        const SizedBox(height: 18),
        const Text('Collection window', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        for (final entry in _windows.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                if (_slotClosed(entry.key)) return _message('${entry.value} closed — the counter can’t hand over in time. Pick another window.');
                setState(() => _window = entry.key);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
                decoration: BoxDecoration(
                  color: _window == entry.key ? const Color(0xFFE9F0EB) : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _window == entry.key ? AppColors.forest : AppColors.line, width: _window == entry.key ? 1.5 : 1),
                ),
                child: Row(children: [
                  Icon(_slotClosed(entry.key) ? Icons.lock_outline : Icons.schedule_rounded, size: 18, color: AppColors.muted),
                  const SizedBox(width: 10),
                  Expanded(child: Text(_slotClosed(entry.key) ? '${entry.value} — closed' : entry.value, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: _slotClosed(entry.key) ? AppColors.muted : AppColors.ink))),
                  if (_window == entry.key && !_slotClosed(entry.key)) const Icon(Icons.check_circle, size: 18, color: AppColors.forest),
                ]),
              ),
            ),
          ),
        // Next-day sweep: always open, for when every today window has closed.
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() => _window = 'tomorrow:06:00'),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
              decoration: BoxDecoration(
                color: _window == 'tomorrow:06:00' ? const Color(0xFFE9F0EB) : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _window == 'tomorrow:06:00' ? AppColors.forest : AppColors.line, width: _window == 'tomorrow:06:00' ? 1.5 : 1),
              ),
              child: Row(children: [
                const Icon(Icons.event_repeat_rounded, size: 18, color: AppColors.muted),
                const SizedBox(width: 10),
                Expanded(child: Text('Tomorrow 5:30 – 7:30 AM', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: _window == 'tomorrow:06:00' ? AppColors.forest : AppColors.ink))),
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
        const Padding(
          padding: EdgeInsets.only(top: 4, left: 4),
          child: Text('Got a plan? Your code is in Account → Redeem a plan code, or on the receipt from the agent where you bought it. Leaving this blank pays per collection.',
              style: TextStyle(fontSize: 11, color: AppColors.muted, height: 1.3)),
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
                Expanded(child: Text('Mobile money — prepayment at booking', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13))),
              ]),
              SizedBox(height: 3),
              Text('Approve the momo prompt on this number and a rider collects for you; no cash, riders never handle the money.',
                  style: AppType.caption),
            ]),
          );
        }),
        // Failed prepayment → keep the sheet open and re-send the prompt here.
        if (_payRetryRef != null) ...[
          const SizedBox(height: 10),
          FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            onPressed: () async {
              final ref = _payRetryRef!;
              setState(() => _saving = true);
              final pay = await DropOffApi.pay(jobRef: ref, phone: store.linkedPhone ?? _recipientPhone.text, idempotencyKey: 'pay-$ref-retry');
              if (!mounted) return;
              setState(() => _saving = false);
              if (!pay.ok) return _message('Pay now failed — check your momo balance and try again.');
              // The POST returns a payment_id, not a status — poll the worker
              // like the first-submit path does or approval is never seen.
              final paymentId = '${pay.body['payment_id'] ?? ''}';
              var retryStatus = 'pending';
              if (paymentId.isNotEmpty) {
                for (var attempt = 0; attempt < 20 && retryStatus == 'pending'; attempt++) {
                  await Future<void>.delayed(const Duration(seconds: 2));
                  if (!mounted) return;
                  final st = await DropOffApi.paymentStatus(paymentId);
                  retryStatus = st.$1 ?? 'pending';
                }
              }
              if (!mounted) return;
              final retryCourier = couriers.firstWhere((c) => c.id == _courierId, orElse: () => couriers.first).name;
              _message(retryStatus == 'success'
                  ? 'Paid — a rider will collect from $retryCourier point.'
                  : retryStatus == 'failed'
                      ? 'Payment failed — check your momo balance and try again.'
                      : 'Prompt sent — approve it on your phone. The rider sweep dispatches when the money lands.');
              if (retryStatus == 'success') setState(() => _payRetryRef = null);
            },
            icon: const Icon(Icons.payments_outlined),
            label: Text(_payRetryDue != null
                ? 'Pay now K${_payRetryDue!.toStringAsFixed(2)}'
                : 'Pay now'),
          ),
        ],
        const SizedBox(height: 6),
        const Row(children: [
          Expanded(child: Text('Approve the momo prompt on this number. No cash, no hidden charges.', style: AppType.caption)),
          HelpIconButton(topic: HelpTopic.courierFare),
        ]),
        const SizedBox(height: 16),
        Card(
          color: AppColors.forest.withValues(alpha: 0.04),
          child: const Padding(
            padding: EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [Icon(Icons.route_outlined, size: 18, color: AppColors.forest), SizedBox(width: 8), Text('What happens next', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13))]),
              SizedBox(height: 8),
              Text('1. Book the collection — a rider is assigned to your sweep slot.', style: TextStyle(fontSize: 12.5, height: 1.4)),
              SizedBox(height: 4),
              Text('2. Approve the momo prompt if payment is required.', style: TextStyle(fontSize: 12.5, height: 1.4)),
              SizedBox(height: 4),
              Text('3. The rider collects at the depot and delivers to the recipient.', style: TextStyle(fontSize: 12.5, height: 1.4)),
            ]),
          ),
        ),
      ],
      ),
      ),
      ),
      Container(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
        decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: AppColors.line))),
        child: SafeArea(top: false, child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('After booking: approve payment if needed, then track the collection in Bookings.', style: TextStyle(fontSize: 11.5, color: AppColors.muted, height: 1.3), textAlign: TextAlign.center),
          const SizedBox(height: 10),
          SizedBox(width: double.infinity, child: FilledButton(
            onPressed: _saving ? null : _submit,
            child: _saving ? const AppLogoSpinner(size: 22, color: Colors.white) : const Text('Book collection'),
          )),
        ])),
      ),
      ]),
    );
  }
}


