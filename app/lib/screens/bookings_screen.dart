// ─────────────────────────────────────────────────────────────────────
// DROPOFF — ownership stamp (do not remove)
// :Godfrey Moses Kalambo:Carpso Solutions:0968551110.
// © 2026 Godfrey Moses Kalambo · Carpso Solutions · Lusaka, Zambia.
// All rights reserved — unauthorised copying, resale or rebranding of
// this source code is prohibited.
// ─────────────────────────────────────────────────────────────────────
import '../ui/app_toast.dart';
import '../widgets/help_sheet.dart';
import '../ui/pay_job.dart';
import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../data/analytics_service.dart';
import '../data/catalog.dart';
import '../data/dropoff_api.dart';
import '../main.dart';
import '../models/booking.dart';
import '../ui/app_theme.dart';
import '../widgets/common.dart';
import 'account_screen.dart';
import 'booking_screen.dart';
import 'tickets_screen.dart';
import 'rider_map_screen.dart';
import 'track_screen.dart';
import 'waybill_screen.dart';
import '../ui/app_spinner.dart';

class BookingsScreen extends StatefulWidget {
  const BookingsScreen({super.key});
  @override
  State<BookingsScreen> createState() => _BookingsScreenState();
}

class _BookingsScreenState extends State<BookingsScreen> {
  List<Map<String, dynamic>> _incoming = const [];

  @override
  void initState() {
    super.initState();
    AnalyticsService.instance.trackScreenView('bookings');
    // Pull the account's server-side jobs (collections, standing orders,
    // ops-created jobs) into the local list — they would otherwise never
    // appear here, since the tab renders the local cache.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) AppScope.of(context).syncJobsFromServer();
    });
    _refresh();
    _loadIncoming();
  }

  Future<void> _refresh() async {
    await _loadIncoming();
    if (!mounted) return;
    // Bookings live in the local store; pull-to-refresh re-reads the latest
    // state (outbox retries and server-synced jobs land here automatically).
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;
    setState(() {});
  }

  /// Parcels addressed to the signed-in caller's phone — claimed automatically,
  /// no link pasting needed. Auto-tagged because the account phone matches the
  /// recipient phone on the job.
  Future<void> _loadIncoming() async {
    final data = await DropOffApi.trackIncoming();
    if (!mounted) return;
    final parcels = (((data?['parcels'] as List?) ?? const []))
        .cast<Map<String, dynamic>>()
        .where((p) => !'${p['status'] ?? ''}'.toLowerCase().contains('cancel'))
        .take(10)
        .toList();
    setState(() => _incoming = parcels);
  }

  Future<void> _openIncoming(Map<String, dynamic> parcel) async {
    final url = '${parcel['tracking_url'] ?? ''}';
    if (url.isEmpty) {
      AppToast.show(context, 'Tracking link not available for this parcel yet.');
      return;
    }
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => TrackScreen(initialToken: url),
    ));
    if (mounted) _loadIncoming();
  }

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    if (!store.linked) {
      // Bookings sync and chat need an identity — show the sign-in door only.
      return Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.lock_outline, size: 44, color: AppColors.muted),
              const SizedBox(height: 16),
              const Text('Sign in to see your bookings', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900), textAlign: TextAlign.center),
              const SizedBox(height: 8),
              const Text('Your parcels, courier handovers and support tickets live behind your account — phone code or email, your choice.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted, height: 1.45)),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AccountScreen())),
                icon: const Icon(Icons.login),
                label: const Text('Sign in'),
              ),
            ]),
          ),
        ),
        ),
      );
    }
    final bookings = store.bookings;
    // SCAFFOLD + WHITE BODY (owner bug 2026-11-20, third pass): the tab used
    // to return a bare SafeArea. When opened from a push (share link, push
    // notification, home tile) the route had no painted background, so the
    // area below the last card showed the grey page canvas. A white Scaffold
    // guarantees no grey band on ANY entry path, tab or pushed route.
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 22, 20, 18),
          child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('My bookings', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: -0.6)),
              SizedBox(height: 5),
              Text('Every pickup and courier handover, in one place.', style: TextStyle(color: AppColors.muted)),
            ])),
            _InboxButton(),
          ]),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _refresh,
            color: AppColors.forest,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 26),
              children: [
                if (_incoming.isNotEmpty) ...[
                  _ParcelsForYou(parcels: _incoming, onOpen: _openIncoming),
                  const SizedBox(height: 14),
                ],
                if (bookings.isEmpty)
                  EmptyState(
                    eyebrow: _incoming.isEmpty ? 'NOTHING IN TRANSIT' : 'AWAITING YOU',
                    title: _incoming.isEmpty ? 'Nothing in transit.' : 'Nothing you sent yet.',
                    message: _incoming.isEmpty
                        ? 'Book your first home-to-depot pickup. Your tracking timeline appears here.'
                        : 'Everything below is addressed to you. When you send a parcel yourself it will appear here too.',
                    action: FilledButton.icon(
                      onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const BookingScreen())),
                      icon: const Icon(Icons.add),
                      label: const Text('Book a pickup'),
                    ),
                  )
                else
                  for (final booking in bookings) ...[
                    BookingCard(
                      booking: booking,
                      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => BookingDetailScreen(bookingId: booking.id))),
                    ),
                    const SizedBox(height: 12),
                  ],
              ],
            ),
          ),
        ),
      ]),
      ),
    );
  }
}

/// Full-screen viewer for a Collection's proof-of-payment receipt — the rider
/// shows it at the courier counter, and the sender can re-check it here.
Future<void> _showReceipt(BuildContext context, String url) async {
  if (url.isEmpty) return;
  final uri = url.startsWith('http') ? url : '${DropOffApi.baseUrl}$url';
  await Navigator.of(context).push<void>(MaterialPageRoute<void>(
    fullscreenDialog: true,
    builder: (_) => Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: AppColors.ink,
        title: const Text('Receipt — the rider shows this at the depot counter'),
      ),
      body: Center(child: Image.network(
        uri,
        headers: DropOffApi.authHeaders,
        fit: BoxFit.contain,
        loadingBuilder: (_, child, progress) =>
            progress == null ? child : const AppLogoSpinner(size: 34),
        errorBuilder: (_, __, ___) => const Text('Receipt could not load — check your connection.',
            style: TextStyle(color: AppColors.muted, fontSize: 12)),
      )),
    ),
  ));
}

