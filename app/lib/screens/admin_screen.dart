import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/dropoff_api.dart';
import '../data/analytics_service.dart';
import '../ui/app_theme.dart';

/// Owner / admin console inside the app: live business stats, security
/// alerts, the fraud queue, depot branches, and SMS broadcasts. The screen
/// re-checks GET /me on open — a seller who deep-links here gets a lock door.
class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  Map<String, dynamic>? _stats;
  List<Map<String, dynamic>> _alerts = const [];
  List<Map<String, dynamic>> _flags = const [];
  bool _loading = true;
  bool _authorized = false;
  bool _superadmin = false;

  final _smsPhone = TextEditingController();
  final _smsBody = TextEditingController();
  String _audience = 'accounts';
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _smsPhone.dispose();
    _smsBody.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final me = await DropOffApi.me();
    final role = '${me?['role'] ?? ''}';
    if (role != 'admin' && role != 'ops') {
      if (mounted) setState(() { _authorized = false; _loading = false; });
      return;
    }
    final stats = await DropOffApi.adminStats();
    final alerts = await DropOffApi.securityAlerts();
    final flags = await DropOffApi.fraudFlags();
    if (!mounted) return;
    setState(() {
      _authorized = true;
      _superadmin = me?['superadmin'] == true;
      _stats = stats;
      _alerts = ((alerts?['alerts'] as List?) ?? const []).cast<Map<String, dynamic>>();
      _flags = ((flags?['flags'] as List?) ?? const []).cast<Map<String, dynamic>>();
      _loading = false;
    });
  }

  Future<void> _sendSms({required bool broadcast}) async {
    final body = _smsBody.text.trim();
    if (body.isEmpty) return;
    setState(() => _sending = true);
    final res = broadcast
        ? await DropOffApi.adminBroadcast(audience: _audience, message: body)
        : await DropOffApi.adminSms(phone: _smsPhone.text.trim(), message: body);
    if (!mounted) return;
    setState(() => _sending = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res.ok
        ? (broadcast ? 'Broadcast queued — sends run in the background.' : 'SMS sent.')
        : 'Send failed: ${res.error}')));
    if (res.ok) {
      _smsBody.clear();
      AnalyticsService.instance.track(
        feature: 'sms_broadcast', action: broadcast ? 'broadcast' : 'send', context: 'admin_sms',
        meta: {'audience': _audience},
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Admin console', style: TextStyle(fontWeight: FontWeight.w900))),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (!_authorized) {
      return Scaffold(
        appBar: AppBar(title: const Text('Admin console', style: TextStyle(fontWeight: FontWeight.w900))),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.lock_outline, size: 44, color: AppColors.muted),
              const SizedBox(height: 16),
              const Text('Staff access only', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900), textAlign: TextAlign.center),
              const SizedBox(height: 8),
              const Text('The admin console is reserved for DropOff admins and ops. Sign in with a staff account to continue.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted, height: 1.45)),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.arrow_back),
                label: const Text('Back'),
              ),
            ]),
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin console', style: TextStyle(fontWeight: FontWeight.w900)),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: () => setState(() { _loading = true; _load(); }),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.forest.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.forest.withValues(alpha: 0.25)),
              ),
              child: const Row(children: [
                Icon(Icons.admin_panel_settings_outlined, color: AppColors.forest),
                SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Operations overview', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: AppColors.forest)),
                  SizedBox(height: 2),
                  Text('Live stats, security, fraud, depot branches and messaging.', style: TextStyle(color: AppColors.muted, fontSize: 12, height: 1.35)),
                ])),
              ]),
            ),
            const SizedBox(height: 16),
            _statsCard(),
            const SizedBox(height: 18),
            const _AnalyticsKpiCard(),
            const SizedBox(height: 18),
            const _DemandForecastCard(),
            const SizedBox(height: 18),
            _alertsCard(),
            const SizedBox(height: 18),
            _fraudCard(),
            const SizedBox(height: 18),
            const _SupportInboxCard(),
            if (_superadmin) ...[
              const SizedBox(height: 18),
              const _UsersCard(),
              const SizedBox(height: 18),
              const _PackCodesCard(),
            ],
            const SizedBox(height: 18),
            const _RiderVerificationAdminCard(),
            const SizedBox(height: 18),
            const _BranchManagerCard(),
            const SizedBox(height: 18),
            _smsCard(),
          ],
        ),
      ),
    );
  }

  Widget _statsCard() {
    final raw = _stats ?? const <String, dynamic>{};
    final entries = raw.entries
        .where((e) => e.value is num && e.key != 'subs_by_tier')
        .toList();
    final tiers = ((raw['subs_by_tier'] as List?) ?? const []).cast<Map<String, dynamic>>();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [
            Icon(Icons.insights_outlined, size: 18, color: AppColors.forest),
            SizedBox(width: 8),
            Text('Last 30 days', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
          ]),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final e in entries)
              Container(
                constraints: const BoxConstraints(minWidth: 104),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(color: AppColors.line.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(12)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(e.key.toString().replaceAll('_', ' '), style: const TextStyle(fontSize: 10, color: AppColors.muted, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(_fmtNum(e.value), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: AppColors.forest)),
                ]),
              ),
          ]),
          if (tiers.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text('Active plans', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: AppColors.muted)),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 6, children: [
              for (final t in tiers)
                Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text('${t['tier']}: ${t['n']}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                ),
            ]),
          ],
        ]),
      ),
    );
  }

  String _fmtNum(Object? v) {
    if (v is! num) return '$v';
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v.toStringAsFixed(2);
  }

  Widget _alertsCard() => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.gpp_maybe_outlined, color: AppColors.forest),
              const SizedBox(width: 8),
              const Expanded(child: Text('Security alerts', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15))),
              Text('${_alerts.length}', style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.forest)),
            ]),
            const SizedBox(height: 8),
            if (_alerts.isEmpty)
              const Text('No alerts. Quiet is good.', style: TextStyle(color: AppColors.muted, fontSize: 12.5)),
            for (final a in _alerts.take(10))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(a['severity'] == 'high' || a['severity'] == 'critical' ? Icons.error_outline : Icons.info_outline,
                      size: 17, color: a['severity'] == 'high' || a['severity'] == 'critical' ? const Color(0xFFB3261E) : AppColors.muted),
                  const SizedBox(width: 8),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${a['type']} · ${a['phone']}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
                    Text('${a['detail']}', style: const TextStyle(color: AppColors.muted, fontSize: 11.5, height: 1.3)),
                  ])),
                  TextButton(
                    onPressed: () async { await DropOffApi.ackAlert((a['id'] as num).toInt()); _load(); },
                    child: const Text('Ack'),
                  ),
                ]),
              ),
          ]),
        ),
      );

  Widget _fraudCard() => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.flag_outlined, color: AppColors.forest),
              const SizedBox(width: 8),
              const Expanded(child: Text('Fraud queue (open)', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15))),
              Text('${_flags.length}', style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.forest)),
            ]),
            const SizedBox(height: 8),
            if (_flags.isEmpty)
              const Text('Nothing flagged.', style: TextStyle(color: AppColors.muted, fontSize: 12.5)),
            for (final f in _flags.take(10))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${f['job_ref']} · score ${f['score']}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
                    Text('${f['reasons']}', style: const TextStyle(color: AppColors.muted, fontSize: 11.5)),
                  ])),
                  TextButton(
                    onPressed: () async {
                      await DropOffApi.reviewFraud((f['id'] as num).toInt(), status: 'cleared');
                      AnalyticsService.instance.track(
                        feature: 'fraud', action: 'clear', context: 'admin_fraud_queue',
                        meta: {'fraud_id': f['id']},
                      );
                      _load();
                    },
                    child: const Text('Clear'),
                  ),
                  TextButton(
                    onPressed: () async {
                      await DropOffApi.reviewFraud((f['id'] as num).toInt(), status: 'confirmed');
                      AnalyticsService.instance.track(
                        feature: 'fraud', action: 'confirm', context: 'admin_fraud_queue',
                        meta: {'fraud_id': f['id']},
                      );
                      _load();
                    },
                    child: const Text('Confirm'),
                  ),
                ]),
              ),
          ]),
        ),
      );

  Widget _smsCard() => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('SMS communication', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
            const SizedBox(height: 10),
            TextField(
              controller: _smsPhone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Single number (09…)', prefixIcon: Icon(Icons.phone_outlined)),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: _audience,
              decoration: const InputDecoration(labelText: 'Or broadcast audience', prefixIcon: Icon(Icons.groups_outlined)),
              items: const [
                DropdownMenuItem(value: 'accounts', child: Text('Registered accounts')),
                DropdownMenuItem(value: 'sellers', child: Text('All sellers (booked before)')),
                DropdownMenuItem(value: 'subscribers', child: Text('Active plan subscribers')),
                DropdownMenuItem(value: 'all', child: Text('Everyone')),
              ],
              onChanged: (v) => setState(() => _audience = v ?? 'accounts'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _smsBody,
              maxLines: 3,
              maxLength: 600,
              decoration: const InputDecoration(labelText: 'Message', hintText: 'Marketing or operational notice…', counterText: ''),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: FilledButton.tonal(
                onPressed: _sending || _smsBody.text.trim().isEmpty ? null : () => _sendSms(broadcast: false),
                child: const Text('Send to one'),
              )),
              const SizedBox(width: 10),
              Expanded(child: FilledButton(
                onPressed: _sending || _smsBody.text.trim().isEmpty ? null : () => _sendSms(broadcast: true),
                child: Text(_sending ? 'Sending…' : 'Broadcast'),
              )),
            ]),
          ]),
        ),
      );
}

