// ─────────────────────────────────────────────────────────────────────
// DROPOFF — ownership stamp (do not remove)
// :Godfrey Moses Kalambo:Carpso Solutions:0968551110.
// © 2026 Godfrey Moses Kalambo · Carpso Solutions · Lusaka, Zambia.
// All rights reserved — unauthorised copying, resale or rebranding of
// this source code is prohibited.
// ─────────────────────────────────────────────────────────────────────
import '../ui/app_toast.dart';
import '../ui/pay_job.dart';
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';

import '../data/catalog.dart';
import '../data/dropoff_api.dart';
import '../data/map_services.dart';
import '../widgets/photo_preview.dart';
import '../data/saved_places.dart';
import '../data/analytics_service.dart';
import '../main.dart';
import '../models/booking.dart';
import '../ui/app_theme.dart';
import '../ui/in_app_browser.dart';
import '../ui/tidy.dart';
import '../widgets/common.dart';
import '../widgets/help_sheet.dart';
import 'in_app_navigator_screen.dart';
import 'account_screen.dart';
import 'bookings_screen.dart';
import 'waybill_screen.dart';
import '../ui/app_spinner.dart';
import 'package:flutter_svg/flutter_svg.dart';

class BookingScreen extends StatefulWidget {
  final String? initialCourierId;
  const BookingScreen({super.key, this.initialCourierId});

  /// Repeat-last-booking hook: BusinessScreen stores a snapshot of the job to
  /// clone (from / to / branch / courier / recipients…) here before pushing;
  /// initState consumes it once and clears it.
  static Map<String, dynamic>? prefill;