class BookingCard extends StatelessWidget {
  final Booking booking;
  final VoidCallback onTap;
  const BookingCard({super.key, required this.booking, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final courier = courierById(booking.courierId);
    final complete = booking.stage == booking.timeline.length - 1;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(17),
          child: Column(children: [
            Row(children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(color: Color(courier.colorValue).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(14)),
                child: Icon(Icons.inventory_2_outlined, color: Color(courier.colorValue)),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // First mile ends at the nominated depot branch — that is the
                // DropOff leg we track and get paid for. Final city is optional
                // last mile and stays secondary.
                Text(
                  (booking.branch?.isNotEmpty == true)
                      ? '${booking.fromCity} → ${booking.branch}'
                      : '${booking.fromCity} → ${booking.toCity}',
                  style: AppType.subhead,
                ),
                const SizedBox(height: 3),
                Text(
                  (booking.branch?.isNotEmpty == true)
                      ? '${courier.name} · onward to ${booking.toCity}'
                      : courier.name,
                  style: const TextStyle(fontSize: 12.5, color: AppColors.ink, height: 1.35),
                ),
              ])),
              const Icon(Icons.chevron_right, color: AppColors.muted),
            ]),
            // COLLECTION (owner 2026-11-20): the sender can see the rider's
            // proof-of-payment receipt — what the rider will show at the depot.
            if (booking.isCollection) ...[
              const SizedBox(height: 6),
              OutlinedButton.icon(
                onPressed: () => _showReceipt(context, booking.collectionReceiptUrl),
                icon: const Icon(Icons.receipt_long_outlined, size: 16, color: AppColors.forest),
                label: Text(
                  booking.hasCollectionReceipt ? 'View receipt photo (rider has it)' : 'Receipt — none uploaded yet',
                  style: const TextStyle(fontSize: 12.5, color: AppColors.ink),
                ),
              ),
            ],
            const SizedBox(height: 16),
            // UNPAID / HELD booking — the one thing a sender must not miss.
            // It shows the exact state their money is in and the way to pay,
            // instead of looking like a normal "placed" parcel.
            if (booking.paymentHeld) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: const Color(0x14B3261E),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0x66B3261E)),
                ),
                child: const Row(children: [
                  Icon(Icons.lock_clock_outlined, size: 20, color: AppColors.danger),
                  SizedBox(width: 10),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Booking held — payment pending', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12.5, color: AppColors.danger)),
                    SizedBox(height: 2),
                    Text('No rider is assigned until the prepayment lands. Tap to open and pay.', style: TextStyle(fontSize: 11.5, color: AppColors.ink, height: 1.35)),
                  ])),
                  Icon(Icons.chevron_right, color: AppColors.danger),
                ]),
              ),
            ],
            Row(children: [
              Expanded(child: Text(booking.reference, style: const TextStyle(fontSize: 11, color: AppColors.muted, fontWeight: FontWeight.w600))),
              if (booking.paymentHeld)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(color: const Color(0xFFFFF1D2), borderRadius: BorderRadius.circular(20)),
                  child: const Text('PAYMENT PENDING', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.danger)),
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(color: complete ? const Color(0xFFE3EFE6) : const Color(0xFFFFF1D2), borderRadius: BorderRadius.circular(20)),
                  child: Text(booking.timeline[booking.stage], style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: complete ? AppColors.forest : const Color(0xFF7B5710))),
                ),
            ]),
          ]),
        ),
      ),
    );
  }
}

class BookingDetailScreen extends StatefulWidget {
  final String bookingId;
  const BookingDetailScreen({super.key, required this.bookingId});
  @override
  State<BookingDetailScreen> createState() => _BookingDetailScreenState();
}