/// Support inbox: every support ticket (kind='support' chat thread) with the
/// seller's last message and unread count. Tap a ticket to read the thread and
/// reply (POST /chat/support/:id/reply — the same endpoint sellers reply with).
class _SupportInboxCard extends StatefulWidget {
  const _SupportInboxCard();

  @override
  State<_SupportInboxCard> createState() => _SupportInboxCardState();
}

class _SupportInboxCardState extends State<_SupportInboxCard> {
  List<Map<String, dynamic>> _threads = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await DropOffApi.adminSupportThreads();
    if (!mounted) return;
    setState(() {
      _threads = ((data?['threads'] as List?) ?? const []).cast<Map<String, dynamic>>();
      _loading = false;
    });
  }

  Future<void> _open(Map<String, dynamic> thread) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (_) => _SupportTicketSheet(threadId: (thread['id'] as num).toInt(), phone: '${thread['phone'] ?? ''}'),
    );
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.support_agent, color: AppColors.forest),
            const SizedBox(width: 8),
            const Expanded(child: Text('Support inbox', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15))),
            IconButton(tooltip: 'Refresh', onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh, size: 18)),
          ]),
          const SizedBox(height: 6),
          if (_loading)
            const Padding(padding: EdgeInsets.all(14), child: Center(child: CircularProgressIndicator()))
          else if (_threads.isEmpty)
            const Text('No tickets. Everyone is happy.', style: TextStyle(color: AppColors.muted, fontSize: 12.5))
          else
            ..._threads.take(12).map((t) {
              final unread = (t['unread'] as num?)?.toInt() ?? 0;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => _open(t),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                    child: Row(children: [
                      const Icon(Icons.chat_bubble_outline, size: 16, color: AppColors.forest),
                      const SizedBox(width: 10),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Ticket #${t['id']} · ${t['phone'] ?? ''}',
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                        if ('${t['last_message'] ?? ''}'.isNotEmpty)
                          Text('${t['last_message']}', maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: AppColors.muted, fontSize: 11.5)),
                      ])),
                      if (unread > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(color: AppColors.forest, borderRadius: BorderRadius.circular(10)),
                          child: Text('$unread', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 11)),
                        ),
                    ]),
                  ),
                ),
              );
            }),
        ]),
      ),
    );
  }
}

