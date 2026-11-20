import '../ui/app_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:share_plus/share_plus.dart';

import '../data/dropoff_api.dart';
import '../data/analytics_service.dart';
import '../ui/app_theme.dart';
import '../ui/app_spinner.dart';

/// Admin console inside the app: live business stats, security
/// alerts, the fraud queue, depot branches, and SMS broadcasts. The screen
/// re-checks GET /me on open — a sender who deep-links here gets a lock door.
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
      _superadmin = role == 'admin';
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
        body: const Center(child: AppLogoSpinner(size: 26)),
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
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_financeOnly ? 'Finance (CFO)' : 'Operations overview', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: AppColors.forest)),
                  const SizedBox(height: 2),
                  Text(_financeOnly
                      ? 'Salaries, turnover, payroll run-rate and ZRA filings. Two signatures release money.'
                      : 'Live stats, security, fraud, depot branches and messaging.',
                      style: const TextStyle(color: AppColors.ink, fontSize: 12.5, height: 1.35)),
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
              const SizedBox(height: 18),
              const _PayoutQueueCard(),
              const SizedBox(height: 18),
              const _ClientCrashesCard(),
              const SizedBox(height: 18),
              const _UsersCard(),
              const SizedBox(height: 18),
              const _PackCodesCard(),
              const SizedBox(height: 18),
              const _PlansAndCouriersCard(),
              const SizedBox(height: 18),
              const _IncentivePromoCard(),
              const SizedBox(height: 18),
              const _RiderVerificationAdminCard(),
              const SizedBox(height: 18),
              const _BranchManagerCard(),
              const SizedBox(height: 18),
              const _BookingDeleteCard(),
              const SizedBox(height: 18),
              const _BookingStrikesCard(),
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
            const Text('Active plans', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: AppColors.ink)),
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
              const Text('No alerts. Quiet is good.', style: TextStyle(color: AppColors.ink, fontSize: 12.5)),
            for (final a in _alerts.take(10))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(a['severity'] == 'high' || a['severity'] == 'critical' ? Icons.error_outline : Icons.info_outline,
                      size: 17, color: a['severity'] == 'high' || a['severity'] == 'critical' ? AppColors.danger : AppColors.muted),
                  const SizedBox(width: 8),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${a['type']} · ${a['phone']}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
                    Text('${a['detail']}', style: AppType.caption),
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
              const Text('Nothing flagged.', style: TextStyle(color: AppColors.ink, fontSize: 12.5)),
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
          const Row(children: [
            Icon(Icons.payments_outlined, color: AppColors.forest),
            SizedBox(width: 8),
            Expanded(child: Text('Salaries — as the business grows', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15))),
          ]),
          const SizedBox(height: 6),
          const Text('K3,000/rider/month incl. K300/week fuel (K1,800 base), weekly K750 per Light cycle. Pace-gated by delivery. This is the real cost of your roster.',
              style: AppType.caption),
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
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: (share ?? 0) <= 25 ? AppColors.forest : (share ?? 100) <= 50 ? AppColors.warning : AppColors.danger)),
            ),
          ],
          const SizedBox(height: 4),
          Text('A full-time rider pays for themselves at ~$sustain PAYG trips/day (K45 each). Plans speed up the cash equation — but trips, not promos, measure pace.',
              style: AppType.caption),
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

  /// Every payout row's money moves only after admin intent → second-admin release.
  Widget _payrollCard({bool financeOnly = false}) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.badge_outlined, color: AppColors.forest),
              const SizedBox(width: 8),
              const Expanded(child: Text('Rider payroll (K3,000/mo)', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15))),
              if (financeOnly)
                const Chip(visualDensity: VisualDensity.compact, label: Text('CFO view', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800))),
            ]),
            const SizedBox(height: 6),
            const Text('Auto-generated: weekly Sun 16:00 CAT, monthly on the 1st. Two signatures release the money.',
                style: TextStyle(color: AppColors.muted, fontSize: 11.5)),
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
      case 'admin_confirmed': return 'awaiting second admin';
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
            const Text('Turnover = DropOff income only (jobs + prepaid delivery legs + plans + COD cut). 0% up to K2,500/month, 5% above. File by the 14th of the next month.',
                style: TextStyle(color: AppColors.muted, fontSize: 11.5)),
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
              const Text('No open chat reports.', style: TextStyle(color: AppColors.ink, fontSize: 12.5)),
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
                      style: const TextStyle(fontSize: 12.5, color: AppColors.ink),
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
            const Row(children: [
              Icon(Icons.campaign_outlined, color: AppColors.forest),
              SizedBox(width: 8),
              Expanded(child: Text('Push — marketing broadcast', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15))),
            ]),
            const SizedBox(height: 4),
            const Text('Push an offer to app users by audience. Title ≤ 80 chars, body ≤ 140 chars. Delivered on devices that previously signed in to the app.',
                style: AppType.caption),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: _pushAudience,
              decoration: const InputDecoration(labelText: 'Audience', prefixIcon: Icon(Icons.groups_outlined)),
              items: const [
                DropdownMenuItem(value: 'accounts', child: Text('Registered accounts')),
                DropdownMenuItem(value: 'sellers', child: Text('All senders (booked before)')),
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
                  border: const Border(left: BorderSide(color: AppColors.amber, width: 3)),
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
                DropdownMenuItem(value: 'sellers', child: Text('All senders (booked before)')),
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
/// reply (POST /chat/support/:id/reply — the same endpoint senders reply with).
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
      _threads = ((data?['threads'] as List?) ?? const <dynamic>[])
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
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
      if (!mounted) return;
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
            const Padding(padding: EdgeInsets.all(14), child: Center(child: AppLogoSpinner(size: 26)))
          else if (_threads.isEmpty)
            const Text('No tickets. Everyone is happy.', style: TextStyle(color: AppColors.ink, fontSize: 12.5))
          else
            ..._threads.take(12).map((t) {
              final unread = (t['unread'] as num?)?.toInt() ?? 0;
              final threadName = '${t['customer_name'] ?? ''}'.trim();
              final seed = threadName.isNotEmpty ? threadName : '${t['phone'] ?? ''}';
              final photoUrl = '${t['customer_photo_url'] ?? ''}'.trim();
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => _open(t),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                    child: Row(children: [
                      _customerAvatar(seed, photoUrl.isEmpty ? null : photoUrl, 16),
                      const SizedBox(width: 10),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${t['subject'] ?? 'Ticket #${t['id']}'} · $seed',
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                        Text('${t['category'] ?? 'other'} · ${t['status'] ?? 'open'}${('${t['last_message'] ?? ''}').isNotEmpty ? ' · ${t['last_message']}' : ''}',
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: AppColors.muted, fontSize: 11.5)),
                      ])),
                      if (unread > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(color: AppColors.forest, borderRadius: BorderRadius.circular(12)),
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
  Map<String, dynamic>? _ticket;
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
    try {
      final data = await DropOffApi.adminSupportThread(widget.threadId);
      if (!mounted) return;
      if (data == null) {
        setState(() { _loading = false; _error = 'Could not load this ticket. Check your connection and staff role, then retry.'; });
        return;
      }
      // Tolerate rows that are not plain maps — a cast here must not wedge the spinner.
      final rows = ((data['messages'] as List?) ?? const <dynamic>[])
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
      setState(() {
        _messages = rows;
        _ticket = (data['ticket'] as Map?)?.cast<String, dynamic>();
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not open this ticket — ${e.toString().split('\n').first.substring(0, e.toString().split('\n').first.length.clamp(0, 180))}';
      });
      return;
    }
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

  /// Staff sets the ticket state. Closing also closes the customer's reply box.
  Future<void> _setTicketStatus(String status) async {
    final res = await DropOffApi.adminTicketStatus(widget.threadId, status);
    if (!mounted) return;
    if (!res.ok) return AppToast.show(context, 'Could not update ticket: ${res.error}');
    AppToast.show(context, 'Ticket marked $status.');
    _load();
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
      child: Container(
        height: MediaQuery.of(context).size.height * 0.82,
        width: double.infinity,
        color: Colors.white,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(children: [
              _sheetAvatar(),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${_ticket?['subject'] ?? 'Ticket #${widget.threadId}'}',
                      style: AppType.subhead, maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text('${_ticket?['category'] ?? 'other'} · ${widget.customerName ?? widget.phone}',
                      maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.muted, fontSize: 11.5)),
                ]),
              ),
              DropdownButton<String>(
                value: '${_ticket?['status'] ?? 'open'}',
                items: const [
                  DropdownMenuItem(value: 'open', child: Text('Open')),
                  DropdownMenuItem(value: 'pending', child: Text('Pending')),
                  DropdownMenuItem(value: 'closed', child: Text('Closed')),
                ],
                onChanged: (v) { if (v != null) _setTicketStatus(v); },
              ),
              IconButton(tooltip: 'Reload', onPressed: () { setState(() { _loading = true; _error = null; }); _load(); }, icon: const Icon(Icons.refresh, size: 18)),
            ]),
          ),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: AppLogoSpinner(size: 26))
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
                        ? const AppLogoSpinner(size: 14)
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
                      ? const AppLogoSpinner(size: 18)
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

