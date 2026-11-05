import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/dropoff_api.dart';
import '../main.dart';
import '../ui/app_theme.dart';
import '../widgets/common.dart';
import 'account_screen.dart';
import 'chat_screen.dart';

/// Recipient parcel tracking — the same public view the SMS link opens,
/// reachable in-app. Paste the tracking link or the token; no account needed.
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
  String? _resolvedToken;
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
      _resolvedToken = data == null ? null : token;
      _error = data == null ? 'Not found — check the link or code from the SMS.' : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    if (!store.linked) {
      // In-app tracking is behind an account (SMS recipients keep using the
      // public link). Sign up first, then paste the code.
      return Scaffold(
        appBar: AppBar(title: const Text('Track a parcel', style: TextStyle(fontWeight: FontWeight.w900))),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.lock_outline, size: 44, color: AppColors.muted),
              const SizedBox(height: 16),
              const Text('Sign up to track', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900), textAlign: TextAlign.center),
              const SizedBox(height: 8),
              const Text('Create your free account to follow your parcel — status, rider location and the depot branch it lands at.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted, height: 1.45)),
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
    return Scaffold(
      appBar: AppBar(title: const Text('Track a parcel', style: TextStyle(fontWeight: FontWeight.w900))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        children: [
          TextField(
            controller: _input,
            textInputAction: TextInputAction.go,
            onSubmitted: (_) => _lookup(),
            decoration: InputDecoration(
              labelText: 'Tracking link or code',
              hintText: 'Paste the link from the SMS',
              prefixIcon: const Icon(Icons.link),
              suffixIcon: IconButton(icon: const Icon(Icons.search), onPressed: _loading ? null : _lookup),
            ),
          ),
          const SizedBox(height: 14),
          if (_loading) const Center(child: Padding(padding: EdgeInsets.all(22), child: CircularProgressIndicator())),
          if (_error != null)
            Text(_error!, style: const TextStyle(color: AppColors.muted, fontSize: 13)),
          if (_data != null) ...[
            _statusHeader(_data!),
            const SizedBox(height: 14),
            FilledButton.tonalIcon(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => ChatScreen.token(_resolvedToken!),
              )),
              icon: const Icon(Icons.chat_bubble_outline),
              label: const Text('Chat about this parcel'),
            ),
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
                    Expanded(child: Text('${e['status']}'.replaceAll('_', ' '), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13))),
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

  Widget _statusHeader(Map<String, dynamic> d) {
    final dropoff = d['dropoff'] as Map<String, dynamic>?;
    final branch = '${dropoff?['branch'] ?? ''}'.trim();
    final dropoffPoint = branch.isNotEmpty ? '$branch (${dropoff?['courier'] ?? ''})' : '${d['dest_city'] ?? 'depot'}';
    final dropoffIsBranch = branch.isNotEmpty;
    return Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(color: AppColors.forest, borderRadius: BorderRadius.circular(24)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${d['status'] ?? ''}'.replaceAll('_', ' ').toUpperCase(),
              style: const TextStyle(color: AppColors.amber, fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 1)),
          const SizedBox(height: 12),
          Text('${d['pickup_city'] ?? 'Pickup'} → $dropoffPoint',
              style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
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
        ]),
      );
  }

  Widget _riderStrip(Map<String, dynamic> d) {
    final rider = d['rider'] as Map<String, dynamic>?;
    final loc = d['location'] as Map<String, dynamic>?;
    if (rider == null && loc == null) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          const Icon(Icons.two_wheeler, color: AppColors.forest),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (rider != null)
              Text('${rider['name']} • ${rider['vehicle']}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
            if (loc != null)
              Text('Last fix ${loc['seen_at'] ?? ''}', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
            if (rider == null)
              const Text('Rider on the way', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
          ])),
          if (loc != null && loc['lat'] != null)
            IconButton(
              tooltip: 'Open in Maps',
              icon: const Icon(Icons.map_outlined, color: AppColors.forest),
              onPressed: () => launchUrl(Uri.parse('https://maps.google.com/?q=${loc['lat']},${loc['lng']}')),
            ),
        ]),
      ),
    );
  }
}
