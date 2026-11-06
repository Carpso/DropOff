import 'package:flutter/material.dart';

import '../data/dropoff_api.dart';
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
    if (res.ok) _smsBody.clear();
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
            _alertsCard(),
            const SizedBox(height: 18),
            _fraudCard(),
            const SizedBox(height: 18),
            const _SupportInboxCard(),
            if (_superadmin) ...[
              const SizedBox(height: 18),
              const _UsersCard(),
            ],
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
            const Text('Active packs', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: AppColors.muted)),
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
                  TextButton(onPressed: () async { await DropOffApi.reviewFraud((f['id'] as num).toInt(), status: 'cleared'); _load(); }, child: const Text('Clear')),
                  TextButton(onPressed: () async { await DropOffApi.reviewFraud((f['id'] as num).toInt(), status: 'confirmed'); _load(); }, child: const Text('Confirm')),
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
                DropdownMenuItem(value: 'subscribers', child: Text('Active pack subscribers')),
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
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 12),
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
    if (res.ok) _load();
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
    if (res.ok) { _name.clear(); _address.clear(); _lat.clear(); _lng.clear(); _phone.clear(); _loadBranches(); }
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
