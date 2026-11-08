import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/catalog.dart';
import '../data/dropoff_api.dart';
import '../data/analytics_service.dart';
import '../data/push_service.dart';
import '../l10n/app_localizations.dart';
import '../main.dart';
import '../screens/admin_screen.dart';
import '../screens/chat_screen.dart';
import '../screens/legal_screen.dart';
import '../state/app_store.dart';
import '../ui/app_theme.dart';
import '../services/device_lock.dart';

/// Email + password sign in / create account (the JWT + phone persist locally;
/// the ops device-link stays separate under Team).
class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _phone = TextEditingController();
  final _fullName = TextEditingController();
  final _referral = TextEditingController();
  final _otpPhone = TextEditingController();
  final _otpCode = TextEditingController();
  final bool _creating = false;
  bool _busy = false;
  final bool _agreed = false;
  bool _remember = true;
  bool _obscure = true;
  bool _otpBusy = false;
  bool _otpSent = false;
  bool _photoBusy = false;
  String? _otpMsg;
  String? _error;

  // Self-contained create-account modal (kept separate from the sign-in flow so
  // the default Account screen is always sign-in first).
  final _cEmail = TextEditingController();
  final _cPassword = TextEditingController();
  final _cPhone = TextEditingController();
  final _cFullName = TextEditingController();
  final _cReferral = TextEditingController();
  bool _cAgreed = false;
  bool _cBusy = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _phone.dispose();
    _fullName.dispose();
    _referral.dispose();
    _otpPhone.dispose();
    _otpCode.dispose();
    _cEmail.dispose();
    _cPassword.dispose();
    _cPhone.dispose();
    _cFullName.dispose();
    _cReferral.dispose();
    super.dispose();
  }

  Future<void> _sendOtp() async {
    setState(() { _otpBusy = true; _otpMsg = null; });
    final res = await DropOffApi.requestOtp(_otpPhone.text);
    if (!mounted) return;
    setState(() {
      _otpBusy = false;
      if (res.ok && res.body['sent'] == true) {
        _otpSent = true;
        _otpMsg = 'Code sent by SMS — it expires in 10 minutes.';
      } else if (res.ok) {
        _otpMsg = 'SMS could not be delivered (${res.body['sms_error'] ?? 'gateway error'}). Use email sign-in below.';
      } else {
        _otpMsg = 'Could not send a code (${res.error}). Try again shortly.';
      }
    });
  }

  Future<void> _verifyOtp() async {
    setState(() { _otpBusy = true; _otpMsg = null; });
    final ok = await AppScope.of(context).confirmOtp(_otpPhone.text, _otpCode.text);
    if (!mounted) return;
    setState(() {
      _otpBusy = false;
      _otpMsg = ok ? null : 'Wrong or expired code — request a new one.';
    });
    if (ok) {
      unawaited(PushService.register());
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Device linked.')));
    }
  }

  bool get _inputsValid {
    final emailOk = _email.text.trim().contains('@');
    final passOk = _password.text.length >= 8;
    if (!emailOk || !passOk) return false;
    if (_creating) {
      final digits = _phone.text.replaceAll(RegExp(r'[^0-9]'), '');
      return digits.length >= 9 && _agreed;
    }
    return true;
  }

  Future<void> _submit() async {
    final store = AppScope.of(context);
    setState(() { _busy = true; _error = null; });
    final ok = _creating
        ? await store.registerEmail(
            email: _email.text.trim(),
            password: _password.text,
            phone: _phone.text,
            fullName: _fullName.text.trim().isEmpty ? null : _fullName.text.trim(),
            remember: _remember,
          )
        : await store.loginEmail(_email.text.trim(), _password.text, remember: _remember);
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      if (_creating && _referral.text.trim().isNotEmpty) {
        unawaited(DropOffApi.claimReferral(_referral.text.trim()));
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_creating ? 'Account created — you are signed in.' : 'Signed in.'),
      ));
    } else {
      setState(() => _error = store.lastAuthError ?? AppStore.authErrorText('unknown'));
    }
  }

  /// Create account from the modal bottom sheet — self-contained, never
  // entangled with the sign-in form above.
  Future<void> _createSubmit() async {
    final store = AppScope.of(context);
    if (!_cAgreed) {
      if (!mounted) return;
      setState(() => _cBusy = false);
      return;
    }
    final digits = _cPhone.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length < 9) {
      if (!mounted) return;
      setState(() { _cBusy = false; });
      return;
    }
    setState(() { _cBusy = true; });
    final ok = await AppScope.of(context).registerEmail(
      email: _cEmail.text.trim(),
      password: _cPassword.text,
      phone: _cPhone.text,
      fullName: _cFullName.text.trim().isEmpty ? null : _cFullName.text.trim(),
      remember: false,
    );
    if (!mounted) return;
    setState(() => _cBusy = false);
    if (ok) {
      if (_cReferral.text.trim().isNotEmpty) {
        unawaited(DropOffApi.claimReferral(_cReferral.text.trim()));
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Account created — you are signed in.')));
    } else {
      setState(() => _error = store.lastAuthError ?? AppStore.authErrorText('unknown'));
    }
  }

  void _showCreateAccountSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Create account', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 19)),
            const SizedBox(height: 4),
            const Text('Your phone is the mobile-money identity for refunds, and the address parcels find you by — every parcel sent to this number appears automatically. Email is the sign-in key.', style: TextStyle(color: AppColors.muted, fontSize: 12, height: 1.4)),
            const SizedBox(height: 14),
            TextField(controller: _cEmail, keyboardType: TextInputType.emailAddress, autofillHints: const [AutofillHints.email], decoration: const InputDecoration(labelText: 'Email')),
            const SizedBox(height: 12),
            TextField(controller: _cPassword, obscureText: true, autofillHints: const [AutofillHints.password], decoration: const InputDecoration(labelText: 'Password (8+ chars)', helperText: 'At least 8 characters')),
            const SizedBox(height: 12),
            TextField(controller: _cPhone, keyboardType: TextInputType.phone, autofillHints: const [AutofillHints.telephoneNumber], decoration: const InputDecoration(labelText: 'Mobile money phone', helperText: '09…, 097… or +260… — parcels addressed to it appear automatically')),
            const SizedBox(height: 12),
            TextField(controller: _cFullName, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Full name (optional)')),
            const SizedBox(height: 12),
            TextField(controller: _cReferral, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'Referral code (optional)', hintText: 'DRP-XXXXX', prefixIcon: Icon(Icons.redeem_rounded))),
            const SizedBox(height: 14),
            Row(children: [
              Checkbox(value: _cAgreed, onChanged: (v) => setSheetState(() => _cAgreed = v ?? false), visualDensity: VisualDensity.compact),
              const SizedBox(width: 8),
              Expanded(child: RichText(text: TextSpan(style: const TextStyle(color: AppColors.muted, fontSize: 12), children: [
                const TextSpan(text: 'I agree to the '),
                TextSpan(text: 'Terms of use', style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.forest), recognizer: TapGestureRecognizer()..onTap = () => Navigator.of(ctx).push(MaterialPageRoute(builder: (_) => const LegalScreen(title: 'Terms of use', asset: 'assets/legal/terms.md')))),
                const TextSpan(text: ' and '),
                TextSpan(text: 'Privacy policy', style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.forest), recognizer: TapGestureRecognizer()..onTap = () => Navigator.of(ctx).push(MaterialPageRoute(builder: (_) => const LegalScreen(title: 'Privacy policy', asset: 'assets/legal/privacy.md')))),
              ]))),
            ]),
            if (_error != null) ...[const SizedBox(height: 10), Text(_error!, style: const TextStyle(color: Color(0xFFB3261E), fontWeight: FontWeight.w700, fontSize: 13))],
            const SizedBox(height: 12),
            SizedBox(width: double.infinity, child: FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
              onPressed: _cBusy ? null : _createSubmit,
              icon: _cBusy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.person_add_alt_1),
              label: const Text('Create account'),
            )),
          ]),
        ),
      ),
    );
  }

  Future<void> _unlink() async {
    await AppScope.of(context).unlink();
    if (mounted) setState(() {});
  }

  Future<void> _openDevices() async {
    final data = await DropOffApi.get('/me/devices');
    if (!mounted) return;
    final list = (((data?['devices'] as List?) ?? const [])).cast<Map<String, dynamic>>();
    AnalyticsService.instance.track(feature: 'devices', action: 'open', context: 'account_devices');
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (sheetContext) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final rows = List<Map<String, dynamic>>.of(list);
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Row(children: [
                  Icon(Icons.devices, color: AppColors.forest),
                  SizedBox(width: 8),
                  Text('Devices signed in', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
                ]),
                const SizedBox(height: 6),
                const Text('Every phone/tablet this account has opened DropOff from. Tap revoke to sign that device out — it cannot be used again until re-authenticated.',
                    style: TextStyle(color: AppColors.muted, fontSize: 11.5, height: 1.35)),
                const SizedBox(height: 10),
                if (rows.isEmpty)
                  const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('No devices on record yet — once you sign in on something, it shows here.', style: TextStyle(color: AppColors.muted, fontSize: 12)))
                else
                  ...rows.map((d) {
                    final isCurrent = d['is_current_session'] == true;
                    final trusted = d['trusted'] == true;
                    final tz = '${d['last_seen'] ?? ''}';
                    final parts = tz.split(' ');
                    final day = parts.isNotEmpty ? parts.first : tz;
                    final time = parts.length >= 2 ? parts[1] : '';
                    final ua = '${d['user_agent'] ?? d['device_id'] ?? 'unknown'}';
                    final ip = '${d['ip'] ?? 'unknown'}';
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
                        child: Row(children: [
                          const Icon(Icons.phone_iphone, size: 22, color: AppColors.muted),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Row(children: [
                                Expanded(child: Text(ua, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5))),
                                if (isCurrent)
                                  const Padding(padding: EdgeInsets.only(left: 6), child: Chip(visualDensity: VisualDensity.compact, label: Text('This device', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800)))),
                              ]),
                              const SizedBox(height: 2),
                              Text('$day $time · IP $ip${trusted ? '' : ' (revoked)'}', style: const TextStyle(color: AppColors.muted, fontSize: 11)),
                            ]),
                          ),
                          TextButton(
                            onPressed: isCurrent
                                ? null
                                : () async {
                                    final ok = await DropOffApi.post('/me/devices/${d['id']}/revoke', const {});
                                    if (ok.ok && mounted) {
                                      setSheetState(() {
                                        d['trusted'] = false;
                                      });
                                      _snackPhoto('Device revoked.');
                                    } else if (mounted) {
                                      _snackPhoto('Could not revoke this device.');
                                    }
                                  },
                            child: Text(isCurrent ? 'current' : 'Revoke'),
                          ),
                        ]),
                      ),
                    );
                  }),
                const SizedBox(height: 6),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final ok = await DropOffApi.post('/me/devices/revoke-others', const {});
                      if (!mounted) return;
                      ScaffoldMessenger.of(sheetContext).showSnackBar(SnackBar(content: Text(ok.ok ? 'Signed out on all other devices.' : 'Could not sign out everywhere.')));
                      if (ok.ok) Navigator.of(sheetContext).pop();
                    },
                    icon: const Icon(Icons.logout, size: 18),
                    label: const Text('Sign out on all other devices'),
                  ),
                ),
              ]),
            ),
          );
        },
      ),
    );
  }

  String get _biomeDescription =>
      'On: opening DropOff asks for your fingerprint or face — your parcels and bookings are nobody else\'s business. Off: the app opens straight away.';

  String _localeLabel(AppLocalizations l10n, String? code) {
    switch ((code ?? 'en').toLowerCase()) {
      case 'ny': return l10n.languageNyanja;
      case 'bem': return l10n.languageBemba;
      case 'toi': return l10n.languageTongaZambia;
      case 'loz': return l10n.languageLozi;
      default: return l10n.languageEnglish;
    }
  }

  Future<void> _showLanguagePicker(AppStore store) async {
    final l10n = AppLocalizations.of(context);
    final options = <({String code, String label})>[
      (code: 'en', label: l10n.languageEnglish),
      (code: 'ny', label: l10n.languageNyanja),
      (code: 'bem', label: l10n.languageBemba),
      (code: 'toi', label: l10n.languageTongaZambia),
      (code: 'loz', label: l10n.languageLozi),
    ];
    String selected = store.localeCode ?? 'en';
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Align(alignment: Alignment.centerLeft, child: Text(l10n.selectLanguage, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900))),
            ),
            RadioGroup<String>(
              groupValue: selected,
              onChanged: (v) async {
                if (v == null) return;
                setSheet(() => selected = v);
                await store.setLocaleCode(v);
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final o in options)
                    RadioListTile<String>(value: o.code, title: Text(o.label)),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ]),
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _setBiometric(bool on, AppStore store) async {
    if (on) {
      final ok = await DeviceLock.isAvailable;
      if (!ok) {
        if (!mounted) return;
        _snackPhoto('No fingerprint or face enrolled on this device - add one in your phone settings first.');
        return;
      }
    }
    await store.setBiometricEnabled(on);
    if (!mounted) return;
    setState(() {});
    _snackPhoto(on ? 'Fingerprint/face unlock is on for this phone.' : 'Fingerprint/face unlock is off.');
  }

  // ---- profile photo (every account type) -----------------------------------

  Future<void> _editPhoto() async {
    if (_photoBusy) return;
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.photo_camera), title: const Text('Take photo with camera'), onTap: () => Navigator.pop(ctx, ImageSource.camera)),
          ListTile(leading: const Icon(Icons.photo_library), title: const Text('Pick from gallery'), onTap: () => Navigator.pop(ctx, ImageSource.gallery)),
        ]),
      ),
    );
    if (source == null) return;
    final picked = await ImagePicker().pickImage(source: source, maxWidth: 1200, imageQuality: 85);
    if (picked == null) return;
    setState(() => _photoBusy = true);
    final bytes = await picked.readAsBytes();
    final name = picked.name.isNotEmpty ? picked.name : 'me.jpg';
    final up = await DropOffApi.uploadImage(bytes, name, kind: 'selfie');
    if (!mounted) return;
    if (!up.ok) {
      setState(() => _photoBusy = false);
      _snackPhoto('Upload failed (${up.error}).');
      return;
    }
    final url = '${up.body['url'] ?? ''}';
    final res = await DropOffApi.addMePhoto(url);
    if (!mounted) return;
    setState(() => _photoBusy = false);
    if (!res.ok) {
      _snackPhoto('Could not save photo (${res.error}).');
      return;
    }
    await AppScope.of(context).refreshRole();
    if (!mounted) return;
    final st = '${res.body['verification_status'] ?? ''}';
    _snackPhoto(st == 'pending'
        ? 'Photo saved — it does not look like one person, so you are back in the review queue.'
        : 'Photo saved — sellers will see you on the tracking page.');
  }

  Future<void> _removePhoto() async {
    if (_photoBusy) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Remove profile photo?'),
        content: const Text('Your photo will be removed and initials will be shown instead.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Remove')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _photoBusy = true);
    final res = await DropOffApi.removeMePhoto();
    if (!mounted) return;
    setState(() => _photoBusy = false);
    if (!res.ok) {
      _snackPhoto('Could not remove photo (${res.error}).');
      return;
    }
    await AppScope.of(context).refreshRole();
    if (mounted) _snackPhoto('Photo removed.');
  }

  void _snackPhoto(String t) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));

  String _initialsOf(String? seed) {
    final parts = (seed ?? '').trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    return parts.take(2).map((s) => s[0].toUpperCase()).join();
  }

  Widget _avatar(String? photoUrl, String? seed, double radius) {
    final initials = _initialsOf(seed);
    return CircleAvatar(
      radius: radius,
      backgroundColor: AppColors.forest.withValues(alpha: 0.12),
      child: photoUrl == null || photoUrl.isEmpty
          ? Text(initials, style: TextStyle(fontWeight: FontWeight.w900, fontSize: radius * 0.62, color: AppColors.forest))
          : ClipOval(
              child: Image.network(
                '${DropOffApi.baseUrl}$photoUrl',
                headers: DropOffApi.authHeaders,
                width: radius * 2,
                height: radius * 2,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Text(initials, style: TextStyle(fontWeight: FontWeight.w900, fontSize: radius * 0.62, color: AppColors.forest)),
              ),
            ),
    );
  }

  Future<void> _forgotPassword() async {
    final email = _email.text.trim();
    if (!email.contains('@')) {
      setState(() => _error = AppStore.authErrorText('invalid_email'));
      return;
    }
    final store = AppScope.of(context);
    setState(() { _busy = true; _error = null; });
    final res = await store.forgotPassword(email);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!res.ok) {
      setState(() => _error = AppStore.authErrorText(res.body['error'] as String? ?? 'unknown'));
      return;
    }
    final dev = res.body['dev_reset_link'] as String?;
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Check your email'),
        content: Text(
          dev != null
              ? 'Email delivery is not configured yet — reset link for this build:\n\n$dev'
              : 'If $email has an account, a reset link valid for 1 hour is on its way.',
        ),
        actions: <Widget>[TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
      ),
    );
  }

  Future<void> _resendVerification() async {
    final email = _email.text.trim();
    if (!email.contains('@')) {
      setState(() => _error = AppStore.authErrorText('invalid_email'));
      return;
    }
    final store = AppScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final res = await store.resendVerification(email);
    if (!mounted) return;
    messenger.showSnackBar(SnackBar(
      content: Text(res.ok ? 'Verification email sent (check spam too).' : 'Could not send right now.'),
    ));
  }

  Widget _legalLink(String title, String asset) => TextButton(
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => LegalScreen(title: title, asset: asset))),
        child: Text(title),
      );

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    final signedIn = store.linked;
    return Scaffold(
      appBar: AppBar(title: const Text('Account')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        children: [
          if (signedIn) ...[
            Card(child: Padding(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                InkWell(
                  borderRadius: BorderRadius.circular(40),
                  onTap: _photoBusy ? null : _editPhoto,
                  child: Stack(children: [
                    _avatar(store.photoUrl, store.fullName ?? store.email ?? store.linkedPhone, 30),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        decoration: BoxDecoration(color: AppColors.forest, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
                        padding: const EdgeInsets.all(3),
                        child: const Icon(Icons.camera_alt, color: Colors.white, size: 12),
                      ),
                    ),
                  ]),
                ),
                const SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Signed in', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
                  const SizedBox(height: 2),
                  Text(store.fullName ?? store.email ?? store.linkedPhone ?? 'Linked device', style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.forest)),
                  if (store.fullName != null && store.email != null) Text(store.email!, style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
                  if (store.linkedPhone != null && store.email != null) Text(store.linkedPhone!, style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
                ])),
                if (_photoBusy) const Padding(padding: EdgeInsets.only(left: 6), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                    onPressed: _photoBusy ? null : _editPhoto,
                    icon: const Icon(Icons.photo_camera_outlined, size: 18),
                    label: Text(store.photoUrl == null ? 'Add photo' : 'Change photo'),
                  ),
                ),
                if (store.photoUrl != null) ...[
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: _photoBusy ? null : _removePhoto,
                    child: const Text('Remove'),
                  ),
                ],
              ]),
              const Divider(height: 24),
              FilledButton.tonalIcon(
                style: FilledButton.styleFrom(backgroundColor: AppColors.line.withValues(alpha: 0.3), foregroundColor: AppColors.ink),
                onPressed: _unlink,
                icon: const Icon(Icons.logout),
                label: const Text('Sign out'),
              ),
            ]))),
            if (signedIn) ...[
              const SizedBox(height: 16),
              Card(child: Padding(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Row(children: [
                  Icon(Icons.fingerprint, color: AppColors.forest),
                  SizedBox(width: 8),
                  Text('Privacy & sign-in', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                ]),
                const SizedBox(height: 2),
                Text(_biomeDescription, style: const TextStyle(color: AppColors.muted, fontSize: 11, height: 1.4)),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Fingerprint / face unlock', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                  subtitle: const Text('Ask for the device biometric to open DropOff on this phone.', style: TextStyle(fontSize: 11.5)),
                  value: store.biometricEnabled,
                  onChanged: (v) => _setBiometric(v, store),
                ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _openDevices,
                    icon: const Icon(Icons.devices, size: 18),
                    label: const Text('Devices signed in'),
                  ),
                ),
                const Divider(height: 20),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.language, color: AppColors.forest),
                  title: Text(AppLocalizations.of(context).selectLanguage, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                  subtitle: Text(_localeLabel(AppLocalizations.of(context), store.localeCode), style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                  trailing: const Icon(Icons.chevron_right, color: AppColors.muted),
                  onTap: () => _showLanguagePicker(store),
                ),
              ]))),
            ],
          ] else ...[
            const Text('Sign in to your account', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
            const SizedBox(height: 6),
            const Text('Phone code or email — your parcels, plans and bookings live behind your account.', style: TextStyle(color: AppColors.muted, fontSize: 12, height: 1.4)),
            const SizedBox(height: 14),
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: 'Email'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _password,
              obscureText: _obscure,
              autofillHints: const [AutofillHints.password],
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Password',
                helperText: 'At least 8 characters',
                suffixIcon: IconButton(
                  tooltip: _obscure ? 'Show password' : 'Hide password',
                  onPressed: () => setState(() => _obscure = !_obscure),
                  icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(children: [
              const Expanded(child: Text("Don't have an account?", style: TextStyle(color: AppColors.muted, fontSize: 13))),
              TextButton(onPressed: _showCreateAccountSheet, child: const Text('Create account', style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.forest))),
            ]),
            if (_error != null) ...[
              const SizedBox(height: 14),
              Text(_error!, style: const TextStyle(color: Color(0xFFB3261E), fontWeight: FontWeight.w700, fontSize: 13)),
            ],
            const SizedBox(height: 10),
            Row(children: [
              Checkbox(
                value: _remember,
                onChanged: (v) => setState(() => _remember = v ?? true),
                visualDensity: VisualDensity.compact,
              ),
              const SizedBox(width: 4),
              const Expanded(
                child: Text('Remember me on this device', style: TextStyle(fontSize: 13, color: AppColors.muted)),
              ),
            ]),
            const SizedBox(height: 8),
            FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              onPressed: (!_busy && _inputsValid) ? _submit : null,
              icon: _busy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(_creating ? Icons.person_add_alt_1 : Icons.login),
              label: Text(_creating ? 'Create account' : 'Sign in'),
            ),
            if (!_creating) ...[
              const SizedBox(height: 8),
              // Wrap (not Row): two long button labels can never overflow or
              // crush each other on narrow phones / large font scales.
              Wrap(alignment: WrapAlignment.center, children: [
                TextButton(
                  onPressed: () => _forgotPassword(),
                  child: const Text('Forgot password?'),
                ),
                TextButton(
                  onPressed: () => _resendVerification(),
                  child: const Text('Resend verification email'),
                ),
              ]),
            ],
            const SizedBox(height: 16),
            Text(
              _creating
                  ? 'Your phone number is the mobile-money identity for refunds and payouts — the email is just the key.'
                  : 'Signing in restores your plans and booking history from the server.',
              style: const TextStyle(color: AppColors.muted, fontSize: 12, height: 1.5),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Wrap(
              alignment: WrapAlignment.center,
              children: [
                _legalLink('Terms of use', 'assets/legal/terms.md'),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6),
                  child: Text('\u2022', style: TextStyle(color: AppColors.muted, fontSize: 12)),
                ),
                _legalLink('Privacy policy', 'assets/legal/privacy.md'),
              ],
            ),
            const SizedBox(height: 22),
            const Row(children: [
              Expanded(child: Divider()),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 10),
                child: Text('or link with your phone', style: TextStyle(color: AppColors.muted, fontSize: 12, fontWeight: FontWeight.w700)),
              ),
              Expanded(child: Divider()),
            ]),
            const SizedBox(height: 14),
            TextField(
              controller: _otpPhone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Mobile number', hintText: '0971234567', prefixIcon: Icon(Icons.phone_outlined)),
            ),
            const SizedBox(height: 10),
            FilledButton.tonal(
              onPressed: _otpBusy ? null : _sendOtp,
              child: Text(_otpSent ? 'Resend one-time code' : 'Send one-time code'),
            ),
            if (_otpSent) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _otpCode,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _verifyOtp(),
                decoration: const InputDecoration(labelText: '6-digit code', prefixIcon: Icon(Icons.password_outlined)),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                onPressed: _otpBusy ? null : _verifyOtp,
                icon: const Icon(Icons.verified_user_outlined),
                label: const Text('Verify & link this device'),
              ),
            ],
            if (_otpMsg != null) ...[
              const SizedBox(height: 10),
              Text(_otpMsg!, style: const TextStyle(color: AppColors.muted, fontSize: 12, height: 1.4), textAlign: TextAlign.center),
            ],
          ],
          if (signedIn) ...[
            const _ReferralCard(),
            const _RecurringCard(),
            Card(
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => const ChatScreen.supportThread(),
                )),
                child: const Padding(
                  padding: EdgeInsets.all(16),
                  child: Row(children: [
                    Icon(Icons.support_agent, color: AppColors.forest),
                    SizedBox(width: 12),
                    Expanded(child: Text('Chat with DropOff support', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14))),
                    Icon(Icons.chevron_right, color: AppColors.muted),
                  ]),
                ),
              ),
            ),
            const _AdminGate(),
          ],
          const _TiersCard(),
          const _PackCodeCard(),
          if (!DropOffApi.enabled && !signedIn) ...[
            const SizedBox(height: 26),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                'Offline build: this device was compiled without the server key, so accounts are unavailable. Bookings still save locally.',
                style: TextStyle(color: AppColors.muted, fontSize: 12, height: 1.5),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Silver / Gold / Platinum plans, exactly what the server bills (the fee line
/// shows the plan price + processing fee charged on the renewal prompt).
class _RecurringCard extends StatefulWidget {
  const _RecurringCard();

  @override
  State<_RecurringCard> createState() => _RecurringCardState();
}

class _RecurringCardState extends State<_RecurringCard> {
  List<Map<String, dynamic>> _plans = const [];
  bool _loading = true;

  static const _weekdays = <int, String>{1: 'Monday', 2: 'Tuesday', 3: 'Wednesday', 4: 'Thursday', 5: 'Friday', 6: 'Saturday', 7: 'Sunday'};

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final plans = await DropOffApi.recurring();
    if (mounted) setState(() { _plans = plans; _loading = false; });
  }

  Future<void> _addPlan() async {
    final store = AppScope.of(context);
    final destCtl = ValueNotifier<String>('Ndola');
    final weightCtl = ValueNotifier<String>('0-5kg');
    final freqCtl = ValueNotifier<String>('weekly');
    final weekdayCtl = ValueNotifier<int?>(2);
    final recipientCtl = TextEditingController();
    final phoneCtl = TextEditingController(text: store.linkedPhone?.replaceAll(RegExp(r'\s'), '') ?? '');
    final descCtl = TextEditingController();
    final error = ValueNotifier<String?>(null);

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => ValueListenableBuilder<String?>(
        valueListenable: error,
        builder: (context, errorText, _) => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Standing order', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            const Text('Pre-load a repeat drop — tap to book it with one tap when due.', style: TextStyle(color: AppColors.muted, fontSize: 13)),
            const SizedBox(height: 14),
            if (errorText != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(errorText, style: const TextStyle(color: Color(0xFFB3261E), fontWeight: FontWeight.w700, fontSize: 12))),
            ValueListenableBuilder<String>(
              valueListenable: destCtl,
              builder: (context, dest, _) => DropdownButtonFormField<String>(
                initialValue: dest,
                decoration: const InputDecoration(labelText: 'Destination'),
                items: [for (final c in cities) DropdownMenuItem(value: c, child: Text(c))],
                onChanged: (v) => destCtl.value = v ?? 'Ndola',
              ),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: ValueListenableBuilder<String>(
                valueListenable: weightCtl,
                builder: (context, w, _) => DropdownButtonFormField<String>(
                  initialValue: w,
                  decoration: const InputDecoration(labelText: 'Weight'),
                  items: const [DropdownMenuItem(value: '0-5kg', child: Text('0-5 kg')), DropdownMenuItem(value: '5-15kg', child: Text('5-15 kg')), DropdownMenuItem(value: '15kg+', child: Text('15 kg+'))],
                  onChanged: (v) => weightCtl.value = v ?? '0-5kg',
                ),
              )),
              const SizedBox(width: 10),
              Expanded(child: ValueListenableBuilder<String>(
                valueListenable: freqCtl,
                builder: (context, f, _) => DropdownButtonFormField<String>(
                  initialValue: f,
                  decoration: const InputDecoration(labelText: 'Frequency'),
                  items: const [DropdownMenuItem(value: 'weekly', child: Text('Weekly')), DropdownMenuItem(value: 'biweekly', child: Text('Biweekly')), DropdownMenuItem(value: 'monthly', child: Text('Monthly'))],
                  onChanged: (v) => freqCtl.value = v ?? 'weekly',
                ),
              )),
            ]),
            const SizedBox(height: 10),
            ValueListenableBuilder<int?>(
              valueListenable: weekdayCtl,
              builder: (context, wd, _) => DropdownButtonFormField<int?>(
                initialValue: wd,
                decoration: const InputDecoration(labelText: 'Day (optional)'),
                items: [const DropdownMenuItem<int?>(value: null, child: Text('Any')), for (final e in _weekdays.entries) DropdownMenuItem<int?>(value: e.key, child: Text(e.value))],
                onChanged: (v) => weekdayCtl.value = v,
              ),
            ),
            const SizedBox(height: 10),
            TextField(controller: recipientCtl, decoration: const InputDecoration(labelText: 'Recipient name', prefixIcon: Icon(Icons.person_outline))),
            const SizedBox(height: 10),
            TextField(controller: phoneCtl, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Recipient phone', prefixIcon: Icon(Icons.phone_outlined))),
            const SizedBox(height: 10),
            TextField(controller: descCtl, decoration: const InputDecoration(labelText: 'What is inside (optional)', prefixIcon: Icon(Icons.inventory_2_outlined))),
            const SizedBox(height: 16),
            FilledButton(onPressed: () async {
              final digits = phoneCtl.text.replaceAll(RegExp(r'[^0-9]'), '');
              if (digits.length < 9) { error.value = 'Recipient phone looks short.'; return; }
              final res = await DropOffApi.createRecurring({
                'dest_city': destCtl.value,
                'weight_class': weightCtl.value,
                'frequency': freqCtl.value,
                'weekday': weekdayCtl.value,
                'recipient_name': recipientCtl.text.trim().isEmpty ? null : recipientCtl.text.trim(),
                'recipient_phone': digits,
                'description': descCtl.text.trim().isEmpty ? null : descCtl.text.trim(),
              });
              if (res.ok) { if (sheetContext.mounted) Navigator.pop(sheetContext, true); }
              else { error.value = 'Could not save (${res.error ?? res.status}).'; }
            }, child: const Text('Save standing order')),
          ]),
        ),
      ),
    );
    recipientCtl.dispose();
    phoneCtl.dispose();
    descCtl.dispose();
    if (saved == true) await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    if (!DropOffApi.enabled) return const SizedBox.shrink();
    return Card(
      margin: const EdgeInsets.only(top: 18),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Expanded(child: Text('Standing orders', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15))),
            TextButton.icon(onPressed: _addPlan, icon: const Icon(Icons.add, size: 18), label: const Text('Add')),
          ]),
          const SizedBox(height: 2),
          const Text('Weekly/biweekly/monthly repeat drops at your depot door. We remember, you tap once to book.', style: TextStyle(color: AppColors.muted, fontSize: 12, height: 1.4)),
          const SizedBox(height: 10),
          if (_loading)
            const Center(child: Padding(padding: EdgeInsets.symmetric(vertical: 12), child: CircularProgressIndicator(strokeWidth: 2)))
          else if (_plans.isEmpty)
            const Text('No standing orders yet.', style: TextStyle(color: AppColors.muted, fontSize: 12))
          else
            ..._plans.map((plan) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                const Icon(Icons.repeat_on, color: AppColors.forest, size: 20),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('→ ${plan['dest_city']} • ${plan['weight_class']}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                  Text(
                    '${plan['frequency']}${plan['weekday'] != null ? ' on ${_weekdays[plan['weekday'] as int] ?? '?'}' : ''}${plan['description'] != null ? ' • ${plan['description']}' : ''}',
                    style: const TextStyle(color: AppColors.muted, fontSize: 11),
                  ),
                ])),
                IconButton(tooltip: 'Delete', icon: const Icon(Icons.delete_outline, color: AppColors.muted), onPressed: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (d) => AlertDialog(
                      title: const Text('Delete recurring plan?'),
                      content: const Text('This will remove the recurring plan. This cannot be undone.'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
                        FilledButton(style: FilledButton.styleFrom(backgroundColor: const Color(0xFFB3261E)), onPressed: () => Navigator.pop(d, true), child: const Text('Delete')),
                      ],
                    ),
                  );
                  if (ok != true) return;
                  await DropOffApi.deleteRecurring((plan['id'] as num).toInt());
                  await _refresh();
                }),
              ]),
            )),
        ]),
      ),
    );
  }
}

