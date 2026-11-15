// ─────────────────────────────────────────────────────────────────────
// DROPOFF — ownership stamp (do not remove)
// :Godfrey Moses Kalambo:Carpso Solutions:0968551110.
// © 2026 Godfrey Moses Kalambo · Carpso Solutions · Lusaka, Zambia.
// All rights reserved — unauthorised copying, resale or rebranding of
// this source code is prohibited.
// ─────────────────────────────────────────────────────────────────────
import '../ui/app_toast.dart';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../data/catalog.dart';
import '../data/dropoff_api.dart';
import '../main.dart';
import '../models/booking.dart';
import '../ui/app_theme.dart';
import '../ui/thermal_print.dart';
import '../widgets/common.dart';

/// Owner directive (2026-11-12): the waybill title leads with the sender's
/// chosen DEPOT in its short form — "PLATINUM COUNTER WAYBILL" — not the
/// courier's full legal name, and never a generic "DEPOT COUNTER WAYBILL"
/// unless the courier is unknown.
String waybillDepotTitle(String courierId, String courierName) {
  var label = courierId.trim();
  if (label.isEmpty) label = courierName.trim().split(RegExp(r'\s+')).first;
  return label.isEmpty ? 'DEPOT COUNTER WAYBILL' : '${label.toUpperCase()} COUNTER WAYBILL';
}

/// Printable depot counter receipt / waybill.
///
/// A sender (or the rider acting for them) shows this screen to counter staff
/// at the courier depot. It renders every DropOff-leg fact a depot needs to
/// identify the parcel and lodge it: route, branch, sender/recipient, size,
/// parcels, vehicle class, DropOff references, declared value / cover status
/// and the fee split. The depot fare is paid at the counter — partner money
/// is never collected by DropOff.
class WaybillScreen extends StatefulWidget {
  final String bookingId;
  const WaybillScreen({super.key, required this.bookingId});

  @override
  State<WaybillScreen> createState() => _WaybillScreenState();
}

class _WaybillScreenState extends State<WaybillScreen> {
  final GlobalKey _captureKey = GlobalKey();

  bool _busy = false;
  bool _linkBusy = false;

  /// Server-side evidence payload (declared value / cover / partner waybill).
  /// Fetched once on open when the booking is dispatched and we are linked.
  Map<String, dynamic>? _evidence;
  bool _evidenceTried = false;

  /// Recipient tracking token/url — minted only on explicit user tap.
  String? _trackingToken;
  String? _trackingUrl;

