import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../data/catalog.dart';
import '../data/dropoff_api.dart';
import '../data/analytics_service.dart';
import '../main.dart';
import '../models/booking.dart';
import '../ui/app_theme.dart';
import '../widgets/common.dart';
import 'account_screen.dart';
import 'bookings_screen.dart';

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
  static const double riderFee = 45;
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
    '06:00': (title: '6:00 – 7:30 AM window', benefit: 'Catches early outbound buses', cutoff: '05:30'),
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
  late String _courierId = widget.initialCourierId ?? 'platinum';
  ParcelSize _size = ParcelSize.small;
  bool _lastMile = false;
  bool _roundTrip = false;
  String _returnCity = 'Lusaka';
  String _payment = 'Mobile money';
  bool _packActive = false;
  bool _saving = false;
  bool _aiBusy = false;
  String? _parcelPhotoUrl;
  bool _parcelPhotoUploading = false;
  List<String> _cities = cities;
  double? _promoPct;
  String _promoNote = '';

  /// Vehicle class for this trip. Trucks are for large cargo (fridges, sofas);
  /// cars/vans cover most everyday parcels.
  String _vehicleClass = 'motorcycle';
  int _parcels = 1;
  final _courierSearchCtl = TextEditingController();
  static const Map<String, int> _maxParcelsByVehicle = {'motorcycle': 3, 'car': 6, 'van': 10, 'truck': 15};
  static const Map<String, String> _vehicleLabels = {'motorcycle': 'Motorcycle', 'car': 'Car', 'van': 'Van', 'truck': 'Truck (large cargo)'};

  @override
  void initState() {
    super.initState();
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
      // Older snapshots/job rows carry the chargebook weight class instead.
      switch ('${pre['weight_class'] ?? ''}') {
        case '0-5kg': _size = ParcelSize.small; break;
        case '5-15kg': _size = ParcelSize.medium; break;
        case '15kg+': _size = ParcelSize.large; break;
      }
      _courierId = courierCatalogForServerId(int.tryParse('${pre['courier_id'] ?? ''}') ?? 1);
      final parcels = (pre['parcels'] as num?)?.toInt() ?? 0;
      if (parcels > 0 && parcels <= _maxParcelsByVehicle[_vehicleClass]!) _parcels = parcels;
      final vehicle = '${pre['vehicle_class'] ?? ''}';
      if (_maxParcelsByVehicle.containsKey(vehicle)) {
        _vehicleClass = vehicle;
        if (_parcels > _maxParcelsByVehicle[vehicle]!) _parcels = _maxParcelsByVehicle[vehicle]!;
      }
    }
    _courierSearchCtl.addListener(() => setState(() {}));
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
    for (final controller in [_pickup, _description, _senderName, _senderPhone, _recipientName, _recipientPhone, _promo, _pack, _returnAddress, _courierSearchCtl]) {
      controller.dispose();
    }
    super.dispose();
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
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Promo $code applied — ${_promoPct!.toStringAsFixed(0)}% off your DropOff charge.')));
    } else {
      setState(() {
        _promoPct = null;
        _promoNote = res?['error'] == 'promo_not_found' ? 'Promo not recognised.' : 'Could not check the promo right now.';
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_promoNote)));
    }
  }

  List<CourierInfo> get _filteredCouriers => couriers.where((c) => c.name.toLowerCase().contains(_courierSearchCtl.text.toLowerCase())).toList();

  double? get _courierFare => courierFareFor(courierId: _courierId, fromCity: _from, toCity: _to, size: _size);

  /// DropOff-only leg: rider fee + door leg (+door-leg platform cut). Never partner money.
  double get _dropOffLeg => riderFee + (_lastMile ? lastMilePrice + DropOffApi.platformFee(lastMilePrice) : 0);

  /// What the customer pays DropOff on the prompt for this order.
  double get _dropOffDue =>
      DropOffApi.collectionFees(DropOffApi.round2(_dropOffLeg), riderFee: riderFee)['prompt_total_zmw'] ?? _dropOffLeg;

  void _message(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

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
    setState(() => _parcelPhotoUploading = true);
    final bytes = await picked.readAsBytes();
    final res = await DropOffApi.uploadImage(bytes, picked.name.isNotEmpty ? picked.name : 'parcel.jpg', kind: 'kyc');
    if (!mounted) return;
    setState(() {
      _parcelPhotoUploading = false;
      if (res.ok && res.body['url'] is String) _parcelPhotoUrl = res.body['url'] as String;
    });
    _message(res.ok ? 'Parcel photo attached — protects you if the parcel is disputed.' : 'Photo upload failed. You can still book.');
  }

  /// AI tidy-up of the free-text pickup address (best-effort; never blocks).
  Future<void> _aiTidyAddress() async {
    final text = _pickup.text.trim();
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
    if (parts.isNotEmpty) _pickup.text = parts.join(', ');
    final phone = '${parsed['phone'] ?? ''}'.trim();
    if (phone.isNotEmpty && _senderPhone.text.trim().isEmpty) _senderPhone.text = phone;
    _message('AI tidied the address - check it before booking.');
  }

  bool _validPhone(String value) => RegExp(r'^(?:\+?260|0)?[79][567]\d{7}$').hasMatch(value.replaceAll(RegExp(r'[\s-]'), ''));

  void _next() {
    if (_step == 0) {
      if (_from == _to) return _message('Choose different pickup and destination cities.');
      if (_pickup.text.trim().length < 4) return _message('Enter the home or shop pickup address.');
    } else if (_step == 1) {
      if (_description.text.trim().length < 3) return _message('Briefly describe what is inside the parcel.');
    }
    setState(() => _step++);
  }

  Future<void> _submit() async {
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
      riderFee: riderFee,
      courierFare: _courierFare,
      lastMileFee: _lastMile ? lastMilePrice : 0,
      pickupWindow: _tomorrowMorning ? 'tomorrow:06:00' : _pickupWindow,
      promoCode: _promo.text.trim(),
      roundTrip: _roundTrip,
      returnCity: _roundTrip ? _returnCity : null,
      returnAddress: _roundTrip ? _returnAddress.text.trim().isEmpty ? null : _returnAddress.text.trim() : null,
      returnLegFee: _roundTrip ? (_courierFare ?? 0) : 0,
      pickupAt: null,
      parcels: _parcels,
      vehicleClass: _vehicleClass,
      parcelPhotoUrl: _parcelPhotoUrl,
    );
    if (store.lastBookingWindowRolled != null) {
      _message('The ${store.lastBookingWindowRolled} window had closed — your booking moved to the next open slot automatically.');
    } else if (_tomorrowMorning) {
      _message('You booked the TOMORROW 6:00 – 7:30 AM early sweep — the rider collects in the morning.');
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
    if (booking.dispatched && inclusion == 'pack') {
      if (mounted) {
        final remaining = (used != null && cap != null) ? cap - used : null;
        _message(
          remaining != null && remaining >= 0
              ? 'Covered by your plan — $justParcels parcel${justParcels == 1 ? '' : 's'} deducted ($remaining left on your plan). No payment due.'
              : 'Covered by your plan — $justParcels parcel${justParcels == 1 ? '' : 's'} deducted. No payment due.',
        );
      }
    } else if (booking.dispatched && inclusion == 'payg' && used != null && cap != null && used >= cap) {
      // Plan cap reached: tier overage applied server-side — still collect.
      if (_payment == 'Mobile money' && DropOffApi.enabled && store.linked && due != null && due > 0) {
        if (mounted) {
          _message('Your plan cap is reached — this trip uses your tier discount. Pay K${due.toStringAsFixed(2)} to dispatch.');
        }
        final res = await DropOffApi.pay(
          jobRef: booking.serverRef!,
          phone: _senderPhone.text,
          idempotencyKey: 'pay-${booking.serverRef}',
        );
        if (res.ok) {
          final paymentId = '${res.body['payment_id']}';
          String status = 'pending';
          for (var attempt = 0; attempt < 20 && status == 'pending'; attempt++) {
            await Future<void>.delayed(const Duration(seconds: 2));
            status = await DropOffApi.paymentStatus(paymentId) ?? 'pending';
          }
          if (!mounted) return;
          final msg = switch (status) {
            'success' => 'Lipila payment received. Your rider is being dispatched.',
            'failed' => 'The mobile-money request was rejected — try Cash at pickup.',
            _ => 'Payment still pending — the rider sweep confirms when your money lands.',
          };
          _message(msg);
        } else if (mounted) {
          _message('Payment could not start now (${res.error}); the booking is saved — settle at pickup or try again.');
        }
      } else if (mounted) {
        _message(due != null && due > 0
            ? 'Plan cap reached — tier discount applied. K${due.toStringAsFixed(2)} due on this DropOff leg.'
            : 'Plan cap reached — tier discount applied to this DropOff leg.');
      }
    } else if (booking.dispatched && DropOffApi.enabled && _payment == 'Mobile money' && store.linked) {
      _message('Sending a Lipila prompt${due != null ? ' for K${due.toStringAsFixed(2)}' : ''} to ${_senderPhone.text}…\nYou pay DropOff only — the courier counter fare stays with the depot.');
      final res = await DropOffApi.pay(
        jobRef: booking.serverRef!,
        phone: _senderPhone.text,
        idempotencyKey: 'pay-${booking.serverRef}',
      );
      if (res.ok) {
        final paymentId = '${res.body['payment_id']}';
        String status = 'pending';
        for (var attempt = 0; attempt < 20 && status == 'pending'; attempt++) {
          await Future<void>.delayed(const Duration(seconds: 2));
          status = await DropOffApi.paymentStatus(paymentId) ?? 'pending';
        }
        if (!mounted) return;
        final msg = switch (status) {
          'success' => 'Lipila payment received. Your rider is being dispatched.',
          'failed' => 'The mobile-money request was rejected — try Cash at pickup.',
          _ => 'Payment still pending — the rider sweep confirms when your money lands.',
        };
        _message(msg);
      } else if (mounted) {
        _message('Payment could not start now (${res.error}); the booking is saved — settle at pickup or try again.');
      }
    } else if (booking.dispatched && due != null && due > 0 && mounted) {
      // Cash at pickup (or offline): still surface the exact amount due.
      _message('DropOff leg due: K${due.toStringAsFixed(2)} — settle by mobile money or at pickup. Courier counter fare is separate.');
    }
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute<void>(builder: (_) => BookingSuccessScreen(bookingId: booking.id)));
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
                Expanded(child: AnimatedContainer(duration: const Duration(milliseconds: 250), height: 4, decoration: BoxDecoration(color: i <= _step ? AppColors.forest : AppColors.line, borderRadius: BorderRadius.circular(4)))),
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
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
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
              TextField(controller: _pickup, minLines: 2, maxLines: 3, textCapitalization: TextCapitalization.sentences, decoration: InputDecoration(labelText: 'Home / shop pickup address', hintText: 'e.g. Kabwata, near the market', prefixIcon: const Icon(Icons.location_on_outlined), alignLabelWithHint: true, suffixIcon: TextButton(onPressed: _aiBusy ? null : _aiTidyAddress, child: _aiBusy ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('AI tidy')))),
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
          const Text('The return ride (depot → your door) is estimated at the depot counter fare for the reverse leg and confirmed at the counter.', style: TextStyle(color: AppColors.muted, fontSize: 11, height: 1.35)),
        ],
        const SizedBox(height: 16),
        const InfoPill(icon: Icons.two_wheeler, label: 'Pickup rider fee: from K45'),
      ];

  List<Widget> _parcelStep(CourierInfo selected) => [
        Text('What are we carrying?', style: TextStyle(fontSize: scaleText(context, 26), fontWeight: FontWeight.w900, letterSpacing: -0.5)),
        const SizedBox(height: 22),
        SegmentedButton<ParcelSize>(
          segments: [for (final size in ParcelSize.values) ButtonSegment(value: size, label: Text(size.label))],
          selected: {_size},
          onSelectionChanged: (selection) => setState(() => _size = selection.first),
        ),
        const SizedBox(height: 16),
        TextField(controller: _description, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(labelText: 'Parcel contents', hintText: 'e.g. Two boxed phones', prefixIcon: Icon(Icons.inventory_2_outlined))),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _parcelPhotoUploading ? null : _pickParcelPhoto,
          icon: _parcelPhotoUploading
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : Icon(_parcelPhotoUrl == null ? Icons.add_a_photo_outlined : Icons.check_circle, color: _parcelPhotoUrl == null ? null : AppColors.success),
          label: Text(_parcelPhotoUrl == null ? 'Add parcel photo (recommended)' : 'Parcel photo attached'),
        ),
        const Padding(
          padding: EdgeInsets.only(top: 4, bottom: 4),
          child: Text('A clear photo of the parcel protects you — the rider\'s depot drop-off photo is checked against it.', style: TextStyle(color: AppColors.muted, fontSize: 11, height: 1.35)),
        ),
        const SizedBox(height: 8),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: DropdownButtonFormField<String>(
            initialValue: _vehicleClass,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Vehicle', hintText: 'Motorcycle', prefixIcon: Icon(Icons.directions)),
            items: _vehicleLabels.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value, maxLines: 1, overflow: TextOverflow.ellipsis))).toList(),
            onChanged: (v) { if (v != null) { _vehicleClass = v; if (_parcels > _maxParcelsByVehicle[v]!) _parcels = _maxParcelsByVehicle[v]!; setState(() {}); } },
          )),
          const SizedBox(width: 12),
          Expanded(child: DropdownButtonFormField<int>(
            initialValue: _parcels.clamp(1, _maxParcelsByVehicle[_vehicleClass]!),
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Parcels', hintText: '1', prefixIcon: Icon(Icons.inventory)),
            items: List.generate(_maxParcelsByVehicle[_vehicleClass]!, (i) => i + 1).map((i) => DropdownMenuItem(value: i, child: Text('$i parcel${i == 1 ? '' : 's'}', maxLines: 1, overflow: TextOverflow.ellipsis))).toList(),
            onChanged: (v) { if (v != null) setState(() => _parcels = v); },
          )),
        ]),
        const SizedBox(height: 6),
        const Text('Each parcel counts as one plan parcel.', style: TextStyle(color: AppColors.muted, fontSize: 11.5)),
        const SizedBox(height: 26),
        Text('Choose the courier', style: TextStyle(fontSize: scaleText(context, 18), fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        const Text('Your rider takes the parcel to this company’s depot.', style: TextStyle(color: AppColors.muted, fontSize: 13)),
        const SizedBox(height: 12),
        const Text('Search couriers', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.muted)),
        const SizedBox(height: 6),
        TextField(controller: _courierSearchCtl, decoration: const InputDecoration(labelText: 'Filter by name', hintText: 'e.g. DHL, Platinum', prefixIcon: Icon(Icons.search), isDense: true)),
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
                  style: TextStyle(color: AppColors.muted, fontSize: 12, height: 1.4),
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
                      Text(courierFareFor(courierId: courier.id, fromCity: _from, toCity: _to, size: _size) == null ? 'Courier fare confirmed at depot' : 'Courier fare ${kwacha(courierFareFor(courierId: courier.id, fromCity: _from, toCity: _to, size: _size))}', style: const TextStyle(fontSize: 11, color: AppColors.muted)),
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
          child: const Row(children: [
            Icon(Icons.info_outline, size: 16, color: AppColors.muted),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Your rider takes the parcel to the nearest depot of the courier you choose — no branch to pick.',
                style: TextStyle(color: AppColors.muted, fontSize: 11, height: 1.4),
              ),
            ),
          ]),
        ),
        if (selected.hasVerifiedRates && _from != 'Lusaka')
          const Text('Platinum’s captured tariff starts from Lusaka. This reverse/other route needs a counter quote.', style: TextStyle(color: AppColors.muted, fontSize: 12, height: 1.4)),
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
        const SizedBox(height: 12),
        TextField(
          controller: _promo,
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(
            labelText: 'Promo code (optional)',
            hintText: 'SELLER20 · FIRSTM10 · LOYAL5',
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
        const Text('Select pickup slot', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
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
            title: const Text('Tomorrow 6:00 – 7:30 AM', style: TextStyle(fontWeight: FontWeight.w800)),
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
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text('The ${slotCopy[entry.key]!.title} closed (book by ${slotCopy[entry.key]!.cutoff}). Pick another slot — late bookings auto-roll to the next open window.'),
                  ));
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
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: _slotClosed(entry.key) ? AppColors.muted : AppColors.ink),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _slotClosed(entry.key)
                          ? 'Book by ${slotCopy[entry.key]!.cutoff} passed — next window still available'
                          : '${slotCopy[entry.key]!.benefit} · Book by ${slotCopy[entry.key]!.cutoff}',
                      style: const TextStyle(color: AppColors.muted, fontSize: 11.5, height: 1.3),
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
            style: TextStyle(color: AppColors.muted, fontSize: 11.5, height: 1.4),
          ),
        ),
        const SizedBox(height: 4),
        _DeliveryIqCard(courierCatalogId: courier.id, window: _pickupWindow),
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
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'Mobile money', icon: Icon(Icons.phone_android), label: Text('Mobile money')),
            ButtonSegment(value: 'Cash at pickup', icon: Icon(Icons.payments_outlined), label: Text('Cash')),
          ],
          selected: {_payment},
          onSelectionChanged: (selection) => setState(() => _payment = selection.first),
        ),
        const SizedBox(height: 24),
        _PlanBanner(parcels: _parcels),
        const SizedBox(height: 14),
        Card(child: Padding(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('$_from → $_to', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
          const SizedBox(height: 4),
          Text('${courier.name} • ${_size.label} parcel • ${pickupWindows[_pickupWindow]}', style: const TextStyle(color: AppColors.muted, fontSize: 13)),
          const Divider(height: 28),
          _priceLine('DropOff rider fee', kwacha(riderFee)),
          if (_lastMile) ...[
            _priceLine('Destination door delivery', kwacha(lastMilePrice)),
            _priceLine('Processing fee (door leg — platform + mobile money)', kwacha(DropOffApi.platformFee(lastMilePrice))),
          ],
          _priceLine('${courier.name.split(' ').first} counter fare', kwacha(_courierFare)),
          const Padding(
            padding: EdgeInsets.only(left: 2, bottom: 4),
            child: Text(
              'Paid directly by you at the depot counter. DropOff never collects partner money — in-app partner collection is coming soon.',
              style: TextStyle(color: AppColors.muted, fontSize: 10.5, height: 1.35),
            ),
          ),
          if (_payment == 'Mobile money') Builder(builder: (context) {
            final fees = DropOffApi.collectionFees(DropOffApi.round2(_dropOffLeg), riderFee: riderFee);
            final processing = fees['processing_fee_zmw'] ?? 0.0;
            return Column(children: [
              _priceLine('Processing fee (platform + mobile money)', kwacha(processing)),
              _priceLine('Charged on your DropOff order', kwacha(_dropOffDue), bold: true),
              const SizedBox(height: 4),
              const Text(
                'You never pay the rider\u2019s payout fees or see driver earnings — that is between DropOff and the driver.',
                style: TextStyle(color: AppColors.muted, fontSize: 10.5, height: 1.4),
              ),
          ]);
          }),
          const Divider(height: 24),
          _priceLine(_courierFare != null ? 'Estimated total outlay (DropOff + depot)' : 'DropOff charge est. now', kwacha(_courierFare != null ? _dropOffDue + _courierFare! : _dropOffLeg), bold: true),
          if (_courierFare == null) const Padding(padding: EdgeInsets.only(top: 8), child: Text('+ courier counter fare to be confirmed at the depot. No estimate is invented.', style: TextStyle(color: AppColors.muted, fontSize: 11))),
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
  /// seller never misses what they actually pay.
  Widget _grandTotalBar() => Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(20, 8, 20, 4),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: AppColors.forest.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.forest.withValues(alpha: 0.22))),
        child: Row(children: [
          const Icon(Icons.receipt_long, size: 18, color: AppColors.forest),
          const SizedBox(width: 8),
          Expanded(child: Text('Estimated total you pay', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: AppColors.muted))),
          const SizedBox(width: 8),
          Text(kwacha(_courierFare != null ? _dropOffDue + _courierFare! : _dropOffLeg), maxLines: 1, overflow: TextOverflow.ellipsis, softWrap: false, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: AppColors.forest)),
          if (_courierFare == null) const Text(' + depot counter fare', maxLines: 1, overflow: TextOverflow.ellipsis, softWrap: false, style: TextStyle(fontSize: 12, color: AppColors.muted)),
        ]),
      );

  Widget _cityDropdown(String label, String value, ValueChanged<String> onChanged) => DropdownButtonFormField<String>(
        initialValue: value,
        decoration: InputDecoration(labelText: label, prefixIcon: const Icon(Icons.location_on_outlined)),
        items: [for (final city in _cities) DropdownMenuItem(value: city, child: Text(city))],
        onChanged: (value) { if (value != null) onChanged(value); },
      );
}

