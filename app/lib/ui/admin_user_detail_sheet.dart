import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/dropoff_api.dart';
import 'app_sheet.dart';
import 'app_spinner.dart';
import 'app_theme.dart';
import 'app_toast.dart';
import '../widgets/common.dart';

/// The dossier behind a row in the admin Users directory.
///
/// Everything a staff member needs to understand an account is on one sheet:
/// identity, money, plan, activity, devices and addresses. Mutations are
/// injected by the caller so this widget remains a pure view with one API read.
class AdminUserDetailSheet extends StatefulWidget {
  const AdminUserDetailSheet({
    super.key,
    required this.user,
    this.onEdit,
    this.onRole,
    this.onDelete,
    this.onChanged,
  });

  final Map<String, dynamic> user;
  final Future<void> Function(Map<String, dynamic> user)? onEdit;
  final Future<void> Function(Map<String, dynamic> user)? onRole;
  final Future<void> Function(Map<String, dynamic> user)? onDelete;
  final VoidCallback? onChanged;

  static Future<void> show(
    BuildContext context, {
    required Map<String, dynamic> user,
    Future<void> Function(Map<String, dynamic>)? onEdit,
    Future<void> Function(Map<String, dynamic>)? onRole,
    Future<void> Function(Map<String, dynamic>)? onDelete,
    VoidCallback? onChanged,
  }) =>
      showAppSheet<void>(
        context,
        child: AdminUserDetailSheet(
          user: user,
          onEdit: onEdit,
          onRole: onRole,
          onDelete: onDelete,
          onChanged: onChanged,
        ),
      );

  @override
  State<AdminUserDetailSheet> createState() => _AdminUserDetailSheetState();
}

class _AdminUserDetailSheetState extends State<AdminUserDetailSheet> {
  Map<String, dynamic>? _detail;
  String? _error;
  bool _busy = false;

  String get _phone => '${widget.user['phone'] ?? ''}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await DropOffApi.adminUserDetail(_phone);
      if (!mounted) return;
      setState(() {
        _detail = data;
        _error = data == null ? 'Could not load this account right now.' : null;
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load this account right now.');
    }
  }

  static List<Map<String, dynamic>> _rows(Object? raw) {
    final list = (raw as List?) ?? const [];
    return list.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
  }