  @override
  void initState() {
    super.initState();
    // AppScope.of() is not legal synchronously in initState — read the store
    // once the frame has landed instead.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadEvidence();
    });
  }

  Booking? _lookup() {
    final store = AppScope.of(context);
    final matches = store.bookings.where((item) => item.id == widget.bookingId);
    return matches.isEmpty ? null : matches.first;
  }

  Future<void> _loadEvidence() async {
    final booking = _lookup();
    final store = AppScope.of(context);
    if (booking == null || !booking.dispatched || !DropOffApi.enabled || !store.linked) {
      if (mounted) setState(() => _evidenceTried = true);
      return;
    }
    final data = await DropOffApi.jobEvidence(booking.serverRef!);
    if (!mounted) return;
    setState(() {
      _evidence = data;
      _evidenceTried = true;
    });
  }

  Future<void> _fetchTrackingLink() async {
    final booking = _lookup();
    if (booking == null || !booking.dispatched) return;
    setState(() => _linkBusy = true);
    final data = await DropOffApi.trackingLink(booking.serverRef!);
    if (!mounted) return;
    setState(() {
      _linkBusy = false;
      _trackingToken = data?['token'] as String?;
      _trackingUrl = data?['url'] as String?;
    });
    if (_trackingUrl == null) {
      AppToast.warning(context, 'Tracking link not ready yet — try again in a moment.');
    }
  }

  Future<Uint8List?> _capturePng() async {
    final boundary = _captureKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return null;
    final image = await boundary.toImage(pixelRatio: 3.0);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData?.buffer.asUint8List();
  }

  /// Portable Bluetooth thermal printer (ESC/POS 58mm). Android only —
  /// cheap receipt printers are classic-Bluetooth SPP devices.
  Future<void> _printBluetooth() async {
    final booking = _lookup();
    if (booking == null || _busy) return;
    final store = AppScope.of(context);
    final courier = courierById(booking.courierId);
    final rider = store.riders.where((item) => item.id == booking.riderId).firstOrNull;
    final branchInfo = _branchInfo(booking, courier);
    final hasBranch = booking.branch?.trim().isNotEmpty == true;
    final ref = booking.serverRef?.isNotEmpty == true ? booking.serverRef! : booking.reference;
    final title = waybillDepotTitle(courier.id, courier.name);
    final data = WaybillPrintData(
      title: title,
      ref: ref,
      route: (hasBranch ? '${booking.fromCity} → ${booking.branch}' : '${booking.fromCity} → ${booking.toCity}').toUpperCase(),
      courierLine: hasBranch ? '${courier.name} · onward to ${booking.toCity}' : courier.name,
      statusLabel: booking.timeline[booking.stage],
      from: booking.fromCity,
      to: booking.toCity,
      branch: hasBranch ? booking.branch! : (branchInfo != null ? branchInfo.name : ''),
      courier: '${courier.name} ($courier.id)',
      pickupAddress: booking.pickupAddress,
      pickupWindow: _ReceiptCard._pickupWindowLabel(booking),
      scheduledSlot: booking.pickupAt == null ? '' : DateFormat('d MMM yyyy · HH:mm').format(DateTime.tryParse(booking.pickupAt!) ?? DateTime.now()),
      size: booking.parcelSize.label,
      parcels: '${booking.parcels}',
      vehicle: _ReceiptCard._vehicleLabel(booking.vehicleClass),
      description: booking.description,
      declaredValue: _declaredValue() == null ? '' : kwacha(_declaredValue()!),
      cover: _coverSummary(),
      partnerWaybill: _partnerWaybill() ?? 'Not recorded yet — counter fills in at lodgement',
      riderFee: kwacha(booking.riderFee),
      lastMileFee: booking.lastMileFee > 0 ? kwacha(booking.lastMileFee) : '',
      promo: booking.promoCode == null ? '' : '${booking.promoCode}${booking.promoDiscount != null ? ' — saved ${kwacha(booking.promoDiscount!)} on the DropOff leg' : ''}',
      dropoffDue: '${kwacha(booking.dropoffLeg)} + processing — DropOff charge, never partner money',
      courierFare: _counterReceipt() != null
          ? (_counterReceipt()!.$2
              ? '${kwacha(_counterReceipt()!.$1)} — paid via DropOff (depot receipt in Bookings)'
              : '${kwacha(_counterReceipt()!.$1)} — depot receipt submitted; pay in Bookings to unlock it')
          : (booking.courierFare != null ? '${kwacha(booking.courierFare!)} — pay at the counter' : 'Confirmed at depot — pay at the counter'),
      paymentMethod: booking.paymentMethod,
      senderName: booking.senderName,
      senderPhone: booking.senderPhone,
      recipientName: booking.recipientName,
      recipientPhone: booking.recipientPhone,
      reference: booking.reference,
      dispatchRef: booking.serverRef?.isNotEmpty == true ? booking.serverRef! : '',
      bookedAt: DateFormat('d MMM yyyy · HH:mm').format(booking.createdAt),
      rider: rider?.name ?? booking.riderName ?? '',
      trackingUrl: _trackingUrl != null ? 'https://dropoff-api.godfreymoseskalambo.workers.dev/t/${_trackingUrl!}' : null,
    );
    await ThermalWaybill.print(context, data);
  }

  String _fileName(Booking booking) {
    final raw = (booking.serverRef?.isNotEmpty == true ? booking.serverRef! : booking.reference);
    final safe = raw.replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '-');
    return 'dropoff-waybill-$safe.png';
  }

  Future<void> _shareImage() async {
    final booking = _lookup();
    if (booking == null || _busy) return;
    setState(() => _busy = true);
    try {
      final bytes = await _capturePng();
      if (bytes == null) throw StateError('capture failed');
      final name = _fileName(booking);
      final track = _trackingUrl ?? '';
      await Share.shareXFiles(
        [XFile.fromData(bytes, mimeType: 'image/png', name: name)],
        subject: 'DropOff waybill ${booking.serverRef ?? booking.reference}',
        text: 'DropOff waybill ${booking.serverRef ?? booking.reference} — ${booking.fromCity} → ${booking.toCity}. Show at the depot counter.${track.isNotEmpty ? '\nTrack: https://dropoff-api.godfreymoseskalambo.workers.dev/t/$track' : ''}',
      );
    } catch (_) {
      if (mounted) {
        AppToast.error(context, 'Could not create the waybill image — try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _downloadImage() async {
    final booking = _lookup();
    if (booking == null || _busy) return;
    setState(() => _busy = true);
    try {
      final bytes = await _capturePng();
      if (bytes == null) throw StateError('capture failed');
      final name = _fileName(booking);
      if (kIsWeb) {
        // Web has no filesystem path — hand the file to the share sheet, which
        // offers the browser's save/download target.
        await Share.shareXFiles([XFile.fromData(bytes, mimeType: 'image/png', name: name)]);
        return;
      }
      Directory? dir;
      try {
        dir = await getDownloadsDirectory();
      } catch (_) {
        dir = null;
      }
      dir ??= await getApplicationDocumentsDirectory();
      final file = File('${dir.path}${Platform.pathSeparator}$name');
      await file.writeAsBytes(bytes, flush: true);
      AppToast.show(context, 'Waybill saved to ${file.path}');
    } catch (_) {
      // Filesystem save failed (permissions / platform) — fall back to the
      // share sheet so the user can still keep the image.
      try {
        final bytes = await _capturePng();
        if (bytes != null) {
          await Share.shareXFiles([
            XFile.fromData(bytes, mimeType: 'image/png', name: _fileName(booking)),
          ]);
          return;
        }
      } catch (_) {
        // fall through to snackbar below
      }
      AppToast.error(context, 'Could not save the waybill image — try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    final booking = _lookup();
    if (booking == null) {
      return const Scaffold(body: Center(child: Text('Booking not found')));
    }
    final courier = courierById(booking.courierId);
    final rider = store.riders.where((item) => item.id == booking.riderId).firstOrNull;
    final branchInfo = _branchInfo(booking, courier);
    final declaredValue = _declaredValue();
    final cover = _coverSummary();
    final partnerWaybill = _partnerWaybill();
    final counterReceipt = _counterReceipt();
    final dateFmt = DateFormat('d MMM yyyy · HH:mm');
    final ref = booking.serverRef?.isNotEmpty == true ? booking.serverRef! : booking.reference;

    return Scaffold(
      appBar: AppBar(title: Text('${courier.name} counter waybill', style: const TextStyle(fontWeight: FontWeight.w800))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
        children: [
          const Text(
            'Hand this screen to the counter — it is everything lodging needs.',
            style: TextStyle(color: AppColors.ink, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 12),

          // ─────────────────────────── Printable receipt ───────────────────────────
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: RepaintBoundary(
                key: _captureKey,
                child: _ReceiptCard(
                  booking: booking,
                  courierName: courier.name,
                  courierId: courier.id,
                  riderName: rider?.name ?? booking.riderName,
                  branchInfo: branchInfo,
                  declaredValue: declaredValue,
                  cover: cover,
                  partnerWaybill: partnerWaybill,
                  counterReceipt: counterReceipt,
                  ref: ref,
                  dateFmt: dateFmt,
                  trackingToken: _trackingToken,
                  trackingUrl: _trackingUrl,
                  evidenceLoading: !_evidenceTried,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),

          if (booking.dispatched && DropOffApi.enabled && store.linked) ...[
            OutlinedButton.icon(
              onPressed: _linkBusy || _trackingUrl != null ? null : _fetchTrackingLink,
              icon: _linkBusy
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(_trackingUrl != null ? Icons.link : Icons.link_outlined),
              label: Text(
                _linkBusy
                    ? 'Preparing tracking link…'
                    : _trackingUrl != null
                        ? 'Tracking link added to receipt'
                        : 'Add recipient tracking link',
              ),
            ),
            const SizedBox(height: 10),
          ],

          FilledButton.icon(
            onPressed: _busy ? null : _shareImage,
            icon: _busy
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.share_outlined),
            label: Text(_busy ? 'Working…' : 'Share waybill image'),
          ),
          if (!kIsWeb && Platform.isAndroid) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _busy ? null : _printBluetooth,
              icon: const Icon(Icons.print_outlined),
              label: const Text('Print on Bluetooth printer'),
            ),
            const SizedBox(height: 4),
            const Text(
              'Portable receipt printers (58 mm Bluetooth). Pair the printer in Android Settings first.',
              textAlign: TextAlign.center,
              style: AppType.caption,
            ),
          ],
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _busy ? null : _downloadImage,
            icon: const Icon(Icons.download_outlined),
            label: const Text('Download / save image'),
          ),
          const SizedBox(height: 10),
          const Text(
            'Share and save capture the receipt card only — buttons and this note are not included.',
            textAlign: TextAlign.center,
            style: AppType.caption,
          ),
        ],
      ),
    );
  }

  /// Declared value in ZMW: top-level field on the evidence payload, with a
  /// nested `evidence` fallback for older server responses. Null = not recorded.
  double? _declaredValue() {
    final top = (_evidence?['declared_value_zmw'] as num?)?.toDouble();
    if (top != null) return top;
    final nested = ((_evidence?['evidence'] as Map?)?.cast<String, dynamic>())?['declared_value_zmw'];
    return (nested as num?)?.toDouble();
  }

  /// Human-readable cover line. Cover is quoted protection, NEVER insurance
  /// (legal/commercial sign-off pending) — copy must not imply otherwise.
  String _coverSummary() {
    if (_evidence == null) {
      return _evidenceTried ? 'Not recorded on this booking' : 'Loading…';
    }
    final cover = (_evidence?['cover'] as Map?)?.cast<String, dynamic>();
    final nested = (_evidence?['evidence'] as Map?)?.cast<String, dynamic>();
    final status = (cover?['status'] ?? nested?['cover_status'] ?? 'none').toString();
    final fee = (cover?['fee_zmw'] as num?)?.toDouble();
    final feePart = fee != null && fee > 0 ? ' · fee ${kwacha(fee)}' : '';
    switch (status) {
      case 'quoted':
        return 'Quoted protection — not insurance$feePart';
      case 'active':
        return 'Cover active — quoted protection, not insurance$feePart';
      case 'declined':
        return 'Cover declined';
      case 'none':
      default:
        return 'No cover elected';
    }
  }

  /// Partner courier waybill number, recorded at the depot when lodged.
  String? _partnerWaybill() {
    final nested = (_evidence?['evidence'] as Map?)?.cast<String, dynamic>();
    final value = nested?['waybill']?.toString().trim();
    return (value == null || value.isEmpty) ? null : value;
  }

  /// Depot counter receipt (owner directive 2026-11-12): the actual written
  /// amount the rider transcribed. Null = not submitted yet.
  (double, bool)? _counterReceipt() {
    final nested = (_evidence?['evidence'] as Map?)?.cast<String, dynamic>();
    final cr = nested?['counter_receipt'] as Map?;
    final amount = (cr?['amount_zmw'] as num?)?.toDouble();
    if (amount == null || amount <= 0) return null;
    return (amount, cr?['paid'] == true);
  }

  /// Best-effort branch contact from the courier catalogue: match the booked
  /// branch name, else any branch in the same city, else nothing.
  CourierBranch? _branchInfo(Booking booking, CourierInfo courier) {
    final wanted = booking.branch?.trim().toLowerCase();
    if (wanted == null || wanted.isEmpty) return null;
    for (final branch in courier.branches) {
      if (branch.name.trim().toLowerCase() == wanted) return branch;
    }
    final bookingCity = booking.toCity.trim().toLowerCase();
    for (final branch in courier.branches) {
      if (branch.city.trim().toLowerCase() == bookingCity) return branch;
    }
    return null;
  }
}

/* ───────────────────────────── receipt widget ───────────────────────────── */

class _ReceiptCard extends StatelessWidget {
  final Booking booking;
  final String courierName;
  final String courierId;
  final String? riderName;
  final CourierBranch? branchInfo;
  final double? declaredValue;
  final String cover;
  final String? partnerWaybill;
  final (double, bool)? counterReceipt;
  final String ref;
  final DateFormat dateFmt;
  final String? trackingToken;
  final String? trackingUrl;
  final bool evidenceLoading;

  const _ReceiptCard({
    required this.booking,
    required this.courierName,
    required this.courierId,
    required this.riderName,
    required this.branchInfo,
    required this.declaredValue,
    required this.cover,
    required this.partnerWaybill,
    required this.counterReceipt,
    required this.ref,
    required this.dateFmt,
    required this.trackingToken,
    required this.trackingUrl,
    required this.evidenceLoading,
  });

  @override
  Widget build(BuildContext context) {
    final hasBranch = booking.branch?.trim().isNotEmpty == true;
    final route = hasBranch ? '${booking.fromCity} → ${booking.branch}' : '${booking.fromCity} → ${booking.toCity}';
    final dropoffLeg = booking.dropoffLeg;
    final total = booking.total;
    // Local copy so the nullable record promotes (`.$1`/`.$2` after the null
    // check) — field promotion does not apply to public class fields.
    final counterReceipt = this.counterReceipt;

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: double.infinity,
        color: Colors.white,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(height: 6, color: AppColors.amber),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 18, 22, 20),
              child: Column(
                children: [
                  const DropOffLogo(size: 54),
                  const SizedBox(height: 10),
                  const Text(
                    'DROPOFF',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17, letterSpacing: 4, color: AppColors.forest),
                  ),
                  // The SENDER's chosen depot leads the title — the counter this
                  // waybill is presented at (e.g. "PLATINUM COUNTER WAYBILL").
                  Text(
                    waybillDepotTitle(courierId, courierName),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 21, letterSpacing: 0.6, color: AppColors.ink),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Home-to-depot pickup · Zambia',
                    style: TextStyle(color: AppColors.muted, fontSize: 11.5),
                  ),
                  const SizedBox(height: 14),

                  // Waybill number + decorative ref barcode
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      ref,
                      style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w900, fontSize: 26, letterSpacing: 1.5),
                    ),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    height: 44,
                    child: CustomPaint(painter: _RefBarcodePainter(ref), child: const SizedBox.expand()),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'DropOff waybill no. — read out or type at the counter',
                    style: TextStyle(color: AppColors.muted, fontSize: 10),
                  ),
                  const SizedBox(height: 14),

                  // Route hero
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppColors.forest,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(children: [
                      Text(
                        route.toUpperCase(),
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 19, height: 1.25),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        hasBranch ? '$courierName · onward to ${booking.toCity}' : courierName,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white70, fontSize: 11.5),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.amber,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          booking.timeline[booking.stage].toUpperCase(),
                          style: const TextStyle(color: AppColors.ink, fontWeight: FontWeight.w900, fontSize: 10, letterSpacing: 0.8),
                        ),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 6),

                  _receiptSection('ROUTE & DEPOT', [
                    _row('From', booking.fromCity),
                    _row('To (final)', booking.toCity),
                    if (hasBranch) _row('Drop-off branch', booking.branch!),
                    if (branchInfo != null) ...[
                      if (branchInfo!.address.trim().isNotEmpty) _row('Branch address', branchInfo!.address),
                      if (branchInfo!.phone?.trim().isNotEmpty == true) _row('Branch phone', branchInfo!.phone!),
                      _row('Branch city', branchInfo!.city),
                    ] else if (hasBranch)
                      _row('Branch info', 'Not in DropOff catalogue — confirm at counter'),
                    _row('Courier', '$courierName ($courierId)'),
                    _row('Pickup point', booking.pickupAddress),
                    _row('Pickup window', _pickupWindowLabel(booking)),
                    if (booking.pickupAt != null) _row('Scheduled slot', _formatSlot(booking.pickupAt!)),
                  ]),

                  _receiptSection('PARCEL', [
                    _row('Size', booking.parcelSize.label),
                    _row('Parcels', '${booking.parcels}'),
                    _row('Vehicle class', _vehicleLabel(booking.vehicleClass)),
                    _row('Description', booking.description),
                    if (booking.roundTrip) ...[
                      _row('Round trip', 'Yes — unreturned parcel comes back to sender'),
                      if (booking.returnCity?.trim().isNotEmpty == true) _row('Return city', booking.returnCity!),
                      if (booking.returnAddress?.trim().isNotEmpty == true) _row('Return address', booking.returnAddress!),
                      if (booking.returnLegFee > 0) _row('Return leg fee', kwacha(booking.returnLegFee)),
                    ],
                  ]),

                  _receiptSection('VALUE & COVER', [
                    _row('Declared value', declaredValue == null ? (evidenceLoading ? 'Loading…' : 'Not provided') : kwacha(declaredValue)),
                    _row('Cover', cover),
                    _row('Partner waybill', partnerWaybill ?? (evidenceLoading ? 'Loading…' : 'Not recorded yet — counter fills in at lodgement')),
                  ]),

                  _receiptSection('FEES & PAYMENT', [
                    _row('Rider fee (DropOff)', kwacha(booking.riderFee)),
                    if (booking.lastMileFee > 0) _row('Last-mile fee (DropOff)', kwacha(booking.lastMileFee)),
                    if (booking.promoCode != null)
                      _row('Promo', '${booking.promoCode}${booking.promoDiscount != null ? ' — saved ${kwacha(booking.promoDiscount)} on the DropOff leg' : ''}'),
                    _row('DropOff due', '${kwacha(dropoffLeg)} + processing — DropOff charge, never partner money'),
                    if (counterReceipt != null)
                      _row('Courier fare', counterReceipt.$2
                          ? '${kwacha(counterReceipt.$1)} — paid via DropOff (depot receipt in Bookings)'
                          : '${kwacha(counterReceipt.$1)} — depot receipt submitted; pay in Bookings to unlock it')
                    else
                      _row('Courier fare', booking.courierFare != null ? '${kwacha(booking.courierFare)} — pay at the counter' : 'Confirmed at depot — pay at the counter'),
                    _row('Booking total', total != null ? kwacha(total) : 'Confirmed at depot (fare set by the counter)'),
                    _row('Payment method', booking.paymentMethod),
                  ]),

                  _receiptSection('SENDER', [
                    _row('Name', booking.senderName),
                    _row('Phone', booking.senderPhone),
                  ]),

                  _receiptSection('RECIPIENT', [
                    _row('Name', booking.recipientName),
                    _row('Phone', booking.recipientPhone),
                    _row('Destination', booking.toCity),
                  ]),

                  _receiptSection('BOOKING', [
                    _row('Reference', booking.reference),
                    if (booking.serverRef?.isNotEmpty == true) _row('Dispatch ref', booking.serverRef!),
                    _row('Booked', dateFmt.format(booking.createdAt)),
                    if (riderName?.trim().isNotEmpty == true) _row('Rider', riderName!),
                    _row('Record id', booking.id),
                  ]),

                  if (trackingUrl?.isNotEmpty == true) ...[
                    const _DashedLine(),
                    const SizedBox(height: 10),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text('RECIPIENT TRACKING', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 10.5, letterSpacing: 1.1, color: AppColors.muted)),
                    ),
                    const SizedBox(height: 4),
                    SelectableText(
                      trackingUrl!,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 11.5, height: 1.4),
                    ),
                    if (trackingToken?.isNotEmpty == true)
                      SelectableText(
                        'Token: $trackingToken',
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 10, color: AppColors.muted),
                      ),
                    const SizedBox(height: 6),
                  ],

                  const _DashedLine(),
                  const SizedBox(height: 10),
                  const Text(
                    'The courier / depot fare is paid directly at the counter — DropOff never collects partner money. Cover shown above is quoted protection, not insurance, until legal and commercial sign-off. Keep this waybill until the parcel is lodged at the depot.',
                    textAlign: TextAlign.center,
                    style: AppType.caption,
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'DropOff — home-to-depot pickup',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.forest, fontWeight: FontWeight.w800, fontSize: 10, letterSpacing: 0.6),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _receiptSection(String title, List<Widget> rows) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _DashedLine(),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 10.5, letterSpacing: 1.1, color: AppColors.muted)),
          ),
          const SizedBox(height: 6),
          for (final row in rows) row,
          const SizedBox(height: 10),
        ],
      );

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3.5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 118,
              child: Text(label, style: AppType.caption),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                value,
                textAlign: TextAlign.right,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12, height: 1.4, color: AppColors.ink),
              ),
            ),
          ],
        ),
      );

  static String _vehicleLabel(String vehicleClass) {
    final v = vehicleClass.trim();
    if (v.isEmpty) return 'Motorcycle';
    return v[0].toUpperCase() + v.substring(1);
  }

  static String _pickupWindowLabel(Booking booking) {
    final window = booking.pickupWindow;
    if (window.startsWith('tomorrow:')) {
      final inner = window.substring('tomorrow:'.length);
      return 'Tomorrow, ${_windowSlot(inner)}';
    }
    switch (window) {
      case 'now':
        return 'Next available sweep (ASAP)';
      case 'unscheduled':
        return 'Unscheduled — next available sweep';
      default:
        return _windowSlot(window);
    }
  }

  static String _windowSlot(String key) => switch (key) {
        '06:00' => '6:00 – 7:30 AM daily sweep',
        '10:00' => '10:00 – 11:30 AM daily sweep',
        '14:00' => '2:00 – 3:30 PM daily sweep',
        _ => key,
      };

  static String _formatSlot(String iso) {
    final parsed = DateTime.tryParse(iso);
    if (parsed == null) return iso;
    return DateFormat('d MMM yyyy · HH:mm').format(parsed);
  }
}