/// One open support ticket: full message history + a reply box.
class _SupportTicketSheet extends StatefulWidget {
  const _SupportTicketSheet({required this.threadId, required this.phone});

  final int threadId;
  final String phone;

  @override
  State<_SupportTicketSheet> createState() => _SupportTicketSheetState();
}

class _SupportTicketSheetState extends State<_SupportTicketSheet> {
  List<Map<String, dynamic>> _messages = const [];
  bool _loading = true;
  bool _sending = false;
  bool _drafting = false;
  final _reply = TextEditingController();
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _reply.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final data = await DropOffApi.adminSupportThread(widget.threadId);
    if (!mounted) return;
    setState(() {
      _messages = ((data?['messages'] as List?) ?? const []).cast<Map<String, dynamic>>();
      _loading = false;
    });
    await Future<void>.delayed(const Duration(milliseconds: 30));
    if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
  }

  Future<void> _send() async {
    final body = _reply.text.trim();
    if (body.isEmpty || _sending) return;
    setState(() => _sending = true);
    _reply.clear();
    final res = await DropOffApi.supportReply(widget.threadId, body);
    if (!mounted) return;
    setState(() => _sending = false);
    if (!res.ok) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Reply failed: ${res.error}')));
      return;
    }
    await _load();
  }

  /// Workers AI draft (never auto-sends) — the reply box fills in, the human presses send.
  Future<void> _aiDraft() async {
    if (_drafting) return;
    setState(() => _drafting = true);
    final res = await DropOffApi.supportAiDraft(widget.threadId);
    if (!mounted) return;
    setState(() => _drafting = false);
    final draft = '${res.body['draft'] ?? ''}'.trim();
    if (!res.ok || draft.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(res.ok ? 'AI returned an empty draft — write the reply yourself.' : 'AI draft unavailable: ${res.error ?? 'try again'}'),
      ));
      return;
    }
    setState(() { _reply.text = draft; });
    _reply.selection = TextSelection.collapsed(offset: draft.length);
  }

  void _copyPhone() {
    Clipboard.setData(ClipboardData(text: widget.phone));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Copied ${widget.phone}')));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.8,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(children: [
              const Icon(Icons.support_agent, color: AppColors.forest),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Ticket #${widget.threadId} · ${widget.phone}',
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
              ),
              IconButton(tooltip: 'Reload', onPressed: _load, icon: const Icon(Icons.refresh, size: 18)),
            ]),
          ),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    itemCount: _messages.length,
                    itemBuilder: (context, i) {
                      final m = _messages[i];
                      final fromOps = '${m['sender_role'] ?? ''}' == 'ops';
                      final time = '${m['created_at'] ?? ''}'.split(' ').last;
                      return Align(
                        alignment: fromOps ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
                          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
                          decoration: BoxDecoration(
                            color: fromOps ? AppColors.forest : AppColors.line.withValues(alpha: 0.22),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('${m['sender_role'] ?? 'user'} · $time',
                                style: TextStyle(color: fromOps ? Colors.white70 : AppColors.muted, fontSize: 10.5, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 3),
                            Text('${m['body'] ?? ''}',
                                style: TextStyle(color: fromOps ? Colors.white : Colors.black87, fontSize: 13, height: 1.3)),
                          ]),
                        ),
                      );
                    },
                  ),
          ),
          SafeArea(
            top: false,
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 2, 14, 0),
                child: Row(children: [
                  TextButton.icon(
                    onPressed: _drafting ? null : _aiDraft,
                    icon: _drafting
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.auto_awesome, size: 16),
                    label: const Text('AI draft reply'),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: _copyPhone,
                    icon: const Icon(Icons.copy, size: 15),
                    label: Text(widget.phone, style: const TextStyle(fontSize: 11)),
                  ),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 2, 14, 12),
                child: Row(children: [
                Expanded(
                  child: TextField(
                    controller: _reply,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    maxLength: 500,
                    decoration: const InputDecoration(hintText: 'Reply as DropOff…', counterText: ''),
                  ),
                ),
                const SizedBox(width: 10),
                IconButton.filled(
                  onPressed: _sending ? null : _send,
                  icon: _sending
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.send_rounded),
                  ),
                ]),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Accounts & roles (superadmin only): review every account and mentor who is
/// admin. The owner's own row can never be demoted (server refuses).
class _UsersCard extends StatefulWidget {
  const _UsersCard();

  @override
  State<_UsersCard> createState() => _UsersCardState();
}

