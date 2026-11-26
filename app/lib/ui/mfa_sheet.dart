import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/dropoff_api.dart';
import '../main.dart';
import 'app_sheet.dart';
import 'app_spinner.dart';
import 'app_theme.dart';
import 'app_toast.dart';

/// Asks for the 6-digit authenticator code after a sign-in that passed the
/// first factor. The challenge token on the store is useless on its own — the
/// API only swaps it for a session once this code verifies.
Future<bool> showMfaChallengeSheet(BuildContext context) async {
  final ctl = TextEditingController();
  var busy = false;
  var error = '';
  final ok = await showAppSheet<bool>(
    context,
    child: StatefulBuilder(builder: (ctx, setSheet) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.line, borderRadius: BorderRadius.circular(4)))),
        const SizedBox(height: 16),
        Row(children: [
          Container(width: 44, height: 44,
              decoration: BoxDecoration(color: AppColors.forest.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.security_rounded, color: AppColors.forest)),
          const SizedBox(width: 12),
          const Expanded(child: Text('Two-factor check',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900))),
        ]),
        const SizedBox(height: 10),
        const Text('Open your authenticator app and enter the current 6-digit code. '
            'Your password / SMS code was accepted — this is the second step.',
            style: TextStyle(fontSize: 12.5, color: AppColors.muted, height: 1.4)),
        const SizedBox(height: 14),
        TextField(controller: ctl, autofocus: true, keyboardType: TextInputType.number,
            maxLength: 6, enabled: !busy,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: '6-digit code', hintText: '000000',
              border: const OutlineInputBorder(), isDense: true,
              errorText: error.isEmpty ? null : error,
            )),
        const SizedBox(height: 14),
        SizedBox(width: double.infinity, child: FilledButton.icon(
          onPressed: busy ? null : () async {
            if (ctl.text.trim().length != 6) {
              setSheet(() => error = 'Enter all 6 digits.');
              return;
            }
            setSheet(() { busy = true; error = ''; });
            final success = await AppScope.of(ctx).completeMfa(ctl.text.trim());
            if (!ctx.mounted) return;
            if (success) {
              Navigator.of(ctx).pop(true);
            } else {
              setSheet(() { busy = false; error = AppScope.of(ctx).lastAuthError ?? 'Wrong code.'; });
            }
          },
          icon: busy ? const AppLogoSpinner(size: 16, color: Colors.white)
              : const Icon(Icons.lock_open_outlined, size: 17),
          label: Text(busy ? 'Checking…' : 'Verify and sign in'),
        )),
      ],
    )),
  );
  return ok == true;
}

/// Account card: turn MFA on/off (available to every account).
class MfaSettingsCard extends StatefulWidget {
  const MfaSettingsCard({super.key});

  @override
  State<MfaSettingsCard> createState() => _MfaSettingsCardState();
}

