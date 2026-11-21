import 'package:flutter/material.dart';

import '../data/analytics_service.dart';
import '../data/dropoff_api.dart';
import '../main.dart';
import '../ui/app_theme.dart';
import '../widgets/common.dart';
import 'tickets_screen.dart';
import 'rider_map_screen.dart';
import '../screens/account_screen.dart';
import '../ui/app_spinner.dart';
import '../ui/app_toast.dart';

/// Recipient parcel tracking — the same view the SMS link opens, reachable
/// in-app. Paste the tracking link or the token. The SERVER decides who sees
/// parcel data: a signed-in DropOff account whose phone is the sender's or
/// recipient's, or staff keys. EVERYONE ELSE gets an account gate —
/// no account, no parcel data. Not phone-OTP, not grants: an account.
class TrackScreen extends StatefulWidget {
  const TrackScreen({super.key, this.initialToken});

  /// Token or full /track/ URL (e.g. pasted from the recipient SMS).
  final String? initialToken;

  @override
  State<TrackScreen> createState() => _TrackScreenState();
}

class _TrackScreenState extends State<TrackScreen> {
  final _input = TextEditingController();
  Map<String, dynamic>? _data;
  String? _autoTriggeredFor;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.initialToken != null && widget.initialToken!.trim().isNotEmpty) {
      _input.text = widget.initialToken!;
      _lookup();
    }
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _lookup() async {
    final token = _input.text.trim();
    if (token.isEmpty) return;
    setState(() { _loading = true; _error = null; });
    final data = await DropOffApi.trackByToken(token);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _data = data;
      _error = data == null ? 'Not found — check the link or code from the SMS.' : null;
    });
  }

  /// Pull a tracking token out of whatever was pasted — a bare token, a full
  /// /track/<token> URL, the /t/<token> vanity path, or a deep link.
  String? _tokenIn(String raw) {
    final v = raw.trim();
    if (v.isEmpty) return null;
    final m = RegExp(r'/(?:track|t)/([A-Za-z0-9_-]{16,})').firstMatch(v);
    if (m != null) return m.group(1);
    if (RegExp(r'^[A-Za-z0-9_-]{16,}$').hasMatch(v)) return v;
    return null;
  }

  /// Paste fires onChanged but never submits — auto-lookup once the pasted
  /// text contains something that looks like a full token.
  void _onChanged(String value) {
    final token = _tokenIn(value);
    if (token == null) {
      if (_autoTriggeredFor != null && !value.contains(_autoTriggeredFor!)) _autoTriggeredFor = null;
      return;
    }
    if (token == _autoTriggeredFor || _loading) return;
    _autoTriggeredFor = token;
    _lookup();
  }

  /// Open the account flow, then retry the lookup with the fresh session.
  Future<void> _openAccount() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AccountScreen()));
    if (!mounted) return;
    if (AppScope.of(context).linked) await _lookup();
  }

  @override
  Widget build(BuildContext context) {
    AnalyticsService.instance.trackScreenView('track');
    final gated = _data?['requires_account'] == true;
    final held = _data?['payment_held'] == true;
    return Scaffold(
      appBar: AppBar(title: const Text('Track a delivery', style: TextStyle(fontWeight: FontWeight.w900))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        children: [
          TextField(
            controller: _input,
            textInputAction: TextInputAction.go,
            onSubmitted: (_) => _lookup(),
            onChanged: _onChanged,
            decoration: InputDecoration(
              labelText: 'Tracking link or code',
              hintText: 'Paste the link from the SMS',
              prefixIcon: const Icon(Icons.link),
              suffixIcon: IconButton(icon: const Icon(Icons.search), onPressed: _loading ? null : _lookup),
            ),
          ),
          const SizedBox(height: 14),
          if (_loading) const Center(child: Padding(padding: EdgeInsets.all(22), child: AppLogoSpinner(size: 26))),
          if (_error != null)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: AppColors.canvas, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.line)),
              child: Row(children: [
                const Icon(Icons.search_off_rounded, color: AppColors.muted),
                const SizedBox(width: 10),
                Expanded(child: Text(_error!, style: const TextStyle(color: AppColors.ink, fontSize: 13, height: 1.35))),
              ]),
            ),
          if (gated) _accountCard(),
          if (held) _heldCard(),
          if (_data != null && !gated && !held) ...[
            _statusHeader(_data!),
            if (AppScope.of(context).linked) ...[
              const SizedBox(height: 14),
              // Support is ticket-only — a stranger with the tracking link has
              // no account and cannot read the parcel or open a ticket.
              FilledButton.tonalIcon(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => TicketsScreen(prefill: 'Question about item ${_data?['ref'] ?? ''}: '),
                )),
                icon: const Icon(Icons.support_agent_outlined),
                label: const Text('Get help with this delivery'),
              ),
              // RECIPIENT RATES THE SENDER (owner 2026-11-21): the sender
              // cannot rate himself; only the parcel's recipient can.
              if (['delivered', 'ready_for_collection']
                  .contains('${_data?['status'] ?? ''}'))
                _RateSenderCard(jobRef: '${_data?['ref'] ?? ''}'),
            ],
            const SizedBox(height: 8),
            _riderStrip(_data!),
            const SizedBox(height: 20),
            const SectionTitle('Journey'),
            const SizedBox(height: 8),
            Card(child: Padding(padding: const EdgeInsets.all(18), child: Column(children: [
              for (final e in ((_data!['events'] as List?) ?? const []))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(children: [
                    const Icon(Icons.check_circle, size: 18, color: AppColors.forest),
                    const SizedBox(width: 10),
                    Expanded(child: Text(_prettyStatus('${e['status']}'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13))),
                  ]),
                ),
              if (((_data!['events'] as List?) ?? const []).isEmpty)
                const Text('No updates yet — refresh in a minute.', style: TextStyle(color: AppColors.muted, fontSize: 12)),
            ]))),
            const SizedBox(height: 10),
            TextButton.icon(
              onPressed: _loading ? null : _lookup,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Refresh'),
            ),
          ],
        ],
      ),
    );
  }

  /// Payment-held parcel (owner directive 2026-11-15): the sender's prepayment
  /// has not settled, so tracking stays locked — no timeline, no rider, no
  /// live location. The server flips it open itself the moment payment lands.
  Widget _heldCard() {
    final hint = '${_data?['hint'] ?? ''}';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [
            Icon(Icons.lock_clock, color: AppColors.amber),
            SizedBox(width: 10),
            Expanded(child: Text('Tracking is locked — payment pending',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16))),
          ]),
          const SizedBox(height: 8),
          Text(
            hint.isEmpty
                ? 'Prepayment pending — tracking opens once the sender’s payment is approved.'
                : hint,
            style: const TextStyle(color: AppColors.ink, fontSize: 13, height: 1.4),
          ),
        ]),
      ),
    );
  }

  /// Account gate — shown when the server says the viewer has no account-backed
  /// access (requires_account). Only a signed-in account whose phone is the
  /// sender's or recipient's can open the parcel; the link alone proves nothing.
  Widget _accountCard() {
    final hint = '${_data?['hint_phone'] ?? ''}';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [
            Icon(Icons.lock_outline, color: AppColors.forest),
            SizedBox(width: 10),
            Expanded(child: Text('An account is needed', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16))),
          ]),
          const SizedBox(height: 8),
          Text(
            hint.isEmpty
                ? 'This item opens only in a DropOff account signed in with the phone it was addressed to (or the sender’s). Sign in or create your account, then open the link again.'
                : 'This item opens only in a DropOff account signed in with the phone it was addressed to (or the sender’s). Try the number ending $hint.',
            style: const TextStyle(color: AppColors.ink, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
              child: FilledButton(
                onPressed: _openAccount,
                child: const Text('Create account', maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton(
                onPressed: _openAccount,
                child: const Text('Sign in', maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          const Text(
            'Create your account with the number the item was sent to and every item addressed to you appears here automatically.',
            style: AppType.caption,
          ),
        ]),
      ),
    );
  }

  static String _prettyStatus(String raw) {
    final s = raw.replaceAll('_', ' ').trim();
    if (s.isEmpty) return s;
    return s.split(RegExp(r'\s+')).map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}').join(' ');
  }

  String? _formatArrival(String? iso) {
    if (iso == null) return null;
    final t = DateTime.tryParse(iso);
    if (t == null) return null;
    final local = t.toLocal();
    final now = DateTime.now();
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final sameDay = local.year == now.year && local.month == now.month && local.day == now.day;
    // 12-hour with AM/PM — how the owner reads every DropOff time.
    final h12 = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final mm = local.minute.toString().padLeft(2, '0');
    final am = local.hour < 12 ? 'AM' : 'PM';
    if (sameDay) return 'today $h12:$mm $am';
    final tomorrow = now.add(const Duration(days: 1));
    if (local.year == tomorrow.year && local.month == tomorrow.month && local.day == tomorrow.day) {
      return 'tomorrow $h12:$mm $am';
    }
    return '${local.day} ${months[local.month - 1]} $h12:$mm $am';
  }

  Widget _statusHeader(Map<String, dynamic> d) {
    final dropoff = d['dropoff'] as Map<String, dynamic>?;
    final branch = '${dropoff?['branch'] ?? ''}'.trim();
    final dropoffPoint = branch.isNotEmpty ? '$branch (${dropoff?['courier'] ?? ''})' : '${d['dest_city'] ?? 'depot'}';
    final dropoffIsBranch = branch.isNotEmpty;
    return Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(color: AppColors.forest, borderRadius: BorderRadius.circular(20)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${d['status'] ?? ''}'.replaceAll('_', ' ').toUpperCase(),
              style: const TextStyle(color: AppColors.amber, fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 1)),
          const SizedBox(height: 12),
          Text('${d['pickup_city'] ?? 'Pickup'} → $dropoffPoint',
              style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          if (d['you_are'] != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                Icon(d['you_are'] == 'recipient' ? Icons.card_giftcard : Icons.verified_user,
                    size: 14, color: AppColors.amber),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    d['you_are'] == 'recipient'
                        ? 'Addressed to you${d['verified_for'] != null ? ' — ${d['verified_for']}' : ''} · this item belongs to your number'
                        : d['you_are'] == 'sender'
                            ? 'You sent this item'
                            : 'Tracking as DropOff team',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12),
                  ),
                ),
              ]),
            ),
          Text(
            dropoffIsBranch
                ? 'First mile: to your nominated ${d['courier'] ?? ''} depot branch${d['dest_city'] != null ? ' · onward to ${d['dest_city']}' : ''}'
                : 'For ${d['recipient_name'] ?? 'recipient'} • via ${d['courier'] ?? 'courier'}',
            style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.35),
          ),
          if (d['eta_minutes'] != null) ...[
            const SizedBox(height: 6),
            Text('ETA ~${d['eta_minutes']} min', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          ],
          if (d['predicted'] is Map<String, dynamic>) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
              ),
              child: Row(children: [
                const Icon(Icons.auto_awesome, size: 15, color: AppColors.amber),
                const SizedBox(width: 8),
                Expanded(child: Builder(builder: (context) {
                  final p = d['predicted'] as Map<String, dynamic>;
                  final eta = (p['eta_minutes'] as num?)?.toInt();
                  final arrival = _formatArrival(p['arrival_by'] as String?);
                  final confidence = '${p['confidence'] ?? ''}';
                  if (eta == 0) {
                    return const Text('Delivered — nothing left to wait for',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12.5));
                  }
                  return Text(
                    'Predicted: ${arrival == null ? 'in ~$eta min' : 'around $arrival'} · $confidence confidence',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12.5),
                  );
                })),
              ]),
            ),
            if ('${(d['predicted'] as Map)['basis'] ?? ''}'.isNotEmpty) ...[
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Text('${(d['predicted'] as Map)['basis']}',
                    style: const TextStyle(color: Colors.white54, fontSize: 10, height: 1.3)),
              ),
            ],
          ],
        ]),
      );
  }

  /// Circular rider avatar: the rider's selfie when uploaded (auth-gated media),
  /// initials otherwise. Verified badge appears only when an admin approved KYC.
  Widget _riderAvatar(String? url, String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    final initials = parts.isEmpty ? '?' : parts.take(2).map((w) => w[0].toUpperCase()).join();
    return CircleAvatar(
      radius: 26,
      backgroundColor: AppColors.forest.withValues(alpha: 0.12),
      child: url == null || url.isEmpty
          ? Text(initials, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: AppColors.forest))
          : ClipOval(
              child: Image.network(
                '${DropOffApi.baseUrl}$url',
                headers: DropOffApi.authHeaders,
                width: 52,
                height: 52,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Text(initials,
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: AppColors.forest)),
              ),
            ),
    );
  }

  Widget _riderStrip(Map<String, dynamic> d) {
    final rider = d['rider'] as Map<String, dynamic>?;
    final loc = d['location'] as Map<String, dynamic>?;
    if (rider == null && loc == null) return const SizedBox.shrink();
    final photo = rider?['photo_url'] as String?;
    final verified = rider?['verified'] == true;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          if (rider != null)
            _riderAvatar(photo, '${rider['name'] ?? ''}')
          else
            const Icon(Icons.two_wheeler, color: AppColors.forest),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (rider != null)
              Text('${rider['name']} • ${rider['vehicle']}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
            if (rider != null) ...[
              const SizedBox(height: 3),
              Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(verified ? Icons.verified : Icons.hourglass_empty,
                    size: 13, color: verified ? AppColors.forest : AppColors.muted),
                const SizedBox(width: 4),
                Text(verified ? 'Verified rider' : 'Verification pending',
                    style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 0.4,
                        color: verified ? AppColors.forest : AppColors.muted)),
              ]),
            ],
            if (loc != null)
              Text('Last fix ${loc['seen_at'] ?? ''}', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
            if (rider == null)
              const Text('Rider on the way', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
          ])),
          if (loc != null && loc['lat'] != null)
            IconButton(
              tooltip: 'Watch live on the map',
              icon: const Icon(Icons.map_outlined, color: AppColors.forest),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => RiderMapScreen(jobRef: d['ref'] as String),
              )),
            ),
        ]),
      ),
    );
  }
}