class _UsersCardState extends State<_UsersCard> {
  List<Map<String, dynamic>> _users = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await DropOffApi.adminUsers();
    if (!mounted) return;
    setState(() {
      _users = ((data?['users'] as List?) ?? const []).cast<Map<String, dynamic>>();
      _loading = false;
    });
  }

  Future<void> _setRole(Map<String, dynamic> user, String role) async {
    final email = '${user['email'] ?? ''}';
    if (email.isEmpty || role == '${user['role'] ?? ''}') return;
    final res = await DropOffApi.adminSetUserRole(email, role);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res.ok
        ? '$email is now $role.'
        : 'Failed: ${res.error == 'owner_cannot_be_demoted' ? 'the owner account cannot be demoted' : res.error}')));
    if (res.ok) {
      _load();
      AnalyticsService.instance.track(
        feature: 'admin_users', action: 'set_role', context: 'admin_users',
        meta: {'email': email, 'role': role},
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.manage_accounts_outlined, color: AppColors.forest),
            const SizedBox(width: 8),
            const Expanded(child: Text('Accounts & roles', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15))),
            IconButton(tooltip: 'Refresh', onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh, size: 18)),
          ]),
          const SizedBox(height: 4),
          const Text('As the owner you decide who is admin (e.g. your spouse to run support). Admins cannot invite more admins.',
              style: TextStyle(color: AppColors.muted, fontSize: 11.5, height: 1.35)),
          const SizedBox(height: 8),
          if (_loading)
            const Padding(padding: EdgeInsets.all(14), child: Center(child: CircularProgressIndicator()))
          else if (_users.isEmpty)
            const Text('No accounts found.', style: TextStyle(color: AppColors.muted, fontSize: 12.5))
          else
            ..._users.take(60).map((u) {
              final role = '${u['role'] ?? 'customer'}';
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(children: [
                  const Icon(Icons.person_outline, size: 16, color: AppColors.forest),
                  const SizedBox(width: 10),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${u['full_name'] ?? u['email'] ?? u['phone'] ?? 'Account'}',
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                    Text('${u['email'] ?? ''} · ${u['phone'] ?? ''}',
                        style: const TextStyle(color: AppColors.muted, fontSize: 11)),
                  ])),
                  PopupMenuButton<String>(
                    tooltip: 'Change role',
                    initialValue: role,
                    onSelected: (r) => _setRole(u, r),
                    itemBuilder: (context) => const [
                      PopupMenuItem(value: 'customer', child: Text('customer')),
                      PopupMenuItem(value: 'admin', child: Text('admin')),
                      PopupMenuItem(value: 'partner', child: Text('partner')),
                    ],
                    child: Chip(
                      visualDensity: VisualDensity.compact,
                      label: Text(role, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ]),
              );
            }),
        ]),
      ),
    );
  }
}

/// Depot-branch manager: pick a courier, add a Lusaka branch (name, area,
/// coordinates, phone) or retire an existing one.
class _BranchManagerCard extends StatefulWidget {
  const _BranchManagerCard();

  @override
  State<_BranchManagerCard> createState() => _BranchManagerCardState();
}

class _BranchManagerCardState extends State<_BranchManagerCard> {
  List<Map<String, dynamic>> _couriers = const [];
  List<Map<String, dynamic>> _branches = const [];
  int? _courierId;
  final _name = TextEditingController();
  final _address = TextEditingController();
  final _lat = TextEditingController();
  final _lng = TextEditingController();
  final _phone = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadCouriers();
  }

  @override
  void dispose() {
    _name.dispose(); _address.dispose(); _lat.dispose(); _lng.dispose(); _phone.dispose();
    super.dispose();
  }

  Future<void> _loadCouriers() async {
    final data = await DropOffApi.couriers();
    if (!mounted) return;
    setState(() {
      _couriers = data;
      _courierId ??= (_couriers.isNotEmpty ? (_couriers.first['id'] as num).toInt() : null);
    });
    _loadBranches();
  }

  Future<void> _loadBranches() async {
    if (_courierId == null) return;
    final data = await DropOffApi.get('/admin/branches?courier_id=$_courierId');
    if (!mounted) return;
    setState(() => _branches = ((data?['branches'] as List?) ?? const []).cast<Map<String, dynamic>>());
  }

  Future<void> _add() async {
    if (_name.text.trim().isEmpty || _courierId == null) return;
    setState(() => _saving = true);
    final res = await DropOffApi.post('/admin/branches', {
      'courier_id': _courierId,
      'name': _name.text.trim(),
      'city': 'Lusaka',
      'address': _address.text.trim(),
      'lat': _lat.text.trim(),
      'lng': _lng.text.trim(),
      'phone': _phone.text.trim(),
    });
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res.ok ? 'Branch added.' : 'Failed: ${res.error}')));
    if (res.ok) {
      _name.clear(); _address.clear(); _lat.clear(); _lng.clear(); _phone.clear(); _loadBranches();
      AnalyticsService.instance.track(
        feature: 'branches', action: 'add', context: 'admin_branch_manager',
        meta: {'courier_id': _courierId},
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Depot branches', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
          const SizedBox(height: 10),
          DropdownButtonFormField<int>(
            initialValue: _courierId,
            decoration: const InputDecoration(labelText: 'Courier', prefixIcon: Icon(Icons.local_shipping_outlined)),
            items: [for (final c in _couriers) DropdownMenuItem(value: (c['id'] as num).toInt(), child: Text('${c['name']} (${c['city']})', overflow: TextOverflow.ellipsis))],
            onChanged: (v) { setState(() => _courierId = v); _loadBranches(); },
          ),
          const SizedBox(height: 8),
          if (_branches.isNotEmpty)
            ..._branches.map((b) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                const Icon(Icons.location_on_outlined, size: 15, color: AppColors.forest),
                const SizedBox(width: 6),
                Expanded(child: Text('${b['name']} — ${b['address'] ?? b['city']}', style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis)),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18, color: AppColors.muted),
                  onPressed: () async { await DropOffApi.delete('/admin/branches/${b['id']}', body: {}); _loadBranches(); },
                ),
              ]),
            )),
          const Divider(height: 22),
          TextField(controller: _name, decoration: const InputDecoration(labelText: 'Branch name', hintText: 'e.g. Longacres branch')),
          const SizedBox(height: 8),
          TextField(controller: _address, decoration: const InputDecoration(labelText: 'Address / area', hintText: 'e.g. Longacres, Airport Rd strip')),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: TextField(controller: _lat, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Lat (optional)'))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: _lng, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Lng (optional)'))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone'))),
          ]),
          const SizedBox(height: 10),
          FilledButton(
            onPressed: _saving ? null : _add,
            child: Text(_saving ? 'Adding…' : 'Add branch'),
          ),
        ]),
      ),
    );
  }
}

