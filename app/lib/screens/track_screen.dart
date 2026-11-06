import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/dropoff_api.dart';
import '../main.dart';
import '../ui/app_theme.dart';
import '../widgets/common.dart';
import 'chat_screen.dart';

/// Recipient parcel tracking — the same view the SMS link opens, reachable
/// in-app. Paste the tracking link or the token. The SERVER decides who sees
/// parcel data: the sender/recipient phone (signed-in or phone-verified) or
/// staff keys. Everyone else gets a phone-verification gate — the link alone
/// proves nothing.
class TrackScreen extends StatefulWidget {
  const TrackScreen({super.key, this.initialToken});

  /// Token or full /track/ URL (e.g. pasted from the recipient SMS).
  final String? initialToken;

  @override
  State<TrackScreen> createState() => _TrackScreenState();
}

class _TrackScreenState extends State<TrackScreen> {
  final _input = TextEditingController();
  final _phoneCtrl = TextEditingController();
  bool _phonePrefilled = false;
  Map<String, dynamic>? _data;
  String? _resolvedToken;
  bool _loading = false;
  String? _error;
  bool _verifying = false;
  String? _verifyError;

  @override
  void initState() {
    super.initState();
    if (widget.initialToken != null && widget.initialToken!.trim().isNotEmpty) {
      _input.text = widget.initialToken!;
      _lookup();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_phonePrefilled) return;
    final store = AppScope.of(context);
    if (store.linkedPhone != null) _phoneCtrl.text = store.linkedPhone!;
    _phonePrefilled = true;
  }

  @override
  void dispose() {
    _input.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _lookup() async {
    final token = _input.text.trim();
    if (token.isEmpty) return;
    setState(() { _loading = true; _error = null; _verifyError = null; });
    final data = await DropOffApi.trackByToken(token);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _data = data;
      _resolvedToken = data == null ? null : token;
      _error = data == null ? 'Not found — check the link or code from the SMS.' : null;
    });
  }

  Future<void> _verify() async {
    final token = _resolvedToken;
    final phone = _phoneCtrl.text.trim();
    if (token == null || phone.isEmpty) return;
    setState(() { _verifying = true; _verifyError = null; });
    final res = await DropOffApi.verifyTrack(token, phone);
    if (!mounted) return;
    if (res == null) {
      setState(() { _verifying = false; _verifyError = "That number isn't on this parcel — only the sender's or recipient's number can open it."; });
      return;
    }
    setState(() { _verifying = false; });
    await _lookup();
  }

  @override
  Widget build(BuildContext context) {
    final gated = _data?['requires_verification'] == true;
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
          if (gated) _verifyCard(),
          if (_data != null && !gated) ...[
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

  /// Phone-verification gate — shown when the server says the viewer isn't
  /// proven yet (requires_verification). Only the sender's or recipient's
  /// number unlocks tracking; no account needed, just ownership of the number.
  Widget _verifyCard() {
    final hint = '${_data?['hint_phone'] ?? ''}';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [
            Icon(Icons.phonelink_lock, color: AppColors.forest),
            SizedBox(width: 10),
            Expanded(child: Text('Who is this parcel for?', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16))),
          ]),
          const SizedBox(height: 8),
          Text(
            hint.isEmpty
                ? 'Tracking opens only from the phone this parcel was addressed to (or the sender\u2019s). Enter that number to continue.'
                : 'Tracking opens only from the phone this parcel was addressed to (or the sender\u2019s). Try the number ending in $hint.',
            style: const TextStyle(color: AppColors.muted, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _phoneCtrl,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _verify(),
            decoration: const InputDecoration(
              labelText: 'Mobile number',
              hintText: 'e.g. 0977 123 456',
              prefixIcon: Icon(Icons.phone_android),
            ),
          ),
          if (_verifyError != null) ...[
            const SizedBox(height: 10),
            Text(_verifyError!, style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12.5, fontWeight: FontWeight.w700)),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _verifying ? null : _verify,
              icon: _verifying ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.verified_user),
              label: Text(_verifying ? 'Checking…' : 'Verify & track'),
            ),
          ),
        ]),
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
          if (d['verified_for'] != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                const Icon(Icons.verified_user, size: 14, color: AppColors.amber),
                const SizedBox(width: 6),
                Text('Verified ${d['verified_for']} — this is their parcel',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12)),
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