/// Accounts & roles (admins): review every account and decide who is
/// admin. The admin key's own row can never be demoted (server refuses).
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

  Future<void> _deleteUser(Map<String, dynamic> user) async {
    final phone = '${user['phone'] ?? ''}';
    if (phone.isEmpty) return;
    final name = '${user['full_name'] ?? user['email'] ?? phone}';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this account?'),
        content: Text('Permanently remove $name ($phone) and every device session and push token.\n\nJob history, payments and audit events are kept — this is a compliance de-listing, not a data shred. The owner account cannot be deleted.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete account'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final res = await DropOffApi.deleteUser(phone, confirm: true);
    if (!mounted) return;
    AppToast.show(context, res.ok
        ? '$name was deleted. Their sessions are dead.'
        : 'Failed: ${res.error == 'superadmin_required' || res.error == 'admin_required' ? 'admins only' : res.error == 'cannot_delete_owner' ? 'that account cannot be deleted' : res.error}');
    if (res.ok) {
      _load();
      AnalyticsService.instance.track(
        feature: 'admin_users', action: 'delete_user', context: 'admin_users',
        meta: {'phone': phone},
      );
    }
  }

  Future<void> _editUser(Map<String, dynamic> user) async {
    final phone = '${user['phone'] ?? ''}';
    if (phone.isEmpty) return;
    final nameCtl = TextEditingController(text: '${user['full_name'] ?? ''}');
    final emailCtl = TextEditingController(text: '${user['email'] ?? ''}');
    final res = await showModalBottomSheet<_EditUserResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 4, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Edit user', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
          const SizedBox(height: 2),
          Text('Phone $phone — emails set here are marked verified, so the account can sign in with password right away.',
              style: AppType.caption),
          const SizedBox(height: 14),
          TextField(
            controller: nameCtl,
            decoration: const InputDecoration(labelText: 'Full name', border: OutlineInputBorder(), isDense: true),
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: emailCtl,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder(), isDense: true, hintText: 'ada@example.com'),
            autocorrect: false,
          ),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: OutlinedButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel'))),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                onPressed: () => Navigator.of(ctx).pop(_EditUserResult(nameCtl.text.trim(), emailCtl.text.trim())),
                icon: const Icon(Icons.save_outlined, size: 18),
                label: const Text('Save'),
              ),
            ),
          ]),
        ]),
      ),
    );
    if (res == null) return;
    final unchanged = res.email == '${user['email'] ?? ''}' && res.fullName == '${user['full_name'] ?? ''}';
    if (unchanged) {
      if (!mounted) return;
      AppToast.show(context, 'Nothing changed.');
      return;
    }
    final out = await DropOffApi.adminUpdateUser(phone, email: res.email, fullName: res.fullName);
    if (!mounted) return;
    AppToast.show(context, out.ok
        ? 'User updated.'
        : 'Failed: ${out.error == 'email_already_used' ? 'that email is already used by another account' : out.error == 'invalid_email' ? 'that email is not valid' : out.error == 'cannot_edit_admin_account' || out.error == 'cannot_edit_master_account' ? 'the admin account cannot be edited' : out.error}');
    if (out.ok) {
      _load();
      AnalyticsService.instance.track(
        feature: 'admin_users', action: 'edit_user', context: 'admin_users',
        meta: {'phone': phone},
      );
    }
  }

  Future<void> _setRole(Map<String, dynamic> user, String role) async {
    final email = '${user['email'] ?? ''}';
    if (email.isEmpty || role == '${user['role'] ?? ''}') return;
    final res = await DropOffApi.adminSetUserRole(email, role);
    if (!mounted) return;
    AppToast.show(context, res.ok
        ? '$email is now $role.'
        : 'Failed: ${res.error == 'owner_cannot_be_demoted' ? 'that account cannot be demoted' : res.error == 'superadmin_required' || res.error == 'admin_required' ? 'admins only' : res.error}');
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
          const Text('Admins decide who is who. Roles you can grant: customer (regular sender), rider (team member — Team/Rider tab, salary payroll), partner (courier depot console), ops (dispatch — fleet-wide tools), admin (full admin console, cannot mint more admins or promote themselves), cfo (finances only — payroll, turnover tax and filings; never moves money on their own).',
              style: AppType.caption),
          const SizedBox(height: 8),
          if (_loading)
            const Padding(padding: EdgeInsets.all(14), child: Center(child: AppLogoSpinner(size: 26)))
          else if (_users.isEmpty)
            const Text('No accounts found.', style: TextStyle(color: AppColors.ink, fontSize: 12.5))
          else
            ..._users.take(60).map((u) {
              final role = '${u['role'] ?? 'customer'}';
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(children: [
                  const Icon(Icons.person_outline, size: 16, color: AppColors.forest),
                  const SizedBox(width: 10),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Text('${u['full_name'] ?? u['email'] ?? u['phone'] ?? 'Account'}',
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                      
                    ]),
                    Text('${u['email'] ?? ''} · ${u['phone'] ?? ''}',
                        style: const TextStyle(color: AppColors.muted, fontSize: 11)),
                  ])),
                  ...[
                    PopupMenuButton<String>(
                      tooltip: 'Change role',
                      initialValue: role,
                      onSelected: (r) => _setRole(u, r),
                      itemBuilder: (context) => const [
                        PopupMenuItem(value: 'customer', child: Text('customer — regular sender')),
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
                    if ('${u['role'] ?? 'customer'}' != 'admin') ...[
                      IconButton(
                        tooltip: 'Edit details',
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.edit_outlined, size: 18, color: AppColors.forest),
                        onPressed: () => _editUser(u),
                      ),
                      IconButton(
                        tooltip: 'Delete account',
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.delete_outline, size: 18, color: AppColors.danger),
                        onPressed: () => _deleteUser(u),
                      ),
                    ],
                    ]]),
              );
            }),
        ]),
      ),
    );
  }
}