  static String _initials(Map<String, dynamic> u) {
    final seed = '${u['full_name'] ?? u['email'] ?? u['phone'] ?? '?'}'.trim();
    final parts = seed.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, parts.first.length.clamp(1, 2)).toUpperCase();
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }

  static String _kw(num? v) =>
      'K${(v ?? 0).toStringAsFixed(v == null || v == v.roundToDouble() ? 0 : 2)}';

  static String _date(Object? v) {
    final raw = '${v ?? ''}';
    if (raw.isEmpty) return '-';
    final dt = DateTime.tryParse(raw.replaceFirst(' ', 'T'));
    if (dt == null) return raw;
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    final u = widget.user;
    final name = '${u['full_name'] ?? u['email'] ?? u['phone'] ?? 'Account'}';
    final role = '${u['role'] ?? 'customer'}';
    final d = _detail ?? const <String, dynamic>{};
    final jobs = _rows(d['jobs']);
    final payments = _rows(d['payments']);
    final devices = _rows(d['devices']);
    final places = _rows(d['places']);
    final strikes = _rows(d['strikes']);
    final subs = _rows(d['subscriptions']);

    return SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.line, borderRadius: BorderRadius.circular(4)))),
        const SizedBox(height: 16),
        // Identity hero.
        Row(children: [
          ClipOval(
            child: SizedBox(
              width: 54,
              height: 54,
              child: (u['photo_url'] != null && '${u['photo_url']}'.isNotEmpty)
                  ? AuthedImage('${u['photo_url']}', width: 54, height: 54)
                  : Container(
                      color: AppColors.forest,
                      alignment: Alignment.center,
                      child: Text(_initials(u), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18)),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, maxLines: 2, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: -0.3)),
            const SizedBox(height: 2),
            Text(_phone, style: const TextStyle(fontSize: 13, color: AppColors.muted, fontWeight: FontWeight.w700)),
          ])),
          _pill(role.toUpperCase(), AppColors.forest),
        ]),
        if (u['superadmin'] == true) ...[
          const SizedBox(height: 8),
          _pill('OWNER IDENTITY', AppColors.amber, darkText: true),
        ],
        const SizedBox(height: 14),
        // Quick stats strip.
        Row(children: [
          _stat('JOBS', '${u['jobs_sent'] ?? 0}'),
          const SizedBox(width: 8),
          _stat('DELIVERED', '${u['jobs_delivered'] ?? 0}'),
          const SizedBox(width: 8),
          _stat('SPEND', _kw((u['spend_zmw'] as num?) ?? 0)),
          const SizedBox(width: 8),
          _stat('WALLET', _kw((d['wallet_balance_zmw'] as num?) ?? (u['wallet_balance_zmw'] as num?) ?? 0)),
        ]),
        const SizedBox(height: 16),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              const Icon(Icons.cloud_off_outlined, color: AppColors.amber),
              const SizedBox(width: 8),
              Expanded(child: Text(_error!, style: const TextStyle(fontSize: 12.5))),
              TextButton(onPressed: _load, child: const Text('Retry')),
            ]),
          )
        else if (_detail == null)
          const Padding(padding: EdgeInsets.all(16), child: Center(child: AppLogoSpinner(size: 24)))
        else ...[
          _section('ACCOUNT', children: [
            _line('Email', '${u['email'] ?? '-'}'),
            _line('Email verified', u['email_verified'] == true ? 'Yes' : 'No'),
            _line('Joined', _date(u['created_at'])),
            _line('Referral code', '${u['referral_code'] ?? '-'}'),
            _line('Door PIN', u['door_pin_set'] == true ? 'Set' : 'Not set'),
            _line('SMS marketing', u['sms_opt_out'] == true ? 'Opted out' : 'Subscribed'),
            _line('Last seen', _date((devices.isNotEmpty ? devices.first['last_seen'] : u['last_seen_at']))),
            _line('Devices', '${devices.length}'),
          ]),
          if (subs.isNotEmpty)
            _section('PLAN', children: [
              for (final s in subs)
                _line('${s['tier'] ?? 'Plan'}', '${s['status'] ?? '-'} · expires ${_date(s['expires_at'])}'),
            ]),
          if (jobs.isNotEmpty)
            _section('RECENT JOBS', children: [
              for (final j in jobs.take(6))
                _line('${j['ref'] ?? 'Job'}', '${j['status'] ?? '-'} · ${_kw((j['total_zmw'] as num?) ?? 0)} · ${_date(j['created_at'])}'),
            ]),
          if (payments.isNotEmpty)
            _section('RECENT PAYMENTS', children: [
              for (final p in payments.take(6))
                _line('${p['kind'] ?? 'payment'} · ${_kw((p['amount_zmw'] as num?) ?? 0)}',
                    '${p['status'] ?? '-'} · ${p['gateway'] ?? '-'} · ${_date(p['created_at'])}'),
            ]),
          if (devices.isNotEmpty)
            _section('DEVICES', children: [
              for (final dev in devices.take(6))
                _line('${dev['device_name'] ?? 'Device'}', '${dev['ip'] ?? '-'} · last ${_date(dev['last_seen'])}'),
            ]),
          if (places.isNotEmpty || strikes.isNotEmpty) ...[
            _section('OTHER', children: [
              if (places.isNotEmpty) _line('Saved places', '${places.length}'),
              if (strikes.isNotEmpty) _line('Booking strikes', '${strikes.length}'),
            ]),
          ],
        ],
        const SizedBox(height: 14),
        Wrap(spacing: 8, runSpacing: 8, children: [
          ActionChip(
            avatar: const Icon(Icons.call_outlined, size: 16),
            label: const Text('Call'),
            onPressed: () => callPhoneNumber(_phone),
          ),
          ActionChip(
            avatar: const Icon(Icons.copy_all_outlined, size: 16),
            label: const Text('Copy number'),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: _phone));
              if (context.mounted) AppToast.show(context, 'Number copied.');
            },
          ),
          if (widget.onEdit != null)
            ActionChip(
              avatar: const Icon(Icons.edit_outlined, size: 16),
              label: const Text('Edit details'),
              onPressed: () async {
                await widget.onEdit!(widget.user);
                _refresh();
              },
            ),
          if (widget.onRole != null)
            ActionChip(
              avatar: const Icon(Icons.admin_panel_settings_outlined, size: 16),
              label: const Text('Change role'),
              onPressed: () async {
                await widget.onRole!(widget.user);
                _refresh();
              },
            ),
          ActionChip(
            avatar: const Icon(Icons.lock_reset_outlined, size: 16),
            label: Text(_busy ? 'Sending…' : 'Reset link'),
            onPressed: _busy ? null : _resetLink,
          ),
          ActionChip(
            avatar: const Icon(Icons.alternate_email_rounded, size: 16),
            label: const Text('Enter email'),
            onPressed: _enterEmail,
          ),
          if (widget.onDelete != null)
            ActionChip(
              avatar: const Icon(Icons.person_off_outlined, size: 16, color: AppColors.danger),
              label: const Text('Delete', style: TextStyle(color: AppColors.danger)),
              onPressed: () async {
                await widget.onDelete!(widget.user);
                if (context.mounted) Navigator.of(context).pop();
              },
            ),
        ]),
      ]),
    );
  }

  void _refresh() {
    widget.onChanged?.call();
    _load();
  }

  Widget _pill(String label, Color color, {bool darkText = false}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.45)),
        ),
        child: Text(label,
            style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w900, letterSpacing: 0.6,
                color: darkText ? AppColors.ink : color)),
      );

  Widget _stat(String label, String value) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.canvas,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.line),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(fontSize: 8.5, fontWeight: FontWeight.w900, letterSpacing: 0.5, color: AppColors.muted),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 3),
            Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: AppColors.forest),
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ]),
        ),
      );

  Widget _section(String title, {required List<Widget> children}) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1, color: AppColors.muted)),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.line),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
          ),
        ]),
      );

  Widget _line(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 112, child: Text(label, style: const TextStyle(fontSize: 11.5, color: AppColors.muted))),
          const SizedBox(width: 6),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.ink),
              maxLines: 2, overflow: TextOverflow.ellipsis)),
        ]),
      );

  Future<void> _enterEmail() async {
    final emailCtl = TextEditingController(text: '${widget.user['email'] ?? ''}');
    final go = await showAppSheet<bool>(
      context,
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.line, borderRadius: BorderRadius.circular(4)))),
        const SizedBox(height: 16),
        const Text('Enter email address', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 19)),
        const SizedBox(height: 6),
        Text('Account $_phone. A confirmation link is sent to the new address. '
            'Owner and admin reset links still go to the phone.',
            style: const TextStyle(fontSize: 12.5, color: AppColors.muted, height: 1.4)),
        const SizedBox(height: 14),
        TextField(
          controller: emailCtl,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          decoration: const InputDecoration(labelText: 'Email', hintText: 'name@carpsosolutions.store', border: OutlineInputBorder(), isDense: true),
        ),
        const SizedBox(height: 16),
        SizedBox(width: double.infinity, child: FilledButton.icon(
          onPressed: () {
            final email = emailCtl.text.trim();
            if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$').hasMatch(email)) return;
            Navigator.of(context).pop(true);
          },
          icon: const Icon(Icons.save_outlined, size: 17),
          label: const Text('Save email'),
        )),
      ]),
    );
    if (go != true) return;
    final res = await DropOffApi.setStaffEmail(_phone, emailCtl.text.trim());
    if (context.mounted) {
      // ignore: use_build_context_synchronously
      AppToast.show(context, res.ok
          ? (res.body['verification_sent'] == true
              ? 'Email saved. A confirmation link is on its way.'
              : 'Email saved. The confirmation message could not be sent right now.')
          : res.error == 'email_already_registered'
              ? 'That email is already linked to another account.'
              : 'Could not save that email. Try again.');
    }
    _refresh();
  }

  Future<void> _resetLink() async {
    final go = await showConfirmSheet(
      context,
      title: 'Send a password reset link?',
      message: 'A one-hour link is texted to $_phone and recorded in the security log. '
          'Owner and admin accounts never receive reset links by email.',
      confirmLabel: 'Send link',
      icon: Icons.lock_reset_outlined,
    );
    if (!go) return;
    setState(() => _busy = true);
    final res = await DropOffApi.adminUserResetLink(_phone);
    if (!mounted) return;
    setState(() => _busy = false);
    final link = res.body['link'] as String?;
    await showInfoSheet(
      context,
      title: res.ok ? 'Reset link ready' : 'Could not create a link',
      message: res.ok
          ? (res.body['sms_sent'] == true
              ? 'The link was sent by SMS to the account phone. It is valid for one hour.'
              : 'SMS was not delivered — check the account phone credit. Use the link below if you are with the account holder:\n\n$link')
          : _adminErrorText(res),
      icon: Icons.lock_reset_outlined,
    );
  }

  String _adminErrorText(ApiResponse res) {
    final code = '${res.body['error'] ?? ''}';
    if (code == 'superadmin_required') return 'Only the owner can issue reset links for protected accounts.';
    if (code == 'no_email_account') return 'This account signs in with the phone OTP; there is no email password to reset.';
    return 'Try again in a moment.';
  }
}
