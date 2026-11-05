import 'package:flutter/material.dart';

import '../data/catalog.dart';
import '../data/dropoff_api.dart';
import '../main.dart';
import '../models/booking.dart';
import '../ui/app_theme.dart';
import '../widgets/common.dart';
import 'bookings_screen.dart';
import 'couriers_screen.dart';

class BookingScreen extends StatefulWidget {
  final String? initialCourierId;
  const BookingScreen({super.key, this.initialCourierId});

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
    'now': 'As soon as possible',
    '06:00': 'Daily sweep 6:00 am',
    '10:00': 'Daily sweep 10:00 am',
    '14:00': 'Daily sweep 2:00 pm',
  };

  /// Seller-facing slot copy: arrival RANGE + benefit + booking cutoff (CAT).
  /// Closed slots stay visible (list-only) and auto-roll forward.
  static const Map<String, ({String title, String benefit, String cutoff})> slotCopy = {
    'now': (title: 'Instant pick-up', benefit: 'Rider dispatched ASAP', cutoff: ''),
    '06:00': (title: '6:00 – 7:30 AM window', benefit: 'Catches early outbound buses', cutoff: '05:30'),
    '10:00': (title: '10:00 – 11:30 AM window', benefit: 'Catches midday courier express', cutoff: '09:30'),
    '14:00': (title: '2:00 – 3:30 PM window', benefit: 'Catches final evening transit', cutoff: '13:30'),
  };

  bool _slotClosed(String key) {
    if (key == 'now') return false;
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
  final _returnAddress = TextEditingController();

  int _step = 0;
  String _from = 'Lusaka';
  String _to = 'Ndola';
  String _pickupWindow = 'now';
  late String _courierId = widget.initialCourierId ?? 'platinum';
  ParcelSize _size = ParcelSize.small;
  bool _lastMile = false;
  bool _roundTrip = false;
  String _returnCity = 'Lusaka';
  DateTime? _customPickup;
  bool _useCustomPickup = false;
  String _payment = 'Mobile money';
  bool _saving = false;
  List<String> _cities = cities;
  double? _promoPct;
  String _promoNote = '';

  /// Vehicle class for this trip. Trucks are for large cargo (fridges, sofas);
  /// cars/vans cover most everyday parcels.
  String _vehicleClass = 'motorcycle';
  int _parcels = 1;
  static const Map<String, int> _maxParcelsByVehicle = {'motorcycle': 3, 'car': 6, 'van': 10, 'truck': 15};
  static const Map<String, String> _vehicleLabels = {'motorcycle': 'Motorcycle', 'car': 'Car', 'van': 'Van', 'truck': 'Truck (large cargo)'};

  @override
  void initState() {
    super.initState();
    // Prefer the live chargebook's coverage when the API is on.
    if (DropOffApi.enabled) {
      DropOffApi.cities().then((list) {
        if (list.isNotEmpty && mounted) {
          final merged = {...list, ...cities}.toList();
          setState(() => _cities = merged);
        }
      });
    }
  }

  @override
  void dispose() {
    for (final controller in [_pickup, _description, _senderName, _senderPhone, _recipientName, _recipientPhone, _promo, _returnAddress]) {
      controller.dispose();
    }
    super.dispose();
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

  double? get _courierFare => courierFareFor(courierId: _courierId, fromCity: _from, toCity: _to, size: _size);

  /// DropOff-only leg: rider fee + door leg (+door-leg platform cut). Never partner money.
  double get _dropOffLeg => riderFee + (_lastMile ? lastMilePrice + DropOffApi.platformFee(lastMilePrice) : 0);

  /// What the customer pays DropOff on the prompt for this order.
  double get _dropOffDue =>
      DropOffApi.collectionFees(DropOffApi.round2(_dropOffLeg), riderFee: riderFee)['prompt_total_zmw'] ?? _dropOffLeg;

  void _message(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  bool _validPhone(String value) => RegExp(r'^(?:\+?260|0)?[79][567]\d{7}$').hasMatch(value.replaceAll(RegExp(r'[\s-]'), ''));

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _customPickup ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 7)),
    );
    if (date == null) return;
    if (!mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_customPickup ?? DateTime.now()),
    );
    if (time == null) return;
    setState(() {
      _customPickup = DateTime(date.year, date.month, date.day, time.hour, time.minute);
      _useCustomPickup = true;
    });
  }

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
    if (_customPickup != null && _customPickup!.isBefore(DateTime.now())) {
      return _message('Pick a pickup time in the future.');
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
      pickupWindow: _pickupWindow,
      promoCode: _promo.text.trim(),
      roundTrip: _roundTrip,
      returnCity: _roundTrip ? _returnCity : null,
      returnAddress: _roundTrip ? _returnAddress.text.trim().isEmpty ? null : _returnAddress.text.trim() : null,
      returnLegFee: _roundTrip ? (_courierFare ?? 0) : 0,
      pickupAt: _customPickup?.toIso8601String(),
      parcels: _parcels,
      vehicleClass: _vehicleClass,
    );

    // Live Lipila collect for mobile-money jobs; the Worker responds with the
    // payment id and the client polls GET /payments/:id/status every 2s.
    if (booking.dispatched && DropOffApi.enabled && _payment == 'Mobile money' && store.linked) {
      _message('Sending a Lipila prompt to ${_senderPhone.text}…\nYou pay DropOff only — the courier counter fare stays with the depot.');
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
    }
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute<void>(builder: (_) => BookingSuccessScreen(bookingId: booking.id)));
  }

  @override
  Widget build(BuildContext context) {
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
        const Text('Where should we go?', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
        const SizedBox(height: 6),
        const Text('We handle the trip from the sender to the courier depot.', style: TextStyle(color: AppColors.muted)),
        const SizedBox(height: 24),
        _cityDropdown('Pickup city', _from, (value) => setState(() => _from = value)),
        const SizedBox(height: 10),
        const Center(child: Icon(Icons.arrow_downward_rounded, color: AppColors.amber)),
        const SizedBox(height: 10),
        _cityDropdown('Parcel destination', _to, (value) => setState(() => _to = value)),
        const SizedBox(height: 18),
        TextField(controller: _pickup, minLines: 2, maxLines: 3, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(labelText: 'Home / shop pickup address', hintText: 'e.g. Kabwata, near the market', prefixIcon: Icon(Icons.location_on_outlined), alignLabelWithHint: true)),
        const SizedBox(height: 16),
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 14),
          tileColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: const BorderSide(color: AppColors.line)),
          title: const Text('Round trip', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          subtitle: const Text('Rider brings the parcel back to the origin depot after delivery'),
          value: _roundTrip,
          onChanged: (value) => setState(() => _roundTrip = value),
        ),
        if (_roundTrip) ...[
          const SizedBox(height: 10),
          _cityDropdown('Return city', _returnCity, (value) => setState(() => _returnCity = value)),
          const SizedBox(height: 10),
          TextField(controller: _returnAddress, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(labelText: 'Return address', hintText: 'Where the parcel comes back to', prefixIcon: Icon(Icons.route_outlined))),
          const SizedBox(height: 6),
          Text('Return leg charged at the depot counter fare for $_returnCity → $_from, confirmed at the counter.', style: const TextStyle(color: AppColors.muted, fontSize: 11, height: 1.35)),
        ],
        const SizedBox(height: 16),
        const InfoPill(icon: Icons.two_wheeler, label: 'Pickup rider fee: from K45, always under the courier counter fare'),
        const SizedBox(height: 18),
        const Card(child: Padding(padding: EdgeInsets.all(16), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.info_outline, size: 20, color: AppColors.forest),
          SizedBox(width: 10),
          Expanded(child: Text('The intercity courier ticket is separate from the local rider fee. Both are shown clearly before booking when a verified fare is available.', style: TextStyle(fontSize: 12, color: AppColors.muted, height: 1.45))),
        ]))),
      ];

  List<Widget> _parcelStep(CourierInfo selected) => [
        const Text('What are we carrying?', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
        const SizedBox(height: 22),
        SegmentedButton<ParcelSize>(
          segments: [for (final size in ParcelSize.values) ButtonSegment(value: size, label: Text(size.label))],
          selected: {_size},
          onSelectionChanged: (selection) => setState(() => _size = selection.first),
        ),
        const SizedBox(height: 16),
        TextField(controller: _description, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(labelText: 'Parcel contents', hintText: 'e.g. Two boxed phones', prefixIcon: Icon(Icons.inventory_2_outlined))),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(flex: 2, child: DropdownButtonFormField<String>(
            initialValue: _vehicleClass,
            decoration: const InputDecoration(labelText: 'Vehicle', hintText: 'Motorcycle', prefixIcon: Icon(Icons.directions)),
            items: _vehicleLabels.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
            onChanged: (v) { if (v != null) { _vehicleClass = v; if (_parcels > _maxParcelsByVehicle[v]!) _parcels = _maxParcelsByVehicle[v]!; setState(() {}); } },
          )),
          const SizedBox(width: 12),
          Expanded(flex: 3, child: DropdownButtonFormField<int>(
            initialValue: _parcels.clamp(1, _maxParcelsByVehicle[_vehicleClass]!),
            decoration: const InputDecoration(
              labelText: 'Parcels in this trip',
              hintText: '1',
              helperText: 'Each parcel counts as one plan parcel',
              prefixIcon: Icon(Icons.inventory),
            ),
            items: List.generate(_maxParcelsByVehicle[_vehicleClass]!, (i) => i + 1).map((i) => DropdownMenuItem(value: i, child: Text('$i parcel${i == 1 ? '' : 's'}'))).toList(),
            onChanged: (v) { if (v != null) setState(() => _parcels = v); },
          )),
        ]),
        const SizedBox(height: 26),
        const Text('Choose the courier', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        const Text('Your rider takes the parcel to this company’s depot.', style: TextStyle(color: AppColors.muted, fontSize: 13)),
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
          for (final courier in couriers)
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
                'DropOff covers the first mile (your pickup → depot) and last mile (depot → recipient). What happens with your nominated courier between depots is their own operation — we never control their route, timing or depot handling.',
                style: TextStyle(color: AppColors.muted, fontSize: 11, height: 1.4),
              ),
            ),
          ]),
        ),
        if (selected.branches.isNotEmpty) ...[
          const SizedBox(height: 22),
          Text('Branches near $_from', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text('Closest to your pickup first — your rider hands the parcel to the nearest ${selected.name.split(' ').first} branch.', style: const TextStyle(color: AppColors.muted, fontSize: 12, height: 1.4)),
          const SizedBox(height: 10),
          for (final branch in selected.branchesNear(_from).take(3))
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: DecoratedBox(
                decoration: BoxDecoration(border: Border.all(color: AppColors.line), borderRadius: BorderRadius.circular(14)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
                  child: Row(children: [
                    const Icon(Icons.location_on_outlined, size: 18, color: AppColors.forest),
                    const SizedBox(width: 10),
                    Expanded(child: Text(branch.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13))),
                    Text(
                      branchDistanceLabel(branch, _from) ?? branch.city,
                      style: const TextStyle(color: AppColors.muted, fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                  ]),
                ),
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              icon: const Icon(Icons.list_alt, size: 16),
              label: Text('View all ${selected.branches.length} branches'),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => CourierDetailScreen(courier: selected, sellerCity: _from),
              )),
            ),
          ),
        ],
        if (selected.hasVerifiedRates && _from != 'Lusaka')
          const Text('Platinum’s captured tariff starts from Lusaka. This reverse/other route needs a counter quote.', style: TextStyle(color: AppColors.muted, fontSize: 12, height: 1.4)),
      ];

  List<Widget> _detailsStep(CourierInfo courier) => [
        const Text('Nearly ready to roll.', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
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
        const SizedBox(height: 14),
        const Text('Select pickup slot for today', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
        const SizedBox(height: 10),
        for (final entry in pickupWindows.entries)
          Padding(
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
                    _slotClosed(entry.key)
                        ? Icons.lock_outline
                        : entry.key == 'now' ? Icons.bolt_rounded : Icons.schedule_rounded,
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
          ),
        const SizedBox(height: 4),
        const Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Riders sweep Lusaka in these windows. Miss the cutoff and your booking auto-rolls to the next open slot — you are never blocked.',
            style: TextStyle(color: AppColors.muted, fontSize: 11.5, height: 1.4),
          ),
        ),
        const SizedBox(height: 10),
        Row(children: [
          const Expanded(child: Text('Custom pickup time', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700))),
          Switch(value: _useCustomPickup, onChanged: (v) => setState(() => _useCustomPickup = v)),
        ]),
        if (_useCustomPickup) ...[
          const SizedBox(height: 10),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 14),
            leading: const Icon(Icons.schedule_rounded),
            title: Text(_customPickup == null ? 'Pick a date and time' : 'Pickup ${_customPickup!.day}/${_customPickup!.month} ${_customPickup!.hour}:${_customPickup!.minute.toString().padLeft(2, '0')}'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: _pickDateTime,
          ),
          const SizedBox(height: 4),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text('Riders get a push 30 and 10 minutes before the slot — and you can track them live in Bookings.', style: TextStyle(color: AppColors.muted, fontSize: 11, height: 1.35)),
          ),
        ],
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
                'You never pay the rider\u2019s payout fees — the rider keeps 90% of the rider fee minus their payout transaction fees.',
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