/// Admin booking delete: the soft-delete the ops console has no button for.
/// Customers can never delete bookings — only admins can, and the
/// job stays in the DB for payments & audit (every listing filters on
/// status != 'deleted').
class _BookingDeleteCard extends StatefulWidget {
  const _BookingDeleteCard();

  @override
  State<_BookingDeleteCard> createState() => _BookingDeleteCardState();
}

class _BookingDeleteCardState extends State<_BookingDeleteCard> {
  final _ref = TextEditingController();
  bool _busy = false;

  Future<void> _delete() async {
    final ref = _ref.text.trim().toUpperCase();
    if (ref.isEmpty) {
      AppToast.show(context, 'Enter the job ref (e.g. DRO-2026-000123).');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this booking?'),
        content: Text('Remove $ref from every user-facing list (sender, recipient, rider, dispatch queues). Payments, history and audit events are kept. Collections and courier counter fares are untouched.\n\nThis cannot be undone from the app.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete booking'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    final res = await DropOffApi.deleteJob(ref);
    if (!mounted) return;
    setState(() => _busy = false);
    if (res.ok) {
      _ref.clear();
      AppToast.show(context, 'Booking $ref deleted from all lists.');
      AnalyticsService.instance.track(
        feature: 'admin_jobs', action: 'delete_booking', context: 'admin_delete_booking',
        meta: {'ref': ref},
      );
    } else {
      AppToast.show(context, res.error == 'admin_required'
          ? 'Admins only.'
          : 'Failed: ${res.error ?? 'try again'}');
    }
  }

  @override
  void dispose() {
    _ref.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [
            Icon(Icons.delete_outline, color: AppColors.danger),
            SizedBox(width: 8),
            Expanded(child: Text('Delete a booking', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15))),
          ]),
          const SizedBox(height: 4),
          const Text('Only admins can delete a booking. Customers see a request-delete button that messages support — their data stays unless staff act on it. Deleting keeps payments and audit events for the books.',
              style: AppType.caption),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _ref,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Job ref',
                  hintText: 'DRO-2026-000123',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 10),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
              onPressed: _busy ? null : _delete,
              icon: _busy
                  ? const AppLogoSpinner(size: 16, color: Colors.white)
                  : const Icon(Icons.delete_outline, size: 18),
              label: const Text('Delete'),
            ),
          ]),
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
                          FilledButton(style: FilledButton.styleFrom(backgroundColor: AppColors.danger), onPressed: () => Navigator.pop(d, true), child: const Text('Delete')),
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
/// leg coverage per courier. No counter fares are published to senders here.
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
                style: AppType.subhead)),
          ]),
          const SizedBox(height: 6),
          const Text(
            'First-mile door → depot runs and collections depot → door. '
            'E.g. door → depot: Kabulonga → Platinum (Lusaka) — our rider fee for that leg. '
            'E.g. depot → door: Icypeed (Lusaka) → Kabulonga — our collection fee. '
            'No counter fares here — depot fares stay at the counter. Locations come from what app users type (most used shown).',
            style: AppType.caption,
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
                  ? const AppLogoSpinner(size: 16)
                  : const Icon(Icons.save_outlined),
              label: Text(_busy ? 'Saving…' : 'Save to chargebook'),
            ),
            if (_quotes.isNotEmpty) ...[
              const SizedBox(height: 14),
              const Text('Latest entries', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: AppColors.ink)),
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
/// payment prompt when a sender redeems one on their own number.
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
          const Text('Sell plans at the counter or to agents. The sender redeems the code in the app — no payment prompt, the plan goes live instantly.', style: AppType.caption),
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
            const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Center(child: AppLogoSpinner(size: 18)))
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
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.line)),
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
/// showing up for senders immediately; existing subscribers keep their cycle
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
  // Platform switches — an admin flips live, admin-key-gated server-side.
  bool _doorToDoor = false;
  bool _overageDiscount = false;
  bool _flagBusy = false;

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
    final settings = await DropOffApi.adminSettings();
    if (!mounted) return;
    setState(() {
      _plans = ((tiers?['tiers'] as List?) ?? const []).cast<Map<String, dynamic>>();
      _couriers = ((couriers?['couriers'] as List?) ?? const []).cast<Map<String, dynamic>>();
      final flags = (settings?['settings'] as Map?) ?? const {};
      _doorToDoor = flags['door_to_door_enabled'] == true;
      _overageDiscount = flags['overage_discount_enabled'] == true;
      _error = tiers == null ? 'Plans/courier catalogue needs an admin sign-in on this device.' : null;
      _loading = false;
    });
  }

  Future<void> _toggleFlag(String key, bool on) async {
    setState(() => _flagBusy = true);
    final res = await DropOffApi.adminSetSetting(key, on);
    if (!mounted) return;
    setState(() => _flagBusy = false);
    _snack(res.ok
        ? (key == 'door_to_door_enabled'
            ? (on ? 'Door-to-door drop-off ON — senders see the option.' : 'Door-to-door OFF — collection points only.')
            : (on ? 'Overage discount ON — tiers apply on PAYG overage.' : 'Overage discount OFF — overage bills at full PAYG.'))
        : 'Could not flip the switch (${res.error ?? 'admins only'})');
    unawaited(Future.delayed(const Duration(milliseconds: 400), _load));
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Widget _flagRow(String title, String blurb, bool value, ValueChanged<bool> onChanged) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
            const SizedBox(height: 2),
            Text(blurb, style: AppType.caption),
          ]),
        ),
        const SizedBox(width: 8),
        Switch(value: value, onChanged: _flagBusy ? null : onChanged),
      ]),
    );
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
    final fee = (t['fee_zmw'] as num?)?.toDouble() ?? 0;
    // Overage discounts removed entirely (owner 2026-11-18) — no discount copy.
    final tag = '${t['tag'] ?? ''}'.trim();
    return 'K${fee.toStringAsFixed(0)} • $cap • ${cycle}d cycle${tag.isNotEmpty ? ' • tag: $tag' : ' • no tag'}';
  }

  Future<void> _editPlan(Map<String, dynamic> t) async {
    final fee = TextEditingController(text: '${(t['fee_zmw'] as num?)?.toDouble() ?? 0}');
    final ppd = TextEditingController(text: '${(t['parcels_per_day'] as num?)?.toInt() ?? 0}');
    final ppm = TextEditingController(text: '${(t['parcels_per_month'] as num?)?.toInt() ?? 0}');
    final rider = TextEditingController(text: '${(t['rider_fee_zmw'] as num?)?.toDouble() ?? 0}');
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
            const Expanded(child: Text('Plans & couriers (admin)',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15))),
            IconButton(
              tooltip: 'Refresh',
              icon: _loading
                  ? const AppLogoSpinner(size: 16)
                  : const Icon(Icons.refresh, size: 20),
              onPressed: _loading ? null : _load,
            ),
          ]),
          const SizedBox(height: 2),
          const Text('Off hides the offer from senders instantly (new subscriptions stop; existing subscribers keep their cycle benefit). Edit every field below — price, parcels/day, parcels/month, cycle length, discount, tag.',
              style: AppType.caption),
          const SizedBox(height: 10),
          const Row(children: [
            Icon(Icons.toggle_on_outlined, size: 16, color: AppColors.forest),
            SizedBox(width: 6),
            Expanded(child: Text('Platform switches — live, no deploy (admin)', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13))),
          ]),
          const SizedBox(height: 6),
          _flagRow(
            'Door-to-door drop-off',
            'Sender’s door → recipient’s door, plans or pay-as-you-go. Off by default — collections are courier-point pickups and the first-mile model stays subscription-first.',
            _doorToDoor,
            (v) => _toggleFlag('door_to_door_enabled', v),
          ),
          const SizedBox(height: 6),
          _flagRow(
            'Tier overage discount',
            'Overage discount permanently OFF (owner 2026-11-18): no plan gives a discount after the cap; extras bill at full pay-as-you-go. The switch stays OFF as a kill switch.',
            _overageDiscount,
            (v) => _toggleFlag('overage_discount_enabled', v),
          ),
          const Divider(height: 18),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: const TextStyle(color: AppColors.danger, fontSize: 11.5))),
          const SizedBox(height: 10),
          for (final t in _plans)
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.line)),
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
          const Row(children: [
            Icon(Icons.local_shipping_outlined, size: 16, color: AppColors.forest),
            SizedBox(width: 6),
            Text('Couriers — availability for senders', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
          ]),
          const SizedBox(height: 8),
          for (final c in _couriers)
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.line)),
              child: Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${c['name']}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
                  const SizedBox(height: 2),
                  Text('${c['city'] ?? ''}${c['depot_name'] != null ? ' • ${c['depot_name']}' : ''} • id ${c['id']}',
                      style: const TextStyle(color: AppColors.muted, fontSize: 10.5), maxLines: 2, overflow: TextOverflow.ellipsis),
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