class _BookingDetailScreenState extends State<BookingDetailScreen> {
  @override
  void initState() {
    super.initState();
    // AUTOMATION (owner directive 2026-11-15): opening a booking pulls the
    // server's latest job state — the timeline, the algorithm-assigned rider
    // and the payment-held gate move on their own. No manual marking.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) AppScope.of(context).syncJobsFromServer();
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    final matches = store.bookings.where((item) => item.id == widget.bookingId);
    if (matches.isEmpty) return const Scaffold(body: Center(child: Text('Booking not found')));
    final booking = matches.first;
    final courier = courierById(booking.courierId);
    final rider = store.riders.where((item) => item.id == booking.riderId).firstOrNull;
    // Tap-to-call: the server ships the rider's number to this booking's
    // participants; staff also fall back to the roster row.
    final riderPhoneOf = booking.riderPhone?.isNotEmpty == true
        ? booking.riderPhone
        : (store.isTeam && rider != null && rider.phone.contains(RegExp(r'\d')) ? rider.phone : null);
    final complete = booking.stage == booking.timeline.length - 1;
    return Scaffold(
      appBar: AppBar(title: Text(booking.reference, style: const TextStyle(fontWeight: FontWeight.w800))),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 6, 20, 28), children: [
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(color: AppColors.forest, borderRadius: BorderRadius.circular(20)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(booking.timeline[booking.stage].toUpperCase(), style: const TextStyle(color: AppColors.amber, fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 1)),
            const SizedBox(height: 12),
            Text(
              (booking.branch?.isNotEmpty == true)
                  ? '${booking.fromCity} → ${booking.branch}'
                  : '${booking.fromCity} → ${booking.toCity}',
              style: const TextStyle(color: Colors.white, fontSize: 25, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Text(
              (booking.branch?.isNotEmpty == true)
                  ? '${courier.name} · onward to ${booking.toCity}'
                  : courier.name,
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 20),
            ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(value: (booking.stage + 1) / booking.timeline.length, minHeight: 5, backgroundColor: Colors.white24, color: AppColors.amber)),
          ]),
        ),
        const SizedBox(height: 24),
        const SectionTitle('Journey'),
        const SizedBox(height: 2),
        const Text('Tap any step — see who updated it and when.', style: AppType.caption),
        const SizedBox(height: 8),
        Card(child: Padding(padding: const EdgeInsets.all(18), child: Column(children: [
          for (var i = 0; i < booking.timeline.length; i++)
            _TimelineRow(title: booking.timeline[i], complete: i <= booking.stage, current: i == booking.stage, last: i == booking.timeline.length - 1, onTap: () => _showMovementLog(context, booking)),
        ]))),
        if (riderPhoneOf != null) ...[
          const SizedBox(height: 14),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: () async {
              final number = riderPhoneOf;
              final ok = await callPhoneNumber(number);
              if (!ok && context.mounted) {
                AppToast.show(context, 'Dialer not available here — call $number');
              }
            },
            icon: const Icon(Icons.phone_outlined),
            label: Text('Call ${rider?.name ?? booking.riderName ?? 'the rider'}'),
          ),
        ],
        const SizedBox(height: 24),
        const SectionTitle('Booking details'),
        const SizedBox(height: 8),
        Card(child: Padding(padding: const EdgeInsets.all(18), child: Column(children: [
          _detailRow('Pickup', booking.pickupAddress),
          if (booking.branch?.isNotEmpty == true)
            _detailRow('Drop-off branch', '${booking.branch} (${courier.name})'),
          _detailRow('Parcel', '${booking.parcelSize.label} • ${booking.description}'),
          _detailRow('Sender', '${booking.senderName}\n${booking.senderPhone}'),
          _detailRow('Recipient', '${booking.recipientName}\n${booking.recipientPhone}'),
          _detailRow('Payment', booking.paymentMethod),
          // The rider the dispatch ALGORITHM picked — never a default
          // "Owner" (owner directive 2026-11-15). Null = nobody assigned yet.
          _detailRow('Rider', rider?.name ?? booking.riderName ?? 'Awaiting rider assignment'),
          _detailRow('DropOff rider fee', kwacha(booking.riderFee)),
          _detailRow('Courier fare', kwacha(booking.courierFare)),
          if (booking.lastMileFee > 0) _detailRow('Last-mile fee', kwacha(booking.lastMileFee)),
          _detailRow('Counter fare', '${booking.courierFare != null ? kwacha(booking.courierFare) : 'Confirmed at depot'} — pay directly to the depot'),
          _detailRow('DropOff due', '${kwacha(booking.riderFee + booking.lastMileFee)} + processing — DropOff charge, never partner money'),
          if (booking.promoCode != null)
            _detailRow('Promo', '${booking.promoCode}${booking.promoDiscount != null ? ' — saved ${kwacha(booking.promoDiscount)} on the DropOff leg' : ''}'),
        ]))),
        const SizedBox(height: 20),
        // PREPAY GATE (owner directive): a booking that never got its momo
        // prepayment approved is HELD — surface it loudly with a working
        // Pay now. [paymentHeld] is the server's own deposit decision,
        // mirrored on every sync; plan-covered bookings never carry it.
        if (booking.dispatched && !complete && booking.paymentHeld &&
            (booking.lastEvent == null ||
                booking.lastEvent == 'prepayment_pending' ||
                booking.lastEvent == 'advance_pending'))
          _PrepayCard(booking: booking),
        // SERVER-SIDE CANCELLATION (hold expired / no-show): the server died
        // this booking on its own — say so instead of a silent stage-0 ghost.
        if (booking.dispatched && !complete &&
            (booking.lastEvent == 'hold_expired' || booking.lastEvent == 'auto_canceled_no_show'))
          _ExpiredCard(booking: booking),
        // DEPOT COUNTER FLOW (owner directive 2026-11-12): the rider fronted
        // the depot's counter fare — the sender repays the exact receipt
        // amount + processing; the receipt photo unlocks after payment.
        if (booking.dispatched && !complete && booking.counterFareDue)
          _CounterReceiptCard(booking: booking),
        if (booking.dispatched && booking.counterReceiptPaid && booking.counterReceiptUrl?.isNotEmpty == true)
          _CounterReceiptPaidCard(booking: booking),
        // DISPATCH IS AUTOMATED (owner directive 2026-11-15): the manual
        // "Operator: mark …" status buttons are gone, and there is no rider
        // dropdown defaulting to the owner. Staff may only ask the server to
        // run its nearest-available-rider algorithm on an unassigned job.
        if (store.isStaff && booking.dispatched && !complete && !booking.paymentHeld) ...[
          _AutoAssignCard(booking: booking),
          const SizedBox(height: 14),
        ],
        if (!store.isStaff && booking.stage >= booking.timeline.length - 1)
          const InfoPill(icon: Icons.check_circle, label: 'Journey complete'),
        if (booking.dispatched && DropOffApi.enabled && store.linked) ...[
          const SizedBox(height: 20),
          Row(children: [
            Expanded(child: FilledButton.tonalIcon(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => TicketsScreen(
                  prefill: 'Issue with booking ${booking.reference}: ',
                ),
              )),
              icon: const Icon(Icons.support_agent_outlined),
              label: const Text('Get help with this delivery'),
            )),
          ]),
          // RECIPIENT TRACKING (owner directive 2026-11-15): the share card
          // exists only once the prepayment is confirmed — a HELD booking
          // never sends "track this delivery" links.
          if (!booking.paymentHeld) ...[
            const SizedBox(height: 20),
            _TrackingLinkCard(jobRef: booking.serverRef!),
          ],
        ],
        if (booking.dispatched && DropOffApi.enabled && complete) ...[
          const SizedBox(height: 20),
          _RatingCard(
            jobRef: booking.serverRef!,
            senderPhone: booking.senderPhone,
            viewerPhone: store.linkedPhone,
          ),
        ],
        if (booking.dispatched && DropOffApi.enabled) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 4, alignment: WrapAlignment.center, children: [
            TextButton.icon(
              icon: const Icon(Icons.map_outlined),
              label: const Text('Track rider live'),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => RiderMapScreen(jobRef: booking.serverRef!),
              )),
            ),
            TextButton.icon(
              icon: const Icon(Icons.verified_user_outlined),
              label: const Text('Share evidence'),
              onPressed: () => _showEvidenceLocker(context, booking),
            ),
          ]),
        ],
        // Depot counter receipt / waybill — only visible after payment lands.
        // Before the momo/prepayment settles, there is nothing to print yet and
        // an empty waybill risks misuse.
        if (!booking.paymentHeld) ...[
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: OutlinedButton.icon(
              icon: const Icon(Icons.receipt_long_outlined),
              label: const Text('Depot receipt / waybill'),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => WaybillScreen(bookingId: booking.id),
              )),
            )),
          ]),
        ],
        const SizedBox(height: 8),
        Center(
          child: Wrap(alignment: WrapAlignment.center, spacing: 8, children: [
            TextButton.icon(
              icon: const Icon(Icons.replay_outlined),
              label: const Text('Quick rebook'),
              onPressed: () {
                BookingScreen.prefill = {
                  'from': booking.fromCity,
                  'to': booking.toCity,
                  'pickup': booking.pickupAddress,
                  'description': booking.description,
                  'sender_name': booking.senderName,
                  'sender_phone': booking.senderPhone,
                  'recipient_name': booking.recipientName,
                  'recipient_phone': booking.recipientPhone,
                  'size': booking.parcelSize.name,
                  'courier_catalog_id': booking.courierId,
                  'parcels': booking.parcels,
                  'vehicle_class': booking.vehicleClass,
                  'pickup_window': booking.pickupWindow,
                  if (booking.branch != null && booking.branch!.isNotEmpty) 'branch': booking.branch,
                };
                Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const BookingScreen()));
              },
            ),
            // One-tap RETURN: only when this booking was booked as a round
            // trip — swaps cities/parties and prefills the return pickup,
            // so a seller never re-types a route they already ran.
            if (booking.roundTrip && (booking.returnCity?.isNotEmpty ?? false))
              TextButton.icon(
                icon: const Icon(Icons.keyboard_return_outlined),
                label: const Text('Book the return'),
                onPressed: () {
                  BookingScreen.prefill = {
                    'from': booking.returnCity ?? booking.toCity,
                    'to': booking.fromCity,
                    'pickup': booking.returnAddress ?? '',
                    'description': booking.description,
                    'sender_name': booking.recipientName,
                    'sender_phone': booking.recipientPhone,
                    'recipient_name': booking.senderName,
                    'recipient_phone': booking.senderPhone,
                    'size': booking.parcelSize.name,
                    'courier_catalog_id': booking.courierId,
                    'parcels': booking.parcels,
                    'vehicle_class': booking.vehicleClass,
                    'pickup_window': booking.pickupWindow,
                  };
                  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const BookingScreen()));
                },
              ),
          ]),
        ),
        const SizedBox(height: 12),
        // REQUEST-DELETE (customer): customers can never delete a booking —
        // deleting drops proof for the depot counter and payments. They ask
        // support; staff delete it from the admin console if it's granted.
        Center(
          child: TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => TicketsScreen(
                prefill: 'Please delete booking #${booking.reference} — it is no longer needed. I am the sender.',
              ),
            )),
            child: const Text('Request deletion of this booking', style: TextStyle(fontSize: 12.5, color: AppColors.muted, decoration: TextDecoration.underline)),
          ),
        ),
        const SizedBox(height: 12),
        const Text('Rider controls update this device. Photo proof, courier waybill upload and sender notifications run through the linked backend.', textAlign: TextAlign.center, style: AppType.caption),
      ]),
    );
  }

  Widget _detailRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(flex: 5, child: Text(label, softWrap: true, style: AppType.caption)),
          const SizedBox(width: 10),
          Expanded(flex: 6, child: Text(value, textAlign: TextAlign.right, softWrap: true, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, height: 1.35))),
        ]),
      );
}

/// Journey steps sheet. Opens INSTANTLY (the tap gives immediate feedback even
/// when the network crawls), then fills in the server's movement log — or an
/// honest retry note when it can't be fetched. The old version awaited the
/// network BEFORE showing anything, so a slow connection made every step tap
/// look completely dead.
Future<void> _showMovementLog(BuildContext context, Booking booking) async {
  final ref = booking.serverRef?.isNotEmpty == true ? booking.serverRef! : booking.reference;
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => _MovementLogSheet(ref: ref),
  );
}

class _MovementLogSheet extends StatefulWidget {
  final String ref;
  const _MovementLogSheet({required this.ref});

  @override
  State<_MovementLogSheet> createState() => _MovementLogSheetState();
}