  @override
  State<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends State<BookingScreen> {
  // First-mile rider fee estimate. MUST match the server's baseRiderFee for
  /// The estimate now mirrors the worker's baseRiderFee exactly — Lusaka distance
  /// bands × vehicle multiplier — so the card never under-states what the
  /// prepaid prompt will charge.
  /// Last-mile door delivery: priced server-side like first-mile PAYG
  /// (recipient-city distance + vehicle). K45 is the default estimate shown
  /// before the server quote; the authoritative charge comes from the Worker.
  static const double lastMilePrice = 45;
  static const Map<String, String> pickupWindows = {
    '06:00': 'Daily sweep 6:00 am',
    '10:00': 'Daily sweep 10:00 am',
    '14:00': 'Daily sweep 2:00 pm',
  };

  /// Seller-facing slot copy: arrival RANGE + benefit + booking cutoff (CAT).
  /// Closed slots stay visible (list-only) and auto-roll forward.
  static const Map<String, ({String title, String benefit, String cutoff})> slotCopy = {
    '06:00': (title: '5:30 – 7:30 AM window', benefit: 'Catches early outbound buses', cutoff: '05:30'),
    '10:00': (title: '10:00 – 11:30 AM window', benefit: 'Catches midday courier express', cutoff: '09:30'),
    '14:00': (title: '2:00 – 3:30 PM window', benefit: 'Catches final evening transit', cutoff: '13:30'),
  };
  bool _tomorrowMorning = false;

  bool _slotClosed(String key) {
    final parts = slotCopy[key]!.cutoff.split(':');
    final now = TimeOfDay.now();
    final cutMin = int.parse(parts[0]) * 60 + int.parse(parts[1]);
    return now.hour * 60 + now.minute > cutMin;
  }

  final _pickup = TextEditingController();
  final _description = TextEditingController();
  final _senderName = TextEditingController();
  final _senderPhone = TextEditingController();
  final _recipientName = TextEditingController();
  final _recipientPhone = TextEditingController();
  final _promo = TextEditingController();
  final _pack = TextEditingController();
  final _returnAddress = TextEditingController();

  int _step = 0;
  String _from = 'Lusaka';
  String _to = 'Ndola';
  String _pickupWindow = '10:00';
  double? _pickupLat;
  double? _pickupLng;
  bool _locating = false;
  late String _courierId = widget.initialCourierId ?? 'platinum';
  ParcelSize _size = ParcelSize.small;
  bool _lastMile = false;
  bool _roundTrip = false;
  String _returnCity = 'Lusaka';
  final String _payment = 'Mobile money';
  bool _packActive = false;
  bool _saving = false;
  bool _aiBusy = false;
  String? _parcelPhotoUrl;
  String? _parcelPhotoPath;
  bool _parcelPhotoUploading = false;
  String? _tidyPinLabel; // '✨ Tidy pinned ≈ Kabwata — bands apply (±1 km)'
  String? _plusCode;
  List<String> _cities = cities;
  double? _promoPct;
  String _promoNote = '';

  // The worker chooses car vs motorcycle from parcel size + count; the sender
  // never picks a vehicle class.
  String get _vehicleClass {
    if (_size == ParcelSize.large) return 'car';
    final cap = switch (_size) {
      ParcelSize.small => 10,
      ParcelSize.medium => 5,
      ParcelSize.large => 1,
    };
    return _parcels > cap ? 'car' : 'motorcycle';
  }
  List<SavedPlace> _saved = const [];
  int _parcels = 1;
  /// Mirrors [_parcels] so the free-typed parcels field always shows the real
  /// value — size/vehicle picks clamp the count and the field must follow
  /// (previously it kept the stale typed number, so taps looked ignored).
  final _parcelsCtl = TextEditingController(text: '1');
  final _courierSearchCtl = TextEditingController();
  /// DECLARED VALUE (owner directive 2026-11-17): the parcel's worth in ZMW,
  /// printed on the depot counter receipt so the depot can verify what it is
  /// carrying. NOT the cover value — protection is not sold in the app.
  final _declaredValue = TextEditingController();
  /// Owner directive (2026-11-13): motorcycle carries at most 10 SMALL,
  /// 5 MEDIUM or 1 LARGE parcel — past that, the rider bumps vehicle, not
  /// stuffing. Cars, vans and trucks carry whole batches: no practical limit.
  /// 9999 = "unlimited" sentinel; the worker applies the same caps with the
  /// same parcel_size key (workers/src/pricing.ts).
  static const int _unlimited = 9999;
  int get _parcelCap => _parcelCapFor(_vehicleClass);
  int _parcelCapFor(String vehicleClass) {
    if (vehicleClass != 'motorcycle') return _unlimited;
    switch (_size) {
      case ParcelSize.small: return 10;
      case ParcelSize.medium: return 5;
      case ParcelSize.large: return 1;
    }
  }

  /// Live plan snapshot ({subscription, plan, remaining_this_period}) — the
  /// estimate mirrors the server's pack-inclusion math so plan members see the
  /// truth BEFORE booking (sender → depot leg covered → K0), not after.
  Map<String, dynamic>? _planSnap;

  @override
  void initState() {
    super.initState();
    SavedPlaces.load().then((list) { if (mounted) setState(() => _saved = list); });
    _refreshPlan();
    // Repeat last booking: adopt the snapshot's fields, then clear it so we
    // never prefill twice for a fresh booking.
    final pre = BookingScreen.prefill;
    if (pre != null) {
      BookingScreen.prefill = null;
      final from = '${pre['from'] ?? ''}'.trim();
      final to = '${pre['to'] ?? ''}'.trim();
      if (from.isNotEmpty && from != to) { _from = from; _to = to; }
      final pickup = '${pre['pickup'] ?? ''}'.trim();
      if (pickup.isNotEmpty) _pickup.text = pickup;
      final desc = '${pre['description'] ?? ''}'.trim();
      if (desc.isNotEmpty) _description.text = desc;
      final sender = '${pre['sender_name'] ?? ''}'.trim();
      if (sender.isNotEmpty) _senderName.text = sender;
      final senderPhone = '${pre['sender_phone'] ?? ''}'.trim();
      if (senderPhone.isNotEmpty) _senderPhone.text = senderPhone;
      final recipient = '${pre['recipient_name'] ?? ''}'.trim();
      if (recipient.isNotEmpty) _recipientName.text = recipient;
      final recipientPhone = '${pre['recipient_phone'] ?? ''}'.trim();
      if (recipientPhone.isNotEmpty) _recipientPhone.text = recipientPhone;
      final size = '${pre['size'] ?? ''}'.toLowerCase();
      for (final s in ParcelSize.values) {
        if (s.name == size) { _size = s; break; }
      }
      // Fee checker pins the pickup GPS — reuse it in dispatch.
      final lat = (pre['pickup_lat'] as num?)?.toDouble();
      final lng = (pre['pickup_lng'] as num?)?.toDouble();
      if (lat != null && lng != null) { _pickupLat = lat; _pickupLng = lng; }
      // Older snapshots/job rows carry the chargebook weight class instead.
      switch ('${pre['weight_class'] ?? ''}') {
        case '0-5kg': _size = ParcelSize.small; break;
        case '5-15kg': _size = ParcelSize.medium; break;
        case '15kg+': _size = ParcelSize.large; break;
      }
      // Fee checker sends the catalog id straight through; legacy snapshots
      // carry server ids instead — accept either, prefer an exact catalog id.
      final direct = '${pre['courier'] ?? ''}'.trim();
      if (direct.isNotEmpty && couriers.any((c) => c.id == direct)) {
        _courierId = direct;
      } else {
        final catalogCourier = '${pre['courier_catalog_id'] ?? ''}'.trim();
        if (catalogCourier.isNotEmpty) {
          _courierId = catalogCourier;
        } else {
          _courierId = courierCatalogForServerId(int.tryParse('${pre['courier_id'] ?? ''}') ?? 1);
        }
      }
      final parcels = (pre['parcels'] as num?)?.toInt() ?? 0;
      if (parcels > 0 && parcels <= _parcelCapFor(_vehicleClass)) {
        _parcels = parcels;
        _parcelsCtl.text = '$parcels';
      }
      final pw = '${pre['pickup_window'] ?? pre['pickupWindow'] ?? ''}'.trim();
      if (pw == 'tomorrow:06:00') {
        _tomorrowMorning = true;
      } else if (pickupWindows.containsKey(pw)) {
        _pickupWindow = pw;
      }
      final promo = '${pre['promo_code'] ?? ''}'.trim();
      if (promo.isNotEmpty) _promo.text = promo;
    }
    _courierSearchCtl.addListener(() => setState(() {}));
    _hintTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted) return;
      setState(() => _hintIdx = (_hintIdx + 1) % _hints.length);
    });
    // Prefer the live chargebook's coverage when the API is on.
    if (DropOffApi.enabled) {
      DropOffApi.cities().then((list) {
        if (list.isNotEmpty && mounted) {
          final merged = {...list, ...cities}.toList();
          setState(() => _cities = merged);
        }
      });
    }
    AnalyticsService.instance.track(
      feature: 'booking', action: 'view', context: 'booking_step_1',
    );
  }

  @override
  void dispose() {
    _hintTimer?.cancel();
    for (final controller in [_pickup, _description, _senderName, _senderPhone, _recipientName, _recipientPhone, _promo, _pack, _returnAddress, _courierSearchCtl, _parcelsCtl, _declaredValue]) {
      controller.dispose();
    }
    super.dispose();
  }

  /// Reload the plan snapshot (also fired after a plan-code redemption so the
  /// estimate flips to "covered" immediately).
  Future<void> _refreshPlan() async {
    if (!DropOffApi.enabled) return;
    final snap = await DropOffApi.subscription();
    if (!mounted) return;
    setState(() => _planSnap = snap);
  }

  /// Redeem a bulk-paid plan code (sold offline) onto the signed-in number.
  Future<void> _applyPack() async {
    final code = _pack.text.trim().toUpperCase();
    if (code.isEmpty) return;
    final res = await DropOffApi.redeemPackCode(code);
    if (!mounted) return;
    if (res.ok) {
      setState(() => _packActive = true);
      final tier = '${res.body['tier'] ?? 'plan'}';
      final end = '${res.body['period_end'] ?? ''}'.split(' ').first;
      _message('$tier plan activated${end.isEmpty ? '' : ' until $end'} — rider fee covered on this booking.');
      unawaited(_refreshPlan());
    } else {
      _message(res.error == 'code_not_found'
          ? 'That plan code was not recognised.'
          : res.error == 'code_used'
              ? 'That plan code has already been used.'
              : 'Could not redeem the plan code (${res.error}).');
    }
  }

  Future<void> _checkPromo() async {
    final code = _promo.text.trim().toUpperCase();
    if (code.isEmpty) {
      setState(() => _promoPct = null);
      return;
    }
    final res = await DropOffApi.checkPromo(code);
    if (res != null && res['ok'] == true) {
      setState(() {
        _promoPct = (res['discount_pct'] as num?)?.toDouble();
        _promoNote = res['note'] as String? ?? 'Applied at dispatch.';
      });
      if (mounted) AppToast.show(context, 'Promo $code applied — ${_promoPct!.toStringAsFixed(0)}% off your DropOff charge.');
    } else {
      setState(() {
        _promoPct = null;
        _promoNote = res?['error'] == 'promo_not_found' ? 'Promo not recognised.' : 'Could not check the promo right now.';
      });
      if (mounted) AppToast.show(context, _promoNote);
    }
  }

  Timer? _hintTimer;
  int _hintIdx = 0;
  List<String> get _hints => courierSearchHintsFor(_from, _to).isNotEmpty
      ? courierSearchHintsFor(_from, _to)
      : courierSearchSamples;
  String get _searchHint => _hints[_hintIdx % _hints.length];
  String? get _queryEstimate {
    final q = _courierSearchCtl.text.trim().toLowerCase();
    if (q.isEmpty) return null;
    final isFareQuery = q.contains('price') || q.contains('fare') || q.contains('how much') ||
        q.contains('cost') || q.contains('charge') || q.contains('quote');
    if (!isFareQuery) return null;
    final from = _from.trim();
    final to = _to.trim();
    if (from == to) return null;
    final est = interTownEstimateZmw(from, to);
    if (est == null) return 'Indicative DropOff delivery ($from → $to): quote at the depot counter.';
    return 'Indicative DropOff delivery ($from → $to): K${est.toStringAsFixed(0)} rider leg • depot fare quoted at counter.';
  }
  List<CourierInfo> get _filteredCouriers => smartCourierSearch(_courierSearchCtl.text, fromCity: _from, toCity: _to, size: _size, activeServerIds: AppScope.of(context).activeCourierIds);

  /// Server-mirrored plan state for THIS trip — 'pack' (sender → depot leg
  /// covered: K0 rider fee, no per-parcel processing fees, no momo prompt),
  /// 'overage' (cap reached: tier discount off PAYG), or null (pay-as-you-go).
  /// Mirrors the pack-inclusion gate in workers/src/index.ts.
  String? get _planLeg {
    final sub = _planSnap?['subscription'] as Map<String, dynamic>?;
    final plan = _planSnap?['plan'] as Map<String, dynamic>?;
    if (sub == null || plan == null || '${sub['status'] ?? ''}' != 'active') return null;
    // Expired period → pay-as-you-go, exactly like the server's SQL gate.
    // D1 writes naive UTC stamps ("2026-12-01 00:00:00") — without the Z the
    // parse reads them as LOCAL time and the pack appears to expire 2h early.
    final rawEnd = '${sub['period_end'] ?? ''}'.trim().replaceFirst(' ', 'T');
    final end = DateTime.tryParse(
      rawEnd.endsWith('Z') || rawEnd.contains('+') ? rawEnd : '${rawEnd}Z',
    );
    if (end != null && end.isBefore(DateTime.now())) return null;
    final remaining = (_planSnap?['remaining_this_period'] as num?)?.toInt() ?? 0;
    return remaining >= _parcels ? 'pack' : 'overage';
  }

  int get _overagePct =>
      ((_planSnap?['plan'] as Map<String, dynamic>?)?['overage_discount_pct'] as num?)?.toInt() ?? 0;
  // The pack discount applies ONLY while the platform re-enables the overage
  // flag — the default catalogue sells packs as full-KYC rates; overage pays
  // PAYG in full. Never price a discount nobody authorised.
  bool get _overageEnabled =>
      (_planSnap?['feature_flags']?['overage_discount_enabled'] as bool?) ?? false;

  /// Server-mirrored base rider fee BEFORE plan math (mirror of baseRiderFee in
  /// workers/src/pricing.ts — the estimate must never lie about the plan fee).
  double get _goRiderFee {
    const multi = {'motorcycle': 1.0, 'car': 1.2, 'van': 1.4, 'truck': 2.0};
    double base;
    if (_from == 'Lusaka' && _pickupLat != null && _pickupLng != null) {
      final km = _haversineKmBooks(_pickupLat!, _pickupLng!, -15.4255, 28.2805);
      base = km <= 5 ? 55.0 : km <= 12 ? 75.0 : 95.0;
    } else {
      base = 70.0;
    }
    base = base * (multi[_vehicleClass] ?? 1.0);
    if (_vehicleClass == 'truck' && base < 100) base = 100;
    return DropOffApi.round2(base);
  }

  double _haversineKmBooks(double aLat, double aLng, double bLat, double bLng) {
    const R = 6371.0, d = 0.0174532925199433;
    final h = 0.5 - math.cos((bLat - aLat) * d) / 2 +
        math.cos(aLat * d) * math.cos(bLat * d) * (1 - math.cos((bLng - aLng) * d)) / 2;
    return 2 * R * math.asin(math.sqrt(h));
  }

  /// Rider fee actually due on the DropOff leg after plan math (server parity:
  /// pack → plan.rider_fee_zmw 0; overage → tierOverageFee discount).
  double get _riderFeeEstimate {
    if (_planLeg == 'pack') return 0;
    if (_planLeg == 'overage') return _overageEnabled ? DropOffApi.round2(_goRiderFee * (1 - _overagePct / 100)) : _goRiderFee;
    return _goRiderFee;
  }

  /// DropOff-only leg: rider fee + door leg (+door-leg platform cut). Never partner money.
  double get _dropOffLeg => _riderFeeEstimate + (_lastMile ? lastMilePrice + DropOffApi.platformFee(lastMilePrice) : 0);

  /// What the customer pays DropOff on the prompt for this order.
  double get _dropOffDue {
    final leg = DropOffApi.round2(_dropOffLeg);
    // Pack parcels carry NO per-parcel processing fees — the server passes
    // riderFee=null to collectionFees() for them, so the prompt is the leg only.
    if (_planLeg == 'pack') return leg;
    return DropOffApi.collectionFees(leg, riderFee: _riderFeeEstimate)['prompt_total_zmw'] ?? leg;
  }

  void _message(String text) => AppToast.show(context, text);

  /// Shared copy for the post-prompt verdict (both pay paths use it).
  /// [failReason] is the telco's own message ("User wallet does not have
  /// enough money...") — shown verbatim so the payer learns WHY.
  String _payResultMessage(String outcome, [String? failReason]) => switch (outcome) {
        'success' => 'Lipila payment received. Your rider is being dispatched.',
        'failed' => (failReason == null || failReason.isEmpty)
            ? 'The mobile-money request was rejected — verify your momo balance has the funds, then tap Pay now to resend the prompt.'
            : 'Payment failed: $failReason — top up your momo wallet, then tap Pay now to resend the prompt.',
        _ => 'Payment still pending — the rider sweep confirms when your money lands.',
      };

  Future<void> _pickParcelPhoto() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.photo_camera), title: const Text('Take parcel photo'), onTap: () => Navigator.pop(ctx, ImageSource.camera)),
          ListTile(leading: const Icon(Icons.photo_library), title: const Text('Pick from gallery'), onTap: () => Navigator.pop(ctx, ImageSource.gallery)),
        ]),
      ),
    );
    if (source == null || !mounted) return;
    final picked = await ImagePicker().pickImage(source: source, imageQuality: 82, maxWidth: 1600);
    if (picked == null) return;
    // Show the shot immediately — before the upload finishes.
    setState(() => _parcelPhotoPath = picked.path);
    setState(() => _parcelPhotoUploading = true);
    final bytes = await picked.readAsBytes();
    DateTime? capturedAt;
    try { capturedAt = await picked.lastModified(); } catch (_) {}
    final res = await DropOffApi.uploadImage(bytes, picked.name.isNotEmpty ? picked.name : 'parcel.jpg', kind: 'kyc', capturedAt: capturedAt);
    if (!mounted) return;
    setState(() {
      _parcelPhotoUploading = false;
      if (res.ok && res.body['url'] is String) _parcelPhotoUrl = res.body['url'] as String;
    });
    _message(res.ok ? 'Parcel photo attached — protects you if the parcel is disputed.' : 'Photo upload failed. You can still book.');
  }

  /// ✨ Tidy, the DropOff app AI (server /ai/address + local pin snap).
  /// Best-effort, never blocks — the reply is captioned for human check.
  Future<void> _tidyAddress() async {
    final text = _pickup.text.trim();
    if (text.length < 5) return _message('Type the address first, then tap Tidy.');
    setState(() => _aiBusy = true);
    // Plus codes are a universal location format any maps tool can open —
    // carry the code through the address string so rider, depot and waybill
    // all read it (no decoder needed).
    _updateTidyPins(text);
    final res = await DropOffApi.aiAddress(text);
    if (!mounted) return;
    setState(() => _aiBusy = false);
    final parsed = res.body['parsed'];
    if (!res.ok || parsed is! Map) {
      return _message(_plusCode == null
          ? '✨ Tidy is unavailable right now — your address is unchanged.'
          : '✨ Tidy is unavailable — but the plus code is pinned to your pickup.');
    }
    final parts = [parsed['street'], parsed['area'], parsed['city']]
        .map((e) => '${e ?? ''}'.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (parts.isNotEmpty) _pickup.text = parts.join(', ');
    final landmark = '${parsed['landmark'] ?? ''}'.trim();
    if (landmark.isNotEmpty && !_pickup.text.toLowerCase().contains(landmark.toLowerCase())) {
      _pickup.text = '${_pickup.text} ($landmark)';
    }
    final plus = '${parsed['plus_code'] ?? ''}'.trim();
    if (plus.isNotEmpty && _plusCode == null) _setPlusCode(plus);
    _updateTidyPins(_pickup.text);
    final phone = '${parsed['phone'] ?? ''}'.trim();
    if (phone.isNotEmpty && _senderPhone.text.trim().isEmpty) _senderPhone.text = phone;
    final conf = '${parsed['confidence'] ?? ''}'.trim();
    final town = '${parsed['city'] ?? ''}'.trim();
    final inZambia = Tidy.isZambiaTown(town) || Tidy.isZambiaTown('${parsed['area'] ?? ''}');
    if (!inZambia && town.isNotEmpty) {
      _message('✨ Tidy isn\'t sure that is a Zambian town — double-check the address.');
    } else if (conf == 'low') {
      _message('✨ Tidy tidied what it could — eyeball it before booking.');
    } else {
      _message('✨ Tidy done — check the address before booking.');
    }
  }

  /// Extract/pin anything offline-detectable: plus code, or the nearest known
  /// Zambian spot for a Lusaka band (never overrides a manual GPS pin).
  void _updateTidyPins(String text) {
    final plus = Tidy.extractPlusCode(text);
    if (plus != null && plus != _plusCode) _setPlusCode(plus);
    if (_pickupLat != null) return; // a real pin already wins
    final match = Tidy.matchZambianPlace(text);
    if (match != null && mounted) {
      setState(() {
        _pickupLat = match.lat;
        _pickupLng = match.lng;
        _tidyPinLabel = '✨ Tidy pinned ≈ ${match.name} — bands apply (±1 km)';
      });
    }
  }

  void _setPlusCode(String code) {
    final c = code.trim();
    setState(() {
      _plusCode = c;
      // Carry the code inside the pickup address — the rider, the depot
      // waybill and the SMS all see it.
      if (!_pickup.text.toLowerCase().contains(c.toLowerCase())) {
        _pickup.text = _pickup.text.trim().isEmpty ? c : '${_pickup.text.trim()} ($c)';
      }
      _tidyPinLabel = 'Plus code pinned — tap View this pin for where it sits';
    });
  }

  /// See the pinned pickup on the DropOff map. With GPS/Tidy coordinates this
  /// opens in-app; a raw plus code or typed address is GEOCODED in-app
  /// (hard-locked to Lusaka) so the sender still gets DropOff turn-by-turn —
  /// the device's maps handler is a silent last resort, never a labelled
  /// choice in this UI.
  Future<void> _openInMaps() async {
    final lat = _pickupLat, lng = _pickupLng;
    if (lat != null && lng != null) {
      Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => InAppNavigatorScreen(
          destLat: lat,
          destLng: lng,
          label: 'Pickup pin — this is where the rider comes to',
        ),
      ));
      return;
    }
    final q = (_plusCode != null && _plusCode!.isNotEmpty) ? _plusCode! : _pickup.text.trim();
    if (q.isEmpty) return;
    final hits = await MapServices.search(q);
    if (!mounted) return;
    if (hits.isNotEmpty) {
      final hit = hits.first;
      Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => InAppNavigatorScreen(
          destLat: hit.point.latitude,
          destLng: hit.point.longitude,
          label: 'Pickup pin — this is where the rider comes to',
        ),
      ));
      return;
    }
    await openInApp('https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(q)}');
  }

  Future<void> _captureLocation() async {
    setState(() => _locating = true);
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        _message('Location permission is needed to pin the pickup.');
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      ).timeout(const Duration(seconds: 12));
      if (!mounted) return;
      setState(() {
        _pickupLat = pos.latitude;
        _pickupLng = pos.longitude;
      });
      unawaited(SavedPlaces.remember(
        _pickup.text.trim().isEmpty ? 'My current location' : _pickup.text.trim(),
        lat: pos.latitude, lng: pos.longitude));
      _message('Pickup location pinned — the nearest rider will dispatch.');
    } catch (_) {
      _message('Could not get your location — type the address or try again.');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  bool _validPhone(String value) => RegExp(r'^(?:\+?260|0)?(5[0-9]|7[0-9]|9[1-9])\d{7}$').hasMatch(value.replaceAll(RegExp(r'[\s-]'), ''));

  /// Tap-to-jump on the step bars (and Continue): going back is always free;
  /// jumping forward only lands when the skipped steps pass the same gates as
  /// Continue — otherwise the same hint toast explains why.
  void _jumpToStep(int target) {
    if (_saving || target == _step) return;
    if (target < _step) {
      setState(() => _step = target);
      return;
    }
    if (_step < 1 && target >= 1) {
      if (_from == _to) return _message('Choose different pickup and destination cities.');
      if (_pickup.text.trim().length < 4) return _message('Enter the home or shop pickup address.');
      // Nudge, never block: a pin gives exact dispatch + turn-by-turn stops;
      // a typed address still books (navigated by its text).
      if (_pickupLat == null) {
        _message('Pin for the nearest rider and an exact route.');
      }
    }
    if (_step < 2 && target >= 2) {
      if (_description.text.trim().length < 3) return _message('Briefly describe what is inside the parcel.');
    }
    setState(() => _step = target);
  }

  void _next() => _jumpToStep(_step + 1);

  Future<void> _openRecipientsPicker() async {
      final list = await DropOffApi.recipients();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Saved recipients', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            if (list.isEmpty)
              const Padding(padding: EdgeInsets.symmetric(vertical: 18), child: Text('No saved recipients yet. Fill in a recipient and tap “Save this recipient”.', style: TextStyle(color: AppColors.muted)))
            else
              Flexible(child: ListView.separated(
                shrinkWrap: true,
                itemCount: list.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final r = list[i];
                  final name = '${r['name'] ?? ''}';
                  final phone = '${r['phone'] ?? ''}';
                  final meta = [if ('${r['city'] ?? ''}'.isNotEmpty) r['city'], if ('${r['address'] ?? ''}'.isNotEmpty) r['address']].whereType<Object>().join(' · ');
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text([phone, if (meta.isNotEmpty) meta].join('\n')),
                    isThreeLine: meta.isNotEmpty,
                    onTap: () {
                      _recipientName.text = name;
                      _recipientPhone.text = phone;
                      setState(() {});
                      Navigator.pop(ctx);
                    },
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline, color: AppColors.muted),
                      onPressed: () async {
                        final id = (r['id'] as num?)?.toInt();
                        if (id == null) return;
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (d) => AlertDialog(
                            title: const Text('Remove saved recipient?'),
                            content: Text('Remove $name ($phone) from your saved recipients?'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
                              FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Remove')),
                            ],
                          ),
                        );
                        if (ok != true) return;
                        await DropOffApi.deleteRecipient(id);
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (mounted) _openRecipientsPicker();
                      },
                    ),
                  );
                },
              )),
          ]),
        ),
      ),
    );
  }

  Future<void> _saveCurrentRecipient() async {
      final name = _recipientName.text.trim();
    final phone = _recipientPhone.text.trim();
    if (name.length < 2 || !_validPhone(phone)) {
      _message('Enter a valid recipient name and Zambian phone number first.');
      return;
    }
    final res = await AppScope.of(context).saveRecipient(name: name, phone: phone, city: _to);
    if (!mounted) return;
    _message(res
      ? 'Recipient saved'
      : 'Could not save recipient — check your connection and try again.');
  }

  Future<void> _submit() async {
      final serverCourierId = courierServerIdOf(_courierId);
    if (serverCourierId == null) {
      return _message('That courier is unavailable right now — pick Platinum, Mercury, DHL, One World, Rovert, Icypeed or Falcon.');
    }
    if (_senderName.text.trim().length < 2 || _recipientName.text.trim().length < 2) {
      return _message('Enter the sender and recipient names.');
    }
    if (!_validPhone(_senderPhone.text) || !_validPhone(_recipientPhone.text)) {
      return _message('Use valid Zambian phone numbers, e.g. 0971234567.');
    }
    if (_roundTrip && _returnAddress.text.trim().isEmpty) {
      return _message('Enter the return address for the round trip.');
    }
    setState(() => _saving = true);
    unawaited(SavedPlaces.remember(_pickup.text.trim(), lat: _pickupLat, lng: _pickupLng));
    final store = AppScope.of(context);
    final booking = await store.createBooking(
      senderName: _senderName.text,
      senderPhone: _senderPhone.text,
      pickupAddress: _pickup.text,
      fromCity: _from,
      toCity: _to,
      courierId: _courierId,
      parcelSize: _size,
      description: _description.text,
      recipientName: _recipientName.text,
      recipientPhone: _recipientPhone.text,
      paymentMethod: _payment,
      riderFee: _riderFeeEstimate,
      courierFare: null,
      lastMileFee: _lastMile ? lastMilePrice : 0,
      pickupWindow: _tomorrowMorning ? 'tomorrow:06:00' : _pickupWindow,
      promoCode: _promo.text.trim(),
      roundTrip: _roundTrip,
      returnCity: _roundTrip ? _returnCity : null,
      returnAddress: _roundTrip ? _returnAddress.text.trim().isEmpty ? null : _returnAddress.text.trim() : null,
      returnLegFee: 0,
      pickupAt: null,
      parcels: _parcels,
      vehicleClass: _vehicleClass,
      pickupLat: _pickupLat,
      pickupLng: _pickupLng,
      parcelPhotoUrl: _parcelPhotoUrl,
      declaredValueZmw: double.tryParse(_declaredValue.text.replaceAll(RegExp(r'[^0-9.]'), '')),
    );
    if (store.lastBookingError != null && store.lastBookingError != 'network_error') {
      if (!mounted) return;
      setState(() => _saving = false);
      final msg = switch (store.lastBookingError) {
        'slot_required' || 'pickup_window_required' => 'Every parcel must be booked onto a Sweep slot (no untimed pickups).',
        _ => store.lastBookingErrorDetail?.isNotEmpty == true
            ? store.lastBookingErrorDetail!
            : "We couldn't place your booking. Check your connection and try again.",
      };
      _message(msg);
      return;
    }
    // Bookings are allowed even with pickup strikes (owner 2026-11-20:
    // "allow to do both collection and pick up no matter what"). Warn instead.
    if ((store.lastBookingStrikes ?? 0) > 0) {
      _message('Booking saved (recent missed pickups — please pay promptly so your next pickup stays reliable).');
    } else if (store.lastBookingDeduped) {
      _message('This trip is already booked and waiting for payment — finish paying it below. No duplicate booking was created.');
    } else if (store.lastBookingWindowRolled != null) {
      _message('That window closed — your booking moved to the next open slot.');
    } else if (_tomorrowMorning) {
      _message('You booked the TOMORROW 5:30 – 7:30 AM early sweep — the rider collects in the morning.');
    }

    // Live Lipila collect for mobile-money jobs; the Worker responds with the
    // payment id and the client polls GET /payments/:id/status every 2s.
    // Plan-covered trips skip payment entirely — the subscription already paid
    // for the rider leg, and the parcels were deducted server-side.
    final inclusion = store.lastBookingPlanInclusion;
    final due = store.lastBookingDueZmw;
    final used = store.lastBookingPlanUsed;
    final cap = store.lastBookingPlanCap;
    final justParcels = store.lastBookingParcels ?? _parcels;
    // SERVER DECISION (owner directive 2026-11-15): the booking flow collects
    // exactly what the server demanded — a momo deposit (deposit_required) or
    // a booking HELD because the prompt never started (deposit_init_failed).
    // Plan-covered ('pack') and staff/ops bookings ride free; the client
    // never invents a payment from plan inclusion alone.
    final depositRequired = store.lastBookingDepositRequired;
    final depositInitFailed = store.lastBookingDepositInitFailed;
    // 'free' = nothing to pay (plan pack / offline-covered); 'paid' = prepayment confirmed;
    // 'held' = prepayment due and NOT confirmed — booking saved but held, no rider.
    // A booking that never reached the server counts as held: no green check without money.
    String paymentOutcome = (depositRequired || depositInitFailed)
        ? 'held'
        : (booking.dispatched ? 'free' : 'held');
    if (booking.dispatched && !depositRequired && !depositInitFailed) {
      // Nothing to collect: plan-covered, staff/ops booking or a zero-fee leg.
      if (mounted) {
        final remaining = (inclusion == 'pack' && used != null && cap != null) ? cap - used : null;
        _message(
          remaining != null && remaining >= 0
              ? 'Covered by your plan — $justParcels parcel${justParcels == 1 ? '' : 's'} deducted ($remaining left on your plan). No payment due.'
              : remaining != null
                  ? 'Covered by your plan — $justParcels parcel${justParcels == 1 ? '' : 's'} deducted. No payment due.'
                  : 'Booking dispatched — no payment due.',
        );
      }
    } else if (booking.dispatched && depositInitFailed) {
      // The provider was down at booking: HELD, and only the sender's
      // deliberate Pay now starts a prompt.
      if (mounted) {
        _message('Payment could not start now; the booking is saved and HELD — no rider until prepayment lands. Verify your momo balance, then tap Pay now on the booking screen to retry.');
      }
      paymentOutcome = 'held';
    } else if (booking.dispatched && depositRequired && DropOffApi.enabled && store.linked && due != null && due > 0) {
      // The server already sent the momo prompt at booking; PayJob reuses
      // that exact prompt (idempotent server-side) and polls until it lands.
      // Discount copy follows the platform flag — senders never see a
      // discount the platform switch has hidden.
      final overageOffered = (_planSnap?['feature_flags']?['overage_discount_enabled'] as bool?) ?? false;
      final overCap = inclusion == 'payg' && used != null && cap != null && used >= cap;
      if (mounted) {
        _message(overCap && overageOffered
            ? 'Your plan cap is reached — this trip uses your tier discount. Pay K${due.toStringAsFixed(2)} to dispatch.'
            : overCap
                ? 'Your plan cap is reached — this trip is billed pay-as-you-go. Pay K${due.toStringAsFixed(2)} to dispatch.'
                : 'Approve the prepayment prompt for K${due.toStringAsFixed(2)} sent to ${_senderPhone.text} — your rider dispatches the moment it lands. The rider fronts the depot fare; you repay the exact photographed receipt through DropOff to reimburse them. It is not a DropOff charge.');
      }
      final out = await PayJob.startAndPoll(jobRef: booking.serverRef!, phone: _senderPhone.text);
      if (!mounted) return;
      paymentOutcome = out.status == 'success' ? 'paid' : 'held';
      if (out.status.startsWith('error:')) {
        _message('Payment could not start now (${out.status.substring(6)}); the booking is saved and HELD — verify your momo balance, then tap Pay now on the booking screen to retry.');
      } else {
        _message(_payResultMessage(out.status, out.failReason));
      }
    } else if (booking.dispatched && due != null && due > 0 && mounted) {
      // Deposit required but no live prompt on this device: the sender
      // approves the momo prompt that was sent at booking time.
      _message('DropOff leg: K${due.toStringAsFixed(2)} — approve the prepayment prompt sent to your momo at booking; your rider dispatches on approval. The rider fronts the depot fare; you repay the photographed receipt through DropOff to reimburse them.');
      paymentOutcome = 'held';
    }
    // In-flow approval releases the HELD gate at once (share/track cards and
    // the Pay-now card follow the booking's paymentHeld flag).
    if (paymentOutcome == 'paid') await store.clearPaymentHeld(booking.id);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute<void>(builder: (_) => BookingSuccessScreen(bookingId: booking.id, paymentHeld: paymentOutcome == 'held')));
    AnalyticsService.instance.track(
      feature: 'booking', action: 'submit', context: 'booking_step_3',
      meta: {
        'parcels': _parcels,
        'weight_class': switch (_size) {
          ParcelSize.small => '0-5kg',
          ParcelSize.medium => '5-15kg',
          ParcelSize.large => '15kg+',
        },
        'vehicle_class': _vehicleClass,
        'pay_method': _payment,
        'last_mile': _lastMile,
        'round_trip': _roundTrip,
        'dispatch': booking.dispatched,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    if (!store.linked) {
      // Booking requires an identity (pricing, plan deduction and payment all
      // hang off the account) — show the sign-up door instead of the form.
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(title: const Text('Book a pickup', style: TextStyle(fontWeight: FontWeight.w900))),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.lock_outline, size: 44, color: AppColors.muted),
              const SizedBox(height: 16),
              const Text('Sign up to book a pickup', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900), textAlign: TextAlign.center),
              const SizedBox(height: 8),
              const Text('Create your free account (phone code or email) to book, pay and track your parcels.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted, height: 1.45)),
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
    final courier = courierById(_courierId);
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Book a pickup', style: TextStyle(fontWeight: FontWeight.w900)),
        leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).pop()),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
          child: Column(children: [
            Row(children: [
              for (var i = 0; i < 3; i++) ...[
                Expanded(child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _saving ? null : () => _jumpToStep(i),
                  child: SizedBox(
                    height: 26,
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: AnimatedContainer(duration: const Duration(milliseconds: 250), height: 4, decoration: BoxDecoration(color: i <= _step ? AppColors.forest : AppColors.line, borderRadius: BorderRadius.circular(4))),
                    ),
                  ),
                )),
                if (i < 2) const SizedBox(width: 7),
              ],
            ]),
            const SizedBox(height: 10),
            Align(alignment: Alignment.centerLeft, child: Text('STEP ${_step + 1} OF 3  •  ${['ROUTE', 'PARCEL & COURIER', 'DETAILS & REVIEW'][_step]}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: AppColors.muted))),
          ]),
        ),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: ListView(
              key: ValueKey(_step),
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
              children: switch (_step) {
                0 => _routeStep(),
                1 => _parcelStep(courier),
                _ => _detailsStep(courier),
              },
            ),
          ),
        ),
        _grandTotalBar(),
        Container(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
          decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: AppColors.line))),
          child: SafeArea(
            top: false,
            child: Row(children: [
              if (_step > 0) ...[
                IconButton.outlined(onPressed: _saving ? null : () => setState(() => _step--), icon: const Icon(Icons.arrow_back)),
                const SizedBox(width: 12),
              ],
              Expanded(child: FilledButton(
                onPressed: _saving ? null : (_step < 2 ? _next : _submit),
                child: _saving
                    ? const AppLogoSpinner(size: 22, color: Colors.white)
                    : Text(_step < 2 ? 'Continue' : 'Place booking'),
              )),
            ]),
          ),
        ),
      ]),
    );
  }

  List<Widget> _routeStep() => [
        Text('Where should we go?', style: TextStyle(fontSize: scaleText(context, 26), fontWeight: FontWeight.w900, letterSpacing: -0.5)),
        const SizedBox(height: 6),
        const Text('We handle the trip from the sender to the courier depot.', style: TextStyle(color: AppColors.muted)),
        const SizedBox(height: 24),
        _cityDropdown('Pickup city', _from, (value) => setState(() => _from = value)),
        const SizedBox(height: 10),
        const Center(child: Icon(Icons.arrow_downward_rounded, color: AppColors.amber)),
        const SizedBox(height: 10),
        _cityDropdown('Depot destination (receipt)', _to, (value) => setState(() => _to = value)),
        const SizedBox(height: 8),
        const InfoPill(icon: Icons.receipt_long, label: 'Your parcel is dropped at the courier depot. The destination above is for your receipt only — it is not the actual door drop-off.', color: AppColors.amber),
        const SizedBox(height: 18),
              TextField(controller: _pickup, minLines: 2, maxLines: 3, textCapitalization: TextCapitalization.sentences, decoration: InputDecoration(labelText: 'Home / shop pickup address', hintText: 'e.g. Kabwata, near the market — or a plus code like 8FQ4+J9', prefixIcon: const Icon(Icons.location_on_outlined), alignLabelWithHint: true, suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [TextButton(onPressed: _aiBusy ? null : _tidyAddress, child: _aiBusy ? const AppLogoSpinner(size: 14) : const Text('✨ Tidy')), IconButton(tooltip: 'Use my current location', onPressed: _locating ? null : _captureLocation, icon: _locating ? const AppLogoSpinner(size: 18) : const Icon(Icons.my_location_outlined, color: AppColors.forest))]))),
        if (_saved.isNotEmpty) ...[
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 2, children: [
            const Text('Saved:', style: TextStyle(fontSize: 10.5, color: AppColors.muted, fontWeight: FontWeight.w800)),
            for (final p in _saved.take(8))
              ActionChip(
                visualDensity: VisualDensity.compact,
                label: Text(p.label, style: const TextStyle(fontSize: 11)),
                onPressed: () => setState(() => _pickup.text = p.label),
              ),
          ]),
        ],
        if (_tidyPinLabel != null) ...[
          const SizedBox(height: 4),
          Row(children: [
            Expanded(child: Text(_tidyPinLabel!, style: const TextStyle(color: AppColors.forest, fontSize: 10.5, height: 1.3))),
            if (_plusCode != null) TextButton(onPressed: _openInMaps, child: const Text('View this pin', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.forest))),
          ]),
        ],
        if (_pickupLat != null && _pickupLng != null) ...[
          const SizedBox(height: 4),
          const Text('Pickup pinned. Great - we will match the nearest rider.',
              style: TextStyle(color: AppColors.forest, fontSize: 10.5, height: 1.3)),
        ] else ...[
          const SizedBox(height: 4),
          const Text('No pin - the rider uses your address. Pin for an exact route.',
              style: TextStyle(color: AppColors.amber, fontSize: 10.5, height: 1.3)),
        ],
        const SizedBox(height: 16),
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 14),
          tileColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: const BorderSide(color: AppColors.line)),
          title: const Text('Round trip', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          subtitle: const Text('If it can\'t travel on, the rider returns the parcel from the depot back to your door — no re-booking'),
          value: _roundTrip,
          onChanged: (value) => setState(() => _roundTrip = value),
        ),
        if (_roundTrip) ...[
          const SizedBox(height: 10),
          _cityDropdown('Return city', _returnCity, (value) => setState(() => _returnCity = value)),
          const SizedBox(height: 10),
          TextField(controller: _returnAddress, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(labelText: 'Return address', hintText: 'Your door — where the parcel comes back', prefixIcon: Icon(Icons.house_outlined))),
          const SizedBox(height: 6),
          const Text('The return ride (depot → your door) is confirmed at the counter before the return starts.', style: AppType.caption),
        ],
        const SizedBox(height: 16),
        const InfoPill(icon: Icons.two_wheeler, label: 'DropOff rider fee K55 / K75 / K95 by band — shown before you book'),
      ];

  List<Widget> _parcelStep(CourierInfo selected) => [
        Text('What are we carrying?', style: TextStyle(fontSize: scaleText(context, 26), fontWeight: FontWeight.w900, letterSpacing: -0.5)),
        const SizedBox(height: 22),
        SegmentedButton<ParcelSize>(
          segments: [for (final size in ParcelSize.values) ButtonSegment(value: size, label: Text(size.label))],
          selected: {_size},
          onSelectionChanged: (selection) => setState(() {
            _size = selection.first;
            if (_parcels > _parcelCap) {
              _parcels = _parcelCap;
              _parcelsCtl.text = '$_parcels';
            }
          }),
        ),
        const SizedBox(height: 16),
        TextField(controller: _description, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(labelText: 'Item contents (required)', hintText: 'e.g. Two boxed phones', helperText: 'Declare what is inside — drugs, weapons, fuel and live animals are forbidden.', prefixIcon: Icon(Icons.inventory_2_outlined))),
        const Row(children: [
          Expanded(child: Text('Contents are required — undeclared items are refused at pickup.', style: AppType.caption)),
          HelpIconButton(topic: HelpTopic.forbiddenItems),
        ]),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _parcelPhotoUploading ? null : _pickParcelPhoto,
          icon: _parcelPhotoUploading
              ? const AppLogoSpinner(size: 18)
              : Icon(_parcelPhotoUrl == null ? Icons.add_a_photo_outlined : Icons.check_circle, color: _parcelPhotoUrl == null ? null : AppColors.success),
          label: Text(_parcelPhotoUrl == null ? 'Add parcel photo (recommended)' : 'Parcel photo attached'),
        ),
        if (_parcelPhotoUrl != null || _parcelPhotoPath != null) ...[
          const SizedBox(height: 8),
          Row(children: [
            PhotoPreview(
              pathOrUrl: _parcelPhotoUrl ?? _parcelPhotoPath!,
              label: 'PARCEL',
              onRemove: () => setState(() {
                _parcelPhotoUrl = null;
                _parcelPhotoPath = null;
              }),
            ),
            const SizedBox(width: 10),
            const Expanded(child: Text('This is the photo the rider sees at pickup - check it before you book. At pickup the rider also photographs every picked-up item with a time-stamped DropOff camera photo.', style: AppType.caption)),
          ]),
        ],
        const Padding(
          padding: EdgeInsets.only(top: 4, bottom: 4),
          child: Row(children: [
            Expanded(child: Text('Photo protects you in disputes.', style: AppType.caption)),
            HelpIconButton(topic: HelpTopic.parcelPhoto),
          ]),
        ),
        // DECLARED VALUE (owner directive 2026-11-17): restored — needed for
        // the counter receipt at the depot. Optional, NOT the cover value.
        TextField(
          controller: _declaredValue,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Declared value (ZMW)',
            hintText: 'What the parcel is worth, e.g. 450',
            prefixIcon: Icon(Icons.payments_outlined),
          ),
        ),
        const Padding(
          padding: EdgeInsets.only(top: 4, bottom: 4),
          child: Text('Optional — printed on the depot counter receipt so the depot knows what it is carrying.', style: AppType.caption),
        ),
        const SizedBox(height: 10),
        // VEHICLE IS SERVER-DECIDED (owner 2026-11-21): motorcycles are the
        // default; the worker upgrades to a car automatically for large or
        // over-cap parcels. No vehicle question is shown to the sender.
        _vehicleClass == 'motorcycle'
            ? DropdownButtonFormField<int>(
                initialValue: _parcels.clamp(1, _parcelCap),
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Items', hintText: '1', prefixIcon: Icon(Icons.inventory)),
                items: List.generate(_parcelCap, (i) => i + 1)
                    .map((i) => DropdownMenuItem(value: i, child: Text('$i parcel${i == 1 ? '' : 's'}')))
                    .toList(),
                onChanged: (v) { if (v != null) { _parcels = v; _parcelsCtl.text = '$v'; setState(() {}); } },
              )
            // Cars, vans and trucks: UNLIMITED parcels — type any number.
            // Controller-driven so the value stays in sync with every clamp.
            : TextFormField(
                controller: _parcelsCtl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Items (no limit)', hintText: '1', prefixIcon: Icon(Icons.inventory)),
                onChanged: (v) {
                  final n = int.tryParse(v.replaceAll(RegExp(r'[^0-9]'), ''));
                  setState(() => _parcels = (n == null || n < 1) ? 1 : n);
                },
              ),
        if (_vehicleClass == 'car') ...[
          const SizedBox(height: 6),
          const Text('A car has been assigned automatically for this parcel size — no vehicle choice needed.',
              style: TextStyle(fontSize: 10.5, color: AppColors.forest, height: 1.3)),
        ],
        const SizedBox(height: 6),
        const Text('Each item uses one plan slot.', style: TextStyle(color: AppColors.muted, fontSize: 11.5)),
        const SizedBox(height: 26),
        Text('Choose the courier', style: TextStyle(fontSize: scaleText(context, 18), fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        const Text('Your rider takes your items to this depot.', style: TextStyle(color: AppColors.ink, fontSize: 13)),
        const SizedBox(height: 12),
        const Text('Search couriers', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.ink)),
        const SizedBox(height: 6),
        TextField(
          controller: _courierSearchCtl,
          decoration: InputDecoration(
            labelText: 'Search courier, town, or inter-town fare',
            hintText: _searchHint,
            prefixIcon: const Icon(Icons.search),
            isDense: true,
            helperText: (_from == 'Lusaka' && _to.isNotEmpty)
                ? 'Depot fare quoted at counter — search inter-town routes (e.g. Lusaka → Ndola).'
                : 'Try: “$_searchHint"',
          ),
        ),
        if (_queryEstimate != null) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.forest.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.forest.withValues(alpha: 0.18)),
            ),
            child: Row(children: [
              const Icon(Icons.local_shipping_outlined, size: 16, color: AppColors.forest),
              const SizedBox(width: 8),
              Expanded(child: Text(_queryEstimate!, style: const TextStyle(fontSize: 12, color: AppColors.ink, height: 1.3))),
            ]),
          ),
        ],
        const SizedBox(height: 12),
        if (_from != 'Lusaka') ...[
          const SizedBox(height: 12),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(Icons.schedule, size: 18, color: AppColors.muted),
                  SizedBox(width: 10),
                  Expanded(child: Text('Coming soon — courier coverage outside Lusaka', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
                ]),
                SizedBox(height: 8),
                Text(
                  'DropOff’s partner depot network is live in Lusaka. Nationwide courier coverage launches shortly — your city will appear here once it does.',
                  style: AppType.caption,
                ),
              ]),
            ),
          ),
          const SizedBox(height: 26),
        ] else ...[
          for (final courier in _filteredCouriers)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: InkWell(
                borderRadius: BorderRadius.circular(17),
                onTap: () => setState(() => _courierId = courier.id),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.all(13),
                  decoration: BoxDecoration(
                    color: _courierId == courier.id ? const Color(0xFFE9F0EB) : Colors.white,
                    borderRadius: BorderRadius.circular(17),
                    border: Border.all(color: _courierId == courier.id ? AppColors.forest : AppColors.line, width: _courierId == courier.id ? 1.5 : 1),
                  ),
                  child: Row(children: [
                    CourierAvatar(courier: courier, size: 42),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(courier.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                      const SizedBox(height: 3),
                      const Text('Depot fare confirmed at counter', style: TextStyle(fontSize: 11, color: AppColors.muted)),
                    ])),
                    Icon(_courierId == courier.id ? Icons.check_circle : Icons.circle_outlined, color: _courierId == courier.id ? AppColors.forest : AppColors.line),
                  ]),
                ),
              ),
            ),
        ],
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(color: AppColors.line.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(12)),
          child: const Text(
            'Nearest depot of your pick — no branch to choose.',
            style: AppType.caption,
          ),
        ),
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Row(children: [
            Expanded(child: Text('Rider pays the depot; you repay the exact receipt here.', style: AppType.caption)),
            HelpIconButton(topic: HelpTopic.courierFare),
          ]),
        ),
      ];

  List<Widget> _detailsStep(CourierInfo courier) => [
        Text('Nearly ready to roll.', style: TextStyle(fontSize: scaleText(context, 26), fontWeight: FontWeight.w900, letterSpacing: -0.5)),
        const SizedBox(height: 20),
        TextField(controller: _senderName, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Sender name', prefixIcon: Icon(Icons.person_outline))),
        const SizedBox(height: 12),
        TextField(controller: _senderPhone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Sender mobile number', hintText: '0971234567', prefixIcon: Icon(Icons.phone_outlined))),
        const SizedBox(height: 20),
        TextField(controller: _recipientName, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Recipient name', prefixIcon: Icon(Icons.person_pin_circle_outlined))),
        const SizedBox(height: 12),
        TextField(controller: _recipientPhone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Recipient mobile number', hintText: '0961234567', prefixIcon: Icon(Icons.phone_outlined))),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 4, children: [
          OutlinedButton.icon(
            onPressed: _openRecipientsPicker,
            icon: const Icon(Icons.contacts_outlined, size: 18),
            label: const Text('Pick saved recipient'),
          ),
          TextButton.icon(
            onPressed: _saveCurrentRecipient,
            icon: const Icon(Icons.bookmark_add_outlined, size: 18),
            label: const Text('Save this recipient'),
          ),
        ]),
        const SizedBox(height: 12),
        TextField(
          controller: _promo,
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(
            labelText: 'Promo code (optional)',
            hintText: 'SENDER20 · FIRSTM10 · LOYAL5',
            prefixIcon: const Icon(Icons.local_offer_outlined),
            suffixIcon: TextButton(onPressed: _checkPromo, child: const Text('Apply')),
            helperText: _promoPct != null ? '-${_promoPct!.toStringAsFixed(0)}% — $_promoNote' : null,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _pack,
          enabled: !_packActive,
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(
            labelText: 'Plan code (paid in bulk)',
            hintText: 'e.g. DROPW-8F2K',
            prefixIcon: const Icon(Icons.card_membership_outlined),
            suffixIcon: TextButton(onPressed: _packActive ? null : _applyPack, child: const Text('Apply')),
            helperText: _packActive
                ? 'Plan active — this booking needs no rider-payment prompt.'
                : 'Bought a plan offline? Enter its code to activate it on your number.',
          ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: const Color(0xFFFFF8E1), borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.amber)),
          child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.warning_amber_rounded, color: Color(0xFF7B5710)),
            SizedBox(width: 10),
            Expanded(child: Text('Missed handovers are logged. You can still book.', style: TextStyle(fontSize: 12, height: 1.35, color: Color(0xFF5D4200)))),
          ]),
        ),
        const SizedBox(height: 10),
        Row(children: [
          const Expanded(child: Text('Select pickup slot', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800))),
          TextButton.icon(
            onPressed: () async {
              final s = await DropOffApi.slotsSuggest(fromCity: _from);
              if (!mounted || s == null) return;
              final w = '${s['suggested_window'] ?? ''}';
              if (pickupWindows.containsKey(w) && !_slotClosed(w)) {
                setState(() => _pickupWindow = w);
                _message('${'Best slot for your area'}: $w');
              }
            },
            icon: const Icon(Icons.auto_awesome, size: 16),
            label: const Text('Best slot for your area', style: TextStyle(fontSize: 12)),
          ),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          ChoiceChip(
            selected: !_tomorrowMorning,
            label: const Text('Today'),
            onSelected: (v) => setState(() => _tomorrowMorning = !v),
          ),
          ChoiceChip(
            selected: _tomorrowMorning,
            label: const Text('Tomorrow morning (06:00)'),
            onSelected: (v) => setState(() => _tomorrowMorning = v),
          ),
        ]),
        if (_tomorrowMorning) ...[
          const SizedBox(height: 10),
          ListTile(
            tileColor: const Color(0xFFE9F0EB),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: AppColors.forest)),
            title: const Text('Tomorrow 5:30 – 7:30 AM', style: TextStyle(fontWeight: FontWeight.w800)),
            subtitle: const Text('Picked up tomorrow morning — after today’s late afternoon window has closed.'),
            trailing: const Icon(Icons.event, color: AppColors.forest),
          ),
        ] else
        ...pickupWindows.entries.map((entry) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () {
                if (_slotClosed(entry.key)) {
                  AppToast.show(context, 'The ${slotCopy[entry.key]!.title} closed (book by ${slotCopy[entry.key]!.cutoff}). Pick another slot — late bookings auto-roll to the next open window.');
                  return;
                }
                setState(() => _pickupWindow = entry.key);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: _pickupWindow == entry.key ? const Color(0xFFE9F0EB) : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _pickupWindow == entry.key ? AppColors.forest : AppColors.line, width: _pickupWindow == entry.key ? 1.5 : 1),
                ),
                child: Row(children: [
                  Icon(
                    _slotClosed(entry.key) ? Icons.lock_outline : Icons.schedule_rounded,
                    size: 20,
                    color: _slotClosed(entry.key) ? AppColors.muted : (_pickupWindow == entry.key ? AppColors.forest : AppColors.muted),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(
                      _slotClosed(entry.key)
                          ? '${slotCopy[entry.key]!.title} — closed'
                          : slotCopy[entry.key]!.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: _slotClosed(entry.key) ? AppColors.muted : AppColors.ink),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _slotClosed(entry.key)
                          ? 'Book by ${slotCopy[entry.key]!.cutoff} passed — next window still available'
                          : '${slotCopy[entry.key]!.benefit} · Book by ${slotCopy[entry.key]!.cutoff}',
                      style: AppType.caption,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ])),
                  if (_pickupWindow == entry.key && !_slotClosed(entry.key))
                    const Icon(Icons.check_circle, size: 20, color: AppColors.forest),
                ]),
              ),
            ),
          );
        }),
        const SizedBox(height: 4),
        const Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Riders sweep Lusaka in these windows; each slot locks 30 minutes before it starts. Closed slots reopen for tomorrow.',
            style: AppType.caption,
          ),
        ),
        const SizedBox(height: 4),
        _DeliveryIqCard(courierCatalogId: courier.id, window: _tomorrowMorning ? '06:00' : _pickupWindow),
        const SizedBox(height: 16),
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 14),
          tileColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: const BorderSide(color: AppColors.line)),
          title: const Text('Door delivery at destination', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          subtitle: const Text('Optional last-mile add-on • from K45 (pay-as-you-go by location)'),
          value: _lastMile,
          onChanged: (value) => setState(() => _lastMile = value),
        ),
        const SizedBox(height: 20),
        const Text('Payment preference', style: TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.forest.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: AppColors.forest.withValues(alpha: 0.35)),
          ),
          child: const Row(children: [
            Icon(Icons.phone_android, color: AppColors.forest),
            SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Mobile money — prepayment at booking', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
              SizedBox(height: 2),
              Text('The prompt pays for your parcel delivery (trip price + processing fee) and dispatches your rider on approval. No cash; riders never handle money.',
                  style: AppType.caption),
            ])),
          ]),
        ),
        const SizedBox(height: 24),
        _CounterReminder(to: _to),
        const SizedBox(height: 8),
        _PlanBanner(parcels: _parcels),
        const SizedBox(height: 14),
        Card(child: Padding(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('$_from → $_to', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
          const SizedBox(height: 4),
          Text('${courier.name} • ${_size.label} parcel • ${_tomorrowMorning ? 'Tomorrow morning sweep (05:30 – 07:30)' : pickupWindows[_pickupWindow]}', style: const TextStyle(color: AppColors.ink, fontSize: 13)),
          const Divider(height: 28),
          if (_planLeg == 'pack')
            _priceLine('DropOff leg (sender → depot)', 'Covered by plan')
          else if (_planLeg == 'overage')
            _priceLine('DropOff rider fee', kwacha(_riderFeeEstimate))
          else
            _priceLine('DropOff rider fee', kwacha(_riderFeeEstimate)),
          if (_lastMile) ...[
            _priceLine('Destination door delivery', kwacha(lastMilePrice)),
            _priceLine('Processing fee (door leg — platform + mobile money)', kwacha(DropOffApi.platformFee(lastMilePrice))),
          ],
          if (_planLeg == 'pack')
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text('Your plan covers this trip\'s sender → depot leg — no momo prompt at booking, no per-parcel fees.',
                  style: TextStyle(color: AppColors.forest, fontSize: 11.5, height: 1.4)),
            )
          else if (_payment == 'Mobile money') Builder(builder: (context) {
            final fees = DropOffApi.collectionFees(DropOffApi.round2(_dropOffLeg), riderFee: _riderFeeEstimate);
            final processing = fees['processing_fee_zmw'] ?? 0.0;
            return Column(children: [
              _priceLine('Processing fee (platform + mobile money)', kwacha(processing)),
              _priceLine('Charged on your DropOff order', kwacha(_dropOffDue), bold: true),
              const SizedBox(height: 4),
              const Text(
                'You never pay the rider payout — that is settled between DropOff and the rider, not added to your fare.',
                style: AppType.caption,
              ),
          ]);
          }),
          const Divider(height: 24),
          _priceLine('DropOff charge est. now', kwacha(_dropOffDue), bold: true),
          const Padding(padding: EdgeInsets.only(top: 8), child: Text('Rider pays the depot; you repay the exact receipt here.', style: TextStyle(color: AppColors.muted, fontSize: 11))),
        ]))),
        ];

  Widget _priceLine(String label, String value, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(children: [
          Expanded(child: Text(label, style: TextStyle(color: bold ? AppColors.ink : AppColors.muted, fontWeight: bold ? FontWeight.w800 : FontWeight.normal))),
          Text(value, style: TextStyle(fontWeight: bold ? FontWeight.w900 : FontWeight.w700, fontSize: bold ? 18 : 14)),
        ]),
      );

  /// Full-width grand-total bar promoted above the Place booking button so the
  /// seller never misses what they actually pay. Plan members see the leg as
  /// covered — the depot counter fare is never part of this number.
  Widget _grandTotalBar() {
    final covered = _planLeg == 'pack';
    return Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(20, 8, 20, 4),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: covered ? AppColors.forest.withValues(alpha: 0.1) : AppColors.forest.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.forest.withValues(alpha: covered ? 0.4 : 0.22)),
        ),
        child: Row(children: [
          Icon(covered ? Icons.card_membership : Icons.receipt_long, size: 18, color: AppColors.forest),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              covered ? 'Plan covers this trip' : 'Estimated total you pay DropOff',
              maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, color: AppColors.ink),
            ),
          ),
          const SizedBox(width: 8),
          Text(kwacha(_dropOffDue), maxLines: 1, overflow: TextOverflow.ellipsis, softWrap: false, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: AppColors.forest)),
          const SizedBox(width: 6),
          const Expanded(
            child: Text('', maxLines: 2, overflow: TextOverflow.ellipsis, softWrap: true, style: TextStyle(fontSize: 11, color: AppColors.muted)),
          ),
        ]),
      );
  }

  Widget _cityDropdown(String label, String value, ValueChanged<String> onChanged) => DropdownButtonFormField<String>(
        initialValue: value,
        decoration: InputDecoration(labelText: label, prefixIcon: const Icon(Icons.location_on_outlined)),
        items: [for (final city in _cities) DropdownMenuItem(value: city, child: Text(city))],
        onChanged: (value) { if (value != null) onChanged(value); },
      );
}