class _ReferralCard extends StatefulWidget {
  const _ReferralCard();

  @override
  State<_ReferralCard> createState() => _ReferralCardState();
}

class _ReferralCardState extends State<_ReferralCard> {
  Map<String, dynamic>? _data;
  bool _copied = false;

  @override
  void initState() {
    super.initState();
    DropOffApi.referralCode().then((value) {
      if (mounted) setState(() => _data = value);
    });
  }

  Future<void> _copy() async {
    final code = _data?['code'] as String? ?? '';
    if (code.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: code));
    if (mounted) setState(() => _copied = true);
    await Future<void>.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _copied = false);
  }

  Future<void> _share() async {
    final code = _data?['code'] as String? ?? '';
    if (code.isEmpty) return;
    final text = 'Join me on DropOff — sellers get home pickup to their courier: https://dropoff-api.godfreymoseskalambo.workers.dev · Code $code';
    await launchUrl(Uri.parse('https://wa.me/?text=${Uri.encodeComponent(text)}'), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    if (!DropOffApi.enabled) return const SizedBox.shrink();
    final code = _data?['code'] as String?;
    final stats = _data?['stats'] as Map<String, dynamic>?;
    final rewarded = (stats?['rewarded'] as num?)?.toInt() ?? 0;
    final pending = (stats?['pending'] as num?)?.toInt() ?? 0;
    return Card(
      margin: const EdgeInsets.only(top: 18, bottom: 4),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Invite sellers — earn', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
          const SizedBox(height: 4),
          const Text('When a seller books their first pickup through your code, you get a single-use 20% promo for your own next drop-off.',
              style: TextStyle(color: AppColors.muted, fontSize: 12, height: 1.45)),
          const SizedBox(height: 12),
          Row(children: [
            if (code != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(color: const Color(0xFF10312A), borderRadius: BorderRadius.circular(10)),
                child: Text(code, style: const TextStyle(color: Color(0xFFF6B73C), fontWeight: FontWeight.w900, letterSpacing: 2, fontSize: 16)),
              )
            else
              const SizedBox(width: 140, height: 38, child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))),
            const SizedBox(width: 10),
            IconButton(tooltip: 'Copy code', icon: Icon(_copied ? Icons.check_rounded : Icons.copy, color: AppColors.forest), onPressed: _copy),
            IconButton(tooltip: 'Share on WhatsApp', icon: const Icon(Icons.share_rounded, color: AppColors.forest), onPressed: _share),
          ]),
          const SizedBox(height: 6),
          Text('$rewarded rewarded · $pending waiting (first booking)', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
        ]),
      ),
    );
  }
}