class _MovementLogSheetState extends State<_MovementLogSheet> {
  List<Map<String, dynamic>> _timeline = const <Map<String, dynamic>>[];
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await DropOffApi.jobEvidence(widget.ref);
    if (!mounted) return;
    setState(() {
      _failed = data == null;
      _timeline = (data?['timeline'] as List?)?.cast<Map<String, dynamic>>() ?? const <Map<String, dynamic>>[];
      _loading = false;
    });
  }

  String _labelFor(String status) => switch (status) {
        'created' => 'Booking placed',
        'rider_assigned' => 'Rider assigned',
        'partner_confirmed' => 'Courier depot accepted the parcel',
        'picked_up' => 'Parcel collected from the depot',
        'at_depot' => 'At courier depot',
        'departed' => 'Left the depot',
        'arrived' => 'Arrived at the destination',
        'delivered' => 'Delivered to the recipient',
        'ready_for_collection' => 'Ready for collection',
        'deposit_paid' => 'Prepayment approved',
        'counter_fare_paid' => 'Depot fare paid at the counter',
        'refund_pending' => 'Refund pending',
        'auto_canceled_no_show' => 'Auto-canceled — no-show',
        'hold_expired' => 'Prepayment window expired',
        'reprompt_paused' => 'Reminders paused by sender',
        'reprompt_resumed' => 'Reminders resumed',
        _ => status.replaceAll('_', ' '),
      };

  String _humanAt(String raw) {
    final parsed = serverTime(raw);
    return DateFormat('d MMM · h:mm a').format(parsed);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
          child: ListView(shrinkWrap: true, children: [
            const Row(children: [
              Icon(Icons.swap_horiz_rounded, color: AppColors.forest),
              SizedBox(width: 10),
              Expanded(child: Text('How this parcel moved', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, letterSpacing: -0.2))),
            ]),
            const SizedBox(height: 4),
            const Text('Every update on this job — who recorded it and when.', style: AppType.body),
            const SizedBox(height: 14),
            if (_loading) ...[
              const Center(child: Padding(padding: EdgeInsets.symmetric(vertical: 18), child: AppLogoSpinner(size: 26))),
            ] else if (_failed && _timeline.isEmpty) ...[
              const Text('Couldn\'t load the journey log just now — check your connection and try again.', style: AppType.body),
              const SizedBox(height: 10),
              Center(child: TextButton.icon(
                onPressed: () { setState(() { _loading = true; _failed = false; }); _load(); },
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Try again'),
              )),
            ] else if (_timeline.isEmpty)
              const Text('No updates yet — they appear here the moment the parcel moves.', style: AppType.body),
            for (final e in _timeline)
              () {
                final who = '${e['who'] ?? 'system'}';
                final actor = '${e['actor'] ?? ''}';
                final status = '${e['status'] ?? ''}';
                final at = _humanAt('${e['at'] ?? ''}');
                final note = '${e['note'] ?? ''}'.trim();
                final (icon, byline) = switch (who) {
                  'rider' => (Icons.two_wheeler, 'Marked updated by rider${actor.isEmpty || actor == 'rider' ? '' : ' — $actor'}'),
                  'partner' => (Icons.storefront_outlined, 'Marked updated by the courier depot'),
                  _ => (Icons.bolt_outlined, 'Recorded automatically'),
                };
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(icon, size: 18, color: AppColors.forest),
                    const SizedBox(width: 10),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(_labelFor(status), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
                      Text('$byline · $at', style: const TextStyle(color: AppColors.muted, fontSize: 11.5)),
                      if (note.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(note, style: const TextStyle(fontSize: 12, height: 1.4, color: AppColors.ink)),
                      ],
                    ])),
                  ]),
                );
              }(),
          ]),
        ),
      ),
    );
  }
}

Future<void> _showEvidenceLocker(BuildContext context, Booking booking) async {
  final ref = booking.serverRef ?? booking.reference;
  final data = await DropOffApi.jobEvidence(ref);
  if (!context.mounted) return;
  if (data == null) {
    AppToast.show(context, 'Evidence not available right now. Sign in and ensure this booking is synced.');
    return;
  }
  final ev = (data['evidence'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
  final check = (ev['parcel_check'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
  final track = '${data['tracking_token'] ?? ''}';
  final bookedAt = data['created_at'] == null || '${data['created_at']}'.isEmpty
      ? 'n/a'
      : DateFormat('d MMM yyyy · h:mm a').format(serverTime('${data['created_at']}'));
  // Compact text summary for the Share button (the visual comparison lives in
  // the sheet itself — photos can't ride in a plain-text share).
  String line(String label, Object? value) => '$label: ${value == null || '$value'.isEmpty ? 'n/a' : value}';
  final summary = [
    'DropOff evidence — ${data['ref'] ?? ref}',
    line('Status', data['status']),
    if (track.isNotEmpty) 'Track: https://api.carpsosolutions.store/t/$track',
    line('Booked', bookedAt),
    line('Booking photo', ev['booking_photo']),
    line('Pickup photo', ev['pickup_photo']),
    line('Dropoff photo', ev['depot_or_dropoff_photo']),
    line('Partner confirmed', ev['partner_confirmed']),
    line('OTP required', ev['otp_required']),
    line('Parcel check', check['same_parcel']),
    line('Confidence', check['confidence']),
    line('Review', check['review_status'] ?? (check['needs_review'] == true ? 'needs_review' : '')),
    line('Declared value', ev['declared_value_zmw']),
  ].join('\n');

  // Parcel-check verdict chip (sender photo vs rider photo, AI + rules).
  final same = '${check['same_parcel'] ?? ''}';
  final (chipIcon, chipColor, chipLabel) = switch (same) {
    'yes' => (Icons.verified_outlined, AppColors.forest, 'Same parcel'),
    'no' => (Icons.warning_amber_rounded, AppColors.danger, 'Mismatch — review'),
    'uncertain' => (Icons.help_outline_rounded, AppColors.warning, 'Uncertain — review'),
    _ => (Icons.hourglass_empty_rounded, AppColors.muted, 'Comparison pending'),
  };

  Future<void> zoom(String? path, String label) async {
    if (path == null || path.isEmpty) return;
    await showDialog<void>(
      context: context,
      builder: (dctx) => Dialog(
        backgroundColor: Colors.black,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
            child: Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
          ),
          Flexible(
            child: InteractiveViewer(
              maxScale: 4,
              child: AuthedImage(path, fit: BoxFit.contain, width: double.infinity),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dctx),
            child: const Text('Close', style: TextStyle(color: Colors.white)),
          ),
        ]),
      ),
    );
  }

  Widget photoTile(String? path, String label) => Expanded(
        child: InkWell(
          onTap: path == null || path.isEmpty ? null : () => zoom(path, label),
          borderRadius: BorderRadius.circular(10),
          child: Column(children: [
            SizedBox(
              width: double.infinity,
              height: 104,
              child: path == null || path.isEmpty
                  ? Container(
                      decoration: BoxDecoration(color: AppColors.line.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(10)),
                      alignment: Alignment.center,
                      child: const Text('None yet', style: TextStyle(color: AppColors.muted, fontSize: 11)),
                    )
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: AuthedImage(path, fit: BoxFit.cover, width: double.infinity, height: 104),
                    ),
            ),
            const SizedBox(height: 4),
            Text(label, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 11.5)),
          ]),
        ),
      );

  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Share evidence — ${data['ref'] ?? ref}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          const Text('Proof-of-condition photos and the parcel comparison. Share only with trusted parties.', style: TextStyle(color: AppColors.ink, fontSize: 12.5, height: 1.35)),
          const SizedBox(height: 12),
          Flexible(
            child: SingleChildScrollView(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // ── Comparison card: sender's booking photo vs the rider's drop photo ──
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: AppColors.line.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(12)),
                  child: Column(children: [
                    const Row(children: [
                      Icon(Icons.compare_rounded, size: 16, color: AppColors.forest),
                      SizedBox(width: 6),
                      Text('PARCEL COMPARISON', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11, color: AppColors.muted)),
                    ]),
                    const SizedBox(height: 10),
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      photoTile('${ev['booking_photo'] ?? ''}'.isEmpty ? null : '${ev['booking_photo']}', 'Sender (booking)'),
                      const SizedBox(width: 10),
                      photoTile('${ev['depot_or_dropoff_photo'] ?? ''}'.isEmpty ? null : '${ev['depot_or_dropoff_photo']}', 'Rider (drop)'),
                    ]),
                    const SizedBox(height: 10),
                    Row(children: [
                      Icon(chipIcon, size: 16, color: chipColor),
                      const SizedBox(width: 6),
                      Text(chipLabel, style: TextStyle(color: chipColor, fontWeight: FontWeight.w900, fontSize: 12.5)),
                      if ('${check['confidence'] ?? ''}'.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Text('· ${check['confidence']}', style: const TextStyle(color: AppColors.muted, fontSize: 11.5)),
                      ],
                    ]),
                    if ('${check['note'] ?? ''}'.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text('${check['note']}', style: const TextStyle(fontSize: 11.5, height: 1.35, color: AppColors.ink)),
                    ],
                  ]),
                ),
                const SizedBox(height: 10),
                // ── Other evidence photos ──
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  photoTile('${ev['pickup_photo'] ?? ''}'.isEmpty ? null : '${ev['pickup_photo']}', 'Pickup'),
                  const SizedBox(width: 10),
                  photoTile('${ev['handover_photo'] ?? ''}'.isEmpty ? null : '${ev['handover_photo']}', 'Handover'),
                  const SizedBox(width: 10),
                  Builder(builder: (_) {
                    final cr = (ev['counter_receipt'] as Map?)?.cast<String, dynamic>();
                    final url = '${cr?['url'] ?? ''}';
                    return photoTile(url.isEmpty ? null : url, 'Depot receipt');
                  }),
                ]),
                const SizedBox(height: 10),
                // ── Facts ──
                Text('Status: ${data['status'] ?? 'n/a'} · Booked $bookedAt', style: const TextStyle(fontSize: 12.5, height: 1.4)),
                Text(
                  'Partner confirmed: ${ev['partner_confirmed'] == true ? 'yes' : 'not yet'} · OTP required: ${ev['otp_required'] == true ? 'yes' : 'no'} · Declared value: ${ev['declared_value_zmw'] ?? 'n/a'}',
                  style: const TextStyle(fontSize: 12.5, height: 1.4),
                ),
                if (track.isNotEmpty)
                  Text('Tracking: api.carpsosolutions.store/t/$track', style: const TextStyle(fontSize: 12, color: AppColors.muted)),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))),
            const SizedBox(width: 10),
            Expanded(child: FilledButton.icon(onPressed: () async { await Share.share(summary, subject: 'DropOff evidence ${data['ref'] ?? ref}'); }, icon: const Icon(Icons.share_outlined), label: const Text('Share evidence'))),
          ]),
        ]),
      ),
    ),
  );
}

