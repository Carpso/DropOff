import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/analytics_service.dart';
import '../data/dropoff_api.dart';
import '../main.dart';
import '../ui/app_theme.dart';
import 'account_screen.dart';
import 'booking_screen.dart';
import 'track_screen.dart';

/// The seller's business dashboard: plan usage, parcels in flight, delivered
/// count, referral income — one glance, all server-backed. Shown as a bottom
/// tab for signed-in sellers (riders keep their Team view; admin keeps theirs).
class BusinessScreen extends StatefulWidget {
  const BusinessScreen({super.key});

  @override
  State<BusinessScreen> createState() => _BusinessScreenState();
}

class _BusinessScreenState extends State<BusinessScreen> {
  Map<String, dynamic>? _sub;
  Map<String, dynamic>? _packs;
  List<Map<String, dynamic>> _jobs = const [];
  Map<String, dynamic>? _refer;
  Map<String, dynamic>? _predict;
  bool _loading = true;

  /// Plan ladder for upgrade suggestions (matches the worker's TIER_RANK).
  static const List<String> _tierLadder = ['weekly', 'silver', 'gold', 'platinum'];

  @override
  void initState() {
    super.initState();
    AnalyticsService.instance.trackScreenView('business');
    _load();
  }

  Future<void> _load() async {
    if (!DropOffApi.enabled) {
      setState(() => _loading = false);
      return;
    }
    final store = AppScope.of(context);
    // Staff identities list jobs via ?phone= (customers are keyed by their JWT).
    final results = await Future.wait<dynamic>([
      DropOffApi.subscription(),
      DropOffApi.get('/jobs', store.linkedPhone != null ? {'phone': store.linkedPhone!} : null),
      DropOffApi.referralCode(),
      DropOffApi.plans(),
      DropOffApi.predictSeller(),
    ]);
    if (!mounted) return;
    setState(() {
      _sub = results[0] as Map<String, dynamic>?;
      _jobs = (((results[1] as Map<String, dynamic>?)?['jobs'] as List?) ?? const [])
          .cast<Map<String, dynamic>>();
      _refer = results[2] as Map<String, dynamic>?;
      _packs = results[3] as Map<String, dynamic>?;
      _predict = results[4] as Map<String, dynamic>?;
      _loading = false;
    });
  }

  bool _inFlight(Map<String, dynamic> job) {
    final status = '${job['status'] ?? job['last_event'] ?? ''}';
    return status != 'delivered' && status != 'ready_for_collection' && status != 'collected';
  }