class _TiersCard extends StatefulWidget {
  const _TiersCard();

  @override
  State<_TiersCard> createState() => _TiersCardState();
}

class _TiersCardState extends State<_TiersCard> {
  Future<Map<String, dynamic>?> _loadPlans() => DropOffApi.plans();
  String? _busyTier;
  int _usageCycle = 0;
  Map<String, dynamic>? _current;
  static const Map<String, int> _tierRank = {'weekly': 1, 'silver': 2, 'gold': 3, 'platinum': 4};

  @override
  void initState() {
    super.initState();
    _loadCurrent();
  }

  Future<void> _loadCurrent() async {
    if (!DropOffApi.enabled) return;
    final snap = await DropOffApi.subscription();
    if (!mounted) return;
    setState(() => _current = snap?['subscription'] as Map<String, dynamic>?);
  }

  String _cycleUnit(Map<String, dynamic>? model) {
    final days = (model?['cycle_days'] as num?)?.toInt() ?? 30;
    return switch (days) {
      1 => '/day',
      7 => '/wk',
      _ => '/mo',
    };
  }

  String _windowLabel(Object? windows) {    final list = (windows as List?)?.cast<Object>() ?? const [];
    // Arrival ranges (CAT) — matches the booking slot picker. Cap at 3 so the
    // label can never balloon into a tall vertical stack.
    const ranges = {
      '06:00': '6:00–7:30 AM',
      '10:00': '10:00–11:30 AM',
      '14:00': '2:00–3:30 PM',
    };
    return list.take(3).map((w) => ranges['$w'] ?? '$w').join(' / ');
  }