/// No-show guard (owner directive): senders with 3+ missed pickups in 14 days
/// are parked from new bookings. Ops reviews the job refs behind the strikes
/// and clears them — that IS the unblock button.
class _BookingStrikesCard extends StatefulWidget {
  const _BookingStrikesCard();

  @override
  State<_BookingStrikesCard> createState() => _BookingStrikesCardState();
}

class _BookingStrikesCardState extends State<_BookingStrikesCard> {
  bool _loading = false;
  List<Map<String, dynamic>> _rows = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final data = await DropOffApi.adminBookingStrikes();
    if (!mounted) return;
    setState(() {
      _rows = ((data?['strikes'] as List?) ?? const [])
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
      _loading = false;
    });
  }

  Future<void> _clear(Map<String, dynamic> row) async {
    final phone = '${row['phone']}';
    final fullName = '${row['sender_name'] ?? ''}'.trim();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear booking strikes?'),
        content: Text('Wipe ALL booking strikes for $phone${fullName.isNotEmpty ? ' ($fullName)' : ''}?\n\nJobs: ${row['job_refs'] ?? '—'}\n\nThey can book immediately after this.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Clear & unblock')),
        ],
      ),
    );
    if (confirmed != true) return;
    final res = await DropOffApi.clearBookingStrikes(phone);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(res.ok ? 'Strikes cleared — $phone can book again.' : 'Could not clear strikes (${res.error})'),
    ));
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.warning_amber_outlined, size: 19, color: AppColors.warning),
            const SizedBox(width: 8),
            const Expanded(child: Text('No-show strikes — parked bookers',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15))),
            IconButton(
              tooltip: 'Refresh',
              icon: _loading
                  ? const AppLogoSpinner(size: 16)
                  : const Icon(Icons.refresh, size: 20),
              onPressed: _loading ? null : _load,
            ),
          ]),
          const SizedBox(height: 2),
          const Text('3 strikes in 14 days parks new bookings. Clear one or all from this list.',
              style: AppType.caption),
          const SizedBox(height: 10),
          if (_rows.isEmpty && !_loading)
            const Text('No strikes on file — nobody is parked right now.',
                style: TextStyle(color: AppColors.muted, fontSize: 12)),
          for (final row in _rows)
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: row['on_hold'] == true ? AppColors.danger.withValues(alpha: 0.05) : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: row['on_hold'] == true ? AppColors.danger.withValues(alpha: 0.4) : AppColors.line),
              ),
              child: Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${row['sender_name'] ?? row['phone']}',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
                  const SizedBox(height: 2),
                  Text('${row['phone']} • ${row['strikes']} strike${row['strikes'] == 1 ? '' : 's'} (${row['strikes_14d']} in 14d) • last ${row['last_strike'] ?? '?'}',
                      style: const TextStyle(color: AppColors.muted, fontSize: 10.5), maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text('jobs: ${row['job_refs'] ?? '—'}',
                      style: const TextStyle(color: AppColors.muted, fontSize: 10, fontFamily: 'monospace'),
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                ])),
                const SizedBox(width: 8),
                if (row['on_hold'] == true)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    margin: const EdgeInsets.only(right: 4),
                    decoration: BoxDecoration(color: AppColors.danger.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
                    child: const Text('PARKED', style: TextStyle(color: AppColors.danger, fontSize: 9, fontWeight: FontWeight.w900)),
                  ),
                TextButton(onPressed: () => _clear(row), child: const Text('Clear')),
              ]),
            ),
        ]),
      ),
    );
  }
}

