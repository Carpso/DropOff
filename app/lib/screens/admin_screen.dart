import '../ui/app_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

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
  Map<String, dynamic>? _runrate;
  List<Map<String, dynamic>> _alerts = const [];
  List<Map<String, dynamic>> _flags = const [];
  List<Map<String, dynamic>> _chatReports = const [];
  List<Map<String, dynamic>> _chatStrikes = const [];
  List<Map<String, dynamic>> _payroll = const [];
  List<Map<String, dynamic>> _payrollSummary = const [];
  List<Map<String, dynamic>> _tax = const [];
  bool _payrollBusy = false;
  bool _taxBusy = false;
  bool _loading = true;
  bool _authorized = false;
  bool _superadmin = false;
  String _role = 'admin';
  bool get _financeOnly => _role == 'cfo';

  final _smsPhone = TextEditingController();
  final _smsBody = TextEditingController();
  final _pushTitle = TextEditingController();
  final _pushBody = TextEditingController();
  String _pushAudience = 'accounts';
  bool _pushSending = false;
  String _pushPreview = '';

  String _audience = 'accounts';
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    // Re-evaluate the Send button (and the preview) as the admin types —
    // otherwise the button looks permanently disabled while the field is
    // filled, because typing never triggers a rebuild on its own.
    _pushTitle.addListener(_revalidateForm);
    _pushBody.addListener(_revalidateForm);
    _smsBody.addListener(_revalidateForm);
    _load();
  }

  void _revalidateForm() => setState(() {});

  @override
  void dispose() {
    _smsPhone.dispose();
    _smsBody.dispose();
    _pushTitle.dispose();
    _pushBody.dispose();
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
    final moderation = await DropOffApi.chatReports();
    final payroll = await DropOffApi.adminPayroll();
    final tax = await DropOffApi.adminTax();
    final runrate = await DropOffApi.adminPayrollRunrate();
    if (!mounted) return;
    setState(() {
      _authorized = true;
      _superadmin = me?['superadmin'] == true;
      _role = role;
      _runrate = runrate;
      _stats = stats;
      _alerts = ((alerts?['alerts'] as List?) ?? const []).cast<Map<String, dynamic>>();
      _flags = ((flags?['flags'] as List?) ?? const []).cast<Map<String, dynamic>>();
      _chatReports = ((moderation?['reports'] as List?) ?? const []).cast<Map<String, dynamic>>();
      _chatStrikes = ((moderation?['strikes'] as List?) ?? const []).cast<Map<String, dynamic>>();
      _payroll = ((payroll?['payouts'] as List?) ?? const []).cast<Map<String, dynamic>>();
      _payrollSummary = ((payroll?['summary'] as List?) ?? const []).cast<Map<String, dynamic>>();
      _tax = ((tax?['periods'] as List?) ?? const []).cast<Map<String, dynamic>>();
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
    AppToast.show(context, res.ok
        ? (broadcast ? 'Broadcast queued — sends run in the background.' : 'SMS sent.')
        : 'Send failed: ${res.error}');
    if (res.ok) {
      _smsBody.clear();
      AnalyticsService.instance.track(
        feature: 'sms_broadcast', action: broadcast ? 'broadcast' : 'send', context: 'admin_sms',
        meta: {'audience': _audience},
      );
    }
  }

  Future<void> _sendPushBroadcast() async {
    final t = _pushTitle.text.trim();
    final msg = _pushBody.text.trim();
    if (t.isEmpty || msg.isEmpty) return;
    setState(() { _pushSending = true; _pushPreview = '$t\n$msg'; });
    final res = await DropOffApi.adminPushBroadcast(audience: _pushAudience, title: t, body: msg);
    if (!mounted) return;
    setState(() => _pushSending = false);
    AppToast.show(context, res.ok
        ? 'Push broadcast queued — FCM sends in the background.'
        : 'Push failed: ${res.error}');
    if (res.ok) {
      _pushTitle.clear();
      _pushBody.clear();
      _pushPreview = '';
      setState(() {});
      AnalyticsService.instance.track(
        feature: 'push_broadcast', action: 'broadcast', context: 'admin_push',
        meta: {'audience': _pushAudience},
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    AnalyticsService.instance.trackScreenView('admin_console');
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
              const Text('This console is reserved for DropOff staff — admins, ops and the CFO. Sign in with a staff account to continue.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted, height: 1.45)),
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
        title: Text(_financeOnly ? 'Finance console' : 'Admin console', style: const TextStyle(fontWeight: FontWeight.w900)),
        actions: [
          if (_role == 'cfo')
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 11),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF1E4F6E).withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF1E4F6E).withValues(alpha: 0.6)),
              ),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.account_balance, size: 12, color: Color(0xFF1E4F6E)),
                SizedBox(width: 4),
                Text('CFO', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 0.9, color: Color(0xFF1E4F6E))),
              ]),
            ),
          if (_superadmin)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 11),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: AppColors.amber.withValues(alpha: 0.22),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.amber.withValues(alpha: 0.65)),
              ),
              // compact SUPERADMIN chip — flags the owner-only console to itself
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.shield, size: 12, color: Color(0xFF7A5200)),
                SizedBox(width: 4),
                Text('SUPERADMIN', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 0.9, color: Color(0xFF7A5200))),
              ]),
            ),
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
              child: Row(children: [
                Icon(_financeOnly ? Icons.account_balance : Icons.admin_panel_settings_outlined, color: AppColors.forest),
                SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_financeOnly ? 'Finance (CFO)' : 'Operations overview', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: AppColors.forest)),
                  SizedBox(height: 2),
                  Text(_financeOnly
                      ? 'Salaries, turnover, payroll run-rate and ZRA filings. Two signatures release money.'
                      : 'Live stats, security, fraud, depot branches and messaging.',
                      style: TextStyle(color: AppColors.muted, fontSize: 12, height: 1.35)),
                ])),
              ]),
            ),
            const SizedBox(height: 16),
            _salaryCard(),
            const SizedBox(height: 18),
            if (!_financeOnly) ...[
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
              _chatReportsCard(),
              const SizedBox(height: 18),
            ],
            _payrollCard(financeOnly: _financeOnly),
            const SizedBox(height: 18),
            _taxCard(),
            if (!_financeOnly) ...[
              const _SupportInboxCard(),
              if (_superadmin) ...[
                const SizedBox(height: 18),
                const _UsersCard(),
              ],
              const SizedBox(height: 18),
              const _PackCodesCard(),
              const SizedBox(height: 18),
              const _PlansAndCouriersCard(),
              const SizedBox(height: 18),
              const _RiderVerificationAdminCard(),
              const SizedBox(height: 18),
              const _BranchManagerCard(),
              const SizedBox(height: 18),
              const _CounterQuoteCard(),
              const SizedBox(height: 18),
              _smsCard(),
              const SizedBox(height: 18),
              _marketingPushCard(),
            ],
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

  /// Chat moderation: open user reports on chat messages ("hide & strike" /
  /// dismiss) plus the strike ledger with the forgiveness lever. Confirms ask
  /// first and track the action like every other admin surface does.
  static String _maskAdminPhone(String phone) =>
      phone.length >= 4 ? '••• ${phone.substring(phone.length - 4)}' : phone;

  // ---- Rider payroll + ZRA turnover tax -------------------------------------

  String _kwacha(num? v) => 'K${(v ?? 0).toStringAsFixed(v == null || v == v.roundToDouble() ? 0 : 2)}';

  Future<void> _payrollAction(String label, Future<ApiResponse> Function() run, {bool reload = true}) async {
    if (_payrollBusy) return;
    setState(() { _payrollBusy = true; });
    final res = await run();
    if (!mounted) return;
    setState(() { _payrollBusy = false; });
    AppToast.show(context, res.ok ? '$label done.' : '$label failed: ${res.error ?? 'try again'}');
    if (res.ok && reload) {
      final p = await DropOffApi.adminPayroll();
      if (mounted) {
        setState(() {
          _payroll = ((p?['payouts'] as List?) ?? const []).cast<Map<String, dynamic>>();
          _payrollSummary = ((p?['summary'] as List?) ?? const []).cast<Map<String, dynamic>>();
        });
      }
    }
  }

  /// Salaries run-rate — the same ZRA-ready view of the payroll budget the
  /// owner uses to decide headcount as the business grows. All figures come
  /// from the live ledger (/admin/payroll/runrate); scenario buttons project
  /// headcount + required monthly turnover at a 25% payroll-share ceiling.
  Widget _salaryCard() {
    final r = _runrate;
    final riders = (r?['verified_active_riders'] as num?)?.toInt() ?? 0;
    final monthlyOut = (r?['monthly_out_zmw'] as num?)?.toDouble() ?? riders * 3000;
    final weeklyOut = (r?['weekly_out_zmw'] as num?)?.toDouble() ?? (riders * 750);
    final annualOut = (r?['annual_out_zmw'] as num?)?.toDouble() ?? monthlyOut * 12;
    final pending = (r?['pending_payroll_zmw'] as num?)?.toDouble() ?? 0;
    final avgTurn = (r?['avg_monthly_turnover_zmw'] as num?)?.toDouble() ?? 0;
    final share = r?['payroll_share_of_turnover_pct'] as num?;
    final sustain = (r?['self_sustain_trips_per_rider_day'] as num?)?.toInt() ?? 3;
    final growth = ((r?['growth_planner'] as List?) ?? const []).cast<Map<String, dynamic>>();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.payments_outlined, color: AppColors.forest),
            const SizedBox(width: 8),
            const Expanded(child: Text('Salaries — as the business grows', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15))),
          ]),
          const SizedBox(height: 6),
          Text('K3,000/rider/month incl. K300/week fuel (K1,800 base), weekly K750 per Light cycle. Pace-gated by delivery. This is the real cost of your roster.',
              style: const TextStyle(color: AppColors.muted, fontSize: 11.5, height: 1.35)),
          const SizedBox(height: 10),
          Wrap(spacing: 10, runSpacing: 10, children: [
            _metricTile('Riders on books', '$riders', 'verified, active', Icons.groups),
            _metricTile('Week outflow', _kwacha(weeklyOut), 'weekly cycle', Icons.calendar_view_week_outlined),
            _metricTile('Month outflow', _kwacha(monthlyOut), 'full payroll', Icons.calendar_month_outlined),
            _metricTile('Annual run-rate', _kwacha(annualOut), 'year projection', Icons.trending_up_rounded),
            _metricTile('Awaiting signatures', _kwacha(pending), 'pending payout funds', Icons.pending_actions),
          ]),
          const SizedBox(height: 10),
          if (avgTurn > 0) ...[
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('ATO turnover (3-mo avg): ${_kwacha(avgTurn)} · payroll = ${share?.toStringAsFixed(1) ?? '?'}% of it',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: (share ?? 0) <= 25 ? AppColors.forest : (share ?? 100) <= 50 ? const Color(0xFF8A5A00) : const Color(0xFFB3261E))),
            ),
          ],
          const SizedBox(height: 4),
          Text('A full-time rider pays for themselves at ~$sustain PAYG trips/day (K45 each). Plans speed up the cash equation — but trips, not promos, measure pace.',
              style: const TextStyle(color: AppColors.muted, fontSize: 11, height: 1.4)),
          if (growth.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text("What's next — headcount headache kept simple", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 6, children: [
              for (final g in growth)
                Chip(
                  visualDensity: VisualDensity.compact,
                  backgroundColor: const Color(0xFF10301E).withValues(alpha: 0.06),
                  label: Text('+${g['add']} riders → ${_kwacha(num.tryParse('${g['monthly_payroll_zmw']}'))}/mo'
                      '${(g['payroll_share_pct'] != null) ? ' · ${(num.tryParse('${g['payroll_share_pct']}') ?? 0).toStringAsFixed(0)}% of turnover' : ''}'
                      ' · needs ${_kwacha(num.tryParse('${g['needed_turnover_zmw']}'))}/mo (≤25%)',
                      style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700)),
                ),
            ]),
          ],
        ]),
      ),
    );
  }

  Widget _metricTile(String label, String value, String sub, IconData icon) => Container(
        constraints: const BoxConstraints(minWidth: 108),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.forest.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.forest.withValues(alpha: 0.22)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Icon(icon, size: 13, color: AppColors.forest), const SizedBox(width: 4), Expanded(child: Text(label, style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: AppColors.muted)))]),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: AppColors.forest)),
          Text(sub, style: const TextStyle(fontSize: 9, color: AppColors.muted)),
        ]),
      );

  /// Every payout row's money moves only after admin intent → superadmin release.
  Widget _payrollCard({bool financeOnly = false}) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.badge_outlined, color: AppColors.forest),
              const SizedBox(width: 8),
              const Expanded(child: Text('Rider payroll (K3,000/mo)', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15))),
              if (financeOnly)
                Chip(visualDensity: VisualDensity.compact, label: const Text('CFO view', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800))),
            ]),
            const SizedBox(height: 6),
            Text('Auto-generated: weekly Sun 16:00 CAT, monthly on the 1st. Two signatures release the money.',
                style: const TextStyle(color: AppColors.muted, fontSize: 11.5)),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 6, children: [
              for (final s in _payrollSummary)
                Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text('${s['status']}: ${s['n']} · ${_kwacha(num.tryParse('${s['total']}'))}',
                      style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800)),
                ),
            ]),
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              TextButton.icon(
                onPressed: _payrollBusy ? null : () => _payrollAction('Generate weekly', () => DropOffApi.adminPayrollGenerate(kind: 'weekly')),
                icon: const Icon(Icons.play_arrow, size: 16), label: const Text('Generate weekly', style: TextStyle(fontSize: 12)),
              ),
              TextButton.icon(
                onPressed: _payrollBusy ? null : () => _payrollAction('Generate monthly', () => DropOffApi.adminPayrollGenerate(kind: 'monthly')),
                icon: const Icon(Icons.play_arrow, size: 16), label: const Text('Generate monthly', style: TextStyle(fontSize: 12)),
              ),
            ]),
            if (_payroll.isEmpty)
              const Text('No payroll rows yet. Verify riders first; rows appear Sunday 16:00 CAT / 1st of the month.',
                  style: TextStyle(color: AppColors.muted, fontSize: 12)),
            for (final p in _payroll.take(10))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(
                      '#${p['id']} ${p['rider_name'] ?? ''} · ${p['period_kind'] == 'monthly_balance' ? 'month balance' : '${p['period_kind']}'} ${'${p['period_start']}'.split('T').first}',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${_kwacha(num.tryParse('${p['amount_zmw']}'))} · ${p['trips'] ?? 0}/${p['period_target'] ?? 0} trips'
                      ' · ${_payrollStatusText('${p['status']}')}'
                      '${((p['note'] ?? '') as String).isNotEmpty ? ' · ${p['note']}' : ''}',
                      style: const TextStyle(color: AppColors.muted, fontSize: 11.5),
                    ),
                  ])),
                  ..._payrollRowActions(p, financeOnly: financeOnly),
                ]),
              ),
          ]),
        ),
      );

  List<Widget> _payrollRowActions(Map<String, dynamic> p, {bool financeOnly = false}) {
    final id = (p['id'] as num).toInt();
    final status = '${p['status']}';
    final proof = TextButton(onPressed: () async {
      final bytes = await DropOffApi.adminPayrollProof(id);
      if (!mounted) return;
      if (bytes == null) {
        AppToast.show(context, 'Proof unavailable — try again.');
        return;
      }
      await Share.shareXFiles([XFile.fromData(bytes, mimeType: 'text/html', name: 'DropOff-payout-$id.html')], subject: 'DropOff payout proof #$id');
    }, child: const Text('Proof', style: TextStyle(fontSize: 12)));
    if (financeOnly) {
      // CFO can see the proof of payment but money never moves from here.
      return [proof];
    }
    if (status == 'pending') {
      return [
        TextButton(onPressed: _payrollBusy ? null : () => _payrollAction('Confirmation 1 (admin)', () => DropOffApi.adminPayrollConfirm(id)), child: const Text('Confirm', style: TextStyle(fontSize: 12))),
        proof,
      ];
    }
    if (status == 'admin_confirmed') {
      return [
        TextButton(onPressed: _payrollBusy ? null : () => _payrollAction('Release payment', () => DropOffApi.adminPayrollConfirm(id)), child: const Text('Release pay', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900))),
        proof,
      ];
    }
    if (status == 'failed') {
      return [
        TextButton(onPressed: _payrollBusy ? null : () => _payrollAction('Retry release', () => DropOffApi.adminPayrollConfirm(id)), child: const Text('Retry', style: TextStyle(fontSize: 12))),
        if (_superadmin)
          TextButton(onPressed: _payrollBusy ? null : () => _payrollAction('Void', () => DropOffApi.adminPayrollVoid(id)), child: const Text('Void', style: TextStyle(fontSize: 12))),
      ];
    }
    if (status == 'paid') {
      return [proof];
    }
    return const [];
  }

  String _payrollStatusText(String status) {
    switch (status) {
      case 'pending': return 'awaiting admin';
      case 'admin_confirmed': return 'awaiting superadmin';
      case 'paid': return 'paid ✓';
      case 'failed': return 'Lipila failed';
      default: return status;
    }
  }

  Future<void> _taxAction(String label, Future<ApiResponse> Function() run) async {
    if (_taxBusy) return;
    setState(() { _taxBusy = true; });
    final res = await run();
    if (!mounted) return;
    setState(() { _taxBusy = false; });
    AppToast.show(context, res.ok ? '$label recorded.' : '$label failed: ${res.error ?? 'try again'}');
    if (res.ok) {
      final t = await DropOffApi.adminTax();
      if (mounted) setState(() { _tax = ((t?['periods'] as List?) ?? const []).cast<Map<String, dynamic>>(); });
    }
  }

  /// ZRA turnover tax: 0% ≤ K2,500 monthly turnover; 5% above; due the 14th.
  Widget _taxCard() => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.account_balance_outlined, color: AppColors.forest),
              const SizedBox(width: 8),
              const Expanded(child: Text('ZRA turnover tax', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15))),
              TextButton(onPressed: _taxBusy ? null : () => _taxAction('Refresh', () => DropOffApi.adminTaxRefresh()), child: const Text('Refresh', style: TextStyle(fontSize: 12))),
            ]),
            Text('Turnover = DropOff income only (jobs + prepaid delivery legs + plans + COD cut). 0% up to K2,500/month, 5% above. File by the 14th of the next month.',
                style: const TextStyle(color: AppColors.muted, fontSize: 11.5)),
            const SizedBox(height: 8),
            if (_tax.isEmpty)
              const Text('No tax periods yet — the ledger fills as payments land.', style: TextStyle(color: AppColors.muted, fontSize: 12)),
            for (final t in _tax.take(8))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(
                      '${t['year_month']} · turnover ${_kwacha(num.tryParse('${t['gross_turnover_zmw']}'))} → due ${t['due_date']}',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Tax: ${_kwacha(num.tryParse('${t['tax_zmw']}'))} · status ${'${t['status']}'.toUpperCase()}',
                      style: const TextStyle(color: AppColors.muted, fontSize: 11.5),
                    ),
                  ])),
                  TextButton(onPressed: () async {
                    final bytes = await DropOffApi.adminTaxReport('${t['year_month']}');
                    if (!mounted) return;
                    if (bytes == null) {
                      AppToast.show(context, 'Report unavailable.');
                      return;
                    }
                    await Share.shareXFiles([XFile.fromData(bytes, mimeType: 'text/html', name: 'DropOff-TOT-${t['year_month']}.html')], subject: 'DropOff TOT ${t['year_month']}');
                  }, child: const Text('Sheet', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900))),
                  if ('${t['status']}' == 'open')
                    TextButton(onPressed: _taxBusy ? null : () => _taxAction('Submitted', () => DropOffApi.adminTaxMark('${t['year_month']}', status: 'submitted')), child: const Text('Mark filed', style: TextStyle(fontSize: 12))),
                  if ('${t['status']}' == 'submitted')
                    TextButton(onPressed: _taxBusy ? null : () => _taxAction('Paid', () => DropOffApi.adminTaxMark('${t['year_month']}', status: 'paid')), child: const Text('Mark paid', style: TextStyle(fontSize: 12))),
                ]),
              ),
          ]),
        ),
      );

  Widget _chatReportsCard() => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.report_outlined, color: AppColors.forest),
              const SizedBox(width: 8),
              const Expanded(child: Text('Chat reports (open)', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15))),
              Text('${_chatReports.length}', style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.forest)),
            ]),
            const SizedBox(height: 8),
            if (_chatReports.isEmpty)
              const Text('No open chat reports.', style: TextStyle(color: AppColors.muted, fontSize: 12.5)),
            for (final r in _chatReports.take(10))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(
                      '${r['job_ref'] ?? 'Support'} · from ${_maskAdminPhone('${r['reported_by'] ?? ''}')} · ${r['reason'] ?? 'other'}',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5),
                    ),
                    Text(
                      '${r['sender_role'] ?? ''} (${_maskAdminPhone('${r['sender_phone'] ?? ''}')}): "${r['message_body'] ?? ''}"',
                      style: const TextStyle(color: AppColors.muted, fontSize: 11.5),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ])),
                  TextButton(
                    onPressed: () async {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Hide this message?'),
                          content: const Text('It disappears from every view of the chat and the sender gets a strike. 3 strikes auto-suspend chat for 7 days.'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Hide')),
                          ],
                        ),
                      );
                      if (ok != true) return;
                      await DropOffApi.reviewChatReport((r['id'] as num).toInt(), action: 'confirm');
                      AnalyticsService.instance.track(
                        feature: 'chat_moderation', action: 'confirm', context: 'admin_chat_reports',
                        meta: {'report_id': r['id']},
                      );
                      _load();
                    },
                    child: const Text('Hide & strike'),
                  ),
                  TextButton(
                    onPressed: () async {
                      await DropOffApi.reviewChatReport((r['id'] as num).toInt(), action: 'dismiss');
                      AnalyticsService.instance.track(
                        feature: 'chat_moderation', action: 'dismiss', context: 'admin_chat_reports',
                        meta: {'report_id': r['id']},
                      );
                      _load();
                    },
                    child: const Text('Dismiss'),
                  ),
                ]),
              ),
            // Strike ledger: abusers accumulate strikes; suspension auto-lifts.
            if (_chatStrikes.isNotEmpty) ...[
              const SizedBox(height: 10),
              const Text('Strike ledger', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
              for (final s in _chatStrikes.take(8))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(children: [
                    Expanded(child: Text(
                      '${_maskAdminPhone('${s['phone'] ?? ''}')} · ${s['strikes'] ?? 0} strikes${s['suspended_until'] != null ? ' · suspended until ${'${s['suspended_until']}'.split(' ').first}' : ''}',
                      style: const TextStyle(fontSize: 12, color: AppColors.muted),
                    )),
                    TextButton(
                      onPressed: () async {
                        await DropOffApi.clearChatStrikes('${s['phone'] ?? ''}');
                        _load();
                      },
                      child: const Text('Forgive'),
                    ),
                  ]),
                ),
            ],
          ]),
        ),
      );

  Widget _marketingPushCard() => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.campaign_outlined, color: AppColors.forest),
              const SizedBox(width: 8),
              const Expanded(child: Text('Push — marketing broadcast', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15))),
            ]),
            const SizedBox(height: 4),
            const Text('Push an offer to app users by audience. Title ≤ 80 chars, body ≤ 140 chars. Delivered on devices that previously signed in to the app.',
                style: TextStyle(color: AppColors.muted, fontSize: 11.5, height: 1.35)),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: _pushAudience,
              decoration: const InputDecoration(labelText: 'Audience', prefixIcon: Icon(Icons.groups_outlined)),
              items: const [
                DropdownMenuItem(value: 'accounts', child: Text('Registered accounts')),
                DropdownMenuItem(value: 'sellers', child: Text('All sellers (booked before)')),
                DropdownMenuItem(value: 'subscribers', child: Text('Active plan subscribers')),
                DropdownMenuItem(value: 'riders', child: Text('Verified riders')),
                DropdownMenuItem(value: 'all', child: Text('Everyone')),
              ],
              onChanged: (v) => setState(() => _pushAudience = v ?? 'accounts'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _pushTitle,
              maxLength: 80,
              decoration: const InputDecoration(labelText: 'Title', hintText: 'e.g. K69 Daily Rider pass is live', counterText: ''),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _pushBody,
              maxLength: 140,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Message', hintText: 'e.g. Ride today for free — subscribe in-app.', counterText: ''),
            ),
            const SizedBox(height: 10),
            if (_pushPreview.isNotEmpty || _pushTitle.text.isNotEmpty) Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Preview', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 11, color: AppColors.muted)),
              const SizedBox(height: 4),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF2D2D2D),
                  borderRadius: BorderRadius.circular(12),
                  border: Border(left: BorderSide(color: AppColors.amber, width: 3)),
                ),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.notifications_active, color: AppColors.amber, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(_pushTitle.text.isEmpty ? '(title)' : _pushTitle.text,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
                    const SizedBox(height: 2),
                    Text(_pushBody.text.isEmpty ? '(message)' : _pushBody.text,
                        style: const TextStyle(color: Colors.white70, fontSize: 11.5, height: 1.3)),
                  ])),
                ]),
              ),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: FilledButton(
                onPressed: _pushSending || _pushTitle.text.trim().isEmpty || _pushBody.text.trim().isEmpty ? null : _sendPushBroadcast,
                child: Text(_pushSending ? 'Sending…' : 'Send push broadcast'),
              )),
            ]),
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
    final id = (thread['id'] as num?)?.toInt();
    if (id == null) {
      AppToast.show(context, 'Ticket is missing its id — pull to refresh and try again.');
      return;
    }
    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
        builder: (_) => _SupportTicketSheet(
          threadId: id,
          phone: '${thread['phone'] ?? ''}',
          photoUrl: '${thread['customer_photo_url'] ?? ''}'.isEmpty ? null : '${thread['customer_photo_url']}',
          customerName: '${thread['customer_name'] ?? ''}'.trim().isEmpty ? null : '${thread['customer_name']}'.trim(),
        ),
      );
    } catch (e) {
      AppToast.show(context, 'Could not open ticket #$id: $e');
      return;
    }
    if (mounted) _load();
  }

  static String _initialsOf(String seed) {
    final parts = seed.trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    return parts.take(2).map((s) => s[0].toUpperCase()).join();
  }

  Widget _customerAvatar(String seed, String? photoUrl, double radius) {
    final initials = _initialsOf(seed);
    if (photoUrl == null || photoUrl.isEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: AppColors.forest.withValues(alpha: 0.10),
        child: Text(initials, style: TextStyle(fontWeight: FontWeight.w900, fontSize: radius * 0.66, color: AppColors.forest)),
      );
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: AppColors.forest.withValues(alpha: 0.10),
      child: ClipOval(
        child: Image.network(
          '${DropOffApi.baseUrl}$photoUrl',
          headers: DropOffApi.authHeaders,
          width: radius * 2,
          height: radius * 2,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Text(initials, style: TextStyle(fontWeight: FontWeight.w900, fontSize: radius * 0.66, color: AppColors.forest)),
        ),
      ),
    );
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
              final threadName = '${t['customer_name'] ?? ''}'.trim();
              final seed = threadName.isNotEmpty ? threadName : '${t['phone'] ?? ''}';
              final photoUrl = '${t['customer_photo_url'] ?? ''}'.trim();
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => _open(t),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                    child: Row(children: [
                      _customerAvatar(seed, photoUrl.isEmpty ? null : photoUrl, 16),
                      const SizedBox(width: 10),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Ticket #${t['id']} · $seed',
                            maxLines: 1, overflow: TextOverflow.ellipsis,
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
  const _SupportTicketSheet({required this.threadId, required this.phone, this.photoUrl, this.customerName});

  final int threadId;
  final String phone;
  final String? photoUrl;
  final String? customerName;

  @override
  State<_SupportTicketSheet> createState() => _SupportTicketSheetState();
}

class _SupportTicketSheetState extends State<_SupportTicketSheet> {
  List<Map<String, dynamic>> _messages = const [];
  bool _loading = true;
  String? _error;
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
    if (data == null) {
      setState(() { _loading = false; _error = 'Could not load this ticket. Check your connection and staff role, then retry.'; });
      return;
    }
    setState(() {
      _messages = ((data['messages'] as List?) ?? const []).cast<Map<String, dynamic>>();
      _error = null;
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
      AppToast.show(context, 'Reply failed: ${res.error}');
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
      AppToast.show(context, res.ok ? 'AI returned an empty draft — write the reply yourself.' : 'AI draft unavailable: ${res.error ?? 'try again'}');
      return;
    }
    setState(() { _reply.text = draft; });
    _reply.selection = TextSelection.collapsed(offset: draft.length);
  }

  Widget _bubble(Map<String, dynamic> m, bool fromOps, String time) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.62),
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
    );
  }

  Widget _sheetAvatar() {
    final name = (widget.customerName ?? widget.phone).trim();
    final parts = name.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
    final initials = parts.isEmpty ? '?' : parts.take(2).map((s) => s[0].toUpperCase()).join();
    const radius = 17.0;
    if (widget.photoUrl == null || widget.photoUrl!.isEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: AppColors.forest.withValues(alpha: 0.10),
        child: Text(initials, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 11, color: AppColors.forest)),
      );
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: AppColors.forest.withValues(alpha: 0.10),
      child: ClipOval(
        child: Image.network(
          '${DropOffApi.baseUrl}${widget.photoUrl}',
          headers: DropOffApi.authHeaders,
          width: radius * 2,
          height: radius * 2,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Text(initials,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 11, color: AppColors.forest)),
        ),
      ),
    );
  }

  void _copyPhone() {
    Clipboard.setData(ClipboardData(text: widget.phone));
    AppToast.show(context, 'Copied ${widget.phone}');
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
              _sheetAvatar(),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Ticket #${widget.threadId}',
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                  Text(widget.customerName ?? widget.phone,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.muted, fontSize: 11.5)),
                ]),
              ),
              IconButton(tooltip: 'Reload', onPressed: () { setState(() { _loading = true; _error = null; }); _load(); }, icon: const Icon(Icons.refresh, size: 18)),
            ]),
          ),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(28),
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            const Icon(Icons.cloud_off_outlined, size: 36, color: AppColors.muted),
                            const SizedBox(height: 10),
                            Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted, height: 1.4)),
                            const SizedBox(height: 14),
                            FilledButton.icon(
                              onPressed: () { setState(() { _loading = true; _error = null; }); _load(); },
                              icon: const Icon(Icons.refresh),
                              label: const Text('Retry'),
                            ),
                          ]),
                        ),
                      )
                    : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    itemCount: _messages.length,
                    itemBuilder: (context, i) {
                      final m = _messages[i];
                      final fromOps = '${m['sender_role'] ?? ''}' == 'ops';
                      final time = '${m['created_at'] ?? ''}'.split(' ').last;
                      final senderPhoto = '${m['sender_photo_url'] ?? ''}'.trim();
                      final avatar = _SheetAvatar(photoUrl: senderPhoto.isEmpty ? null : senderPhoto, label: '${m['sender_role'] ?? 'user'}', mine: fromOps);
                      return Align(
                        alignment: fromOps ? Alignment.centerRight : Alignment.centerLeft,
                        child: Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end,
                          children: fromOps ? [_bubble(m, fromOps, time), const SizedBox(width: 7), avatar] : [avatar, const SizedBox(width: 7), _bubble(m, fromOps, time)],
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
    AppToast.show(context, res.ok
        ? '$email is now $role.'
        : 'Failed: ${res.error == 'owner_cannot_be_demoted' ? 'the owner account cannot be demoted' : res.error == 'superadmin_required' ? 'only the owner can change roles' : res.error}');
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
          const Text('As the owner you decide who is who. Roles you can grant: customer (regular sender/seller), rider (team member — Team/Rider tab, salary payroll), partner (courier depot console), ops (dispatch — fleet-wide tools), admin (full admin console, cannot mint more admins or promote themselves), cfo (finances only — payroll, turnover tax and filings; never moves money on their own).',
              style: TextStyle(color: AppColors.muted, fontSize: 11.5, height: 1.35)),
          const SizedBox(height: 8),
          if (_loading)
            const Padding(padding: EdgeInsets.all(14), child: Center(child: CircularProgressIndicator()))
          else if (_users.isEmpty)
            const Text('No accounts found.', style: TextStyle(color: AppColors.muted, fontSize: 12.5))
          else
            ..._users.take(60).map((u) {
              final role = '${u['role'] ?? 'customer'}';
              final superadmin = u['superadmin'] == true;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(children: [
                  const Icon(Icons.person_outline, size: 16, color: AppColors.forest),
                  const SizedBox(width: 10),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Text('${u['full_name'] ?? u['email'] ?? u['phone'] ?? 'Account'}',
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                      if (superadmin) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.amber.withValues(alpha: 0.22),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: AppColors.amber.withValues(alpha: 0.65)),
                          ),
                          child: const Text('SUPERADMIN', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: 0.7, color: Color(0xFF7A5200))),
                        ),
                      ],
                    ]),
                    Text('${u['email'] ?? ''} · ${u['phone'] ?? ''}',
                        style: const TextStyle(color: AppColors.muted, fontSize: 11)),
                  ])),
                  if (superadmin) const Chip(visualDensity: VisualDensity.compact, label: Text('SUPERADMIN', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900)))
                  else
                    PopupMenuButton<String>(
                      tooltip: 'Change role',
                      initialValue: role,
                      onSelected: (r) => _setRole(u, r),
                      itemBuilder: (context) => const [
                        PopupMenuItem(value: 'customer', child: Text('customer — regular sender/seller')),
                        PopupMenuItem(value: 'rider', child: Text('rider — team member (salary)')),
                        PopupMenuItem(value: 'partner', child: Text('partner — courier depot console')),
                        PopupMenuItem(value: 'ops', child: Text('ops — dispatch tools (fleet-wide)')),
                        PopupMenuItem(value: 'admin', child: Text('admin — admin console (no role minting)')),
                        PopupMenuItem(value: 'cfo', child: Text('cfo — finances (payroll, tax, books; no money moves)')),
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
    AppToast.show(context, res.ok ? 'Branch added.' : 'Failed: ${res.error}');
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
                  onPressed: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (d) => AlertDialog(
                        title: const Text('Delete branch?'),
                        content: Text('Remove "${b['name'] ?? 'this branch'}"? This cannot be undone.'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
                          FilledButton(style: FilledButton.styleFrom(backgroundColor: const Color(0xFFB3261E)), onPressed: () => Navigator.pop(d, true), child: const Text('Delete')),
                        ],
                      ),
                    );
                    if (ok != true) return;
                    await DropOffApi.delete('/admin/branches/${b['id']}', body: {});
                    _loadBranches();
                  },
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

