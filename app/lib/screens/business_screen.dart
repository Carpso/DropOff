import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/dropoff_api.dart';
import '../main.dart';
import '../ui/app_theme.dart';
import 'account_screen.dart';
import 'booking_screen.dart';
import 'track_screen.dart';

/// The seller's business dashboard: pack usage, parcels in flight, delivered
/// count, referral income — one glance, all server-backed. Shown as a bottom
/// tab for signed-in sellers (riders keep their Team view; admin keeps theirs).
class BusinessScreen extends StatefulWidget {
  const BusinessScreen({super.key});

  @override
  State<BusinessScreen> createState() => _BusinessScreenState();
}

class _BusinessScreenState extends State<BusinessScreen> {
  Map<String, dynamic>? _sub;
  List<Map<String, dynamic>> _jobs = const [];
  Map<String, dynamic>? _refer;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
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
    ]);
    if (!mounted) return;
    setState(() {
      _sub = results[0] as Map<String, dynamic>?;
      _jobs = (((results[1] as Map<String, dynamic>?)?['jobs'] as List?) ?? const [])
          .cast<Map<String, dynamic>>();
      _refer = results[2] as Map<String, dynamic>?;
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

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    if (!store.linked) {
      return const SafeArea(
        child: Center(child: Text('Sign in to see your business.', style: TextStyle(color: AppColors.muted))),
      );
    }
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
            const Text('Your pack, your parcels, your referrals — at a glance.', style: TextStyle(color: AppColors.muted, height: 1.4)),
            const SizedBox(height: 16),
            if (_loading)
              const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
            else ...[
              _planCard(),
              const SizedBox(height: 14),
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

  Widget _planCard() {
    final sub = _sub?['subscription'] as Map<String, dynamic>?;
    final plan = _sub?['plan'] as Map<String, dynamic>?;
    if (sub == null || plan == null || sub['status'] != 'active') {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            const Icon(Icons.card_giftcard_outlined, color: AppColors.forest),
            const SizedBox(width: 12),
            const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('No pack yet', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
              SizedBox(height: 3),
              Text('Packs bundle the rider — from K69 for a Daily Dash. Pay once, no rider fee per parcel.', style: TextStyle(color: AppColors.muted, fontSize: 11.5, height: 1.35)),
            ])),
            FilledButton.tonal(
              style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AccountScreen())),
              child: const Text('Browse'),
            ),
          ]),
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
            Expanded(child: Text('$tier pack', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15))),
            FilledButton.tonal(
              style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AccountScreen())),
              child: const Text('Manage'),
            ),
          ]),
          const SizedBox(height: 10),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('$used', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 30, color: AppColors.forest)),
            Text(' / $cap parcels used', style: const TextStyle(color: AppColors.muted, fontWeight: FontWeight.w700, height: 2.6)),
            const Spacer(),
            Text(used >= cap ? 'Cap reached' : '$remaining left', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: AppColors.amber)),
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
    final rewarded = ((_refer?['stats']?['rewarded'] as num?)?.toInt()) ?? 0;
    final pending = ((_refer?['stats']?['pending'] as num?)?.toInt()) ?? 0;
    return Row(children: [
      Expanded(child: _Stat(value: '$inFlight', label: 'In flight', icon: Icons.local_shipping_outlined, accent: true)),
      const SizedBox(width: 10),
      Expanded(child: _Stat(value: '$delivered', label: 'Delivered · recent', icon: Icons.check_circle_outline)),
      const SizedBox(width: 10),
      Expanded(child: _Stat(value: '$rewarded', label: 'Referrals earned${pending > 0 ? ' (+$pending pending)' : ''}', icon: Icons.handshake_outlined)),
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
            const Expanded(child: Text('Parcels in flight', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15))),
            TextButton(
              onPressed: flying.isEmpty ? null : () => _track(flying.first),
              child: const Text('Track'),
            ),
          ]),
          const SizedBox(height: 4),
          if (flying.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(children: [
                const Expanded(child: Text('Nothing on the road right now.', style: TextStyle(color: AppColors.muted, fontSize: 12.5))),
                FilledButton(
                  style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const BookingScreen())),
                  child: const Text('Book a pickup'),
                ),
              ]),
            )
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
                          Text('${job['ref'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                          const SizedBox(height: 2),
                          Text(
                            '${_jobDestination(job)} · for ${job['recipient_name'] ?? 'recipient'}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: AppColors.muted, fontSize: 11),
                          ),
                        ])),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                          decoration: BoxDecoration(color: AppColors.forest.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
                          child: Text('${job['status'] ?? 'created'}'.replaceAll('_', ' '),
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
