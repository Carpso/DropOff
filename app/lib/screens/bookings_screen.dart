import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/catalog.dart';
import '../data/dropoff_api.dart';
import '../main.dart';
import '../models/booking.dart';
import '../ui/app_theme.dart';
import '../widgets/common.dart';
import 'account_screen.dart';
import 'booking_screen.dart';
import 'chat_screen.dart';
import 'inbox_screen.dart';
import 'rider_map_screen.dart';

class BookingsScreen extends StatelessWidget {
  const BookingsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    if (!store.linked) {
      // Bookings sync and chat need an identity — show the sign-in door only.
      return SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.lock_outline, size: 44, color: AppColors.muted),
              const SizedBox(height: 16),
              const Text('Sign in to see your bookings', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900), textAlign: TextAlign.center),
              const SizedBox(height: 8),
              const Text('Your parcels, courier handovers and chats live behind your account — phone code or email, your choice.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted, height: 1.45)),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AccountScreen())),
                icon: const Icon(Icons.login),
                label: const Text('Sign in'),
              ),
            ]),
          ),
        ),
      );
    }
    final bookings = store.bookings;
    return SafeArea(
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
          child: bookings.isEmpty
              ? EmptyState(
                  icon: Icons.inventory_2_outlined,
                  title: 'No parcels yet',
                  message: 'Book your first home-to-depot pickup. Your tracking timeline will appear here.',
                  action: FilledButton.icon(
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const BookingScreen())),
                    icon: const Icon(Icons.add),
                    label: const Text('Book a pickup'),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 26),
                  itemCount: bookings.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final booking = bookings[index];
                    return BookingCard(booking: booking, onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => BookingDetailScreen(bookingId: booking.id))));
                  },
                ),
        ),
      ]),
    );
  }
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
                Text('${booking.fromCity} → ${booking.toCity}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                const SizedBox(height: 3),
                Text(courier.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
              ])),
              const Icon(Icons.chevron_right, color: AppColors.muted),
            ]),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: Text(booking.reference, style: const TextStyle(fontSize: 11, color: AppColors.muted, fontWeight: FontWeight.w600))),
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

class BookingDetailScreen extends StatelessWidget {
  final String bookingId;
  const BookingDetailScreen({super.key, required this.bookingId});

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    final matches = store.bookings.where((item) => item.id == bookingId);
    if (matches.isEmpty) return const Scaffold(body: Center(child: Text('Booking not found')));
    final booking = matches.first;
    final courier = courierById(booking.courierId);
    final rider = store.riders.where((item) => item.id == booking.riderId).firstOrNull;
    final complete = booking.stage == booking.timeline.length - 1;
    return Scaffold(
      appBar: AppBar(title: Text(booking.reference, style: const TextStyle(fontWeight: FontWeight.w800))),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 6, 20, 28), children: [
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(color: AppColors.forest, borderRadius: BorderRadius.circular(24)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(booking.timeline[booking.stage].toUpperCase(), style: const TextStyle(color: AppColors.amber, fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 1)),
            const SizedBox(height: 12),
            Text('${booking.fromCity} → ${booking.toCity}', style: const TextStyle(color: Colors.white, fontSize: 25, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            Text(courier.name, style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 20),
            ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(value: (booking.stage + 1) / booking.timeline.length, minHeight: 5, backgroundColor: Colors.white24, color: AppColors.amber)),
          ]),
        ),
        const SizedBox(height: 24),
        const SectionTitle('Journey'),
        const SizedBox(height: 8),
        Card(child: Padding(padding: const EdgeInsets.all(18), child: Column(children: [
          for (var i = 0; i < booking.timeline.length; i++)
            _TimelineRow(title: booking.timeline[i], complete: i <= booking.stage, current: i == booking.stage, last: i == booking.timeline.length - 1),
        ]))),
        const SizedBox(height: 24),
        const SectionTitle('Booking details'),
        const SizedBox(height: 8),
        Card(child: Padding(padding: const EdgeInsets.all(18), child: Column(children: [
          _detailRow('Pickup', booking.pickupAddress),
          _detailRow('Parcel', '${booking.parcelSize.label} • ${booking.description}'),
          _detailRow('Sender', '${booking.senderName}\n${booking.senderPhone}'),
          _detailRow('Recipient', '${booking.recipientName}\n${booking.recipientPhone}'),
          _detailRow('Payment', booking.paymentMethod),
          _detailRow('Rider', rider?.name ?? 'DropOff Owner'),
          _detailRow('Rider fee', kwacha(booking.riderFee)),
          _detailRow('Courier fare', kwacha(booking.courierFare)),
          if (booking.lastMileFee > 0) _detailRow('Last-mile fee', kwacha(booking.lastMileFee)),
          _detailRow('Counter fare', '${booking.courierFare != null ? kwacha(booking.courierFare) : 'Confirmed at depot'} — pay directly to the depot'),
          _detailRow('DropOff due', '${kwacha(booking.riderFee + booking.lastMileFee)} + processing — DropOff charge, never partner money'),
          if (booking.promoCode != null)
            _detailRow('Promo', '${booking.promoCode}${booking.promoDiscount != null ? ' — saved ${kwacha(booking.promoDiscount)} on the DropOff leg' : ''}'),
        ]))),
        const SizedBox(height: 20),
        if (store.riders.where((item) => item.active).length > 1) ...[
          DropdownButtonFormField<String>(
            initialValue: booking.riderId,
            decoration: const InputDecoration(labelText: 'Assign rider / driver', prefixIcon: Icon(Icons.two_wheeler)),
            items: [for (final item in store.riders.where((item) => item.active)) DropdownMenuItem(value: item.id, child: Text('${item.name} • ${item.vehicle}'))],
            onChanged: (value) { if (value != null) store.assignRider(booking.id, value); },
          ),
          const SizedBox(height: 14),
        ],
        if (booking.stage < booking.timeline.length - 1)
          FilledButton.icon(
            onPressed: () => store.advanceBooking(booking.id),
            icon: const Icon(Icons.update),
            label: Text('Operator: mark “${booking.timeline[booking.stage + 1]}”'),
          )
        else
          const InfoPill(icon: Icons.check_circle, label: 'Journey complete'),
        if (booking.dispatched && DropOffApi.enabled && store.linked) ...[
          const SizedBox(height: 20),
          Row(children: [
            Expanded(child: FilledButton.tonalIcon(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => ChatScreen.job(booking.serverRef!),
              )),
              icon: const Icon(Icons.chat_bubble_outline),
              label: const Text('Chat about this delivery'),
            )),
          ]),
          const SizedBox(height: 20),
          _TrackingLinkCard(jobRef: booking.serverRef!),
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
          TextButton.icon(
            icon: const Icon(Icons.map_outlined),
            label: const Text('Track rider live'),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => RiderMapScreen(jobRef: booking.serverRef!),
            )),
          ),
        ],
        const SizedBox(height: 12),
        const Text('Rider controls update this device. Photo proof, courier waybill upload and seller notifications run through the linked backend.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted, fontSize: 11, height: 1.4)),
      ]),
    );
  }

  Widget _detailRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 95, child: Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 12))),
          const SizedBox(width: 10),
          Expanded(child: Text(value, textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, height: 1.35))),
        ]),
      );
}