/// App-bar door into support tickets: unread staff replies badge.
class _InboxButton extends StatefulWidget {
  const _InboxButton();

  @override
  State<_InboxButton> createState() => _InboxButtonState();
}

class _InboxButtonState extends State<_InboxButton> {
  int _unread = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await DropOffApi.tickets();
    if (!mounted) return;
    final tickets = ((data?['tickets'] as List?) ?? const []).cast<Map<String, dynamic>>();
    setState(() => _unread = tickets.fold<int>(0, (sum, t) => sum + ((t['unread'] as num?)?.toInt() ?? 0)));
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Support tickets',
      onPressed: () async {
        await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const TicketsScreen()));
        if (mounted) _load();
      },
      icon: Badge(
        isLabelVisible: _unread > 0,
        label: Text('$_unread'),
        child: const Icon(Icons.support_agent_outlined),
      ),
    );
  }
}

class _TimelineRow extends StatelessWidget {
  final String title;
  final bool complete;
  final bool current;
  final bool last;
  final VoidCallback? onTap;
  const _TimelineRow({required this.title, required this.complete, required this.current, required this.last, this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Column(children: [
              Icon(complete ? Icons.check_circle : Icons.circle_outlined, size: 22, color: complete ? AppColors.forest : AppColors.line),
              if (!last) Expanded(child: Container(width: 2, color: complete ? AppColors.forest : AppColors.line)),
            ]),
            const SizedBox(width: 13),
            Expanded(child: Padding(
              padding: EdgeInsets.only(bottom: last ? 2 : 24, top: 1),
              child: Row(children: [
                Expanded(child: Text(title, style: TextStyle(fontSize: 14, fontWeight: current ? FontWeight.w900 : FontWeight.w600, color: complete ? AppColors.ink : AppColors.muted))),
                Opacity(
                  opacity: onTap == null ? 0 : 0.5,
                  child: const Icon(Icons.chevron_right, size: 18, color: AppColors.muted),
                ),
              ]),
            )),
          ]),
        ),
      );
}

/// STAFF DISPATCH CARD (owner directive 2026-11-15): staff never hand-pick a
/// rider and nothing defaults to the owner — this asks the server to run its
/// nearest-available-rider algorithm (verified, active, free capacity,
/// emptiest-rider tie-break) on an unassigned job.
class _AutoAssignCard extends StatefulWidget {
  final Booking booking;
  const _AutoAssignCard({required this.booking});

  @override
  State<_AutoAssignCard> createState() => _AutoAssignCardState();
}

class _AutoAssignCardState extends State<_AutoAssignCard> {
  bool _busy = false;
  String? _note;

  Future<void> _run() async {
    setState(() { _busy = true; _note = null; });
    final res = await DropOffApi.autoAssignJob(widget.booking.serverRef!);
    if (!mounted) return;
    final ok = res?['ok'] == true;
    final depotHint = (res == null || ok) ? null : (res['hint'] as String?)?.trim();
    final atDepot = (res?['excluded_at_depot'] as List?) ?? const [];
    setState(() {
      _busy = false;
      _note = ok
          ? null
          : depotHint ??
              (atDepot.isNotEmpty
                  ? 'Rider(s) busy at depot — the system auto-assigns the moment a depot job closes.'
                  : 'No verified rider available right now — the server keeps retrying automatically.');
    });
    if (ok && res != null) {
      final store = AppScope.of(context);
      await store.setBookingRider(
        widget.booking.id,
        riderId: '${res['rider_id'] ?? ''}',
        riderName: res['rider'] as String?,
      );
      if (!mounted) return;
      AppToast.success(context, 'Rider ${res['rider'] ?? ''} assigned — ETA ${res['eta_minutes'] ?? '?'} min.');
    } else if (depotHint != null && depotHint.isNotEmpty) {
      // Fancy depot-aware toast — server embeds the physical depot name.
      AppToast.warning(context, '🚚 $depotHint', duration: const Duration(seconds: 6));
    } else {
      AppToast.warning(context, 'No rider available — the server retries automatically.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final assigned = widget.booking.riderName?.trim().isNotEmpty == true;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.two_wheeler, color: AppColors.forest),
            const SizedBox(width: 10),
            Expanded(child: Text(assigned ? 'Rider assigned' : 'Dispatch', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
          ]),
          const SizedBox(height: 8),
          Text(
            assigned
                ? 'The algorithm assigned ${widget.booking.riderName}. Status moves on its own as the rider acts.'
                : 'No rider yet. Dispatch runs the nearest-available-rider algorithm — the server also retries automatically every minute.',
            style: AppType.caption,
          ),
          if (_note != null) ...[
            const SizedBox(height: 8),
            Text(_note!, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
          ],
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            onPressed: _busy ? null : _run,
            icon: _busy
                ? const AppLogoSpinner(size: 16)
                : const Icon(Icons.auto_mode),
            label: Text(_busy ? 'Dispatching…' : (assigned ? 'Re-run algorithm' : 'Dispatch nearest rider')),
          ),
        ]),
      ),
    );
  }
}