/// Admin console: run rider incentive programmes as named promos
/// ("Christmas Bonus", "Hydro-gen Sprint"…). Toggle on/off to promote or
/// retire — amounts never cash out in-app, they flow through the same payroll
/// confirmation chain as salary. Only ONE programme can be active at a time.
class _IncentivePromoCard extends StatefulWidget {
  const _IncentivePromoCard();

  @override
  State<_IncentivePromoCard> createState() => _IncentivePromoCardState();
}

class _IncentivePromoCardState extends State<_IncentivePromoCard> {
  bool _loading = false;
  List<Map<String, dynamic>> _rows = const [];
  Map<String, dynamic>? _active;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final data = await DropOffApi.adminIncentives();
    if (!mounted) return;
    setState(() {
      _rows = ((data?['programmes'] as List?) ?? const [])
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
      _active = (data?['active'] as Map?)?.cast<String, dynamic>();
      _loading = false;
    });
  }

  Future<void> _toggle(Map<String, dynamic> row) async {
    final id = (row['id'] as num).toInt();
    final on = !(row['active'] == 1 || row['active'] == true);
    final res = await DropOffApi.adminIncentiveToggle(id, active: on);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(res.ok ? '${on ? 'Activated' : 'Ended'} "${row['title']}" — through payroll, as always.' : 'Could not toggle (${res.error})'),
    ));
    await _load();
  }

  Future<void> _edit(Map<String, dynamic>? row) async {
    final title = TextEditingController(text: row?['title'] as String? ?? '');
    final endsOn = TextEditingController(text: row?['ends_on'] as String? ?? '');
    final perExtra = TextEditingController(text: '${row?['per_extra_parcel_zmw'] ?? 5}');
    final completion = TextEditingController(text: '${row?['completion_bonus_zmw'] ?? 200}');
    final cap = TextEditingController(text: '${row?['per_extra_cap'] ?? 135}');
    final stretch = TextEditingController(text: '${row?['stretch_ratio'] ?? 1.25}');
    final stretchBonus = TextEditingController(text: '${row?['stretch_bonus_zmw'] ?? 150}');
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(row == null ? 'New rider incentive' : 'Edit: ${row['title']}',
            style: const TextStyle(fontWeight: FontWeight.w900)),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: title, decoration: const InputDecoration(labelText: 'Promo title (e.g. Christmas Bonus)', hintText: 'Christmas Bonus')),
            const SizedBox(height: 8),
            TextField(controller: endsOn, decoration: const InputDecoration(labelText: 'Ends on (blank = always-on)', hintText: '2026-12-31')),
            Row(children: [
              Expanded(child: Padding(padding: const EdgeInsets.only(right: 6), child: TextField(controller: completion, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Completion K')))),
              Expanded(child: TextField(controller: perExtra, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Per extra parcel K'))),
            ]),
            Row(children: [
              Expanded(child: Padding(padding: const EdgeInsets.only(right: 6), child: TextField(controller: cap, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Max extra parcels')))),
              Expanded(child: TextField(controller: stretch, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Stretch ratio'))),
            ]),
            TextField(controller: stretchBonus, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Stretch bonus K')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    if (result != true) return;
    final res = await DropOffApi.adminSaveIncentive({
      if (row != null) 'id': row['id'],
      'title': title.text.trim(),
      'ends_on': endsOn.text.trim().isEmpty ? null : endsOn.text.trim(),
      'completion_bonus_zmw': double.tryParse(completion.text.trim()) ?? 200,
      'per_extra_parcel_zmw': double.tryParse(perExtra.text.trim()) ?? 5,
      'per_extra_cap': int.tryParse(cap.text.trim()) ?? 135,
      'stretch_ratio': double.tryParse(stretch.text.trim()) ?? 1.25,
      'stretch_bonus_zmw': double.tryParse(stretchBonus.text.trim()) ?? 150,
      'active': 1,
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(res.ok ? 'Saved "${title.text.trim()}" — it pays through payroll, never cash-in-app.' : 'Could not save (${res.error})'),
    ));
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.card_giftcard, size: 18, color: AppColors.amber),
            const SizedBox(width: 8),
            const Expanded(child: Text('Rider incentive promos', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15))),
            IconButton(
              tooltip: 'New promo',
              icon: const Icon(Icons.add_circle_outline),
              onPressed: _loading ? null : () => _edit(null),
            ),
            IconButton(
              tooltip: 'Refresh',
              icon: _loading
                  ? const AppLogoSpinner(size: 16)
                  : const Icon(Icons.refresh, size: 20),
              onPressed: _loading ? null : _load,
            ),
          ]),
          const SizedBox(height: 2),
          const Text('Up the incentive for a period (Christmas Bonus, Year-End Sprint…). Toggle to promote or retire — flows through the same payroll confirmation chain as salary, never as cash-in-app.',
              style: AppType.caption),
          if (_active != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(children: [
                const Icon(Icons.play_circle_outline, size: 15, color: AppColors.forest),
                const SizedBox(width: 6),
                Expanded(child: Text('Active now: "${_active!['title'] ?? '—'}"', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: AppColors.forest))),
              ]),
            ),
          const SizedBox(height: 12),
          if (_rows.isEmpty && !_loading)
            const Text('No rider incentives configured — the built-in bonus applies.', style: TextStyle(color: AppColors.muted, fontSize: 12)),
          for (final row in _rows) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: row['active'] == 1 || row['active'] == true ? AppColors.forest.withValues(alpha: 0.08) : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: row['active'] == 1 || row['active'] == true ? AppColors.forest.withValues(alpha: 0.45) : AppColors.line),
              ),
              child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${row['title'] ?? 'Promo'}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
                  Text('K${(row['completion_bonus_zmw'] ?? 0).toStringAsFixed(0)} completion · +K${(row['per_extra_parcel_zmw'] ?? 0).toStringAsFixed(0)}/extra (max ${row['per_extra_cap'] ?? 135}) · stretch ×${(row['stretch_ratio'] ?? 1.25)} +K${(row['stretch_bonus_zmw'] ?? 150).toStringAsFixed(0)}',
                      style: const TextStyle(color: AppColors.muted, fontSize: 10.5), maxLines: 2, overflow: TextOverflow.ellipsis),
                  if ((row['ends_on'] as String?)?.isNotEmpty == true)
                    Text('Ends ${row['ends_on']}', style: const TextStyle(color: AppColors.muted, fontSize: 10)),
                ])),
                Switch(
                  value: row['active'] == 1 || row['active'] == true,
                  onChanged: (_) => _toggle(row),
                  activeThumbColor: AppColors.forest,
                ),
                TextButton(onPressed: () => _edit(row), child: const Text('Edit')),
              ]),
            ),
          ],
        ]),
      ),
    );
  }
}

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
      final msg = res.error == 'network_error'
          ? 'Could not reach the AI — check your connection and retry (vision models are cold-start slow).'
          : 'AI check failed (${res.error}).';
      AppToast.show(context, msg);
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
    final faceColor = faceVerdict == 'pass' ? AppColors.forest : AppColors.danger;
    final matchSame = '${faceMatch?['same_person'] ?? ''}';
    final matchLabel = matchSame == 'yes' ? 'SAME PERSON' : matchSame == 'no' ? 'DIFFERENT' : 'UNCERTAIN';
    final matchColor = matchSame == 'yes' ? AppColors.forest : matchSame == 'no' ? AppColors.danger : AppColors.warning;
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('AI KYC identity check'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Plate match: ${plateMatch ? 'YES' : 'no'}', style: TextStyle(fontWeight: FontWeight.w800, color: plateMatch ? AppColors.forest : AppColors.danger)),
          const SizedBox(height: 4),
          Text('NRC match: ${nrcMatch ? 'YES' : 'no'}', style: TextStyle(fontWeight: FontWeight.w800, color: nrcMatch ? AppColors.forest : AppColors.danger)),
          const SizedBox(height: 4),
          Text('Selfie face: ${faceVerdict.isEmpty ? 'not checked' : faceVerdict.toUpperCase()}',
              style: TextStyle(fontWeight: FontWeight.w800, color: faceVerdict.isEmpty ? AppColors.muted : faceColor)),
          if (faceNote.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text('AI note: $faceNote', style: AppType.caption),
          ],
          if (faceMatch != null) ...[
            const SizedBox(height: 4),
            Text('Selfie vs ID portrait: $matchLabel  (${faceMatch['confidence'] ?? 'low'} confidence)',
                style: TextStyle(fontWeight: FontWeight.w800, color: matchColor)),
            if ('${faceMatch['note'] ?? ''}'.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text('AI note: ${faceMatch['note']}', style: AppType.caption),
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
              style: AppType.caption),
          const SizedBox(height: 12),
          Wrap(spacing: 6, runSpacing: 6, children: [
            ChoiceChip(selected: !_showAll, label: Text('Pending only ($pending)'), onSelected: (v) => setState(() => _showAll = !v)),
            ChoiceChip(selected: _showAll, label: Text('All riders (${_riders.length})'), onSelected: (v) => setState(() => _showAll = v)),
          ]),
          const SizedBox(height: 8),
          if (_loading)
            const Padding(padding: EdgeInsets.symmetric(vertical: 14), child: Center(child: AppLogoSpinner(size: 18)))
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
                    Expanded(child: Text('${rider['full_name'] ?? 'Driver'}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5), maxLines: 2, overflow: TextOverflow.ellipsis)),
                    _statusChip('${rider['verification_status'] ?? 'pending'}'),
                  ]),
                  const SizedBox(height: 2),
                  Text('${rider['phone'] ?? ''} - ${rider['vehicle'] ?? ''} ${rider['vehicle_class'] ?? ''}',
                      style: AppType.caption),
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
                    Text('Note: ${rider['verification_note']}', style: const TextStyle(color: AppColors.danger, fontSize: 11, height: 1.35)),
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
      'rejected' => (AppColors.danger, 'REJECTED'),
      _ => (AppColors.warning, 'PENDING'),
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
        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: onTrack ? AppColors.forest : AppColors.warning),
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
            const Padding(padding: EdgeInsets.symmetric(vertical: 14), child: Center(child: AppLogoSpinner(size: 18)))
          else ...[
            const Text('Operations — the real work (live data)', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: AppColors.ink)),
            const SizedBox(height: 6),
            if (ops == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 6),
                child: Text('Could not load operational KPIs — worker endpoint /admin/analytics/ops may not be deployed yet.', style: AppType.caption),
              )
            else ...[
              Row(children: [
                Expanded(child: _KpiMetric('Booked', '${ops['parcels_booked'] ?? 0} · ${ops['parcels_booked_today'] ?? 0} today', Icons.inventory_2_outlined)),
                const SizedBox(width: 8),
                Expanded(child: _KpiMetric('Delivered', '${ops['deliveries'] ?? 0} · ${ops['deliveries_today'] ?? 0} today', Icons.local_shipping_outlined)),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: _KpiMetric('Active senders', '${ops['active_sellers'] ?? 0}', Icons.storefront_outlined)),
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
            const Text('App usage — telemetry', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: AppColors.ink)),
            const SizedBox(height: 6),
            if (kpi == null)
              const Text('Could not load usage telemetry (GET /admin/analytics/kpi).', style: TextStyle(color: AppColors.muted, fontSize: 12))
            else if (total == 0 && features.isEmpty)
              const Text('No usage events yet — they flush every 5 minutes while the app is open. Check back after the next use.', style: AppType.caption)
            else ...[
              Row(children: [
                Expanded(child: _KpiMetric('Events', '$total', Icons.event_note)),
                Expanded(child: _KpiMetric('Features', '${features.length}', Icons.apps)),
                Expanded(child: _KpiMetric('Active days', '${dau.length}', Icons.today)),
              ]),
              const SizedBox(height: 10),
              const Text('Most used features', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: AppColors.ink)),
              const SizedBox(height: 6),
              ...features.take(6).map((f) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(children: [
                  Expanded(child: Text('${f['feature']}', style: const TextStyle(fontSize: 12), maxLines: 2, overflow: TextOverflow.ellipsis)),
                  Text('${f['n']}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: AppColors.forest)),
                  const SizedBox(width: 6),
                  Text('${f['users']} users', style: const TextStyle(color: AppColors.muted, fontSize: 11)),
                ]),
              )),
              const SizedBox(height: 8),
              const Text('Most visited screens', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: AppColors.ink)),
              const SizedBox(height: 6),
              if (screens.isEmpty)
                const Text('No screen views recorded yet.', style: TextStyle(color: AppColors.muted, fontSize: 12))
              else
                ...screens.take(6).map((s) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(children: [
                    Expanded(child: Text('${s['screen'] ?? 'unknown'}', style: const TextStyle(fontSize: 12), maxLines: 2, overflow: TextOverflow.ellipsis)),
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
              const Text('Conversion funnel (unique users)', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: AppColors.ink)),
              const SizedBox(height: 6),
              ...funnel.take(5).map((f) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(children: [
                  Expanded(child: Text('${f['feature']}', style: const TextStyle(fontSize: 12), maxLines: 2, overflow: TextOverflow.ellipsis)),
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
            style: AppType.caption,
          ),
          const SizedBox(height: 12),
          if (_loading)
            const Padding(padding: EdgeInsets.all(14), child: Center(child: AppLogoSpinner(size: 26)))
          else if (days.isEmpty)
            const Text('No bookings in the last 8 weeks to learn from yet.', style: TextStyle(color: AppColors.ink, fontSize: 12.5))
          else ...[
            // branch x window heat grid for the busiest branches (top 12)
            if (branches.isNotEmpty) ...[
              const Text('By depot branch', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: AppColors.ink)),
              const SizedBox(height: 6),
              for (final b in branches.take(8))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(children: [
                    Expanded(
                      child: Text('${b['branch']}', maxLines: 2, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(width: 8),
                    Text('${b['predicted_7d_parcels']} parcels', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: AppColors.forest)),
                  ]),
                ),
            ],
            const SizedBox(height: 12),
            const Text('Per day (all branches)', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: AppColors.ink)),
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
            Text('${_data?['basis'] ?? ''}', style: AppType.caption),
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

/// Refund / settlement payout ledger — the Chisomo-style guarded retry engine.
/// Shows attempt count, last gateway error and a superadmin retry button.
class _PayoutQueueCard extends StatefulWidget {
  const _PayoutQueueCard();
  @override
  State<_PayoutQueueCard> createState() => _PayoutQueueCardState();
}

class _PayoutQueueCardState extends State<_PayoutQueueCard> {
  List<Map<String, dynamic>> _rows = const [];
  bool _loading = true;
  int? _busyId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await DropOffApi.adminPayouts();
    if (!mounted) return;
    setState(() {
      _rows = ((data?['payouts'] as List?) ?? const []).cast<Map<String, dynamic>>();
      _loading = false;
    });
  }

  Future<void> _retry(int id) async {
    setState(() => _busyId = id);
    final res = await DropOffApi.retryPayout(id);
    if (!mounted) return;
    setState(() => _busyId = null);
    AppToast.show(context, res.ok ? 'Payout requeued for immediate retry.' : 'Retry failed: ${res.error}');
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.payments_outlined, color: AppColors.forest),
            const SizedBox(width: 8),
            const Expanded(child: Text('Payout queue', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15))),
            IconButton(tooltip: 'Refresh', onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh, size: 18)),
          ]),
          const SizedBox(height: 4),
          const Text('Refunds retry every 30 minutes until Lipila confirms. Only you and staff see this ledger.', style: TextStyle(fontSize: 11, color: AppColors.muted)),
          const SizedBox(height: 10),
          if (_loading)
            const Padding(padding: EdgeInsets.all(12), child: Center(child: AppLogoSpinner(size: 26)))
          else if (_rows.isEmpty)
            const Text('No payouts queued.', style: TextStyle(fontSize: 12.5))
          else
            ..._rows.take(10).map((p) {
              final id = (p['id'] as num?)?.toInt() ?? 0;
              final status = '${p['status'] ?? 'queued'}';
              final retryable = status == 'failed' || status == 'queued';
              final error = '${p['last_error'] ?? ''}';
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(color: AppColors.canvas, borderRadius: BorderRadius.circular(10)),
                  child: Row(children: [
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('K${(p['amount_zmw'] as num?)?.toStringAsFixed(2) ?? '0.00'} · ${p['kind']} · #${p['id']}',
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
                      Text('${p['reference'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 10, color: AppColors.muted)),
                      Text('$status · attempt ${p['attempts'] ?? 0}${error.isNotEmpty ? ' · $error' : ''}',
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 10, color: status == 'success' ? AppColors.success : AppColors.warning)),
                    ])),
                    if (retryable)
                      IconButton(
                        tooltip: 'Retry now (superadmin)',
                        onPressed: _busyId != null ? null : () => _retry(id),
                        icon: _busyId == id
                            ? const AppLogoSpinner(size: 16)
                            : const Icon(Icons.replay, size: 19),
                      ),
                  ]),
                ),
              );
            }),
        ]),
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