/// App-bar door into chat: total unread badge across all my threads.
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
    final data = await DropOffApi.chatThreads();
    if (!mounted) return;
    final threads = ((data?['threads'] as List?) ?? const []).cast<Map<String, dynamic>>();
    setState(() => _unread = threads.fold<int>(0, (sum, t) => sum + ((t['unread'] as num?)?.toInt() ?? 0)));
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Inbox',
      onPressed: () async {
        await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const InboxScreen()));
        if (mounted) _load();
      },
      icon: Badge(
        isLabelVisible: _unread > 0,
        label: Text('$_unread'),
        child: const Icon(Icons.chat_bubble_outline),
      ),
    );
  }
}

class _TimelineRow extends StatelessWidget {
  final String title;
  final bool complete;
  final bool current;
  final bool last;
  const _TimelineRow({required this.title, required this.complete, required this.current, required this.last});

  @override
  Widget build(BuildContext context) => IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Column(children: [
            Icon(complete ? Icons.check_circle : Icons.circle_outlined, size: 22, color: complete ? AppColors.forest : AppColors.line),
            if (!last) Expanded(child: Container(width: 2, color: complete ? AppColors.forest : AppColors.line)),
          ]),
          const SizedBox(width: 13),
          Expanded(child: Padding(
            padding: EdgeInsets.only(bottom: last ? 2 : 24, top: 1),
            child: Text(title, style: TextStyle(fontSize: 14, fontWeight: current ? FontWeight.w900 : FontWeight.w600, color: complete ? AppColors.ink : AppColors.muted)),
          )),
        ]),
      );
}

class _TrackingLinkCard extends StatefulWidget {
  final String jobRef;
  const _TrackingLinkCard({required this.jobRef});

  @override
  State<_TrackingLinkCard> createState() => _TrackingLinkCardState();
}

class _TrackingLinkCardState extends State<_TrackingLinkCard> {
  bool _busy = false;

  Future<void> _copy() async {
    setState(() => _busy = true);
    final data = await DropOffApi.trackingLink(widget.jobRef);
    if (!mounted) return;
    setState(() => _busy = false);
    final url = data?['url'] as String?;
    if (url == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not create the tracking link. Check your connection.')),
      );
      return;
    }
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Recipient tracking link copied — send it by SMS or WhatsApp.')),
    );
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
              style: TextStyle(color: AppColors.muted, fontSize: 12, height: 1.4),
            ),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: _busy ? null : _copy,
              icon: _busy
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
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
      _message = 'Thanks — your rating keeps sellers, drivers and couriers honest.';
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
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
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
            'Score the driver, the courier and — if you were the recipient — the seller. Comments are optional but help everyone.',
            style: TextStyle(color: AppColors.muted, fontSize: 11.5, height: 1.35),
          ),
          const SizedBox(height: 14),
          for (final target in targets) ...[
            _targetRow(target),
            if (target != targets.last) const SizedBox(height: 16),
          ],
          if (!_canRateSeller) ...[
            const SizedBox(height: 14),
            const Text(
              'Sellers are rated by recipients — share the tracking link so the buyer can score you here.',
              style: TextStyle(color: AppColors.muted, fontSize: 11, height: 1.35),
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _submitting ? null : _submit,
              icon: _submitting
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
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