  Future<void> _chooseTier(String tier) async {
    final store = AppScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    if (!store.linked) {
      messenger.showSnackBar(const SnackBar(content: Text('Sign in first — your plan is tied to your phone.')));
      return;
    }
    final currentTier = '${_current?['tier'] ?? ''}';
    final active = '${_current?['status'] ?? ''}' == 'active';
    if (active && currentTier.isNotEmpty && currentTier != tier) {
      final curRank = _tierRank[currentTier] ?? -1;
      final newRank = _tierRank[tier] ?? -1;
      if (newRank < curRank) {
        messenger.showSnackBar(const SnackBar(content: Text('Downgrades apply automatically at your next renewal — nothing to pay now.')));
        return;
      }
      if (newRank > curRank) {
        setState(() => _busyTier = tier);
        final up = await DropOffApi.upgradeSubscription(tier);
        if (!mounted) return;
        setState(() => _busyTier = null);
        if (!up.ok) {
          messenger.showSnackBar(SnackBar(content: Text(up.error == 'payment_already_pending'
              ? 'A payment prompt is already waiting on your phone — approve it first.'
              : 'Could not upgrade (${up.error}). Try again.')));
          return;
        }
        final extra = ((up.body['amount_zmw'] as num?) ?? 0).toDouble();
        messenger.showSnackBar(SnackBar(content: Text(extra > 0
            ? '${tier.toUpperCase()} is live now — approve the K${extra.toStringAsFixed(2)} prorated prompt.'
            : '${tier.toUpperCase()} is live — nothing extra to pay this cycle.')));
        setState(() => _usageCycle++);
        _loadCurrent();
        AnalyticsService.instance.track(
          feature: 'subscriptions', action: 'upgrade', context: 'account_tiers',
          meta: {'tier': tier},
        );
        return;
      }
    }
    setState(() => _busyTier = tier);
    final res = await DropOffApi.subscribe(tier: tier);
    if (!res.ok) {
      if (!mounted) return;
      setState(() => _busyTier = null);
      messenger.showSnackBar(SnackBar(content: Text('Could not start the plan (${res.error}). Try again.')));
      return;
    }
    // Lipila prompt for the plan price; success activates the plan server-side.
    final pay = await DropOffApi.paySubscription();
    if (!mounted) return;
    if (!pay.ok) {
      setState(() => _busyTier = null);
      // The Lipila prompt never reached the phone (no pending payment is
      // created on a failed init), so there's nothing to "pay from this
      // screen" — let the seller resubscribe to retry the prompt.
      messenger.showSnackBar(SnackBar(content: Text(pay.error == 'lipila_init_failed'
          ? 'Mobile-money prompt failed to start — check your phone/network and tap the plan again.'
          : 'Could not start the mobile-money prompt (${pay.error ?? 'network'}). Tap the plan again.')));
      return;
    }
    final paymentId = '${pay.body['payment_id']}';
    var status = 'pending';
    for (var attempt = 0; attempt < 20 && status == 'pending'; attempt++) {
      await Future<void>.delayed(const Duration(seconds: 2));
      status = await DropOffApi.paymentStatus(paymentId) ?? 'pending';
    }
    if (!mounted) return;
    setState(() { _busyTier = null; _usageCycle++; });
    _loadCurrent();
    AnalyticsService.instance.track(
      feature: 'subscriptions', action: status == 'success' ? 'subscribe' : 'subscribe_pending',
      context: 'account_tiers',
      meta: {'tier': tier, 'status': status},
    );
      messenger.showSnackBar(SnackBar(content: Text(switch (status) {
      'success' when tier == 'weekly' => 'Weekly Sprint is LIVE — 7 days of parcels are ready.',
      'success' => '$tier plan is LIVE — your monthly parcels are ready.',
      'failed' => 'The mobile-money prompt was rejected — pay again from this screen.',
      _ => 'Payment still pending — the plan activates the moment it lands.',
    })));
  }