class BookingSuccessScreen extends StatelessWidget {
  final String bookingId;
  const BookingSuccessScreen({super.key, required this.bookingId});

  @override
  Widget build(BuildContext context) {
    final booking = AppScope.of(context).bookings.firstWhere((item) => item.id == bookingId);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(26),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Spacer(),
            const CircleAvatar(radius: 48, backgroundColor: Color(0xFFE3EFE6), child: Icon(Icons.check_rounded, color: AppColors.forest, size: 52)),
            const SizedBox(height: 26),
            const Text('Your pickup is booked.', textAlign: TextAlign.center, style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
            const SizedBox(height: 10),
            Text('Reference ${booking.reference}\n${booking.fromCity} → ${booking.toCity}', textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted, height: 1.6)),
            const SizedBox(height: 18),
            InfoPill(icon: Icons.route_rounded, label: 'DropOff rides to the courier — reference ${booking.reference}'),
            const Spacer(),
            FilledButton(onPressed: () => Navigator.of(context).pushReplacement(MaterialPageRoute<void>(builder: (_) => BookingDetailScreen(bookingId: booking.id))), child: const Text('Track this booking')),
            const SizedBox(height: 10),
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Back to home')),
          ]),
        ),
      ),
    );
  }
}



/// Shows the signed-in seller which plan is active and how this trip deducts
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
              'Pay-as-you-go — rider fee per trip. Plans from K69 cover the rider fee inside your plan parcels.',
              style: TextStyle(color: AppColors.muted, fontSize: 11.5, height: 1.35),
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
          decoration: BoxDecoration(color: AppColors.forest.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(13), border: Border.all(color: AppColors.forest.withValues(alpha: 0.35))),
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
              style: const TextStyle(color: AppColors.muted, fontSize: 11.5, height: 1.35),
            ),
          ]),
        );
      },
    );
  }
}