class _TrackingLinkCard extends StatefulWidget {
  final String jobRef;
  const _TrackingLinkCard({required this.jobRef});

  @override
  State<_TrackingLinkCard> createState() => _TrackingLinkCardState();
}

class _TrackingLinkCardState extends State<_TrackingLinkCard> {
  bool _busy = false;

  /// Copies a message WITH context (not the bare URL) so whatever channel the
  /// user pastes it into is instantly understood: what it is, whose parcel,
  /// how to use it.
  Future<void> _copy() async {
    setState(() => _busy = true);
    final data = await DropOffApi.trackingLink(widget.jobRef);
    if (!mounted) return;
    setState(() => _busy = false);
    final url = data?['url'] as String?;
    if (url == null) {
      AppToast.warning(context, 'Tracking link not ready yet — check your connection and try again.');
      return;
    }
    final ref = widget.jobRef;
    final text = 'DropOff — parcel $ref is on the way!\n'
        'Track it live here (parcel status + rider GPS on the map, no account needed, prices never shown):\n'
        '$url';
    await Share.share(text, subject: 'DropOff parcel $ref — live tracking link');
    if (!mounted) return;
    AppToast.success(context, 'Tracking link ready to share — paste into WhatsApp/SMS.');
  }

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Row(children: [
              Icon(Icons.share_location, color: AppColors.forest),
              SizedBox(width: 10),
              Expanded(child: Text('Recipient tracking', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
            ]),
            const SizedBox(height: 8),
            const Text(
              'Send the recipient a live link with the parcel status and rider location. No account needed — it never exposes prices or your phone number.',
              style: AppType.caption,
            ),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: _busy ? null : _copy,
              icon: _busy
                  ? const AppLogoSpinner(size: 16)
                  : const Icon(Icons.link),
              label: Text(_busy ? 'Preparing…' : 'Copy tracking link'),
            ),
          ]),
        ),
      );
}

class _RatingCard extends StatefulWidget {
  final String jobRef;
  final String senderPhone;
  final String? viewerPhone;
  const _RatingCard({required this.jobRef, required this.senderPhone, this.viewerPhone});

  @override
  State<_RatingCard> createState() => _RatingCardState();
}

class _RatingCardState extends State<_RatingCard> {
  static const _allTargets = ['driver', 'courier', 'seller'];
  final Map<String, int> _stars = {for (final t in _allTargets) t: 0};
  final Map<String, TextEditingController> _comments = {
    for (final t in _allTargets) t: TextEditingController(),
  };
  final Map<String, ({int count, double? average})> _summary = {};
  final Map<String, int> _saved = {};
  bool _loading = true;
  bool _submitting = false;
  String? _message;

  bool get _canRateSeller =>
      widget.viewerPhone != null && widget.viewerPhone != widget.senderPhone;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final controller in _comments.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final data = await DropOffApi.jobRatings(widget.jobRef);
    if (!mounted) return;
    setState(() {
      if (data != null) {
        final list = (data['ratings'] as List?) ?? const [];
        for (final raw in list) {
          final r = (raw as Map).cast<String, dynamic>();
          final target = '${r['target_type']}';
          if (!_stars.containsKey(target)) continue;
          if ('${r['reviewer_phone']}' != widget.viewerPhone) continue;
          final stars = (r['stars'] as num?)?.toInt() ?? 0;
          _stars[target] = stars;
          _saved[target] = stars;
          final comment = '${r['comment'] ?? ''}';
          if (comment.isNotEmpty) _comments[target]!.text = comment;
        }
        final summary = (data['summary'] as Map?) ?? const {};
        summary.forEach((key, value) {
          final v = (value as Map).cast<String, dynamic>();
          _summary['$key'] = (
            count: (v['count'] as num?)?.toInt() ?? 0,
            average: (v['average'] as num?)?.toDouble(),
          );
        });
      }
      _loading = false;
    });
  }

  Future<void> _submit() async {
    final chosen = [
      for (final t in _allTargets)
        if (_stars[t]! > 0 && (t != 'seller' || _canRateSeller)) t,
    ];
    if (chosen.isEmpty) {
      setState(() => _message = 'Tap the stars to pick a score first.');
      return;
    }
    setState(() {
      _submitting = true;
      _message = null;
    });
    for (final target in chosen) {
      final res = await DropOffApi.rateJob(
        jobRef: widget.jobRef,
        targetType: target,
        stars: _stars[target]!,
        comment: _comments[target]!.text,
      );
      if (!res.ok) {
        if (!mounted) return;
        setState(() {
          _submitting = false;
          _message = res.error == 'not_complete'
              ? 'Ratings open once the parcel is delivered.'
              : 'Could not save the ${_label(target)} rating — try again.';
        });
        return;
      }
      _saved[target] = _stars[target]!;
    }
    if (!mounted) return;
    setState(() {
      _submitting = false;
      _message = 'Thanks — your rating keeps senders, drivers and couriers honest.';
    });
    _load();
  }

  String _label(String target) => switch (target) {
        'driver' => 'driver',
        'courier' => 'courier',
        _ => 'seller',
      };

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Center(child: AppLogoSpinner(size: 22)),
        ),
      );
    }
    final targets = ['driver', 'courier', if (_canRateSeller) 'seller'];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [
            Icon(Icons.star_rounded, color: AppColors.amber),
            SizedBox(width: 10),
            Expanded(child: Text('Rate this delivery', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16))),
          ]),
          const SizedBox(height: 4),
          const Text(
            'Score the driver, the courier and — if you were the recipient — the sender. Comments are optional but help everyone.',
            style: AppType.caption,
          ),
          const SizedBox(height: 14),
          for (final target in targets) ...[
            _targetRow(target),
            if (target != targets.last) const SizedBox(height: 16),
          ],
          if (!_canRateSeller) ...[
            const SizedBox(height: 14),
            const Text(
              'Senders are rated by recipients — share the tracking link so the buyer can score you here.',
              style: AppType.caption,
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _submitting ? null : _submit,
              icon: _submitting
                  ? const AppLogoSpinner(size: 16)
                  : const Icon(Icons.send_outlined),
              label: Text(_submitting ? 'Saving…' : 'Submit ratings'),
            ),
          ),
          if (_message != null) ...[
            const SizedBox(height: 10),
            Text(_message!, style: const TextStyle(fontSize: 11.5, color: AppColors.muted, height: 1.35)),
          ],
        ]),
      ),
    );
  }

  Widget _targetRow(String target) {
    final score = _stars[target]!;
    final saved = _saved[target];
    final summary = _summary[target];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(
          child: Text(
            _label(target).toUpperCase(),
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 11, letterSpacing: 0.8),
          ),
        ),
        if (saved != null && saved > 0)
          Text('Verified $saved/5', style: const TextStyle(fontSize: 10.5, color: AppColors.forest, fontWeight: FontWeight.w700)),
        if (summary != null && summary.count > 0) ...[
          const SizedBox(width: 8),
          Text(
            '${summary.average?.toStringAsFixed(1) ?? '–'} ★ (${summary.count})',
            style: const TextStyle(fontSize: 10.5, color: AppColors.muted),
          ),
        ],
      ]),
      Row(children: [
        for (var i = 1; i <= 5; i++)
          IconButton(
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(minWidth: 42, minHeight: 42),
            onPressed: () => setState(() => _stars[target] = i),
            icon: Icon(
              i <= score ? Icons.star_rounded : Icons.star_border_rounded,
              color: AppColors.amber,
              size: 30,
            ),
          ),
      ]),
      TextField(
        controller: _comments[target],
        maxLength: 500,
        minLines: 1,
        maxLines: 2,
        decoration: InputDecoration(
          labelText: 'Comment for the ${_label(target)} (optional)',
          counterText: '',
          isDense: true,
        ),
      ),
    ]);
  }
}