/// Ops chargebook capture: the staff/ops side of the DropOff leg chargebook —
/// door → depot first-mile runs (e.g. Kabulonga → Platinum) and collections
/// (depot → door). Locations come from what app users actually type (most-used
/// first), with free typing allowed; depots come from the live courier list.
/// Every entry is keyed to the depot courier it belongs to so ops can read
/// leg coverage per courier. No counter fares are published to sellers here.
class _CounterQuoteCard extends StatefulWidget {
  const _CounterQuoteCard();

  @override
  State<_CounterQuoteCard> createState() => _CounterQuoteCardState();
}

class _CounterQuoteCardState extends State<_CounterQuoteCard> {
  List<Map<String, dynamic>> _couriers = const [];
  List<Map<String, dynamic>> _quotes = const [];
  List<String> _localities = const [];
  int? _courierId;
  String _leg = 'dropoff'; // 'dropoff' (door → depot) | 'collection' (depot → door)
  String _weight = '0-5kg';
  final _price = TextEditingController();
  TextEditingController? _autoCtl;
  bool _busy = false;
  String? _error;

  static const _weights = ['0-5kg', '5-15kg', '15kg+'];
  /// Fallback area suggestions when no user-typed addresses are on file yet.
  static const _fallbackLocalities = [
    'Kabulonga', 'Makeni', 'Woodlands', 'Emmasdale', 'Mass Media', 'Chelston',
    'Garden', 'Chilenje', 'Kalingalinga', 'Matero', 'Misisi', 'Zingalume',
    'Chilanga', 'Chongwe', 'Kafue', 'Chelanga', 'Riverside',
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _price.dispose();
    _autoCtl?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final couriers = await DropOffApi.couriers();
    final quotes = await DropOffApi.adminQuotes();
    final localities = await DropOffApi.adminLocalities();
    if (!mounted) return;
    setState(() {
      _couriers = couriers;
      _quotes = quotes;
      _localities = localities.isEmpty ? _fallbackLocalities : localities;
      if (_courierId == null && couriers.isNotEmpty) {
        _courierId = (couriers.first['id'] as num?)?.toInt();
      }
    });
  }