  Future<void> _track(Map<String, dynamic> job) async {
    final ref = '${job['ref'] ?? ''}';
    if (ref.isEmpty) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Opening tracking…')));
    final link = await DropOffApi.trackingLink(ref);
    if (!mounted) return;
    final url = '${link?['url'] ?? ''}';
    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tracking not available for this parcel yet.')));
      return;
    }
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => TrackScreen(initialToken: url)));
    if (mounted) _load();
  }

  Future<void> _shareReferral() async {
    final code = '${_refer?['code'] ?? ''}';
    if (code.isEmpty) return;
    final text = '${_refer?['share_text'] ?? 'Join me on DropOff — Code $code'}';
    await launchUrl(Uri.parse('https://wa.me/?text=${Uri.encodeComponent(text)}'), mode: LaunchMode.externalApplication);
  }

  // ---- retention math -------------------------------------------------------

  /// Worker timestamps are UTC; naive ones ('YYYY-MM-DD HH:MM:SS') get a Z.
  DateTime? _ts(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return null;
    final t = s.replaceFirst(' ', 'T');
    final naive = !t.endsWith('Z') && !t.contains('+00:00') && !RegExp(r'[+-]\d{2}:?\d{2}$').hasMatch(t);
    return DateTime.tryParse(naive ? '${t}Z' : t);
  }

  bool _within30d(Map<String, dynamic> job) {
    final created = _ts('${job['created_at'] ?? ''}');
    if (created == null) return false;
    return DateTime.now().difference(created) <= const Duration(days: 30);
  }

  /// DropOff leg spend across the last 30 days: rider fee + door legs +
  /// processing (what the seller pays DropOff per parcel). Partner money is not
  /// counted — sellers don't see courier fares here anyway.
  ({double k, int parcels}) get _spend {
    var k = 0.0;
    var n = 0;
    for (final job in _jobs.where(_within30d)) {
      final fee = ((job['rider_fee_zmw'] ?? 0) as num).toDouble() +
          ((job['leg2_fee_zmw'] ?? 0) as num).toDouble() +
          ((job['leg2_processing_fee_zmw'] ?? 0) as num).toDouble();
      k += fee;
      n += (job['parcels'] as num?)?.toInt() ?? 1;
    }
    return (k: (k * 100).roundToDouble() / 100, parcels: n);
  }

  Map<String, dynamic>? _planOf(String tier) =>
      (_packs?['plans'] as Map<String, dynamic>?)?[tier] as Map<String, dynamic>?;

  Map<String, dynamic>? get _sub2 => _sub?['subscription'] as Map<String, dynamic>?;
  Map<String, dynamic>? get _plan => _sub?['plan'] as Map<String, dynamic>?;

  /// One-tap renewal: re-subscribes the current tier — the worker sends the
  /// momo prompt; payment status flips at the webhook exactly like first purchase.
  Future<void> _renew() async {
    final sub = _sub2;
    if (sub == null) return;
    final tier = '${sub['tier'] ?? ''}';
    if (tier.isEmpty) return;
    FocusScope.of(context).unfocus();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Momo prompt on its way — approve it to renew.')));
    final res = await DropOffApi.subscribe(
      tier: tier,
      pickupWindow: '${sub['pickup_window'] ?? '10:00'}',
      city: '${sub['city'] ?? 'Lusaka'}',
    );
    if (!mounted) return;
    final err = res.error ?? (res.ok ? null : 'Something went wrong.');
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err == null || err.isEmpty ? 'Prompt sent — approve on your phone to renew $tier.' : err)));
    if (err == null || err.isEmpty) _load();
  }

  /// Retention card: the maths that keeps sellers subscribed — pay-for-itself
  /// (no plan but regular shipping), overage savings (cap exhausted), and
  /// renewal-in-window with one tap.
  Widget? _retentionCard() {
    final sub = _sub2;
    final plan = _plan;
    if (sub == null) {
      final s = _spend;
      if (s.parcels < 3) return null; // not a regular yet — don't be pushy
      return _banner(
        icon: Icons.trending_up_rounded,
        title: '3+ parcels a month pays off with a plan',
        body: 'You shipped ${s.parcels > 30 ? 30 : s.parcels} parcels paying per trip. A Weekly Sprint (K399, 20/cycle) or monthly Silver / Gold / Platinum removes the per-parcel rider cost — most regulars save K${(s.k).toStringAsFixed(0)}+.',
        cta: 'Browse plans',
        onCta: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AccountScreen())),
      );
    }
    if ((sub['status'] ?? '') != 'active') return null;
    final cap = (plan?['parcels_per_month'] as num?)?.toInt() ?? 0;
    final used = (_sub?['usage_this_period'] as num?)?.toInt() ?? 0;
    final tier = '${sub['tier'] ?? ''}';
    final fee = (plan?['fee_zmw'] as num?)?.toDouble() ?? 0;
    final end = _ts('${sub['period_end'] ?? ''}');
    final renewsSoon = end != null && DateTime.now().add(const Duration(days: 3)).isAfter(end);
    if (renewsSoon) {
      final expired = DateTime.now().isAfter(end);
      final label = expired ? 'Renew now' : 'Renew early';
      return _banner(
        icon: Icons.schedule_rounded,
        title: expired ? 'Your $tier plan has run out' : '$tier plan ends ${'${sub['period_end'] ?? ''}'.split(' ').first}',
        body: expired
            ? (fee > 0 ? 'Renew for K${fee.toStringAsFixed(0)} to keep your plan rate — trips right now bill ad hoc.' : 'Renew to keep your plan rate — trips right now bill ad hoc.')
            : 'Renew now and the cycle starts over — your free-rider parcels stay topped up. We auto-bill 3 days before with a momo prompt.',
        cta: label,
        onCta: _renew,
      );
    }
    if (cap > 0 && used >= cap) {
      final pct = (plan?['overage_discount_pct'] as num?)?.toInt() ?? 0;
      final idx = _tierLadder.indexOf(tier);
      final nextTier = idx >= 0 && idx + 1 < _tierLadder.length ? _tierLadder[idx + 1] : null;
      final next = nextTier == null ? null : _planOf(nextTier);
      return _banner(
        icon: Icons.savings_outlined,
        title: 'You outgrew the $tier plan this cycle',
        body: next == null
            ? 'Extra parcels keep your ${pct > 0 ? '$pct% overage discount' : 'tier discount'} — you never pay full PAYG price.'
            : '${next['tag'] ?? nextTier!.toUpperCase()} adds ${(next['parcels_per_month'] as num?)?.toInt() ?? 0} parcels for K${(next['fee_zmw'] as num?)?.toStringAsFixed(0) ?? ''} —${pct > 0 ? ' and overages stay $pct% off' : ' pro-rated to the day'}. One tap in Manage.',
        cta: next == null ? 'Manage' : 'See $nextTier',
        onCta: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AccountScreen())),
      );
    }
    return null;
  }

  Widget _banner({required IconData icon, required String title, required String body, required String cta, required VoidCallback onCta}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.amber.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.amber.withValues(alpha: 0.35)),
      ),
      child: Row(children: [
        Icon(icon, size: 20, color: AppColors.amber),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13, height: 1.2)),
            const SizedBox(height: 3),
            Text(body, style: const TextStyle(color: AppColors.muted, fontSize: 11, height: 1.35)),
          ]),
        ),
        const SizedBox(width: 8),
        FilledButton(
          style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
          onPressed: onCta,
          child: Text(cta, maxLines: 1),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    if (!store.linked) {
      return const SafeArea(
        child: Center(child: Text('Sign in to see your business.', style: TextStyle(color: AppColors.muted))),
      );
    }
    final retention = _retentionCard();
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          children: [
            Row(children: [
              const Text('Business', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: -0.6)),
              const Spacer(),
              IconButton(tooltip: 'Refresh', onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh)),
            ]),
            const Text('Your plan, your parcels, your referrals — at a glance.', style: TextStyle(color: AppColors.muted, height: 1.4)),
            const SizedBox(height: 16),
            if (_loading)
              const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
            else ...[
              _planCard(),
              const SizedBox(height: 14),
              if (retention != null) ...[
                retention,
                const SizedBox(height: 14),
              ],
              if (_predictCard() != null) ...[
                _predictCard()!,
                const SizedBox(height: 14),
              ],
              _statsRow(),
              const SizedBox(height: 14),
              _inFlightCard(),
              const SizedBox(height: 14),
              _referralCard(),
            ],
          ],
        ),
      ),
    );
  }

  /// One-tap switch to the recommended plan — same momo-prompt activation
  /// path as renewing (webhook flips the plan live on payment).
  Future<void> _switchToPlan(String tier, String label) async {
    FocusScope.of(context).unfocus();
    final sub = _sub2;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Momo prompt on its way — approve it to activate $label.')));
    final res = await DropOffApi.subscribe(
      tier: tier,
      pickupWindow: '${sub?['pickup_window'] ?? '10:00'}',
      city: '${sub?['city'] ?? 'Lusaka'}',
    );
    if (!mounted) return;
    final err = res.error ?? (res.ok ? null : 'Something went wrong.');
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(err == null || err.isEmpty ? 'Prompt sent — approve on your phone to activate.' : err),
    ));
    if (err == null || err.isEmpty) _load();
  }

  /// DropOff Predict card: what the seller will likely ship next 30 days,
  /// and the cheapest plan that covers it. Hidden when the worker has no data.
  Widget? _predictCard() {
    final p = _predict;
    if (p == null) return null;
    final forecast = (p['forecast_next_30d'] as num?)?.toInt() ?? 0;
    final trend = (p['trend_parcels_per_month'] as num?)?.toDouble() ?? 0;
    final confidence = '${p['confidence'] ?? 'low'}';
    const weekdays = ['Sundays', 'Mondays', 'Tuesdays', 'Wednesdays', 'Thursdays', 'Fridays', 'Saturdays'];
    final wd = (p['peak_weekday'] as num?)?.toInt();
    final peakDay = wd != null && wd >= 0 && wd <= 6 ? weekdays[wd] : null;
    final peakWindow = p['peak_window'] as String?;
    final rec = p['recommended_plan'] as Map<String, dynamic>?;
    final daily = p['daily_option'] as Map<String, dynamic>?;
    final basis = '${p['basis'] ?? ''}';
    final trendUp = trend > 0;
    final trendFlat = trend == 0;
    final headline = forecast <= 0
        ? 'Not enough shipments yet to predict'
        : '≈ $forecast parcels in the next 30 days';
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: AppColors.forest.withValues(alpha: 0.28), width: 1.3),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.auto_awesome, color: AppColors.forest, size: 20),
            const SizedBox(width: 8),
            const Expanded(child: Text('DropOff Predict', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, letterSpacing: 0.2))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: AppColors.line.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(8)),
              child: Text('${confidence.toUpperCase()} CONFIDENCE', style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 0.6, color: AppColors.muted)),
            ),
          ]),
          const SizedBox(height: 10),
          Text(headline, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17, height: 1.25)),
          const SizedBox(height: 6),
          Wrap(spacing: 10, runSpacing: 4, children: [
            if (!trendFlat)
              Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(trendUp ? Icons.trending_up : Icons.trending_down, size: 15, color: trendUp ? AppColors.forest : AppColors.amber),
                const SizedBox(width: 4),
                Text('${trendUp ? '+' : ''}${trend.toStringAsFixed(1)} per month', style: const TextStyle(fontSize: 11, color: AppColors.muted, fontWeight: FontWeight.w700)),
              ]),
            if (peakDay != null)
              Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.calendar_today, size: 13, color: AppColors.muted),
                const SizedBox(width: 4),
                Text('Busiest on $peakDay', style: const TextStyle(fontSize: 11, color: AppColors.muted, fontWeight: FontWeight.w700)),
              ]),
            if (peakWindow != null)
              Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.schedule, size: 13, color: AppColors.muted),
                const SizedBox(width: 4),
                Text('$peakWindow window', style: const TextStyle(fontSize: 11, color: AppColors.muted, fontWeight: FontWeight.w700)),
              ]),
          ]),
          if (rec != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppColors.forest.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(12)),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Best fit: ${(rec['tag'] as String?) ?? '${rec['tier']}'.toUpperCase()} · K${(rec['fee_zmw'] as num?)?.toStringAsFixed(0)}',
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12.5)),
                    const SizedBox(height: 2),
                    Text('Covers ~${rec['parcels_per_month']} parcels — est. save K${(rec['est_savings_zmw'] as num?)?.toStringAsFixed(0) ?? '0'} vs pay-as-you-go',
                        style: const TextStyle(color: AppColors.muted, fontSize: 11)),
                  ]),
                ),
                const SizedBox(width: 8),
                FilledButton.tonal(
                  style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
                  onPressed: () => _switchToPlan('${rec['tier']}', '${rec['tag'] ?? rec['tier']}'),
                  child: const Text('Switch'),
                ),
              ]),
            ),
          ] else if (daily != null) ...[
            const SizedBox(height: 12),
            Text(
              'Shipping in bursts? The Daily Rider pass (K49/day, 2 parcels included) likely beats a monthly plan — ${daily['days_needed']} day(s) ≈ K${daily['cost_zmw']}.',
              style: const TextStyle(color: AppColors.muted, fontSize: 11.5, height: 1.4),
            ),
          ],
          const SizedBox(height: 8),
          if (basis.isNotEmpty)
            Text(basis, style: const TextStyle(color: AppColors.muted, fontSize: 9.5, height: 1.3)),
        ]),
      ),
    );
  }

  Widget _planCard() {
    final sub = _sub?['subscription'] as Map<String, dynamic>?;
    final plan = _sub?['plan'] as Map<String, dynamic>?;
    if (sub == null || plan == null || sub['status'] != 'active') {
      return Card(
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Icon(Icons.card_giftcard_outlined, color: AppColors.forest, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'No plan yet',
                          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Subscription plans bundle the rider — Weekly Sprint K399 or monthly Silver K250 / Gold K500 / Platinum K750. Pay once, no rider fee per parcel.',
                          softWrap: true,
                          style: TextStyle(color: AppColors.muted, fontSize: 12.5, height: 1.4),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.tonal(
                  style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AccountScreen())),
                  child: const Text('Browse plans'),
                ),
              ),
            ],
          ),
        ),
      );
    }
    final cap = (plan['parcels_per_month'] as num?)?.toInt() ?? 0;
    final used = (_sub?['usage_this_period'] as num?)?.toInt() ?? 0;
    final remaining = (_sub?['remaining_this_period'] as num?)?.toInt() ?? 0;
    final tier = '${sub['tier'] ?? ''}'.toUpperCase();
    final renews = '${sub['period_end'] ?? ''}'.split(' ').first;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.workspace_premium_outlined, color: AppColors.forest),
            const SizedBox(width: 10),
            Expanded(child: Text('$tier plan', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15))),
            FilledButton.tonal(
              style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AccountScreen())),
              child: const Text('Manage'),
            ),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            // alphabetic baseline (instead of the old height:2.6 hack) keeps the
            // big counter and its caption aligned on every font scale — the
            // caption used to misalign / render letter-per-line on some sizes.
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text('$used', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 30, color: AppColors.forest)),
                  const SizedBox(width: 5),
                  Text(' / $cap parcels used', style: const TextStyle(color: AppColors.muted, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            Text(used >= cap ? 'Cap reached' : '$remaining left', maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: AppColors.amber)),
          ]),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: cap > 0 ? (used / cap).clamp(0.0, 1.0) : 0,
              minHeight: 7,
              backgroundColor: AppColors.line.withValues(alpha: 0.4),
              color: used >= cap ? AppColors.amber : AppColors.forest,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            used >= cap
                ? 'Extra parcels now pay your tier discount — auto-applied at booking. Renews $renews.'
                : 'Each parcel counts as one — even several in one trip. Cycle renews $renews.',
            style: const TextStyle(color: AppColors.muted, fontSize: 11, height: 1.35),
          ),
        ]),
      ),
    );
  }

  Widget _statsRow() {
    final inFlight = _jobs.where(_inFlight).length;
    final delivered = _jobs.length - inFlight;
    final spend = _spend;
    return Row(children: [
      Expanded(child: _Stat(value: '$inFlight', label: 'In flight', icon: Icons.local_shipping_outlined, accent: true)),
      const SizedBox(width: 10),
      Expanded(child: _Stat(value: '$delivered', label: 'Delivered · recent', icon: Icons.check_circle_outline)),
      const SizedBox(width: 10),
      Expanded(child: _Stat(
        value: spend.k > 0 ? 'K${spend.k % 1 == 0 ? spend.k.toStringAsFixed(0) : spend.k.toStringAsFixed(2)}' : 'K0',
        label: spend.k > 0 ? 'DropOff spend · 30d (${spend.parcels} parcels)' : 'DropOff spend · 30d',
        icon: Icons.account_balance_wallet_outlined,
      )),
    ]);
  }

  Widget _inFlightCard() {
    final flying = _jobs.where(_inFlight).take(4).toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.route_rounded, color: AppColors.forest),
            const SizedBox(width: 8),
            // maxLines:1 — when both action buttons squeeze the row (small
            // phones / large system font) an unconstrained title used to wrap
            // letter-by-letter down the card ("Parcels in flight" vertical
            // text bug).
            const Expanded(
              child: Text(
                'Parcels in flight',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
              ),
            ),
            if (_jobs.isNotEmpty)
              TextButton(
                style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 6), minimumSize: Size.zero),
                onPressed: () {
                  // Repeat-last-booking: clone the most recent job's details into
                  // the booking form (cities, branch, courier, recipients…).
                  final src = _jobs.first;
                  BookingScreen.prefill = {
                    'from': src['from_city'] ?? 'Lusaka',
                    'to': src['dest_city'] ?? '',
                    'branch': src['branch'] ?? '',
                    'pickup': src['pickup_address'] ?? '',
                    'description': src['description'] ?? '',
                    'sender_name': src['sender_name'] ?? '',
                    'sender_phone': src['sender_phone'] ?? '',
                    'recipient_name': src['recipient_name'] ?? '',
                    'recipient_phone': src['recipient_phone'] ?? '',
                    'weight_class': src['weight_class'] ?? '',
                    'courier_id': src['courier_id'],
                    'parcels': src['parcels'],
                    'vehicle_class': src['vehicle_class'] ?? '',
                  };
                  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const BookingScreen()));
                },
                child: const Text('Repeat last'),
              ),
            TextButton(
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 6), minimumSize: Size.zero),
              onPressed: flying.isEmpty ? null : () => _track(flying.first),
              child: const Text('Track'),
            ),
          ]),
          const SizedBox(height: 4),
          if (flying.isEmpty)
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text(
                'Nothing on the road right now.',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: AppColors.muted, fontSize: 12.5),
              ),
              const SizedBox(height: 10),
              FilledButton(
                style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const BookingScreen())),
                child: const Text('Book a pickup', maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ])
          else
            ...flying.map((job) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => _track(job),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 7),
                      child: Row(children: [
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('${job['ref'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                          const SizedBox(height: 2),
                          Text(
                            '${_jobDestination(job)} · for ${job['recipient_name'] ?? 'recipient'}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: AppColors.muted, fontSize: 11),
                          ),
                        ])),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                          decoration: BoxDecoration(color: AppColors.forest.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
                          child: Text('${job['status'] ?? 'created'}'.replaceAll('_', ' '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              softWrap: false,
                              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.forest)),
                        ),
                      ]),
                    ),
                  ),
                )),
          if (flying.isNotEmpty)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => Clipboard.setData(ClipboardData(text: '${flying.first['ref'] ?? ''}')),
                icon: const Icon(Icons.copy, size: 15),
                label: const Text('Copy ref', style: TextStyle(fontSize: 12)),
              ),
            ),
        ]),
      ),
    );
  }

  String _jobDestination(Map<String, dynamic> job) {
    final branch = '${job['branch'] ?? ''}'.trim();
    if (branch.isNotEmpty) return '${job['pickup_city'] ?? job['from_city'] ?? 'Pickup'} → $branch';
    return '${job['pickup_city'] ?? job['from_city'] ?? 'Pickup'} → ${job['dest_city'] ?? ''}';
  }

  Widget _referralCard() {
    final code = '${_refer?['code'] ?? ''}';
    final rewarded = ((_refer?['stats']?['rewarded'] as num?)?.toInt()) ?? 0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.card_giftcard_outlined, color: AppColors.forest),
            const SizedBox(width: 8),
            const Expanded(child: Text('Invite sellers — earn', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15))),
            Text('$rewarded earned', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: AppColors.forest)),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                decoration: BoxDecoration(color: AppColors.line.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(12)),
                child: Text(code.isEmpty ? 'Loading code…' : code, style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.4, fontSize: 15)),
              ),
            ),
            const SizedBox(width: 10),
            IconButton.filled(
              tooltip: 'Copy code',
              onPressed: code.isEmpty ? null : () => Clipboard.setData(ClipboardData(text: code)),
              icon: const Icon(Icons.copy, size: 18),
            ),
            const SizedBox(width: 4),
            IconButton.filledTonal(
              tooltip: 'Share on WhatsApp',
              onPressed: code.isEmpty ? null : _shareReferral,
              icon: const Icon(Icons.share_rounded, size: 18),
            ),
          ]),
        ]),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label, required this.icon, this.accent = false});

  final String value;
  final String label;
  final IconData icon;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: accent ? AppColors.forest.withValues(alpha: 0.07) : AppColors.line.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent ? AppColors.forest.withValues(alpha: 0.22) : AppColors.line),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 18, color: accent ? AppColors.forest : AppColors.muted),
        const SizedBox(height: 8),
        Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 19, color: accent ? AppColors.forest : AppColors.ink)),
        const SizedBox(height: 2),
        Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.muted, fontSize: 10.5, height: 1.25, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}