  @override
  Widget build(BuildContext context) {
    if (!DropOffApi.enabled) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 26),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Send more, pay less', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
              const SizedBox(height: 4),
               const Text(
                'Plans bundle the rider into ONE mobile-money prompt — a 7-day Weekly Sprint, or a monthly Silver / Gold / Platinum plan. Every parcel counts as one — two parcels in one trip to the same receiver = two parcels.',
                style: TextStyle(color: AppColors.muted, fontSize: 12, height: 1.45),
              ),
              const SizedBox(height: 12),
              _PlanUsageMeter(key: ValueKey(_usageCycle)),
              FutureBuilder<Map<String, dynamic>?>(
                future: _loadPlans(),
                builder: (context, snap) {
                  final models = snap.data?['plans'] as Map<String, dynamic>?;
                  if (models == null) {
                    return const Text('Tier prices load when the server is reachable.', style: TextStyle(color: AppColors.muted, fontSize: 12));
                  }
                  const display = <String, ({String label, String blurb})>{
                    'weekly': (label: 'WEEKLY SPRINT', blurb: '20 parcels / 7 days — no monthly lock-in'),
                    'silver': (label: 'SILVER', blurb: '10 parcels / month — low-volume senders'),
                    'gold': (label: 'GOLD', blurb: '25 parcels / month — weekly shippers'),
                    'platinum': (label: 'PLATINUM', blurb: '50 parcels / month — daily bulk senders'),
                  };
                  final currentTier = '${_current?['tier'] ?? ''}';
                  final currentActive = '${_current?['status'] ?? ''}' == 'active';
                  return Column(children: [
                    for (final entry in display.entries)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: _busyTier != null ? null : () => _chooseTier(entry.key),
                          child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: currentActive && currentTier == entry.key
                                ? AppColors.forest.withValues(alpha: 0.08)
                                : AppColors.line.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: currentActive && currentTier == entry.key ? AppColors.forest : AppColors.line,
                              width: currentActive && currentTier == entry.key ? 1.4 : 1,
                            ),
                          ),
                          // Fixed-width price/button rail on the right keeps the
                          // left text block wide enough to read HORIZONTALLY —
                          // the rail can never expand and crush the blurb into a
                          // one-word-per-line vertical ribbon.
                          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Row(children: [
                                  Flexible(
                                    child: Text(entry.value.label,
                                        maxLines: 1, overflow: TextOverflow.ellipsis, softWrap: false,
                                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: 0.4)),
                                  ),
                                  if (currentActive && currentTier == entry.key) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(color: AppColors.forest, borderRadius: BorderRadius.circular(20)),
                                      child: const Text('CURRENT', style: TextStyle(color: Colors.white, fontSize: 8.5, fontWeight: FontWeight.w900, letterSpacing: 0.4)),
                                    ),
                                  ],
                                  if (models[entry.key]?['tag'] != null) ...[
                                    const SizedBox(width: 6),
                                    Flexible(
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(color: AppColors.amber.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(20)),
                                        child: Text('${models[entry.key]['tag']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF7B5710), fontSize: 9.5, fontWeight: FontWeight.w900, letterSpacing: 0.4)),
                                      ),
                                    ),
                                  ],
                                ]),
                                const SizedBox(height: 4),
                                Text(entry.value.blurb,
                                    style: const TextStyle(color: AppColors.muted, fontSize: 12, height: 1.35)),
                                const SizedBox(height: 2),
                                Text(_windowLabel(models[entry.key]?['windows']),
                                    style: const TextStyle(color: AppColors.forest, fontSize: 11, height: 1.35, fontWeight: FontWeight.w600)),
                              ]),
                            ),
                            const SizedBox(width: 10),
                            SizedBox(
                              width: 96,
                              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                                FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerRight,
                                  child: Text('K${models[entry.key]?['fee_zmw'] ?? '—'}${_cycleUnit(models[entry.key])}',
                                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: AppColors.forest)),
                                ),
                                const SizedBox(height: 8),
                                FilledButton(
                                  style: FilledButton.styleFrom(
                                    visualDensity: VisualDensity.compact,
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                  ),
                                  onPressed: _busyTier != null ? null : () => _chooseTier(entry.key),
                                  child: _busyTier == entry.key
                                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                                      : Text(
                                          currentActive && currentTier == entry.key
                                              ? 'Renew'
                                              : currentActive && (_tierRank[entry.key] ?? 0) > (_tierRank[currentTier] ?? 0)
                                                  ? 'Upgrade'
                                                  : 'Choose',
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                                        ),
                                ),
                              ]),
                            ),
                          ]),
                        ),
                        ),
                      ),
                  ]);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bulk/offline plan codes: sold by agents or at market days; redeeming one