  Map<String, dynamic>? get _depot =>
      _couriers.where((c) => (c['id'] as num?)?.toInt() == _courierId).firstOrNull;

  String get _depotLabel {
    final d = _depot;
    if (d == null) return '';
    return '${d['name']} (${d['city'] ?? ''})';
  }

  Future<void> _save() async {
    final price = double.tryParse(_price.text.trim());
    final locality = (_autoCtl?.text ?? '').trim();
    if (_courierId == null) return _msg('Pick the depot first.');
    if (locality.length < 3) return _msg('Type the customer locality, e.g. Kabulonga.');
    if (price == null || price <= 0) return _msg('Enter the DropOff leg fee in Kwacha, e.g. 55.');
    setState(() { _busy = true; _error = null; });
    final res = await DropOffApi.upsertQuote(
      courierId: _courierId!,
      fromCity: _leg == 'dropoff' ? locality : _depotLabel,
      toCity: _leg == 'dropoff' ? _depotLabel : locality,
      weightClass: _weight,
      service: _leg,
      counterPriceZmw: price,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (!res.ok) {
      _msg(res.body['detail']?.toString() ?? 'Could not save (${res.error ?? 'network'}).');
      return;
    }
    final recorded = _fromToText;
    _price.clear();
    _autoCtl?.clear();
    AppToast.show(context,
        'Chargebook updated — $recorded now shows the recorded ${_leg == 'dropoff' ? 'drop-off' : 'collection'} leg fee.');
    await _load();
  }

  String get _fromToText {
    final locality = (_autoCtl?.text ?? '').trim();
    return _leg == 'dropoff' ? '$locality → $_depotLabel' : '$_depotLabel → $locality';
  }

  void _msg(String m) {
    if (!mounted) return;
    setState(() => _error = m);
  }

  String _legBadge(Map<String, dynamic> q) {
    final s = '${q['service'] ?? ''}';
    if (s == 'dropoff') return 'drop-off leg';
    if (s == 'collection') return 'collection';
    return s;
  }

  Widget _depotField(String label) => DropdownButtonFormField<int>(
        initialValue: _courierId,
        isExpanded: true,
        decoration: InputDecoration(labelText: label, isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
        items: [for (final c in _couriers)
          DropdownMenuItem(value: (c['id'] as num?)?.toInt(), child: Text('${c['name']} — ${c['city'] ?? ''}', overflow: TextOverflow.ellipsis))],
        onChanged: (v) => setState(() => _courierId = v),
      );

  Widget _localityField(String label) => Autocomplete<String>(
        optionsBuilder: (value) {
          final q = value.text.trim().toLowerCase();
          if (q.isEmpty) return _localities.take(15);
          return _localities.where((l) => l.toLowerCase().contains(q));
        },
        fieldViewBuilder: (ctx, ctl, focusNode, onSubmit) {
          _autoCtl = ctl;
          return TextField(
            controller: ctl,
            focusNode: focusNode,
            onSubmitted: (_) => onSubmit(),
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(labelText: label, isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
          );
        },
        optionsMaxHeight: 220,
        onSelected: (v) => _autoCtl?.text = v,
      );

  @override
  Widget build(BuildContext context) {
    final coverage = _quotes.length;
    final localityLabel = _leg == 'dropoff' ? 'From (customer locality)' : 'To (customer locality)';
    final depotLabel = _leg == 'dropoff' ? 'To (depot)' : 'From (depot)';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.menu_book_outlined, size: 18, color: AppColors.forest),
            const SizedBox(width: 8),
            Expanded(child: Text('Chargebook — DropOff legs ($coverage on file)',
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15))),
          ]),
          const SizedBox(height: 6),
          const Text(
            'First-mile door → depot runs and collections depot → door. '
            'E.g. door → depot: Kabulonga → Platinum (Lusaka) — our rider fee for that leg. '
            'E.g. depot → door: Icypeed (Lusaka) → Kabulonga — our collection fee. '
            'No counter fares here — depot fares stay at the counter. Locations come from what app users type (most used shown).',
            style: TextStyle(color: AppColors.muted, fontSize: 11.5, height: 1.4),
          ),
          const SizedBox(height: 12),
          Wrap(spacing: 8, children: [
            ChoiceChip(
              label: const Text('Door → depot (drop-off)'),
              selected: _leg == 'dropoff',
              onSelected: (_) => setState(() { _leg = 'dropoff'; _autoCtl = null; }),
            ),
            ChoiceChip(
              label: const Text('Depot → door (collection)'),
              selected: _leg == 'collection',
              onSelected: (_) => setState(() { _leg = 'collection'; _autoCtl = null; }),
            ),
          ]),
          const SizedBox(height: 12),
          if (_couriers.isEmpty)
            const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('Loading depots…', style: TextStyle(color: AppColors.muted, fontSize: 12)))
          else ...[
            Row(children: [
              Expanded(child: _leg == 'dropoff'
                  ? _localityField(localityLabel)
                  : _depotField(depotLabel)),
              const Padding(padding: EdgeInsets.symmetric(horizontal: 6), child: Icon(Icons.arrow_forward, size: 16, color: AppColors.muted)),
              Expanded(child: _leg == 'dropoff'
                  ? _depotField(depotLabel)
                  : _localityField(localityLabel)),
            ]),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: _weight,
              decoration: const InputDecoration(labelText: 'Parcel size', isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
              items: [for (final w in _weights) DropdownMenuItem(value: w, child: Text(w))],
              onChanged: (v) => setState(() => _weight = v ?? _weight),
            ),
            const SizedBox(height: 10),
            TextField(controller: _price, keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'DropOff leg fee (ZMW)', prefixText: 'K ', hintText: 'e.g. 55')),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
            ],
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _busy ? null : _save,
              icon: _busy
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.save_outlined),
              label: Text(_busy ? 'Saving…' : 'Save to chargebook'),
            ),
            if (_quotes.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text('Latest entries', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: AppColors.muted)),
              const SizedBox(height: 6),
              ..._quotes.take(5).map((q) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(children: [
                  if (q['stale'] == 1)
                    const Padding(
                      padding: EdgeInsets.only(right: 4),
                      child: Icon(Icons.warning_amber_rounded, size: 13, color: Colors.orangeAccent),
                    ),
                  Expanded(
                    child: Text(
                      '${q['courier_name']} · ${q['from_city']} → ${q['to_city']} · ${q['weight_class']} · K${q['counter_price_zmw']}'
                      ' · ${_legBadge(q)} · ${q['source'] == 'recorded' ? 'recorded at source' : 'ops'}'
                      "${q['stale'] == 1 ? ' · STALE — reconfirm' : ''}",
                      style: TextStyle(
                        fontSize: 11.5,
                        color: q['stale'] == 1 ? Colors.orangeAccent.shade700 : AppColors.muted,
                      ),
                    ),
                  ),
                ]),
              )),
            ],
          ],
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
  List<Map<String, dynamic>> _history = const [];
  bool _loadingHistory = false;
  String _filter = 'all';

  static const Map<String, String> _labels = {
    'weekly': 'Weekly Sprint',
    'silver': 'Silver',
    'gold': 'Gold',
    'platinum': 'Platinum',
  };

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    setState(() => _loadingHistory = true);
    final res = await DropOffApi.packCodes();
    if (!mounted) return;
    setState(() {
      _loadingHistory = false;
      _history = (res?['codes'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    });
  }

  void _copy(String code) {
    Clipboard.setData(ClipboardData(text: code));
    AppToast.show(context, '$code copied.');
  }

  Future<void> _generate() async {
    setState(() => _busy = true);
    final res = await DropOffApi.generatePackCodes(tier: _tier, count: _count, note: _note.text.trim());
    if (!mounted) return;
    setState(() => _busy = false);
    if (!res.ok) {
      AppToast.show(context, 'Could not generate codes (${res.error}).');
      return;
    }
    final codes = ((res.body['codes'] as List?) ?? const []).map((c) => '$c').toList();
    final persisted = ((res.body['persisted_codes'] as List?) ?? const []).cast<Map<String, dynamic>>();
    setState(() {
      _codes = codes;
      if (persisted.isNotEmpty) _history = persisted;
    });
    AnalyticsService.instance.track(
      feature: 'pack_codes', action: 'generate', context: 'admin_pack_codes',
      meta: {'tier': _tier, 'count': codes.length},
    );
    if (codes.isEmpty) {
      AppToast.show(context, 'No codes generated - try again.');
    } else {
      AppToast.show(context, '${codes.length} code${codes.length == 1 ? '' : 's'} generated.');
    }
    await _loadHistory();
  }

  void _copyAll() {
    if (_codes.isEmpty) return;
    Clipboard.setData(ClipboardData(text: _codes.join('\n')));
    AppToast.show(context, '${_codes.length} code${_codes.length == 1 ? '' : 's'} copied.');
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
          const Text('Sell plans at the counter or to agents. The seller redeems the code in the app — no payment prompt, the plan goes live instantly.', style: TextStyle(color: AppColors.muted, fontSize: 11.5, height: 1.4)),
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
            label: Text(_busy ? 'Generating…' : 'Generate $_count ${_labels[_tier]} code${_count == 1 ? '' : 's'}'),
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
          const SizedBox(height: 14),
          Row(children: [
            const Expanded(child: Text('Code history', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13))),
            TextButton(onPressed: _loadingHistory ? null : _loadHistory, child: const Text('Refresh')),
          ]),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final f in const ['all', 'unused', 'active', 'used', 'expired'])
              ChoiceChip(
                selected: _filter == f,
                label: Text(f[0].toUpperCase() + f.substring(1)),
                onSelected: (v) => setState(() => _filter = f),
              ),
          ]),
          const SizedBox(height: 8),
          if (_loadingHistory)
            const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))))
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: ListView(
                shrinkWrap: true,
                physics: const ClampingScrollPhysics(),
                children: _history
                    .where((c) => _filter == 'all' || (c['status'] as String? ?? '') == _filter)
                    .map((c) {
                  final code = '${c['code'] ?? ''}';
                  final status = '${c['status'] ?? ''}';
                  final usedBy = '${c['redeemed_name'] ?? c['used_by'] ?? ''}';
                  final color = status == 'active'
                      ? AppColors.success
                      : status == 'expired'
                          ? AppColors.danger
                          : status == 'used'
                              ? AppColors.warning
                              : AppColors.muted;
                  return Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.line)),
                    child: Row(children: [
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(code, style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w800, fontSize: 12.5, letterSpacing: 1.0, color: AppColors.ink)),
                        const SizedBox(height: 2),
                        Text('${c['tier']} • ${c['cycle_days']}d${c['note'] != null && '${c['note']}'.isNotEmpty ? ' • ${c['note']}' : ''}', style: const TextStyle(color: AppColors.muted, fontSize: 10.5)),
                        if (usedBy.isNotEmpty)
                          Text('Redeemed by $usedBy ${c['redeemed_email'] != null ? '(${c['redeemed_email']})' : ''} • ${c['used_at']}', style: const TextStyle(color: AppColors.muted, fontSize: 10.5)),
                      ])),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20)),
                        child: Text(status.toUpperCase(), style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w900)),
                      ),
                      const SizedBox(width: 6),
                      IconButton(icon: const Icon(Icons.copy, size: 16), onPressed: () => _copy(code), tooltip: 'Copy'),
                    ]),
                  );
                }).toList(),
              ),
            ),
        ]),
      ),
    );
  }
}