/// The recipient scores the SENDER (owner 2026-11-21). A sender opening their
/// own tracking link is rejected by the worker's cannot_rate_self guard.
class _RateSenderCard extends StatefulWidget {
  final String jobRef;
  const _RateSenderCard({required this.jobRef});

  @override
  State<_RateSenderCard> createState() => _RateSenderCardState();
}

class _RateSenderCardState extends State<_RateSenderCard> {
  int _stars = 0;
  bool _busy = false;
  bool _done = false;

  Future<void> _submit() async {
    if (_stars < 1) {
      AppToast.show(context, 'Tap the stars to rate the sender first.');
      return;
    }
    setState(() => _busy = true);
    final res = await DropOffApi.rateJob(
      jobRef: widget.jobRef,
      targetType: 'seller',
      stars: _stars,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (res.ok || res.error == 'cannot_rate_self' || res.error == 'already_rated') _done = true;
    });
    AppToast.show(context, switch (res.error) {
      'cannot_rate_self' => 'You are the sender — only the recipient can rate you.',
      _ => res.ok ? 'Done — Thank You for rating the sender. Your rating helps Riders, Couriers and Senders build a good name.' : 'Could not save your rating. Check your connection and try again.',
    });
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Row(children: [
                Icon(Icons.star_rounded, color: AppColors.amber),
                SizedBox(width: 8),
                Expanded(child: Text('Rate the sender', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15))),
              ]),
              const SizedBox(height: 4),
              const Text('You received this item — your score is the sender\'s rating.', style: AppType.caption),
              const SizedBox(height: 8),
              Row(children: [
                for (var i = 1; i <= 5; i++)
                  IconButton(
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints(minWidth: 42, minHeight: 42),
                    onPressed: _done ? null : () => setState(() => _stars = i),
                    icon: Icon(i <= _stars ? Icons.star_rounded : Icons.star_border_rounded,
                        color: AppColors.amber, size: 28),
                  ),
              ]),
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _done || _busy ? null : _submit,
                  icon: _busy
                      ? const AppLogoSpinner(size: 16)
                      : Icon(_done ? Icons.check_circle : Icons.send_outlined),
                  label: Text(_done ? 'Done' : (_busy ? 'Saving…' : 'Submit rating')),
                ),
              ),
            ]),
          ),
        ),
      );
}