/// Shown after booking. Plan-covered trips (nothing due) or a CONFIRMED
/// prepayment see the success view. When the DropOff prepayment never landed,
/// the SAME screen flips to the HELD variant: the booking details stay visible,
/// the green check is gone, and a big "Pay now — dispatch rider" button re-tries
/// the momo prompt. No "your pickup is booked" screen without confirmed money.
class BookingSuccessScreen extends StatefulWidget {
  final String bookingId;
  final bool paymentHeld;
  const BookingSuccessScreen({super.key, required this.bookingId, this.paymentHeld = false});

  @override
  State<BookingSuccessScreen> createState() => _BookingSuccessScreenState();
}

class _BookingSuccessScreenState extends State<BookingSuccessScreen>
    with WidgetsBindingObserver {
  bool _busy = false;
  bool _pausing = false;
  bool? _pausedOverride;
  late bool _paid = !widget.paymentHeld;

  // HELD-PAYMENT WATCH (owner bug 2026-11-17: "I paid but the payment screen
  // didn't check or poll the transacting number"): the held screen polls
  // GET /jobs/:ref/payments — the booking-time prompt's row, INCLUDING the
  // transacting phone — and the server re-checks pending rows against Lipila
  // on every call. A prompt approved late (or whose webhook never arrived)
  // still settles here, flips the screen to PAID and dispatches the rider.
  Timer? _watchTimer;
  int _watchCalls = 0;
  bool _watchInFlight = false;
  Object? _lastFailedPayId; // one rejection toast per payment row
  String? _promptPhone; // the number the momo prompt was fired at

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.paymentHeld) {
      // AppScope.of walks an InheritedNotifier — never read it inside
      // initState; the first tick runs right after the first frame.
      WidgetsBinding.instance.addPostFrameCallback((_) => _watchTick());
      _watchTimer = Timer.periodic(const Duration(seconds: 3), (_) => _watchTick());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _watchTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Returning from the momo app is exactly when an approval may have landed.
    if (state == AppLifecycleState.resumed && widget.paymentHeld) _watchTick();
  }

  /// One reconcile step: ≈3 s cadence for the first 90 s, then a slower tail
  /// (every 4th tick) up to ~7 min total. Every app RESUME forces a check
  /// regardless of cadence.
  Future<void> _watchTick() async {
    if (!mounted || _paid || _watchInFlight) return;
    _watchCalls++;
    if (_watchCalls > 30 && _watchCalls % 4 != 0) return;
    if (_watchCalls > 108) {
      _watchTimer?.cancel();
      return;
    }
    final store = AppScope.of(context);
    Booking? booking;
    for (final item in store.bookings) {
      if (item.id == widget.bookingId) {
        booking = item;
        break;
      }
    }
    final jobRef = booking?.serverRef;
    if (jobRef == null || jobRef.isEmpty) return; // not synced yet — retry next tick
    _watchInFlight = true;
    try {
      final pay = await DropOffApi.latestJobPayment(jobRef);
      if (!mounted || _paid) return;
      if (pay != null) {
        final phone = '${pay['phone'] ?? ''}'.trim();
        if (phone.isNotEmpty && phone != _promptPhone) setState(() => _promptPhone = phone);
        final status = '${pay['status'] ?? ''}';
        if (status == 'success') {
          _watchTimer?.cancel();
          setState(() => _paid = true);
          AppToast.show(context, 'Prepayment received — your rider is being dispatched.');
          unawaited(AppScope.of(context).syncJobsFromServer());
          return;
        }
        if (status == 'failed') {
          final pid = pay['payment_id'];
          if (pid != _lastFailedPayId) {
            _lastFailedPayId = pid;
            final why = pay['fail_reason'] as String?;
            AppToast.show(context, (why == null || why.isEmpty)
                ? 'That momo prompt was rejected — tap Pay now to send a fresh one.'
                : 'Payment failed: $why — top up your momo wallet, then tap Pay now to send a fresh one.');
          }
        }
      }
    } finally {
      _watchInFlight = false;
    }
  }

  Future<void> _togglePause(Booking booking, bool pause) async {
    final jobRef = booking.serverRef;
    if (jobRef == null || jobRef.isEmpty) {
      AppToast.show(context, 'This booking has not reached the server yet.');
      return;
    }
    setState(() => _pausing = true);
    final res = await DropOffApi.jobPauseReprompt(jobRef, paused: pause);
    if (!mounted) return;
    setState(() {
      _pausing = false;
      if (res.ok) _pausedOverride = pause;
    });
    AppToast.show(context, res.ok
        ? (pause ? 'Reminders paused — the booking stays HELD. Resume anytime.' : 'Reminders resumed — tap Pay now when you are ready.')
        : 'Could not update reminders (${res.error ?? 'try again'}).');
    if (res.ok) unawaited(AppScope.of(context).syncJobsFromServer());
  }

  Future<void> _payNow(Booking booking) async {
    final jobRef = booking.serverRef;
    if (jobRef == null || jobRef.isEmpty) {
      AppToast.show(context, 'This booking has not reached the server yet — it syncs when you are back online.');
      return;
    }
    if (_busy) return;
    setState(() => _busy = true);
    final out = await PayJob.startAndPoll(jobRef: jobRef, phone: booking.senderPhone);
    if (!mounted) return;
    setState(() => _busy = false);
    switch (out.status) {
      case 'success':
        _watchTimer?.cancel();
        AppToast.show(context, 'Prepayment received — your rider is being dispatched.');
        setState(() => _paid = true);
        unawaited(AppScope.of(context).syncJobsFromServer());
        break;
      case 'failed':
        AppToast.show(context, (out.failReason == null || out.failReason!.isEmpty)
            ? 'The momo prompt was rejected — verify your mobile-money balance has the funds, then tap Pay now again.'
            : 'Payment failed: ${out.failReason} — top up your momo wallet, then tap Pay now again.');
        break;
      default:
        if (out.status.startsWith('error:')) {
          AppToast.show(context, 'Payment could not start (${out.status.substring(6)}) — check your connection and tap Pay now again.');
        } else {
          AppToast.show(context, 'Prompt sent — approve it on your phone to dispatch your rider.');
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Safe lookup — firstWhere would THROW if the booking dropped out of the
    // store mid-view (sync prune / sign-out), crashing the payment screen.
    Booking? found;
    for (final item in AppScope.of(context).bookings) {
      if (item.id == widget.bookingId) {
        found = item;
        break;
      }
    }
    if (found == null) {
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.cloud_off_outlined, size: 44, color: AppColors.muted),
              const SizedBox(height: 14),
              const Text('Booking is syncing…',
                  textAlign: TextAlign.center, style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              const Text('It appears here the moment the server sync completes.',
                  textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted, height: 1.5)),
              const SizedBox(height: 18),
              FilledButton.tonal(onPressed: () => Navigator.of(context).pop(), child: const Text('Back to home')),
            ]),
          ),
        ),
      );
    }
    final Booking booking = found; // promote once — closures below capture a non-null local
    if (!_paid) return _held(booking);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(26),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Spacer(),
            SvgPicture.asset('assets/brand/dropoff-logo.svg', height: 48),
            const SizedBox(height: 16),
            const CircleAvatar(radius: 48, backgroundColor: Color(0xFFE3EFE6), child: Icon(Icons.check_rounded, color: AppColors.forest, size: 52)),
            const SizedBox(height: 26),
            const Text('Your pickup is booked.', textAlign: TextAlign.center, style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
            const SizedBox(height: 10),
            Text('Reference ${booking.reference}\n${booking.fromCity} → ${booking.toCity}', textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted, height: 1.6)),
            const SizedBox(height: 18),
            InfoPill(icon: Icons.route_rounded, label: 'DropOff rides to the courier — reference ${booking.reference}'),
            const Spacer(),
            FilledButton.tonalIcon(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => WaybillScreen(bookingId: booking.id))),
              icon: const Icon(Icons.receipt_long_outlined, size: 20),
              label: const Text('Show at depot'),
            ),
            const SizedBox(height: 10),
            FilledButton(onPressed: () => Navigator.of(context).pushReplacement(MaterialPageRoute<void>(builder: (_) => BookingDetailScreen(bookingId: booking.id))), child: const Text('Track this booking')),
            const SizedBox(height: 10),
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Back to home')),
          ]),
        ),
      ),
    );
  }

  /// HELD variant — the unpaid booking. Details ON SCREEN, Pay now button,
  /// no success copy, no dispatch language until money lands. Includes a
  /// Pause/Resume toggle for the sender who can't pay right now.
  Widget _held(Booking booking) {
    final paused = _pausedOverride ?? booking.repromptPaused;
    return Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(26),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Spacer(),
              const CircleAvatar(radius: 48, backgroundColor: Color(0xFFFDECEA), child: Icon(Icons.pause_rounded, color: AppColors.danger, size: 52)),
              const SizedBox(height: 22),
              Text(paused ? 'Reminders paused — payment held' : 'Payment required to dispatch', textAlign: TextAlign.center, style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w900)),
              const SizedBox(height: 10),
              Text(paused
                  ? 'You asked us not to prompt you for now. The booking stays saved and HELD — no rider until you pay. Pushes already on your phone can\'t be recalled.'
                  : 'Your booking is saved but HELD. No rider is assigned — and nothing moves — until your prepayment lands.', textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted, height: 1.5)),
              const SizedBox(height: 18),
              Text('Reference ${booking.reference}\n${booking.fromCity} → ${booking.toCity}', textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted, height: 1.6)),
              const SizedBox(height: 10),
              if (paused)
                const InfoPill(icon: Icons.notifications_off_outlined, label: 'Reminders paused by you — resume below')
              // The transacting number comes from the payment row via the
              // held-watch — the user knows exactly which phone to approve on.
              else InfoPill(
                  icon: Icons.payments_outlined,
                  label: _promptPhone == null
                      ? 'Momo prompt pending — approve it to dispatch'
                      : 'Momo prompt sent to $_promptPhone — approve it to dispatch'),
              const Spacer(),
              if (!paused && (_watchTimer?.isActive ?? false)) ...[
                const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  AppLogoSpinner(size: 13),
                  SizedBox(width: 8),
                  Text('Checking your payment…',
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: AppColors.muted)),
                ]),
                const SizedBox(height: 12),
              ],
              if (!paused) SizedBox(
                height: 54,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: AppColors.danger, foregroundColor: Colors.white),
                  onPressed: _busy ? null : () => _payNow(booking),
                  icon: _busy
                      ? const AppLogoSpinner(size: 18, color: Colors.white)
                      : const Icon(Icons.payments_outlined),
                  label: Text(_busy ? 'Sending prompt…' : 'Pay now — dispatch rider', style: AppType.subhead),
                ),
              ),
              if (!paused) const SizedBox(height: 4),
              TextButton.icon(
                onPressed: _pausing ? null : () => _togglePause(booking, !paused),
                icon: _pausing
                    ? const AppLogoSpinner(size: 16)
                    : Icon(paused ? Icons.notifications_active_outlined : Icons.notifications_off_outlined, size: 18),
                label: Text(_pausing ? 'Working…' : (paused ? 'Resume reminders' : 'Pause reminders — I can\'t pay right now'),
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: paused ? AppColors.forest : AppColors.danger)),
              ),
              const SizedBox(height: 4),
              FilledButton.tonalIcon(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => BookingDetailScreen(bookingId: booking.id))),
                icon: const Icon(Icons.receipt_long_outlined, size: 20),
                label: const Text('Booking details'),
              ),
              const SizedBox(height: 10),
              TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Back to home')),
            ]),
          ),
        ),
      );
  }
}