/// Mint bulk plan codes for offline/agent sale. Codes activate a plan with no
/// payment prompt when a seller redeems one on their own number.
class _PackCodesCard extends StatefulWidget {
  const _PackCodesCard();

  @override
  State<_PackCodesCard> createState() => _PackCodesCardState();
}

class _PackCodesCardState extends State<_PackCodesCard> {
  String _tier = 'weekly';
  int _count = 5;
  final _note = TextEditingController();
  List<String> _codes = const [];
  bool _busy = false;

  static const Map<String, String> _labels = {
    'weekly': 'Weekly Sprint',
    'silver': 'Silver',
    'gold': 'Gold',
    'platinum': 'Platinum',
  };

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    setState(() => _busy = true);
    final res = await DropOffApi.generatePackCodes(tier: _tier, count: _count, note: _note.text.trim());
    if (!mounted) return;
    setState(() => _busy = false);
    if (!res.ok) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not generate codes (${res.error}).')));
      return;
    }
    final codes = ((res.body['codes'] as List?) ?? const []).map((c) => '$c').toList();
    setState(() => _codes = codes);
    AnalyticsService.instance.track(
      feature: 'pack_codes', action: 'generate', context: 'admin_pack_codes',
      meta: {'tier': _tier, 'count': codes.length},
    );
    if (codes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No codes generated � try again.')));
    }
  }

  void _copyAll() {
    if (_codes.isEmpty) return;
    Clipboard.setData(ClipboardData(text: _codes.join('\n')));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${_codes.length} code${_codes.length == 1 ? '' : 's'} copied.')));
  }

  @override
  Widget build(BuildContext context) {
    if (!DropOffApi.enabled) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.card_membership_outlined, color: AppColors.forest),
            const SizedBox(width: 10),
            const Expanded(child: Text('Plan codes (offline sales)', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15))),
            if (_codes.isNotEmpty)
              TextButton(onPressed: _copyAll, child: const Text('Copy all')),
          ]),
          const SizedBox(height: 4),
          const Text('Sell plans at the counter or to agents. The seller redeems the code in the app � no payment prompt, the plan goes live instantly.', style: TextStyle(color: AppColors.muted, fontSize: 11.5, height: 1.4)),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _tier,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Tier'),
                items: _labels.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value, maxLines: 1, overflow: TextOverflow.ellipsis))).toList(),
                onChanged: (v) { if (v != null) setState(() => _tier = v); },
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 96,
              child: DropdownButtonFormField<int>(
                initialValue: _count,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'How many'),
                items: [1, 2, 5, 10, 20, 50].map((n) => DropdownMenuItem(value: n, child: Text('$n'))).toList(),
                onChanged: (v) { if (v != null) setState(() => _count = v); },
              ),
            ),
          ]),
          const SizedBox(height: 10),
          TextField(controller: _note, decoration: const InputDecoration(labelText: 'Note (optional)', hintText: 'e.g. Market day batch, agent Chanda')),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _busy ? null : _generate,
            icon: const Icon(Icons.qr_code_2, size: 18),
            label: Text(_busy ? 'Generating�' : 'Generate $_count ${_labels[_tier]} code${_count == 1 ? '' : 's'}'),
          ),
          if (_codes.isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppColors.line.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (final code in _codes)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(code, style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w800, letterSpacing: 1.1, fontSize: 13)),
                  ),
              ]),
            ),
          ],
        ]),
      ),
    );
  }
}

/// Owner/admin verification queue: driver ID, plate and photo checks, plus the
/// daily/monthly target line for every driver. Approval is admin-only server
/// side; ops can view but not decide.
class _RiderVerificationAdminCard extends StatefulWidget {
  const _RiderVerificationAdminCard();

  @override
  State<_RiderVerificationAdminCard> createState() => _RiderVerificationAdminCardState();
}