/// Client crash digest — the free crash reporting answer. Compact, actionable,
/// first sign of trouble on a fresh build. Data: `/admin/client-crashes`,
/// deduped per device+stack server-side.
class _ClientCrashesCard extends StatefulWidget {
  const _ClientCrashesCard();

  @override
  State<_ClientCrashesCard> createState() => _ClientCrashesCardState();
}

class _ClientCrashesCardState extends State<_ClientCrashesCard> {
  Map<String, dynamic>? _data;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await DropOffApi.adminClientCrashes();
    if (!mounted) return;
    setState(() {
      _data = data;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final rows = ((_data?['crashes'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final total = (_data?['crashes_last_24h'] as num?)?.toInt() ?? 0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.bug_report_outlined, color: total > 0 ? AppColors.danger : AppColors.forest),
            const SizedBox(width: 8),
            const Expanded(child: Text('Client crashes', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15))),
            IconButton(tooltip: 'Refresh', onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh, size: 18)),
          ]),
          const SizedBox(height: 2),
          if (_loading)
            const Padding(padding: EdgeInsets.all(14), child: Center(child: AppLogoSpinner(size: 26)))
          else ...[
            Text('$total crash${total == 1 ? '' : 'es'} in 24h — deduplicated. On a fresh build, any row below is urgent.', style: const TextStyle(color: AppColors.muted, fontSize: 11.5)),
            const SizedBox(height: 6),
            if (rows.isEmpty)
              const Text('Quiet. No client crashes on record.', style: TextStyle(color: AppColors.ink, fontSize: 12.5))
            else
              ...rows.take(8).map((c) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('×${(c['count'] as num?)?.toInt() ?? 1}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: AppColors.danger)),
                  const SizedBox(width: 10),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${c['message']}', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, height: 1.35), maxLines: 3, overflow: TextOverflow.ellipsis),
                    Text('v${c['app_version'] ?? '?'} · ${c['platform'] ?? '?'} · ${c['last_seen_at'] ?? ''}', style: const TextStyle(color: AppColors.muted, fontSize: 10.5)),
                  ])),
                ]),
              )),
          ],
        ]),
      ),
    );
  }
}


class _EditUserResult {
  final String fullName;
  final String email;
  const _EditUserResult(this.fullName, this.email);
}