/// "Parcels for you" — parcels addressed to the signed-in caller's phone,
/// auto-claimed by phone match. Tap any row to open its live tracking page.
class _ParcelsForYou extends StatelessWidget {
  final List<Map<String, dynamic>> parcels;
  final Future<void> Function(Map<String, dynamic>) onOpen;
  const _ParcelsForYou({required this.parcels, required this.onOpen});

  static String _statusLabel(String raw) => raw.replaceAll('_', ' ').toUpperCase();

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: AppColors.forest.withValues(alpha: 0.35), width: 1.4),
      ),
      color: AppColors.forest.withValues(alpha: 0.04),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.mark_email_unread_outlined, color: AppColors.forest, size: 20),
            const SizedBox(width: 10),
            const Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Parcels for you', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                Text('Addressed to your number — tap to track', style: TextStyle(color: AppColors.muted, fontSize: 11.5)),
              ]),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(color: AppColors.forest, borderRadius: BorderRadius.circular(12)),
              child: Text('${parcels.length}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12)),
            ),
          ]),
          const SizedBox(height: 10),
          for (final p in parcels)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => onOpen(p),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                  child: Row(children: [
                    const Icon(Icons.inventory_2_outlined, size: 17, color: AppColors.forest),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${p['ref'] ?? 'Parcel'} · ${p['courier'] ?? ''}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                        Text('To ${p['dest_city'] ?? 'destination'}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: AppColors.muted, fontSize: 11)),
                      ]),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.line)),
                      child: Text(_statusLabel('${p['status'] ?? ''}'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w900, letterSpacing: 0.6, color: AppColors.forest)),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.chevron_right, size: 18, color: AppColors.muted),
                  ]),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}

/// PREPAY GATE card: a dispatched booking whose DropOff-leg prepayment has not
/// landed is HELD — no rider is assigned until the momo prompt is approved.
/// 'prepayment_pending' = the provider never started the prompt (booking held
/// at booking time); 'advance_pending' = a prompt is live on the sender's
/// phone. Pay now reuses the live prompt or issues a fresh one; approval
/// settles the payment server-side and dispatches the rider.
/// The server canceled this booking on its own (prepayment never approved, or
/// the parcel never moved) — surfaced so the sender is not left staring at a
/// silent stage-0 booking. Nothing was charged; they can rebook freely.
class _ExpiredCard extends StatelessWidget {
  final Booking booking;
  const _ExpiredCard({required this.booking});

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Row(children: [
              Icon(Icons.event_busy, color: AppColors.muted),
              SizedBox(width: 10),
              Expanded(child: Text('Booking canceled', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15))),
            ]),
            const SizedBox(height: 6),
            Text(
              booking.lastEvent == 'hold_expired'
                  ? 'The prepayment was never approved within 24 hours, so this booking was canceled. No money was taken. Book again in the app when you are ready.'
                  : 'This booking was canceled by the system (the parcel never moved). Any unspent prepayment is returned to your momo automatically.',
              style: const TextStyle(color: AppColors.ink, fontSize: 12.5, height: 1.4),
            ),
          ]),
        ),
      );
}

class _PrepayCard extends StatefulWidget {
  final Booking booking;
  const _PrepayCard({required this.booking});

  @override
  State<_PrepayCard> createState() => _PrepayCardState();
}

class _PrepayCardState extends State<_PrepayCard> {
  bool _busy = false;
  bool _pausing = false;
  bool? _pausedOverride;

  bool get _paused => _pausedOverride ?? widget.booking.repromptPaused;

  Future<void> _payNow() async {
    final store = AppScope.of(context);
    setState(() => _busy = true);
    final out = await PayJob.startAndPoll(jobRef: widget.booking.serverRef!, phone: widget.booking.senderPhone);
    if (!mounted) return;
    setState(() => _busy = false);
    AppToast.show(context, out.status == 'success'
        ? 'Prepayment received — your rider is being dispatched.'
        : out.status == 'failed'
            ? (out.failReason == null || out.failReason!.isEmpty)
                ? 'The momo prompt was rejected. Verify your momo balance has the funds, then tap Pay now again.'
                : 'Payment failed: ${out.failReason} — top up your momo wallet, then tap Pay now again.'
            : out.status.startsWith('error:')
                ? (out.status.contains('already paid')
                    ? 'This delivery is already paid.'
                    : 'Payment could not start (${out.status.substring(6)}) — verify your momo balance and connection, then retry.')
                : 'Prompt sent — approve it on your phone to dispatch your rider.');
    unawaited(store.syncJobsFromServer());
  }

  /// Pause/resume DropOff's payment reminders for this booking — for the
  /// sender who realised the money isn't there right now.
  Future<void> _togglePause(bool pause) async {
    final store = AppScope.of(context);
    setState(() => _pausing = true);
    final resume = await DropOffApi.jobPauseReprompt(widget.booking.serverRef!, paused: pause);
    if (!mounted) return;
    setState(() {
      _pausing = false;
      if (resume.ok) _pausedOverride = pause;
    });
    AppToast.show(context, resume.ok
        ? (pause ? 'Reminders paused — the booking stays HELD. Resume anytime.' : 'Reminders resumed — tap Pay now when you are ready.')
        : 'Could not update reminders (${resume.error ?? 'try again'}).');
    if (resume.ok) unawaited(store.syncJobsFromServer());
  }

  @override
  Widget build(BuildContext context) {
    final held = widget.booking.lastEvent == 'prepayment_pending';
    if (_paused) {
      return Card(
        color: const Color(0x14B3261E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: Color(0x66B3261E))),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Row(children: [
              Icon(Icons.notifications_off_outlined, size: 18, color: AppColors.danger),
              SizedBox(width: 8),
              Expanded(child: Text('Reminders paused — booking HELD', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5))),
            ]),
            const SizedBox(height: 4),
            const Text('You asked us not to prompt for payment right now. Nothing new goes out to your phone (pushes already on it can\'t be recalled). The booking stays saved and held — no rider until you pay.',
                style: AppType.caption),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: _pausing ? null : () => _togglePause(false),
              icon: _pausing
                  ? const AppLogoSpinner(size: 15)
                  : const Icon(Icons.notifications_active_outlined),
              label: Text(_pausing ? 'Resuming…' : 'Resume reminders'),
            ),
          ]),
        ),
      );
    }
    return Card(
      color: held ? const Color(0x14B3261E) : AppColors.amber.withValues(alpha: 0.14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: held ? const Color(0x66B3261E) : AppColors.amber.withValues(alpha: 0.5))),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(held ? Icons.pause_circle_outline : Icons.schedule_outlined,
                size: 18, color: held ? AppColors.danger : const Color(0xFF7B5710)),
            const SizedBox(width: 8),
            Expanded(child: Text(held ? 'Booking HELD — prepayment not started'
                    : 'Prepayment prompt waiting on your phone',
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5))),
          ]),
          const SizedBox(height: 4),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: Text(held
                ? 'Prompt never started — no rider yet. Verify momo balance, tap Pay now.'
                : 'Approve the momo prompt to dispatch your rider.',
                style: AppType.caption)),
            const HelpIconButton(topic: HelpTopic.depositRejection, size: 16),
          ]),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: _busy ? null : _payNow,
            icon: _busy
                ? const AppLogoSpinner(size: 15)
                : const Icon(Icons.payments_outlined),
            label: Text(_busy ? 'Starting prompt…' : 'Pay now — dispatch rider'),
          ),
          const SizedBox(height: 6),
          TextButton.icon(
            onPressed: _pausing ? null : () => _togglePause(true),
            icon: const Icon(Icons.notifications_off_outlined, size: 16),
            label: Text(_pausing ? 'Pausing…' : 'Pause reminders — I can\'t pay right now',
                style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: AppColors.danger)),
          ),
        ]),
      ),
    );
  }
}