/// SMART COUNTER REMINDER (owner directive 2026-11-12): a repeat sender sees
/// what they ACTUALLY paid at that destination's depot last time — drawn only
/// from PAID depot receipts already filed on their bookings. This is memory
/// of real receipts, never a quote: the next trip's fare is still decided at
/// the depot counter and repaid from the receipt photo.
class _CounterReminder extends StatelessWidget {
  final String to;
  const _CounterReminder({required this.to});

  @override
  Widget build(BuildContext context) {
    final dest = to.trim().toLowerCase();
    if (dest.isEmpty) return const SizedBox.shrink();
    final hits = AppScope.of(context)
        .bookings
        .where((b) =>
            b.dispatched &&
            b.counterReceiptPaid &&
            (b.counterReceiptZmw ?? 0) > 0 &&
            b.toCity.trim().toLowerCase() == dest)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (hits.isEmpty) return const SizedBox.shrink();
    final last = hits.first;
    final courierName = courierById(last.courierId).name;
    final d = last.createdAt;
    final when = '${d.day}/${d.month}/${d.year}';
    final parcelsSeen = hits.fold<int>(0, (n, b) => n + b.parcels);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.amber.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.amber.withValues(alpha: 0.4)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.history, size: 15, color: Color(0xFF7B5710)),
          SizedBox(width: 6),
          Text('Smart reminder', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: Color(0xFF7B5710))),
        ]),
        const SizedBox(height: 5),
        Text(
          'Last time to ${last.toCity} you paid K${(last.counterReceiptZmw ?? 0).toStringAsFixed(2)} at the $courierName counter ($when).'
          '${parcelsSeen > 1 ? ' Across ${hits.length} paid trip${hits.length == 1 ? '' : 's'} ($parcelsSeen parcels) since you started booking there.' : ''}'
          ' Expect a similar depot amount — your rider fronts it and you repay exactly what the receipt says.',
          style: AppType.caption,
        ),
      ]),
    );
  }
}