/// Owner/admin console: full plans editor (duration, limits, price, discount,
/// tag, active) + courier availability toggles. A hidden plan/courier stops
/// showing up for sellers immediately; existing subscribers keep their cycle
/// benefit (server-side). Nothing here holds money — it changes the offer.
class _PlansAndCouriersCard extends StatefulWidget {
  const _PlansAndCouriersCard();

  @override
  State<_PlansAndCouriersCard> createState() => _PlansAndCouriersCardState();
}

class _PlansAndCouriersCardState extends State<_PlansAndCouriersCard> {
  bool _loading = false;
  String? _error;
  List<Map<String, dynamic>> _plans = const [];
  List<Map<String, dynamic>> _couriers = const [];

  static const _tierLabels = {
    'rider_daily': 'Daily Rider',
    'weekly': 'Weekly Sprint',
    'silver': 'Silver',
    'gold': 'Gold',
    'platinum': 'Platinum',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final tiers = await DropOffApi.adminTiers();
    final couriers = await DropOffApi.adminCouriers();
    if (!mounted) return;
    setState(() {
      _plans = ((tiers?['tiers'] as List?) ?? const []).cast<Map<String, dynamic>>();
      _couriers = ((couriers?['couriers'] as List?) ?? const []).cast<Map<String, dynamic>>();
      _error = tiers == null ? 'Plans/courier catalogue needs an admin sign-in on this device.' : null;
      _loading = false;
    });
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _togglePlan(Map<String, dynamic> t, bool on) async {
    final res = await DropOffApi.adminSaveTier({'tier': t['tier'], 'active': on ? 1 : 0});
    if (!mounted) return;
    _snack(res.ok ? 'Plan ${on ? 'ON' : 'OFF'} — ${_tierLabels['${t['tier']}'] ?? t['tier']}' : 'Could not toggle plan (${res.error ?? 'try again'})');
    await _load();
  }

  Future<void> _toggleCourier(Map<String, dynamic> c, bool on) async {
    final res = await DropOffApi.adminCourierToggle((c['id'] as num).toInt(), on);
    if (!mounted) return;
    _snack(res.ok ? 'Courier ${on ? 'ON' : 'OFF'} — ${c['name']}' : 'Could not toggle courier (${res.error ?? 'try again'})');
    await _load();
  }

  String _planSubtitle(Map<String, dynamic> t) {
    final ppd = (t['parcels_per_day'] as num?)?.toInt() ?? 0;
    final ppm = (t['parcels_per_month'] as num?)?.toInt() ?? 0;
    final cap = ppd > 0 ? '$ppd parcel${ppd == 1 ? '' : 's'}/day' : (ppm > 0 ? '$ppm parcels/month' : 'no cap');
    final cycle = (t['cycle_days'] as num?)?.toInt() ?? 0;
    final disc = (t['overage_discount_pct'] as num?)?.toDouble() ?? 0;
    final fee = (t['fee_zmw'] as num?)?.toDouble() ?? 0;
    return 'K${fee.toStringAsFixed(0)} • $cap • ${cycle}d cycle${disc > 0 ? ' • ${disc.toStringAsFixed(0)}% overage discount' : ''}';
  }

  Future<void> _editPlan(Map<String, dynamic> t) async {
    final fee = TextEditingController(text: '${(t['fee_zmw'] as num?)?.toDouble() ?? 0}');
    final ppd = TextEditingController(text: '${(t['parcels_per_day'] as num?)?.toInt() ?? 0}');
    final ppm = TextEditingController(text: '${(t['parcels_per_month'] as num?)?.toInt() ?? 0}');
    final rider = TextEditingController(text: '${(t['rider_fee_zmw'] as num?)?.toDouble() ?? 0}');
    final disc = TextEditingController(text: '${(t['overage_discount_pct'] as num?)?.toDouble() ?? 0}');
    final days = TextEditingController(text: '${(t['cycle_days'] as num?)?.toInt() ?? 30}');
    final tag = TextEditingController(text: '${t['tag'] ?? ''}');
    var active = (t['active'] == true || t['active'] == 1);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Edit plan — ${_tierLabels['${t['tier']}'] ?? t['tier']}',
            style: const TextStyle(fontWeight: FontWeight.w900)),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: fee, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Fee per cycle (K)')),
            TextField(controller: ppd, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Parcels per day (0 = monthly plan)')),
            TextField(controller: ppm, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Parcels per month (0 = none)')),
            TextField(controller: rider, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Rider fee inside cap (0 = bundled)')),
            TextField(controller: disc, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Overage discount %')),
            TextField(controller: days, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Cycle length (days)')),
            TextField(controller: tag, decoration: const InputDecoration(labelText: 'Tag (shown in the app)', hintText: 'e.g. Most popular')),
            StatefulBuilder(
              builder: (ctx2, setDialog) => SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('Plan active (visible for sale)'),
                value: active,
                onChanged: (v) => setDialog(() => active = v),
              ),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final res = await DropOffApi.adminSaveTier({
                'tier': t['tier'],
                'fee_zmw': double.tryParse(fee.text.trim()) ?? 0,
                'parcels_per_day': int.tryParse(ppd.text.trim()) ?? 0,
                'parcels_per_month': int.tryParse(ppm.text.trim()) ?? 0,
                'rider_fee_zmw': double.tryParse(rider.text.trim()) ?? 0,
                'overage_discount_pct': double.tryParse(disc.text.trim()) ?? 0,
                'cycle_days': int.tryParse(days.text.trim()) ?? 30,
                'tag': tag.text.trim().isEmpty ? null : tag.text.trim(),
                'active': active ? 1 : 0,
              });
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              if (mounted) {
                _snack(res.ok ? 'Plan saved' : 'Save failed (${res.error ?? 'try again'})');
                await _load();
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.tune, size: 19, color: AppColors.forest),
            const SizedBox(width: 8),
            const Expanded(child: Text('Plans & couriers (owner)',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15))),
            IconButton(
              tooltip: 'Refresh',
              icon: _loading
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.refresh, size: 20),
              onPressed: _loading ? null : _load,
            ),
          ]),
          const SizedBox(height: 2),
          const Text('Off hides the offer from sellers instantly (new subscriptions stop; existing subscribers keep their cycle benefit). Edit every field below — price, parcels/day, parcels/month, cycle length, discount, tag.',
              style: TextStyle(color: AppColors.muted, fontSize: 11.5, height: 1.4)),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: const TextStyle(color: AppColors.danger, fontSize: 11.5))),
          const SizedBox(height: 10),
          for (final t in _plans)
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.line)),
              child: Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_tierLabels['${t['tier']}'] ?? '${t['tier']}',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                  const SizedBox(height: 2),
                  Text(_planSubtitle(t), style: const TextStyle(color: AppColors.muted, fontSize: 10.5)),
                ])),
                Switch(
                  value: t['active'] == true || t['active'] == 1,
                  onChanged: (v) => _togglePlan(t, v),
                ),
                TextButton(onPressed: () => _editPlan(t), child: const Text('Edit')),
              ]),
            ),
          const Divider(height: 24),
          Row(children: [
            const Icon(Icons.local_shipping_outlined, size: 16, color: AppColors.forest),
            const SizedBox(width: 6),
            const Text('Couriers — availability for sellers', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
          ]),
          const SizedBox(height: 8),
          for (final c in _couriers)
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.line)),
              child: Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${c['name']}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
                  const SizedBox(height: 2),
                  Text('${c['city'] ?? ''}${c['depot_name'] != null ? ' • ${c['depot_name']}' : ''} • id ${c['id']}',
                      style: const TextStyle(color: AppColors.muted, fontSize: 10.5), maxLines: 1, overflow: TextOverflow.ellipsis),
                ])),
                Switch(
                  value: c['active'] == true || c['active'] == 1,
                  onChanged: (v) => _toggleCourier(c, v),
                ),
              ]),
            ),
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
  bool _showAll = false;
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
        if (mounted) AppToast.show(context, 'A rejection reason is required.');
        return;
      }
    }
    setState(() => _busy = 'verify-$id');
    final res = await DropOffApi.adminVerifyRider(id, status: status, note: note);
    if (!mounted) return;
    setState(() => _busy = null);
    AppToast.show(context, res.ok
        ? (status == 'verified' ? 'Driver verified.' : 'Driver rejected.')
        : 'Could not update (${res.error}).');
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
      AppToast.show(context, 'AI check failed (${res.error}).');
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
    final faceMatch = (res.body['face_match'] as Map?)?.cast<String, dynamic>();
    final faceVerdict = '${face?['verdict'] ?? ''}';
    final faceNote = '${face?['note'] ?? ''}';
    final faceColor = faceVerdict == 'pass' ? AppColors.forest : const Color(0xFFB3261E);
    final matchSame = '${faceMatch?['same_person'] ?? ''}';
    final matchLabel = matchSame == 'yes' ? 'SAME PERSON' : matchSame == 'no' ? 'DIFFERENT' : 'UNCERTAIN';
    final matchColor = matchSame == 'yes' ? AppColors.forest : matchSame == 'no' ? const Color(0xFFB3261E) : const Color(0xFF8A5A00);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('AI KYC identity check'),
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
          if (faceMatch != null) ...[
            const SizedBox(height: 4),
            Text('Selfie vs ID portrait: $matchLabel  (${faceMatch['confidence'] ?? 'low'} confidence)',
                style: TextStyle(fontWeight: FontWeight.w800, color: matchColor)),
            if ('${faceMatch['note'] ?? ''}'.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text('AI note: ${faceMatch['note']}', style: const TextStyle(color: AppColors.muted, fontSize: 11, height: 1.3)),
              ),
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
            const Expanded(child: Text('Rider verification & targets', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15))),
            IconButton(visualDensity: VisualDensity.compact, onPressed: _load, icon: const Icon(Icons.refresh, size: 18)),
          ]),
          Text('$pending pending review - $verified verified. Daily target is 30 parcels; month pace carries any missed day.',
              style: const TextStyle(color: AppColors.muted, fontSize: 11.5, height: 1.4)),
          const SizedBox(height: 12),
          Wrap(spacing: 6, runSpacing: 6, children: [
            ChoiceChip(selected: !_showAll, label: Text('Pending only ($pending)'), onSelected: (v) => setState(() => _showAll = !v)),
            ChoiceChip(selected: _showAll, label: Text('All riders (${_riders.length})'), onSelected: (v) => setState(() => _showAll = v)),
          ]),
          const SizedBox(height: 8),
          if (_loading)
            const Padding(padding: EdgeInsets.symmetric(vertical: 14), child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))))
          else if (_riders.isEmpty)
            const Text('No riders registered yet.', style: TextStyle(color: AppColors.muted, fontSize: 12))
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 480),
              child: ListView(
                shrinkWrap: true,
                physics: const ClampingScrollPhysics(),
                children: [
                  for (final rider in (_showAll ? _riders : _riders.where((r) => '${r['verification_status']}' == 'pending'))) ...[
              Container(
                key: ValueKey('rider-${rider['id']}'),
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
                ],
              ),
            ),
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

/// High-value KPI for the admin console, in two layers:
///  A) OPERATIONAL — GET /admin/analytics/ops: the real work, computed from
///     the operational tables (jobs/events/payments/float/subscriptions):
///     parcels booked/delivered today & 30d, active sellers/riders, PAYG vs
///     float money, MoMo success rate. Always real, never telemetry-fuzzy.
///  B) APP USAGE — GET /admin/analytics/kpi: telemetry (screens, features,
///     funnel, DAU) — as good as the outbox; kept secondary on purpose.
class _AnalyticsKpiCard extends StatefulWidget {
  const _AnalyticsKpiCard();

  @override
  State<_AnalyticsKpiCard> createState() => _AnalyticsKpiCardState();
}

class _AnalyticsKpiCardState extends State<_AnalyticsKpiCard> {
  Map<String, dynamic>? _ops;
  Map<String, dynamic>? _usage;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final results = await Future.wait([
      DropOffApi.getAdmin('/admin/analytics/ops?days=30'),
      DropOffApi.getAdmin('/admin/analytics/kpi?days=30'),
    ]);
    if (!mounted) return;
    setState(() {
      _ops = results[0];
      _usage = results[1];
      _loading = false;
    });
  }

  /// GET /admin/analytics/kpi may ship `by_role` either as a map
  /// ({admin: 123} or {admin: {n: 123, users: 45}}) or as a list of
  /// {role, n} rows — normalise both shapes; returns [] when absent/odd.
  List<MapEntry<String, num>> _roleEntries(Object? raw) {
    final out = <MapEntry<String, num>>[];
    if (raw is Map) {
      raw.forEach((k, v) {
        if (v is num) {
          out.add(MapEntry('$k', v));
        } else if (v is Map && v['n'] is num) {
          out.add(MapEntry('$k', v['n'] as num));
        }
      });
    } else if (raw is List) {
      for (final e in raw) {
        if (e is! Map) continue;
        final role = '${e['role'] ?? ''}'.trim();
        final n = e['n'] ?? e['events'] ?? e['users'];
        if (role.isEmpty || n is! num) continue;
        out.add(MapEntry(role, n));
      }
    }
    out.sort((a, b) => b.value.compareTo(a.value));
    return out;
  }

  static String _fmtCount(num n) => n == n.roundToDouble() ? n.toInt().toString() : n.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final ops = _ops;
    final kpi = _usage;
    final total = kpi?['total_events'] as num? ?? 0;
    final features = ((kpi?['top_features'] as List?) ?? const [])
        .cast<Map<String, dynamic>>();
    final funnel = ((kpi?['funnel'] as List?) ?? const [])
        .cast<Map<String, dynamic>>();
    final dau = ((kpi?['dau'] as List?) ?? const [])
        .cast<Map<String, dynamic>>();
    final screens = ((kpi?['top_screens'] as List?) ?? const [])
        .cast<Map<String, dynamic>>();
    final roles = _roleEntries(kpi?['by_role']);
    String zmw(num? v) {
      final d = (v ?? 0).toDouble();
      return 'K${d.toStringAsFixed(d == d.roundToDouble() ? 0 : 2)}';
    }
    String pct(num? v) => v == null ? '—' : '${v.toStringAsFixed(1)}%';
    final deliveryPct = ops?['delivery_rate_pct'] as num?;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.insights_outlined, color: AppColors.forest),
            const SizedBox(width: 8),
            const Expanded(child: Text('KPI — last 30 days', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15))),
            TextButton.icon(
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 10)),
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh, size: 17),
              label: const Text('Refresh', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
            ),
          ]),
          const SizedBox(height: 12),
          if (_loading)
            const Padding(padding: EdgeInsets.symmetric(vertical: 14), child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))))
          else ...[
            const Text('Operations — the real work (live data)', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: AppColors.muted)),
            const SizedBox(height: 6),
            if (ops == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 6),
                child: Text('Could not load operational KPIs — worker endpoint /admin/analytics/ops may not be deployed yet.', style: TextStyle(color: AppColors.muted, fontSize: 12, height: 1.4)),
              )
            else ...[
              Row(children: [
                Expanded(child: _KpiMetric('Booked', '${ops['parcels_booked'] ?? 0} · ${ops['parcels_booked_today'] ?? 0} today', Icons.inventory_2_outlined)),
                const SizedBox(width: 8),
                Expanded(child: _KpiMetric('Delivered', '${ops['deliveries'] ?? 0} · ${ops['deliveries_today'] ?? 0} today', Icons.local_shipping_outlined)),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: _KpiMetric('Active sellers', '${ops['active_sellers'] ?? 0}', Icons.storefront_outlined)),
                const SizedBox(width: 8),
                Expanded(child: _KpiMetric('Riders', '${ops['active_riders'] ?? 0} worked · ${ops['riders_on_books'] ?? 0} on books', Icons.two_wheeler)),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: _KpiMetric('PAYG collected', zmw(ops['payg_collected_zmw'] as num?), Icons.payments_outlined)),
                const SizedBox(width: 8),
                Expanded(child: _KpiMetric('Float charges', zmw(ops['wallet_charges_zmw'] as num?), Icons.point_of_sale_outlined)),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: _KpiMetric('MoMo success', pct(ops['momo_success_pct'] as num?), Icons.phone_android_outlined)),
                const SizedBox(width: 8),
                Expanded(child: _KpiMetric('Subs active', '${ops['subscriptions_active'] ?? 0}', Icons.workspace_premium_outlined)),
              ]),
              const SizedBox(height: 6),
              Text('Delivery rate ${deliveryPct == null ? '—' : '${deliveryPct.toStringAsFixed(1)}%'} · Pickups ${ops['pickups'] ?? 0} · Parcels shipped ${ops['parcels_shipped'] ?? 0} · Chargebook routes learned ${ops['chargebook_routes_learned'] ?? 0} · Float jobs ${ops['wallet_charge_jobs'] ?? 0}',
                  style: const TextStyle(color: AppColors.muted, fontSize: 11)),
            ],
            const SizedBox(height: 14),
            const Text('App usage — telemetry', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: AppColors.muted)),
            const SizedBox(height: 6),
            if (kpi == null)
              const Text('Could not load usage telemetry (GET /admin/analytics/kpi).', style: TextStyle(color: AppColors.muted, fontSize: 12))
            else if (total == 0 && features.isEmpty)
              const Text('No usage events yet — they flush every 5 minutes while the app is open. Check back after the next use.', style: TextStyle(color: AppColors.muted, fontSize: 12, height: 1.4))
            else ...[
              Row(children: [
                Expanded(child: _KpiMetric('Events', '$total', Icons.event_note)),
                Expanded(child: _KpiMetric('Features', '${features.length}', Icons.apps)),
                Expanded(child: _KpiMetric('Active days', '${dau.length}', Icons.today)),
              ]),
              const SizedBox(height: 10),
              const Text('Most used features', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: AppColors.muted)),
              const SizedBox(height: 6),
              ...features.take(6).map((f) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(children: [
                  Expanded(child: Text('${f['feature']}', style: const TextStyle(fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis)),
                  Text('${f['n']}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: AppColors.forest)),
                  const SizedBox(width: 6),
                  Text('${f['users']} users', style: const TextStyle(color: AppColors.muted, fontSize: 11)),
                ]),
              )),
              const SizedBox(height: 8),
              const Text('Most visited screens', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: AppColors.muted)),
              const SizedBox(height: 6),
              if (screens.isEmpty)
                const Text('No screen views recorded yet.', style: TextStyle(color: AppColors.muted, fontSize: 12))
              else
                ...screens.take(6).map((s) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(children: [
                    Expanded(child: Text('${s['screen'] ?? 'unknown'}', style: const TextStyle(fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis)),
                    Text('${s['n'] ?? 0}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: AppColors.forest)),
                    const SizedBox(width: 6),
                    Text('${s['users'] ?? 0} users', style: const TextStyle(color: AppColors.muted, fontSize: 11)),
                  ]),
                )),
              if (roles.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 6, children: [
                  for (final r in roles.take(6))
                    Chip(
                      visualDensity: VisualDensity.compact,
                      label: Text('${r.key} · ${_fmtCount(r.value)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                    ),
                ]),
              ],
              const SizedBox(height: 8),
              const Text('Conversion funnel (unique users)', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: AppColors.muted)),
              const SizedBox(height: 6),
              ...funnel.take(5).map((f) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(children: [
                  Expanded(child: Text('${f['feature']}', style: const TextStyle(fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis)),
                  Text('${f['users']}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: AppColors.forest)),
                ]),
              )),
            ],
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
          Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, color: AppColors.muted, fontWeight: FontWeight.w700))),
        ]),
        const SizedBox(height: 6),
        Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: AppColors.forest)),
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

/// Tiny sender avatar for support-ticket bubbles (the account photo, or initials).
class _SheetAvatar extends StatelessWidget {
  const _SheetAvatar({this.photoUrl, required this.label, required this.mine});
  final String? photoUrl;
  final String label;
  final bool mine;

  String get _initials {
    final parts = label.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    return parts.take(2).map((w) => w[0].toUpperCase()).join();
  }

  @override
  Widget build(BuildContext context) {
    const radius = 14.0;
    final bg = mine ? AppColors.forest.withValues(alpha: 0.25) : AppColors.line.withValues(alpha: 0.6);
    if (photoUrl == null || photoUrl!.isEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: bg,
        child: Text(_initials,
            style: const TextStyle(fontSize: 8.5, fontWeight: FontWeight.w900, color: AppColors.forest)),
      );
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: bg,
      child: ClipOval(
        child: Image.network(
          '${DropOffApi.baseUrl}$photoUrl',
          headers: DropOffApi.authHeaders,
          width: radius * 2,
          height: radius * 2,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Text(_initials,
              style: const TextStyle(fontSize: 8.5, fontWeight: FontWeight.w900, color: AppColors.forest)),
        ),
      ),
    );
  }
}