/// activates the plan on this number with no payment prompt.
class _PackCodeCard extends StatefulWidget {
  const _PackCodeCard();

  @override
  State<_PackCodeCard> createState() => _PackCodeCardState();
}

class _PackCodeCardState extends State<_PackCodeCard> {
  final _code = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _redeem() async {
    final code = _code.text.trim().toUpperCase();
    if (code.isEmpty) return;
    final store = AppScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    if (!store.linked) {
      messenger.showSnackBar(const SnackBar(content: Text('Sign in first — the plan attaches to your number.')));
      return;
    }
    setState(() => _busy = true);
    final res = await DropOffApi.redeemPackCode(code);
    if (!mounted) return;
    setState(() => _busy = false);
    if (res.ok) {
      _code.clear();
      final tier = '${res.body['tier'] ?? 'plan'}';
      final end = '${res.body['period_end'] ?? ''}'.split(' ').first;
      messenger.showSnackBar(SnackBar(content: Text('$tier plan activated${end.isEmpty ? '' : ' — runs to $end'}. No payment needed.')));
      AnalyticsService.instance.track(
        feature: 'pack_codes', action: 'redeem', context: 'account_pack_code',
        meta: {'tier': tier},
      );
    } else {
      messenger.showSnackBar(SnackBar(content: Text(res.error == 'code_not_found'
          ? 'That plan code was not recognised.'
          : res.error == 'code_used'
              ? 'That plan code has already been used.'
              : 'Could not redeem (${res.error}).')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!DropOffApi.enabled) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Row(children: [
              Icon(Icons.card_membership_outlined, color: AppColors.forest),
              SizedBox(width: 10),
              Expanded(child: Text('Have a plan code?', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15))),
            ]),
            const SizedBox(height: 4),
            const Text('Bought a plan from an agent or at a market day? Redeem the code — it activates instantly on your number.', style: TextStyle(color: AppColors.muted, fontSize: 11.5, height: 1.4)),
            const SizedBox(height: 12),
            TextField(
              controller: _code,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                labelText: 'Plan code',
                hintText: 'DROP-8F2K-19QA',
                prefixIcon: const Icon(Icons.qr_code_2),
                suffixIcon: TextButton(onPressed: _busy ? null : _redeem, child: _busy ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Redeem')),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Live "X of Y parcels used this cycle" meter for the signed-in seller's plan.
/// Shows the Admin console door only when the server says this identity is
/// admin/ops (the owner's phone resolves to admin via OWNER_PHONE).
class _AdminGate extends StatefulWidget {  const _AdminGate();

  @override
  State<_AdminGate> createState() => _AdminGateState();
}

class _AdminGateState extends State<_AdminGate> {
  bool _isAdmin = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final me = await DropOffApi.me();
    if (!mounted) return;
    final role = '${me?['role'] ?? ''}';
    setState(() => _isAdmin = role == 'admin' || role == 'ops');
  }

  @override
  Widget build(BuildContext context) {
    if (!_isAdmin) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AdminScreen())),
          child: const Padding(
            padding: EdgeInsets.all(16),
            child: Row(children: [
              Icon(Icons.admin_panel_settings_outlined, color: AppColors.forest),
              SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Admin console', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                SizedBox(height: 2),
                Text('Stats, security alerts, fraud queue and SMS broadcasts.', style: TextStyle(color: AppColors.muted, fontSize: 11.5, height: 1.3)),
              ])),
              Icon(Icons.chevron_right, color: AppColors.muted),
            ]),
          ),
        ),
      ),
    );
  }
}