/// DEPOT COUNTER FLOW — due card: the rider fronted the depot's counter fare
/// and submitted the written receipt; the sender repays the exact amount +
/// processing to DropOff by momo. The receipt photo is server-locked until
/// this payment lands, then it unlocks here and the rider is reimbursed.
class _CounterReceiptCard extends StatefulWidget {
  final Booking booking;
  const _CounterReceiptCard({required this.booking});

  @override
  State<_CounterReceiptCard> createState() => _CounterReceiptCardState();
}

class _CounterReceiptCardState extends State<_CounterReceiptCard> {
  bool _busy = false;

  Future<void> _payNow() async {
    final store = AppScope.of(context);
    setState(() => _busy = true);
    final res = await DropOffApi.payCounterFare(
      jobRef: widget.booking.serverRef!,
      phone: widget.booking.senderPhone,
      idempotencyKey: 'cfare-${widget.booking.serverRef}-${DateTime.now().millisecondsSinceEpoch}',
    );
    if (!mounted) return;
    if (!res.ok) {
      setState(() => _busy = false);
      AppToast.show(context, switch (res.error) {
        'counter_fare_already_paid' => 'This counter fare is already paid — the receipt is revealed in Bookings.',
        _ => 'Payment could not start (${res.error ?? 'network'}) — verify your momo balance and connection, then retry.',
      });
      return;
    }
    final paymentId = '${res.body['payment_id']}';
    final total = (res.body['amount_zmw'] as num?)?.toDouble();
    var status = 'pending';
    String? failReason;
    for (var attempt = 0; attempt < 20 && status == 'pending'; attempt++) {
      await Future<void>.delayed(const Duration(seconds: 2));
      final st = await DropOffApi.paymentStatus(paymentId);
      status = st.$1 ?? 'pending';
      failReason = st.$2;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    AppToast.show(context, switch (status) {
      'success' => 'Counter fare paid — your depot receipt is revealed below.',
      'failed' => (failReason == null || failReason.isEmpty)
          ? 'The momo prompt was rejected. Verify your momo balance has the funds, then tap Pay now again.'
          : 'Payment failed: $failReason — top up your momo wallet, then tap Pay now again.',
      _ => total != null
          ? 'Prompt sent for K${total.toStringAsFixed(2)} — approve it on your phone to reveal the receipt.'
          : 'Prompt sent — approve it on your phone to reveal the receipt.',
    });
    unawaited(store.syncJobsFromServer());
  }

  @override
  Widget build(BuildContext context) {
    final url = widget.booking.counterReceiptUrl;
    return Card(
      color: AppColors.amber.withValues(alpha: 0.14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: AppColors.amber.withValues(alpha: 0.5))),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [
            Icon(Icons.receipt_long_outlined, size: 18, color: Color(0xFF7B5710)),
            SizedBox(width: 8),
            Expanded(child: Text('Depot counter fare due',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5))),
          ]),
          const SizedBox(height: 4),
          Text('Your rider paid the depot counter out of their own pocket. The receipts below are YOURS — revealed when you pay — and the rider gets reimbursed.'
              '${(widget.booking.counterReceipts.length > 1) ? ' The depot split the batch into ${widget.booking.counterReceipts.length} receipts; you repay the exact total DropOff computed from them.' : ''}',
              style: AppType.caption),
          // REAL receipt photo (owner directive): the rider's actual depot
          // receipt is served to the sender, but rendered blurred behind a
          // lock until the depot bill is cleared — never a placeholder.
          if (url != null && url.isNotEmpty) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AspectRatio(
                aspectRatio: 1.4,
                child: Stack(fit: StackFit.expand, children: [
                  ImageFiltered(
                    imageFilter: ui.ImageFilter.blur(sigmaX: 9, sigmaY: 9),
                    child: Image.network(url, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const ColoredBox(
                            color: Color(0x11800000),
                            child: Center(child: Icon(Icons.lock_outline, size: 34, color: Color(0xFF7B5710))))),
                  ),
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(20)),
                      child: const Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.lock_outline, size: 14, color: Colors.white),
                        SizedBox(width: 6),
                        Text('Depot receipt — revealed after payment',
                            style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
                      ]),
                    ),
                  ),
                ]),
              ),
            ),
          ],
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: _busy ? null : _payNow,
            icon: _busy
                ? const AppLogoSpinner(size: 15)
                : const Icon(Icons.lock_open_outlined),
            label: Text(_busy ? 'Starting prompt…' : 'Pay now — reveal receipt'),
          ),
        ]),
      ),
    );
  }
}

/// Counter fare settled — show the unlocked depot receipt photo(s). A depot
/// that split a multi-parcel batch across receipts shows ALL of them.
class _CounterReceiptPaidCard extends StatelessWidget {
  final Booking booking;
  const _CounterReceiptPaidCard({required this.booking});

  @override
  Widget build(BuildContext context) {
    // Full filed list when the job carried multiple receipts; otherwise the
    // single primary photo.
    final receipts = booking.counterReceipts.isNotEmpty
        ? booking.counterReceipts
        : (booking.counterReceiptUrl?.isNotEmpty == true
            ? [(booking.counterReceiptZmw ?? 0, booking.counterReceiptUrl!)]
            : <(double, String)>[]);
    if (receipts.isEmpty) return const SizedBox.shrink();
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: AppColors.forest.withValues(alpha: 0.4))),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.verified_outlined, size: 18, color: AppColors.forest),
            const SizedBox(width: 8),
            Expanded(child: Text(receipts.length > 1
                ? 'Counter fare paid — ${receipts.length} depot receipts'
                : 'Counter fare paid — depot receipt',
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(color: AppColors.forest.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
              child: Text('K${(booking.counterReceiptZmw ?? 0).toStringAsFixed(2)}',
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 11.5, color: AppColors.forest)),
            ),
          ]),
          const SizedBox(height: 10),
          for (var i = 0; i < receipts.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 260),
                child: Stack(alignment: Alignment.topRight, children: [
                  Image.network(
                    receipts[i].$2,
                    fit: BoxFit.contain,
                    loadingBuilder: (_, child, progress) =>
                        progress == null ? child : const Padding(padding: EdgeInsets.all(18), child: Center(child: AppLogoSpinner(size: 22))),
                    errorBuilder: (_, __, ___) => const Text('Receipt photo could not load — it is stored safely on the server.',
                        style: TextStyle(color: AppColors.muted, fontSize: 11.5)),
                  ),
                  if (receipts.length > 1)
                    Container(
                      margin: const EdgeInsets.all(6),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(12)),
                      child: Text('Receipt ${i + 1} · K${receipts[i].$1.toStringAsFixed(2)}',
                          style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)),
                    ),
                ]),
              ),
            ),
          ],
        ]),
      ),
    );
  }
}