class _RiderVerificationAdminCardState extends State<_RiderVerificationAdminCard> {
  List<Map<String, dynamic>> _riders = const [];
  bool _loading = true;
  String? _busy;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final res = await DropOffApi.adminRiders();
    if (!mounted) return;
    setState(() {
      _riders = ((res?['riders'] as List?) ?? const [])
          .map((e) => (e as Map).cast<String, dynamic>())
          .toList();
      _loading = false;
    });
  }

  Future<void> _verify(Map<String, dynamic> rider, String status) async {
    final id = (rider['id'] as num?)?.toInt();
    if (id == null) return;
    String? note;
    if (status == 'rejected') {
      final controller = TextEditingController();
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Reject driver'),
          content: TextField(
            controller: controller,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Reason (sent to the driver)'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Reject')),
          ],
        ),
      );
      if (ok != true) return;
      note = controller.text.trim();
      if (note.isEmpty) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('A rejection reason is required.')));
        return;
      }
    }
    setState(() => _busy = 'verify-$id');
    final res = await DropOffApi.adminVerifyRider(id, status: status, note: note);
    if (!mounted) return;
    setState(() => _busy = null);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res.ok
        ? (status == 'verified' ? 'Driver verified.' : 'Driver rejected.')
        : 'Could not update (${res.error}).')));
    if (res.ok) {
      _load();
      AnalyticsService.instance.track(
        feature: 'rider_verification', action: status, context: 'admin_verification_queue',
        meta: {'rider_id': id},
      );
    }
  }

  Future<void> _aiCheck(Map<String, dynamic> rider) async {
    final id = (rider['id'] as num?)?.toInt();
    if (id == null) return;
    setState(() => _busy = 'ai-$id');
    final res = await DropOffApi.adminAiCheckRider(id);
    if (!mounted) return;
    setState(() => _busy = null);
    if (!res.ok) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('AI check failed (${res.error}).')));
      return;
    }
    AnalyticsService.instance.track(
      feature: 'rider_verification', action: 'ai_check', context: 'admin_verification_queue',
      meta: {'rider_id': id, 'plate_match': res.body['plate_match'], 'nrc_match': res.body['nrc_match'],
             'face_verdict': (res.body['face'] as Map?)?['verdict']},
    );
    final text = '${res.body['text'] ?? ''}'.trim();
    final plateMatch = res.body['plate_match'] == true;
    final nrcMatch = res.body['nrc_match'] == true;
    final face = (res.body['face'] as Map?)?.cast<String, dynamic>();
    final faceVerdict = '${face?['verdict'] ?? ''}';
    final faceNote = '${face?['note'] ?? ''}';
    final faceColor = faceVerdict == 'pass' ? AppColors.forest : const Color(0xFFB3261E);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('AI document check'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Plate match: ${plateMatch ? 'YES' : 'no'}', style: TextStyle(fontWeight: FontWeight.w800, color: plateMatch ? AppColors.forest : const Color(0xFFB3261E))),
          const SizedBox(height: 4),
          Text('NRC match: ${nrcMatch ? 'YES' : 'no'}', style: TextStyle(fontWeight: FontWeight.w800, color: nrcMatch ? AppColors.forest : const Color(0xFFB3261E))),
          const SizedBox(height: 4),
          Text('Selfie face: ${faceVerdict.isEmpty ? 'not checked' : faceVerdict.toUpperCase()}',
              style: TextStyle(fontWeight: FontWeight.w800, color: faceVerdict.isEmpty ? AppColors.muted : faceColor)),
          if (faceNote.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text('AI note: $faceNote', style: const TextStyle(color: AppColors.muted, fontSize: 11, height: 1.3)),
          ],
          const SizedBox(height: 10),
          const Text('Text read from the photo:', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
          const SizedBox(height: 4),
          SelectableText(text.isEmpty ? '(nothing readable)' : text, style: const TextStyle(fontSize: 12, height: 1.4)),
          const SizedBox(height: 10),
          const Text('AI is an assist only - the decision is still yours.', style: TextStyle(color: AppColors.muted, fontSize: 11)),
        ]),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
      ),
    );
    _load();
  }

  void _preview(String? url) {
    if (url == null || url.isEmpty) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        child: InteractiveViewer(
          child: Image.network('${DropOffApi.baseUrl}$url', headers: DropOffApi.authHeaders, fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Padding(padding: EdgeInsets.all(24), child: Text('Photo unavailable'))),
        ),
      ),
    );
  }

  Widget _thumb(String? url, String label) {
    if (url == null || url.isEmpty) return const SizedBox.shrink();
    return InkWell(
      onTap: () => _preview(url),
      borderRadius: BorderRadius.circular(8),
      child: Column(children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.network('${DropOffApi.baseUrl}$url', headers: DropOffApi.authHeaders, width: 62, height: 50, fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(width: 62, height: 50, color: AppColors.line, child: const Icon(Icons.broken_image_outlined, size: 16))),
        ),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(fontSize: 9, color: AppColors.muted, fontWeight: FontWeight.w700)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pending = _riders.where((r) => '${r['verification_status']}' == 'pending').length;
    final verified = _riders.where((r) => '${r['verification_status']}' == 'verified').length;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.verified_user_outlined, color: AppColors.forest),
            const SizedBox(width: 10),
            const Expanded(child: Text('Driver verification & targets', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15))),
            IconButton(visualDensity: VisualDensity.compact, onPressed: _load, icon: const Icon(Icons.refresh, size: 18)),
          ]),
          Text('$pending pending review - $verified verified. Daily target is 30 parcels; month pace carries any missed day.',
              style: const TextStyle(color: AppColors.muted, fontSize: 11.5, height: 1.4)),
          const SizedBox(height: 12),
          if (_loading)
            const Padding(padding: EdgeInsets.symmetric(vertical: 14), child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))))
          else if (_riders.isEmpty)
            const Text('No riders registered yet.', style: TextStyle(color: AppColors.muted, fontSize: 12))
          else
            for (final rider in _riders) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.line.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.line),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text('${rider['full_name'] ?? 'Driver'}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5), maxLines: 1, overflow: TextOverflow.ellipsis)),
                    _statusChip('${rider['verification_status'] ?? 'pending'}'),
                  ]),
                  const SizedBox(height: 2),
                  Text('${rider['phone'] ?? ''} - ${rider['vehicle'] ?? ''} ${rider['vehicle_class'] ?? ''}',
                      style: const TextStyle(color: AppColors.muted, fontSize: 11, height: 1.35)),
                  const SizedBox(height: 4),
                  Text('Plate: ${_orDash(rider['plate_number'])}   NRC: ${_orDash(rider['nrc_number'])}   ${_orDash(rider['vehicle_make'])} ${_orDash(rider['vehicle_color'])}',
                      style: const TextStyle(fontSize: 11.5, height: 1.4)),
                  _targetLine(rider),
                  if (_hasPhotos(rider)) ...[
                    const SizedBox(height: 8),
                    Wrap(spacing: 8, runSpacing: 6, children: [
                      _thumb(rider['photo_url'] as String?, 'Selfie'),
                      _thumb(rider['nrc_photo_url'] as String?, 'NRC'),
                      _thumb(rider['plate_photo_url'] as String?, 'Plate'),
                      _thumb(rider['license_photo_url'] as String?, 'Licence'),
                    ]),
                  ],
                  if ('${rider['verification_note'] ?? ''}'.trim().isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text('Note: ${rider['verification_note']}', style: const TextStyle(color: Color(0xFFB3261E), fontSize: 11, height: 1.35)),
                  ],
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, runSpacing: 6, children: [
                    if ('${rider['verification_status']}' != 'verified')
                      FilledButton(
                        style: FilledButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), minimumSize: const Size(0, 32)),
                        onPressed: _busy != null ? null : () => _verify(rider, 'verified'),
                        child: const Text('Approve', style: TextStyle(fontSize: 12)),
                      ),
                    TextButton(
                      onPressed: _busy != null ? null : () => _verify(rider, 'rejected'),
                      child: const Text('Reject', style: TextStyle(fontSize: 12)),
                    ),
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), minimumSize: const Size(0, 32)),
                      onPressed: _busy != null ? null : () => _aiCheck(rider),
                      child: Text(_busy == 'ai-${rider['id']}' ? 'Checking...' : 'AI check', style: const TextStyle(fontSize: 12)),
                    ),
                  ]),
                ]),
              ),
            ],
        ]),
      ),
    );
  }

  static String _orDash(Object? value) {
    final text = '${value ?? ''}'.trim();
    return text.isEmpty ? '-' : text;
  }

  static bool _hasPhotos(Map<String, dynamic> rider) =>
      [rider['photo_url'], rider['nrc_photo_url'], rider['plate_photo_url'], rider['license_photo_url']]
          .any((u) => u != null && '$u'.isNotEmpty);

  Widget _statusChip(String status) {
    final (color, label) = switch (status) {
      'verified' => (AppColors.forest, 'VERIFIED'),
      'rejected' => (const Color(0xFFB3261E), 'REJECTED'),
      _ => (const Color(0xFF8A5A00), 'PENDING'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: TextStyle(color: color, fontSize: 8.5, fontWeight: FontWeight.w900, letterSpacing: 0.4)),
    );
  }

  Widget _targetLine(Map<String, dynamic> rider) {
    final targets = (rider['targets'] as Map?)?.cast<String, dynamic>();
    final today = (targets?['today'] as num?)?.toInt() ?? 0;
    final daily = (targets?['daily_target'] as num?)?.toInt() ?? 30;
    final month = (targets?['month'] as num?)?.toInt() ?? 0;
    final pace = (targets?['pace_target'] as num?)?.toInt() ?? 0;
    final onTrack = targets?['on_track'] == true;
    final met = today >= daily;
    return Padding(
      padding: const EdgeInsets.only(top: 5),
      child: Text(
        'Today $today/$daily${met ? ' (met)' : ''} - month $month vs pace $pace${onTrack ? ' (on track)' : ' (behind)'}',
        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: onTrack ? AppColors.forest : const Color(0xFF8A5A00)),
      ),
    );
  }
}