/// Shows the signed-in sender which plan is active and how this trip deducts
/// from it — no more guessing between plan parcels and pay-as-you-go.
class _PlanBanner extends StatefulWidget {
  final int parcels;
  const _PlanBanner({required this.parcels});

  @override
  State<_PlanBanner> createState() => _PlanBannerState();
}

class _PlanBannerState extends State<_PlanBanner> {
  // Cached so the subscription is fetched ONCE — not on every rebuild/keystroke.
  late final Future<Map<String, dynamic>?> _future = DropOffApi.subscription();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: _future,
      builder: (context, snap) {
        final sub = snap.data?['subscription'] as Map<String, dynamic>?;
        final plan = snap.data?['plan'] as Map<String, dynamic>?;
        if (snap.connectionState != ConnectionState.done) return const SizedBox.shrink();
        if (sub == null || plan == null || sub['status'] != 'active') {
          return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AppColors.line.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(12)),
            child: const Text(
              'Pay-as-you-go — rider fee billed per trip.',
              style: AppType.caption,
            ),
          );
        }
        final tier = '${sub['tier']}'.toUpperCase();
        final cap = (plan['parcels_per_month'] as num?)?.toInt() ?? 0;
        final used = (snap.data?['usage_this_period'] as num?)?.toInt() ?? 0;
        final remaining = (snap.data?['remaining_this_period'] as num?)?.toInt() ?? 0;
        final pct = (plan['overage_discount_pct'] as num?)?.toInt() ?? 0;
        final renews = '${sub['period_end'] ?? ''}'.split(' ').first;
        final covered = remaining >= widget.parcels;
        return Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(color: AppColors.forest.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.forest.withValues(alpha: 0.35))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.card_membership, size: 17, color: AppColors.forest),
              const SizedBox(width: 8),
              Expanded(child: Text('$tier plan active — $used of $cap parcels used', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: AppColors.forest))),
            ]),
            const SizedBox(height: 5),
            Text(
              covered
                  ? 'This trip deducts ${widget.parcels} parcel${widget.parcels == 1 ? '' : 's'} — $remaining left. Renews $renews.'
                  : 'Only $remaining left on your $tier plan — this trip pays your tier discount ($pct% off pay-as-you-go). Renews $renews.',
              style: AppType.caption,
            ),
          ]),
        );
      },
    );
  }
}