/* ─────────────────────────── decorative pieces ─────────────────────────── */

/// Dashed separator between receipt sections — pure CustomPaint, captures
/// cleanly inside a RepaintBoundary.
class _DashedLine extends StatelessWidget {
  const _DashedLine();

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 1.4,
        width: double.infinity,
        child: CustomPaint(painter: _DashedLinePainter()),
      );
}

class _DashedLinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.line
      ..strokeWidth = size.height;
    const dash = 6.0, gap = 4.0;
    var x = 0.0;
    while (x < size.width) {
      final end = (x + dash).clamp(0.0, size.width);
      canvas.drawLine(Offset(x, size.height / 2), Offset(end, size.height / 2), paint);
      x += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Decorative pseudo-barcode derived deterministically from the reference —
/// NOT a scannable symbology; the printed ref text above is the source of truth.
class _RefBarcodePainter extends CustomPainter {
  _RefBarcodePainter(this.seed);

  final String seed;

  @override
  void paint(Canvas canvas, Size size) {
    var state = 0x9e3779b9;
    for (final unit in seed.codeUnits) {
      state = (state * 31 + unit) & 0x7fffffff;
    }
    if (state == 0) state = 0x2545f491;

    int next() {
      state = (state * 1103515245 + 12345) & 0x7fffffff;
      return state;
    }

    final paint = Paint()..color = AppColors.ink;
    var x = 0.0;
    while (x < size.width) {
      final bar = (next() % 4 + 1) * 2.4;
      final gap = (next() % 2 + 1) * 2.0;
      if (x + bar > size.width) break;
      canvas.drawRect(Rect.fromLTWH(x, 0, bar, size.height), paint);
      x += bar + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _RefBarcodePainter oldDelegate) => oldDelegate.seed != seed;
}