class _MfaSettingsCardState extends State<MfaSettingsCard> {
  bool? _enabled;
  bool _busy = false;
  Map<String, dynamic>? _enrollment;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await DropOffApi.mfaStatus();
      if (mounted) setState(() => _enabled = data?['enabled'] == true);
    } catch (_) {
      if (mounted) setState(() => _enabled = false);
    }
  }

  Future<void> _enroll() async {
    setState(() => _busy = true);
    final data = await DropOffApi.mfaEnroll();
    if (!mounted) return;
    setState(() { _busy = false; _enrollment = data; });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _showEnrollment();
    });
  }

  Future<void> _confirm(String code) async {
    setState(() => _busy = true);
    final res = await DropOffApi.mfaConfirm(code);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!res.ok) {
      AppToast.show(context, res.error == 'wrong_code' ? 'Wrong code — check your app and try again.' : 'Could not turn on two-factor authentication.');
      return;
    }
    final codes = ((res.body['recovery_codes'] as List?) ?? const []).map((e) => '$e').toList();
    setState(() { _enabled = true; _enrollment = null; });
    if (codes.isNotEmpty) {
      await Clipboard.setData(ClipboardData(text: codes.join('\n')));
    }
    if (!mounted) return;
    await showInfoSheet(
      context,
      title: 'Two-factor authentication is ON',
      message: codes.isEmpty
          ? 'Your account now asks for a 6-digit code at every sign-in.'
          : 'Your account now asks for a 6-digit code at every sign-in. '
              '${codes.length} recovery codes were copied to your clipboard — store them somewhere safe.',
      icon: Icons.verified_user_outlined,
    );
  }

  Future<void> _disable() async {
    final ctl = TextEditingController();
    final ok = await showAppSheet<bool>(
      context,
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.line, borderRadius: BorderRadius.circular(4)))),
        const SizedBox(height: 16),
        const Text('Turn off two-factor authentication?',
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        const Text('Enter a current 6-digit code (or one recovery code) to confirm. '
            'Without the code, nobody can switch it off.',
            style: TextStyle(fontSize: 12.5, color: AppColors.muted)),
        const SizedBox(height: 12),
        TextField(controller: ctl, autofocus: true, keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Code', border: OutlineInputBorder(), isDense: true)),
        const SizedBox(height: 14),
        SizedBox(width: double.infinity, child: FilledButton(
          onPressed: () {
            if (ctl.text.trim().isEmpty) return;
            Navigator.of(context).pop(true);
          },
          child: const Text('Turn off'),
        )),
      ]),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    final res = await DropOffApi.mfaDisable(ctl.text.trim());
    if (!mounted) return;
    setState(() { _busy = false; if (res.ok) _enabled = false; });
    AppToast.show(context, res.ok
        ? 'Two-factor authentication is off.'
        : 'That code did not match — nothing changed.');
  }

  void _showEnrollment() {
    final secret = '${_enrollment?['secret'] ?? ''}';
    final uri = '${_enrollment?['uri'] ?? ''}';
    final ctl = TextEditingController();
    showAppSheet<void>(
      context,
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.line, borderRadius: BorderRadius.circular(4)))),
        const SizedBox(height: 16),
        const Text('Set up two-factor authentication',
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        const Text('1. Open your authenticator app and add a new account. '
            '2. Scan the setup link below or paste the secret. '
            '3. Enter the 6-digit code to finish.',
            style: TextStyle(fontSize: 12.5, height: 1.45, color: AppColors.muted)),
        const SizedBox(height: 12),
        SelectableText(uri, style: const TextStyle(fontSize: 11.5, color: AppColors.forest)),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: SelectableText(secret, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, letterSpacing: 1.5))),
          IconButton(tooltip: 'Copy secret', icon: const Icon(Icons.copy_all_outlined, size: 18),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: secret));
                // ignore: use_build_context_synchronously
                if (context.mounted) AppToast.show(context, 'Secret copied.');
              }),
        ]),
        const SizedBox(height: 12),
        TextField(controller: ctl, autofocus: true, keyboardType: TextInputType.number,
            maxLength: 6, inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: '6-digit code', border: OutlineInputBorder(), isDense: true)),
        const SizedBox(height: 14),
        SizedBox(width: double.infinity, child: FilledButton.icon(
          onPressed: _busy || ctl.text.trim().length != 6 ? null : () => _confirm(ctl.text.trim()),
          icon: const Icon(Icons.security_rounded, size: 17),
          label: Text(_busy ? 'Checking…' : 'Turn on two-factor authentication'),
        )),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.forest.withValues(alpha: 0.24))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 38, height: 38,
              decoration: BoxDecoration(color: AppColors.forest.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(11)),
              child: const Icon(Icons.security_rounded, color: AppColors.forest, size: 20)),
          const SizedBox(width: 10),
          const Expanded(child: Text('Two-factor authentication',
              style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w900))),
          if (_enabled == true)
            Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: AppColors.forest.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
              child: const Text('ON', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w900, color: AppColors.forest))),
        ]),
        const SizedBox(height: 8),
        const Text('Add an authenticator code on top of your password or SMS code. '
            'Available to every account — you choose whether to switch it on.',
            style: TextStyle(fontSize: 12, height: 1.4, color: AppColors.muted)),
        const SizedBox(height: 12),
        SizedBox(width: double.infinity, child: _enabled == null
            ? const Center(child: AppLogoSpinner(size: 20))
            : FilledButton.tonal(
                onPressed: _busy ? null : _enabled! ? _disable : _enroll,
                child: Text(_busy ? 'Working…' : _enabled! ? 'Turn off two-factor authentication' : 'Set up two-factor authentication'),
              )),
      ]),
    );
  }
}