/// Feature usage / click KPI for the admin console — which app features are
/// used frequently (superadmin and admin). Reads the aggregated analytics
/// from GET /admin/analytics/kpi.
class _AnalyticsKpiCard extends StatefulWidget {
  const _AnalyticsKpiCard();

  @override
  State<_AnalyticsKpiCard> createState() => _AnalyticsKpiCardState();
}

class _AnalyticsKpiCardState extends State<_AnalyticsKpiCard> {
  Map<String, dynamic>? _kpi;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await DropOffApi.getAdmin('/admin/analytics/kpi?days=30');
    if (!mounted) return;
    setState(() {
      _kpi = data;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final kpi = _kpi;
    final total = kpi?['total_events'] as num? ?? 0;
    final features = ((kpi?['top_features'] as List?) ?? const [])
        .cast<Map<String, dynamic>>();
    final funnel = ((kpi?['funnel'] as List?) ?? const [])
        .cast<Map<String, dynamic>>();
    final dau = ((kpi?['dau'] as List?) ?? const [])
        .cast<Map<String, dynamic>>();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.insights_outlined, color: AppColors.forest),
            const SizedBox(width: 8),
            const Expanded(child: Text('App usage KPI (30 days)', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15))),
            IconButton(tooltip: 'Refresh', onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh, size: 18)),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: _KpiMetric('Events', '$total', Icons.event_note)),
            Expanded(child: _KpiMetric('Features', '${features.length}', Icons.apps)),
            Expanded(child: _KpiMetric('Active days', '${dau.length}', Icons.today)),
          ]),
          const SizedBox(height: 12),
          if (_loading)
            const Padding(padding: EdgeInsets.symmetric(vertical: 14), child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))))
          else ...[
            const Text('Most used features', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: AppColors.muted)),
            const SizedBox(height: 6),
            ...features.take(8).map((f) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                Expanded(child: Text('${f['feature']}', style: const TextStyle(fontSize: 12.5), maxLines: 1, overflow: TextOverflow.ellipsis)),
                Text('${f['n']}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12.5, color: AppColors.forest)),
                const SizedBox(width: 6),
                Text('${f['users']} users', style: const TextStyle(color: AppColors.muted, fontSize: 11)),
              ]),
            )),
            const SizedBox(height: 10),
            const Text('Conversion funnel (unique users)', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: AppColors.muted)),
            const SizedBox(height: 6),
            ...funnel.take(5).map((f) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                Expanded(child: Text('${f['feature']}', style: const TextStyle(fontSize: 12.5), maxLines: 1, overflow: TextOverflow.ellipsis)),
                Text('${f['users']}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12.5, color: AppColors.forest)),
              ]),
            )),
          ],
        ]),
      ),
    );
  }
}

