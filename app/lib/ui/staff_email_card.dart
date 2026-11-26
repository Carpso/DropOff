import 'package:flutter/material.dart';

import '../data/dropoff_api.dart';
import '../main.dart';
import 'app_spinner.dart';
import 'app_theme.dart';
import 'app_toast.dart';

/// Provision for owner/admin/ops/CFO accounts to ADD or CHANGE their email
/// (owner directive 2026-11-26).
///
/// Before this, staff rows were explicitly protected from edits, so an
/// OTP-only owner or admin had no way to enter an address for email sign-in or
/// recovery. Email reset remains blocked for protected accounts — it still
/// goes to the account phone — so entering an email never weakens that guard.
class StaffEmailCard extends StatefulWidget {
  const StaffEmailCard({
    super.key,
    required this.phone,
    this.email,
  });

  final String? phone;
  final String? email;

  @override
  State<StaffEmailCard> createState() => _StaffEmailCardState();
}

class _StaffEmailCardState extends State<StaffEmailCard> {
  late final TextEditingController _ctl;
  bool _busy = false;
  String? _saved;

  @override
  void initState() {
    super.initState();
    _ctl = TextEditingController(text: widget.email ?? '');
    _saved = widget.email;
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  bool get _valid => RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$').hasMatch(_ctl.text.trim());
  bool get _changed => _ctl.text.trim().toLowerCase() != (_saved ?? '').toLowerCase();

  Future<void> _save() async {
    if (!_valid || !_changed || (widget.phone ?? '').isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    final res = await DropOffApi.setStaffEmail(widget.phone!, _ctl.text.trim());
    if (!mounted) return;
    setState(() => _busy = false);
    if (!res.ok) {
      final code = res.error ?? '';
      AppToast.show(context, switch (code) {
        'email_already_registered' => 'That email is already linked to another account.',
        'invalid_email' => 'Enter a valid email address.',
        'staff_required' => 'Only staff accounts can set an email here.',
        'network_error' => "Can't reach DropOff right now — try again.",
        _ => 'Could not save that email. Try again.',
      });
      return;
    }
    final verified = res.body['verification_sent'] == true;
    setState(() => _saved = '${res.body['email'] ?? _ctl.text.trim()}');
    try {
      await AppScope.of(context).refreshRole(force: true);
    } catch (_) {
      /* refresh is best-effort — the save already landed */
    }
    if (!mounted) return;
    AppToast.show(
      context,
      verified
          ? 'Email saved. Open the confirmation link we sent to finish verifying it.'
          : 'Email saved. We could not send the confirmation message just now — you can resend it from the admin console.',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.forest.withValues(alpha: 0.24)),
        boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 8, offset: Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(color: AppColors.forest.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(11)),
            child: const Icon(Icons.alternate_email_rounded, color: AppColors.forest, size: 20),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text('Your email address',
                style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w900, letterSpacing: -0.2)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: AppColors.amber.withValues(alpha: 0.20), borderRadius: BorderRadius.circular(20)),
            child: const Text('STAFF', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 0.6, color: AppColors.ink)),
          ),
        ]),
        const SizedBox(height: 10),
        const Text(
          'Add or change the email on your staff account. We send a confirmation link to the new address. '
          'Owner and admin passwords are always reset with a link to your phone, never by email.',
          style: TextStyle(fontSize: 12, height: 1.4, color: AppColors.muted),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _ctl,
          onChanged: (_) => setState(() {}),
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          autofillHints: const [AutofillHints.email],
          enabled: !_busy,
          decoration: const InputDecoration(
            labelText: 'Email address',
            hintText: 'you@carpsosolutions.store',
            prefixIcon: Icon(Icons.mail_outline_rounded, size: 20),
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _busy || !_valid || !_changed ? null : _save,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_busy)
                  const AppLogoSpinner(size: 16, color: Colors.white)
                else
                  const Icon(Icons.save_outlined, size: 17),
                const SizedBox(width: 8),
                Text(_busy ? 'Saving…' : 'Save email',
                    style: const TextStyle(fontWeight: FontWeight.w800)),
              ],
            ),
          ),
        ),
        if ((widget.phone ?? '').isEmpty) ...[
          const SizedBox(height: 8),
          const Text('Sign in once with your phone number so we know which account to update.',
              style: TextStyle(fontSize: 11.5, color: AppColors.danger)),
        ],
      ]),
    );
  }
}