class _PlanUsageMeter extends StatefulWidget {
  const _PlanUsageMeter({super.key});

  @override
  State<_PlanUsageMeter> createState() => _PlanUsageMeterState();
}

class _PlanUsageMeterState extends State<_PlanUsageMeter> {
  // Cached: one fetch per mount, not one per parent rebuild.
  late final Future<Map<String, dynamic>?> _future = DropOffApi.subscription();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: _future,
      builder: (context, snap) {
        final sub = snap.data?['subscription'] as Map<String, dynamic>?;
        final plan = snap.data?['plan'] as Map<String, dynamic>?;
        if (sub == null || plan == null || sub['status'] != 'active') return const SizedBox.shrink();
        final cap = (plan['parcels_per_month'] as num?)?.toInt() ?? 0;
        final used = (snap.data?['usage_this_period'] as num?)?.toInt() ?? 0;
        final remaining = (snap.data?['remaining_this_period'] as num?)?.toInt() ?? 0;
        if (cap <= 0) return const SizedBox.shrink();
        final tier = '${sub['tier'] ?? ''}'.toUpperCase();
        final renews = '${sub['period_end'] ?? ''}'.split(' ').first;
        return Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(color: AppColors.forest.withValues(alpha: 0.07), borderRadius: BorderRadius.circular(13)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.inventory_2_outlined, size: 16, color: AppColors.forest),
              const SizedBox(width: 8),
              // Expanded label + FLEXIBLE counter: the trailing count can never
              // squeeze the label into a vertical ribbon.
              Expanded(
                child: Text('$tier plan — $used of $cap parcels used',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text('$remaining left',
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: AppColors.forest)),
              ),
            ]),
            const SizedBox(height: 9),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: (used / cap).clamp(0.0, 1.0),
                minHeight: 6,
                backgroundColor: AppColors.line.withValues(alpha: 0.4),
                color: used >= cap ? AppColors.amber : AppColors.forest,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              used >= cap
                  ? 'Cap reached — extra parcels now pay your tier discount (auto-applied at booking).'
                  : 'Each parcel counts as one. Cycle renews $renews.',
              style: const TextStyle(color: AppColors.muted, fontSize: 11, height: 1.35),
            ),
          ]),
        );
      },
    );
  }
}