/// Depot-branch picker for the selected courier: server branches (admin-
/// managed) with the catalog fallback. The seller says exactly which branch
/// the rider hands the parcel to.
/// Catalog ids ('platinum', 'mercury'…) map onto the live chargebook ids.
const Map<String, int> kCourierServerIds = {
  'platinum': 1, 'mercury': 3, 'dhl': 14, 'rovert': 22, 'oneworld': 6, 'icypeed': 4,
};
int courierServerIdOf(String catalogId) => kCourierServerIds[catalogId] ?? 1;

/// Inverse of courierServerIdOf: turn a live chargebook id back into the
/// catalog name the booking UI tracks ('dhl', 'mercury'…).
String courierCatalogForServerId(int serverId) =>
    (kCourierServerIds.entries.firstWhere((e) => e.value == serverId,
            orElse: () => const MapEntry('platinum', 1)))
        .key;

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
    _future = DropOffApi.iqEta(courierServerIdOf(widget.courierCatalogId), w);
  }

  @override
  Widget build(BuildContext context) {
    if (!DropOffApi.enabled) return const SizedBox.shrink();
    return FutureBuilder<Map<String, dynamic>?>(
      future: _future,
      builder: (context, snap) {
        final data = snap.data;
        final p50 = (data?['minutes_p50'] as num?)?.toInt();
        if (p50 == null) return const SizedBox.shrink(); // no data yet — stay quiet
        final p90 = ((data?['minutes_p90'] as num?)?.toInt() ?? p50).toString();
        final n = (data?['sample_count'] as num?)?.toInt() ?? 0;
        final fallback = data?['fallback'] == true;
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
                fallback
                    ? 'Delivery IQ (advertised): this courier usually reaches the depot in ~$p50 min; busy days up to $p90 min. Measured averages appear from the first pickups.'
                    : 'Delivery IQ: this courier usually reaches the depot in ~$p50 min; busy days up to $p90 min (from $n recent pickups).',
                style: const TextStyle(color: AppColors.forest, fontSize: 11.5, height: 1.35),
              ),
            ),
          ]),
        );
      },
    );
  }
}

