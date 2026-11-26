import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/dropoff_api.dart';
import 'app_spinner.dart';
import 'app_theme.dart';
import 'app_toast.dart';

/// Admin code generator for the team (owner 2026-11-26): "1 free delivery"
/// codes the owner can hand to staff. Every code has an on/off switch — one
/// tap retires it without deleting its redemption history.
class AdminTeamCodesCard extends StatefulWidget {
  const AdminTeamCodesCard({super.key});

  @override
  State<AdminTeamCodesCard> createState() => _AdminTeamCodesCardState();
}

class _AdminTeamCodesCardState extends State<AdminTeamCodesCard> {
  List<Map<String, dynamic>> _codes = const [];
  bool _loading = true;
  bool _generating = false;
  int _uses = 1;
  int _pct = 100;
  String _audience = 'sender';
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final data = await DropOffApi.adminPromos();
      if (!mounted) return;
      if (data == null) {
        setState(() { _loading = false; _error = 'Could not load codes.'; });
        return;
      }
      final rows = (data['promos'] as List?)?.whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .where((m) => ['team', 'sender'].contains('${m['kind'] ?? ''}')
              || '${m['code'] ?? ''}'.startsWith('TEAM-')
              || '${m['code'] ?? ''}'.startsWith('SEND-'))
          .toList() ?? const <Map<String, dynamic>>[];
      setState(() { _codes = rows; _loading = false; });
    } catch (_) {
      if (mounted) setState(() { _loading = false; _error = 'Could not load codes.'; });
    }
  }

  Future<void> _generate() async {
    if (_generating) return;
    setState(() => _generating = true);
    final res = await DropOffApi.adminGeneratePromo(
      audience: _audience, discountPct: _pct, uses: _uses,
    );
    if (!mounted) return;
    setState(() => _generating = false);
    final code = '${res.body['code'] ?? ''}';
    if (!res.ok) {
      AppToast.show(context, 'Could not generate a code. Try again.');
      return;
    }
    await Clipboard.setData(ClipboardData(text: code));
    _load();
    if (mounted) {
      AppToast.show(context,
          '$code copied — ${_pct == 100 ? 'free delivery' : '$_pct% off'} for $_audience, ON.');
    }
  }

  Future<void> _toggle(Map<String, dynamic> code, bool on) async {
    final res = await DropOffApi.adminTogglePromo('${code['code'] ?? ''}', on);
    if (!mounted) return;
    if (res.ok) {
      setState(() => _codes = _codes.map((c) => c == code
          ? {...c, 'active': on ? 1 : 0} : c).toList());
      AppToast.show(context, on ? 'Code switched ON.' : 'Code switched OFF — nobody can redeem it now.');
    } else {
      AppToast.show(context, 'Could not change that code.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.line),
          boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 10, offset: Offset(0, 3))]),
      child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 40, height: 40,
              decoration: BoxDecoration(color: AppColors.amber.withValues(alpha: 0.22), borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.card_giftcard_outlined, color: AppColors.forest, size: 21)),
          const SizedBox(width: 10),
          const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Promo codes', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
            Text('Free delivery or a percentage cut for senders, or a team code. '
                'Each code has an on/off switch.',
                style: TextStyle(fontSize: 11.5, color: AppColors.muted)),
          ])),
          IconButton(tooltip: 'Refresh', onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh, size: 18, color: AppColors.forest)),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          const Expanded(child: Text('Who gets it', style: TextStyle(fontSize: 12.5))),
          for (final (value, label) in [('sender', 'Senders'), ('team', 'Team')])
            Padding(padding: const EdgeInsets.only(left: 6), child: ChoiceChip(
              label: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
              selected: _audience == value,
              onSelected: (_) => setState(() => _audience = value),
            )),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          const Expanded(child: Text('Discount', style: TextStyle(fontSize: 12.5))),
          for (final pct in [100, 50, 20])
            Padding(padding: const EdgeInsets.only(left: 6), child: ChoiceChip(
              label: Text(pct == 100 ? 'FREE' : '-$pct%', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
              selected: _pct == pct,
              onSelected: (_) => setState(() => _pct = pct),
            )),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          const Expanded(child: Text('Uses', style: TextStyle(fontSize: 12.5))),
          for (final n in [1, 3, 10])
            Padding(padding: const EdgeInsets.only(left: 6), child: ChoiceChip(
              label: Text('$n', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
              selected: _uses == n,
              onSelected: (_) => setState(() => _uses = n),
            )),
        ]),
        const SizedBox(height: 10),
        SizedBox(width: double.infinity, child: FilledButton.icon(
          onPressed: _generating ? null : _generate,
          icon: _generating
              ? const AppLogoSpinner(size: 16, color: Colors.white)
              : const Icon(Icons.qr_code_rounded, size: 18),
          label: Text(_generating ? 'Generating…' : 'Generate ${_pct == 100 ? 'free' : '$_pct% off'} code for $_audience'),
        )),
        const SizedBox(height: 14),
        if (_error != null)
          Text(_error!, style: const TextStyle(fontSize: 12.5, color: AppColors.danger))
        else if (_loading)
          const Padding(padding: EdgeInsets.all(12), child: Center(child: AppLogoSpinner(size: 22)))
        else if (_codes.isEmpty)
          const Text('No team codes yet. Generate one above.', style: TextStyle(fontSize: 12.5, color: AppColors.muted))
        else
          for (final c in _codes.take(12))
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: AppColors.canvas, borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.line)),
              child: Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${c['code'] ?? ''}', style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w900, letterSpacing: 0.6)),
                  Text('${c['uses_left'] ?? 0} left · ${c['discount_pct'] ?? 0}% off · ${c['note'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, color: AppColors.muted)),
                ])),
                IconButton(tooltip: 'Copy code', icon: const Icon(Icons.copy_all_outlined, size: 18),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: '${c['code'] ?? ''}'));
                    // ignore: use_build_context_synchronously
                    if (mounted) AppToast.show(context, 'Code copied.');
                  }),
                Switch(
                  value: (c['active'] as num?) == 1 || c['active'] == true,
                  onChanged: (v) => _toggle(c, v),
                  activeThumbColor: AppColors.forest,
                ),
              ]),
            ),
      ])),
    );
  }
}