class _KpiMetric extends StatelessWidget {
  const _KpiMetric(this.label, this.value, this.icon);
  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AppColors.line.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 16, color: AppColors.forest),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 10, color: AppColors.muted, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 6),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: AppColors.forest)),
      ]),
    );
  }
}

/// DropOff Predict (ops view): predicted parcels for the next 7 days per
/// depot branch and pickup window (same weekday+window average of the
/// trailing 8 weeks, CAT). Staffing/bonus planner for the week.
class _DemandForecastCard extends StatefulWidget {
  const _DemandForecastCard();

  @override
  State<_DemandForecastCard> createState() => _DemandForecastCardState();
}

class _DemandForecastCardState extends State<_DemandForecastCard> {
  static const _windowOrder = ['06:00', '10:00', '14:00', 'now', 'unscheduled'];

  Map<String, dynamic>? _data;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await DropOffApi.adminDemandForecast();
    if (!mounted) return;
    setState(() {
      _data = data;
      _loading = false;
    });
  }

  List<String> _orderedWindowKeys(List<Map<String, dynamic>> days) {
    final keys = <String>{};
    for (final d in days) {
      keys.addAll(((d['windows'] as Map?) ?? const {}).keys.cast<String>());
    }
    final ordered = _windowOrder.where(keys.contains).toList();
    final rest = keys.where((k) => !ordered.contains(k)).toList()..sort();
    return [...ordered, ...rest];
  }

  @override
  Widget build(BuildContext context) {
    final days = (((_data?['days'] as List?) ?? const [])).cast<Map<String, dynamic>>();
    final branches = (((_data?['branches'] as List?) ?? const [])).cast<Map<String, dynamic>>();
    final totals = (_data?['totals'] as Map?) ?? const {};
    final windows = _orderedWindowKeys(days);
    var maxCell = 0.0;
    for (final d in days) {
      final w = (d['windows'] as Map?) ?? const {};
      for (final v in w.values) {
        final n = (v as num?)?.toDouble() ?? 0;
        if (n > maxCell) maxCell = n;
      }
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.query_stats, color: AppColors.forest),
            const SizedBox(width: 8),
            const Expanded(child: Text('DropOff Predict — next 7 days', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15))),
            IconButton(tooltip: 'Refresh', onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh, size: 18)),
          ]),
          const SizedBox(height: 4),
          Text(
            _loading
                ? 'Learning from the last 8 weeks…'
                : '≈ ${totals['predicted_7d_parcels'] ?? 0} parcels predicted'
                  '${totals['busiest_branch'] != null ? ' · busiest: ${totals['busiest_branch']}' : ''}'
                  '${totals['busiest_window'] != null ? ' · window ${totals['busiest_window']}' : ''}',
            style: const TextStyle(color: AppColors.muted, fontSize: 12, height: 1.4),
          ),
          const SizedBox(height: 12),
          if (_loading)
            const Padding(padding: EdgeInsets.all(14), child: Center(child: CircularProgressIndicator()))
          else if (days.isEmpty)
            const Text('No bookings in the last 8 weeks to learn from yet.', style: TextStyle(color: AppColors.muted, fontSize: 12.5))
          else ...[
            // branch x window heat grid for the busiest branches (top 12)
            if (branches.isNotEmpty) ...[
              const Text('By depot branch', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: AppColors.muted)),
              const SizedBox(height: 6),
              for (final b in branches.take(8))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(children: [
                    Expanded(
                      child: Text('${b['branch']}', maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(width: 8),
                    Text('${b['predicted_7d_parcels']} parcels', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: AppColors.forest)),
                  ]),
                ),
            ],
            const SizedBox(height: 12),
            const Text('Per day (all branches)', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: AppColors.muted)),
            const SizedBox(height: 6),
            Table(
              defaultColumnWidth: const IntrinsicColumnWidth(),
              border: TableBorder.all(color: AppColors.line.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(8)),
              children: [
                TableRow(children: [
                  _heatCell('Day', header: true),
                  for (final w in windows) _heatCell(w, header: true),
                  _heatCell('Σ', header: true),
                ]),
                for (final d in days)
                  TableRow(children: [
                    _heatCell('${d['weekday']} ${('${d['date'] ?? ''}'.split('-').length == 3 ? ('${d['date']}').substring(8, 10) : d['date'])}'),
                    for (final w in windows) _heatCell('${((d['windows'] as Map?) ?? const {})[w] ?? 0}', intensity: maxCell),
                    _heatCell('${d['total'] ?? 0}', header: true),
                  ]),
              ],
            ),
            const SizedBox(height: 8),
            Text('${_data?['basis'] ?? ''}', style: const TextStyle(color: AppColors.muted, fontSize: 9.5, height: 1.3)),
          ],
        ]),
      ),
    );
  }

  Widget _heatCell(String text, {bool header = false, double intensity = 0}) {
    final v = double.tryParse(text) ?? 0;
    final alpha = header || intensity <= 0 ? 0.0 : (0.06 + 0.45 * (v / intensity)).clamp(0.06, 0.55);
    return Container(
      constraints: const BoxConstraints(minWidth: 44),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      color: header ? AppColors.line.withValues(alpha: 0.35) : AppColors.forest.withValues(alpha: alpha),
      child: Center(
        child: Text(text,
            style: TextStyle(fontSize: header ? 10 : 11, fontWeight: header ? FontWeight.w800 : FontWeight.w700,
                color: header ? AppColors.ink : AppColors.forest)),
      ),
    );
  }
}