/// Catalog → live chargebook ids: see data/catalog.dart (kCourierServerIds,
/// courierServerIdOf, courierCatalogForServerId) — single source of truth.

/// Delivery IQ — how fast this courier's depot actually receives parcels:
/// the typical (and slow-day) pickup→depot minutes from the last 90 days of
/// real job events, shown right where the pickup window is picked.
class _DeliveryIqCard extends StatefulWidget {
  const _DeliveryIqCard({required this.courierCatalogId, required this.window});

  final String courierCatalogId;
  final String window;

  @override
  State<_DeliveryIqCard> createState() => _DeliveryIqCardState();
}

class _DeliveryIqCardState extends State<_DeliveryIqCard> {
  Future<Map<String, dynamic>?>? _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _DeliveryIqCard old) {
    super.didUpdateWidget(old);
    if (old.courierCatalogId != widget.courierCatalogId || old.window != widget.window) _load();
  }

  void _load() {
    if (!DropOffApi.enabled) return;
    // 'now' is a UI-only slot — the IQ window filter wants a real slot or none.
    final w = widget.window == 'now' ? '' : widget.window;
    _future = DropOffApi.iqEta(courierServerIdOf(widget.courierCatalogId) ?? 1, w);
  }

  @override
  Widget build(BuildContext context) {
    if (!DropOffApi.enabled) return const SizedBox.shrink();
    return FutureBuilder<Map<String, dynamic>?>(
      future: _future,
      builder: (context, snap) {
        final data = snap.data;
        final p50 = (data?['minutes_p50'] as num?)?.toInt();
        final p90 = ((data?['minutes_p90'] as num?)?.toInt() ?? p50 ?? 45).toString();
        if (p50 == null) return const SizedBox.shrink(); // no data yet — stay quiet
        // Hide the advertised fallback — senders reading "~50 min" are being
        // told a fabricated number. Show only real measured averages.
        final fallback = data?['fallback'] == true;
        final n = (data?['sample_count'] as num?)?.toInt() ?? 0;
        if (fallback || n < 5) return const SizedBox.shrink();
        return Container(
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.forest.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.forest.withValues(alpha: 0.18)),
          ),
          child: Row(children: [
            const Icon(Icons.speed_rounded, size: 18, color: AppColors.forest),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Delivery IQ: this courier usually reaches the depot in ~$p50 min; busy days up to $p90 min (from $n recent pickups).',
                style: const TextStyle(color: AppColors.forest, fontSize: 11.5, height: 1.35),
              ),
            ),
          ]),
        );
      },
    );
  }
}

