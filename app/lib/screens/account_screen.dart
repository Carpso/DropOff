import '../ui/app_toast.dart';
import '../ui/proof_upload_overlay.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/services.dart';

import '../data/catalog.dart';
import '../widgets/help_sheet.dart';
import '../widgets/tutorial_sheet.dart';
import '../data/dropoff_api.dart';
import '../data/analytics_service.dart';
import '../data/push_service.dart';
import '../main.dart';
import '../screens/admin_screen.dart';
import '../screens/tickets_screen.dart';
import '../screens/legal_screen.dart';
import '../screens/plan_receipt_screen.dart';
import '../state/app_store.dart';
import '../ui/app_theme.dart';
import '../ui/app_sheet.dart';
import '../ui/in_app_browser.dart';
import '../services/device_lock.dart';
import '../ui/money_errors.dart';
import '../ui/app_spinner.dart';
import '../services/step_sounds.dart';
import '../ui/offline_map_sheet.dart';
import '../ui/staff_email_card.dart';
import '../ui/mfa_sheet.dart';

/// Email + password sign in / create account (the JWT + phone persist locally;
/// the ops device-link stays separate under Team).
class AccountScreen extends StatefulWidget {
  /// Optional one-shot referral code for pre-fill (used by the dropoff.carpsosolutions.store/r/CODE deep link).
  static String? prefillReferral;
  final bool focusPlans;
  final bool openCreate;
  const AccountScreen({super.key, this.focusPlans = false, this.openCreate = false});

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
  bool _stepSounds = true; // step-complete chime — persisted option (owner 2026-11-20)
  bool _voiceGuidance = true; // spoken turns — persisted option (owner audit 2026-11-21)
  double _voiceRate = 0.5;
  String? _otpMsg;
  String? _error;
  // "Resend verification email" only matters when the error actually mentions
  // verification — otherwise it just crowds the sign-in screen (owner request).
  bool _showResendVerification = false;
  final _listController = ScrollController();
  final _plansAnchorKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    // /r/CODE deep link: prefill the referral box on account creation.
    if (widget.focusPlans) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToPlans());
    }
    if (widget.openCreate) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showCreateAccountSheet();
      });
    }
    StepSounds.load().then((_) {
      if (mounted) {
        setState(() {
          _stepSounds = StepSounds.enabled;
          _voiceGuidance = StepSounds.voiceGuidance;
          _voiceRate = StepSounds.voiceRate;
        });
      }
    });
  }

  void _scrollToPlans() {
    final ctx = _plansAnchorKey.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 350), alignment: 0);
  }

  // Create-account modal lives as a self-contained StatefulWidget at the
  // bottom of this file (own controllers, error and busy state).

  @override
  void dispose() {
    _listController.dispose();
    _email.dispose();
    _password.dispose();
    _phone.dispose();
    _fullName.dispose();
    _referral.dispose();
    _otpPhone.dispose();
    _otpCode.dispose();
    super.dispose();
  }

  Future<void> _sendOtp() async {
    // Client-side gate first: the server would answer 400 and the user
    // shouldn't have to learn what shape a Zambian number takes by failing.
    final digits = _otpPhone.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length < 9 || digits.length > 15) {
      setState(() => _otpMsg = 'Enter a full mobile number — 09…, 097… or +260…');
      return;
    }
    setState(() { _otpBusy = true; _otpMsg = null; });
    final res = await DropOffApi.requestOtp(_otpPhone.text);
    if (!mounted) return;
    setState(() {
      _otpBusy = false;
      if (res.ok && res.body['sent'] == true) {
        _otpSent = true;
        _otpCode.clear();
        _otpMsg = 'Code sent by SMS — it expires in 10 minutes.';
        if (context.mounted) AppToast.show(context, 'Code sent — check your SMS.');
      } else if (res.ok) {
        _otpMsg = 'SMS could not be delivered. Use email sign-in below.';
      } else {
        final why = res.error ?? 'error';
        _otpMsg = why == 'network_error'
            // Name the usual blockers explicitly — "network error" alone sent
            // this owner chasing the wrong screen half the morning.
            ? 'Can\'t reach the DropOff API — check your connection, and any Private DNS / VPN / ad-blocker.'
            : 'Could not send a code ($why). Try again shortly.';
      }
    });
  }

  Future<void> _verifyOtp() async {
    setState(() { _otpBusy = true; _otpMsg = null; });
    final store = AppScope.of(context);
    final ok = await store.confirmOtp(_otpPhone.text, _otpCode.text);
    if (!mounted) return;
    if (store.pendingMfaChallenge != null) {
      final done = await showMfaChallengeSheet(context);
      if (!mounted) return;
      setState(() {
        _otpBusy = false;
        _otpMsg = done ? null : (store.lastAuthError ?? 'Second-factor check needed.');
      });
      if (done) {
        unawaited(PushService.register());
        AppToast.show(context, 'Device linked.');
      }
      return;
    }
    setState(() {
      _otpBusy = false;
      _otpMsg = ok ? null : 'Wrong or expired code — request a new one.';
    });
    if (ok) {
      unawaited(PushService.register());
      AppToast.show(context, 'Device linked.');
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
    if (!_inputsValid) {
      setState(() => _error = _email.text.trim().contains('@')
          ? (_password.text.isEmpty
              ? 'Enter your password.'
              : 'Password must be at least 8 characters.')
          : 'Enter a valid email address.');
      return;
    }
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
    if (store.pendingMfaChallenge != null) {
      final done = await showMfaChallengeSheet(context);
      if (!mounted) return;
      if (done) {
        if (!mounted) return;
        Navigator.of(context).pop();
        AppToast.show(context, 'Signed in.');
      } else {
        setState(() => _error = store.lastAuthError ?? 'Second-factor check needed.');
      }
      return;
    }
    if (ok) {
      if (_creating && _referral.text.trim().isNotEmpty) {
        unawaited(DropOffApi.claimReferral(_referral.text.trim()));
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      AppToast.show(context, _creating ? 'Account created — you are signed in.' : 'Signed in.');
    } else {
      final message = store.lastAuthError ?? AppStore.authErrorText('unknown');
      setState(() {
        _error = message;
        _showResendVerification = message.toLowerCase().contains('verif');
      });
    }
  }

  void _showCreateAccountSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => const _CreateAccountSheet(),
    );
  }

  Future<void> _unlink() async {
    await AppScope.of(context).unlink();
    if (mounted) setState(() {});
  }

  /// View / change the recipient's own door PIN.
  Future<void> _editDoorPin() async {
    final store = AppScope.of(context);
    final current = store.doorPin ?? '';
    final ctrl = TextEditingController(text: current);
    bool busy = false;
    bool revealed = current.isNotEmpty;
    final res = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setDialog) => SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.line, borderRadius: BorderRadius.circular(4)))),
            const SizedBox(height: 16),
            const Text('Door handover PIN', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20)),
            const SizedBox(height: 8),
            Text(
              current.isNotEmpty
                  ? 'Your current door PIN is shown below. You can change it anytime if you forgot it or want a new one.'
                  : 'Choose a 4-digit code. The rider asks for it when your parcel reaches your door.',
              style: const TextStyle(fontSize: 12.5, height: 1.4, color: AppColors.muted),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              maxLength: 4,
              obscureText: !revealed,
              decoration: InputDecoration(
                labelText: '4-digit PIN',
                counterText: '',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  tooltip: revealed ? 'Hide PIN' : 'Show PIN',
                  icon: Icon(revealed ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                  onPressed: () => setDialog(() => revealed = !revealed),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: OutlinedButton(onPressed: busy ? null : () => Navigator.pop(ctx, false), child: const Text('Cancel'))),
              const SizedBox(width: 10),
              Expanded(child: FilledButton(
                onPressed: busy ? null : () async {
                  final pin = ctrl.text.replaceAll(RegExp(r'[^0-9]'), '');
                  if (pin.length != 4) { _snackSimple('Enter exactly 4 digits.'); return; }
                  setDialog(() => busy = true);
                  final out = await DropOffApi.setDoorPin(pin);
                  if (!ctx.mounted) return;
                  if (out.ok) {
                    await store.refreshRole(force: true);
                  }
                  if (!ctx.mounted) return;
                  Navigator.pop(ctx, out.ok);
                  if (mounted) _snackSimple(out.ok ? 'Door PIN saved.' : moneyErrorText(out, 'Could not save PIN'));
                },
                child: busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Save PIN'),
              )),
            ]),
          ]),
        ),
      )),
    );
    if (res == true && mounted) setState(() {});
  }

  void _snackSimple(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
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
          final revokingIds = <Object>{};
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
              child: SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.82),
                  child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Row(children: [
                  Icon(Icons.devices, color: AppColors.forest),
                  SizedBox(width: 8),
                  Text('Devices signed in', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
                ]),
                const SizedBox(height: 6),
                const Row(children: [
                  Expanded(
                    child: Text('Tap Revoke to sign a device out.', style: TextStyle(color: AppColors.muted, fontSize: 12))
                  ),
                  HelpIconButton(topic: HelpTopic.deviceList),
                ]),
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
                      final realName = '${d['device_name'] ?? ''}'.trim();
                      final uaRaw = '${d['user_agent'] ?? ''}'.trim();
                      final ua = realName.isNotEmpty ? realName : (uaRaw.isEmpty ? '${d['device_id'] ?? 'unknown'}' : uaRaw);
                      final loc = '${d['location'] ?? ''}'.trim();
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
                              Text('$day $time${loc.isNotEmpty ? ' · $loc' : ''} · IP $ip${trusted ? '' : ' (revoked)'}', style: const TextStyle(color: AppColors.muted, fontSize: 11)),
                            ]),
                          ),
                          TextButton(
                            onPressed: isCurrent || revokingIds.contains(d['id'])
                                ? null
                                : () async {
                                    setSheetState(() => revokingIds.add(d['id']));
                                    final ok = await DropOffApi.post('/me/devices/${d['id']}/revoke', const {});
                                    setSheetState(() => revokingIds.remove(d['id']));
                                    if (ok.ok && mounted) {
                                      setSheetState(() {
                                        d['trusted'] = false;
                                      });
                                      _snackPhoto('Device revoked — its sessions are now signed out.');
                                    } else if (mounted) {
                                      _snackPhoto('Could not revoke this device — check your connection and try again.');
                                    }
                                  },
                            child: isCurrent
                                ? const Text('current')
                                : (revokingIds.contains(d['id'])
                                    ? const AppLogoSpinner(size: 16)
                                    : const Text('Revoke')),
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
                      if (!sheetContext.mounted) return;
                      AppToast.show(sheetContext, ok.ok ? 'Signed out on all other devices.' : 'Could not sign out everywhere.');
                      if (ok.ok) Navigator.of(sheetContext).pop();
                    },
                    icon: const Icon(Icons.logout, size: 18),
                    label: const Text('Sign out on all other devices'),
                  ),
                ),
                  ]),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  String get _biomeDescription =>
      'Fingerprint or face sign-in — your call.';

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
    try {
      final bytes = await picked.readAsBytes();
      DateTime? capturedAt;
      try { capturedAt = await picked.lastModified(); } catch (_) {}
      final name = picked.name.isNotEmpty ? picked.name : 'me.jpg';
      if (!mounted) return;
      final up = await ProofUploadOverlay.run(
        context,
        title: 'Securing your photo',
        task: DropOffApi.uploadImage(bytes, name, kind: 'selfie', capturedAt: capturedAt),
      );
      if (!mounted) return;
      if (!up.ok) {
        setState(() => _photoBusy = false);
        _snackPhoto('Upload failed (${up.error}).');
        return;
      }
      final url = '${up.body['url'] ?? ''}';
      if (url.isEmpty) {
        setState(() => _photoBusy = false);
        _snackPhoto('Upload failed. Try again.');
        return;
      }
      final res = await DropOffApi.addMePhoto(url);
      if (!mounted) return;
      setState(() => _photoBusy = false);
      if (!res.ok) {
        _snackPhoto('Could not save photo (${res.error}).');
        return;
      }
      await AppScope.of(context).refreshRole(force: true);
      if (!mounted) return;
      final st = '${res.body['verification_status'] ?? ''}';
      _snackPhoto(st == 'pending'
          ? 'Photo saved - it does not look like one person, so you are back in the review queue.'
          : 'Photo saved - senders will see you on the tracking page.');
      return;
    } catch (_) {
      if (!mounted) return;
      setState(() => _photoBusy = false);
      _snackPhoto('Could not upload the photo. Check camera permission and try again.');
      return;
    }
  }

  Future<void> _removePhoto() async {
    if (_photoBusy) return;
    final ok = await showConfirmSheet(
      context,
      title: 'Remove profile photo?',
      message: 'Your photo will be removed and initials will be shown instead.',
      confirmLabel: 'Remove',
      danger: true,
      icon: Icons.delete_outline,
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
    await AppScope.of(context).refreshRole(force: true);
    if (mounted) _snackPhoto('Photo removed.');
  }

  void _snackPhoto(String t) => AppToast.show(context, t);

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
    // Honest delivery: the worker reports whether mail actually went out, so
    // "check your email" is never shown for a send that failed.
    final sent = res.body['sent'] == true;
    final delivered = sent || dev != null;
    await showInfoSheet(
      context,
      title: delivered ? 'Check your messages' : 'We could not send the link',
      message: dev != null
          ? 'Email delivery is not configured yet — reset link for this build:\n\n$dev'
          : delivered
              // Owner/admin accounts are protected: their link goes to the
              // phone by SMS, never to the mailbox.
              ? 'If $email has an account, a reset link valid for 1 hour is on its way. '
                  'Owner and admin accounts get the link by SMS on the account phone, never by email.'
              : 'The reset message could not be sent just now. Try again in a moment, '
                  'or sign in with your phone number and the 6-digit SMS code.',
      icon: delivered ? Icons.mark_email_read_outlined : Icons.error_outline_rounded,
    );
  }

  Future<void> _resendVerification() async {
    final email = _email.text.trim();
    if (!email.contains('@')) {
      setState(() => _error = AppStore.authErrorText('invalid_email'));
      return;
    }
    final store = AppScope.of(context);
    final res = await store.resendVerification(email);
    if (!mounted) return;
    AppToast.show(context, res.ok ? 'Verification email sent (check spam too).' : 'Could not send right now.');
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
      body: RefreshIndicator(
        onRefresh: () async {
          await store.syncJobsFromServer();
          if (mounted) setState(() {});
        },
        child: ListView(
        controller: _listController,
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
                  if (store.role != null) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: AppColors.forest.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(20)),
                      child: Text(store.role!.toUpperCase(), style: const TextStyle(color: AppColors.forest, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 0.6)),
                    ),
                  ],
                  const SizedBox(height: 2),
                  Text(store.fullName ?? store.email ?? store.linkedPhone ?? 'Linked device', style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.forest)),
                  if (store.fullName != null && store.email != null) Text(store.email!, style: const TextStyle(color: AppColors.ink, fontSize: 12.5)),
                  if (store.linkedPhone != null && store.email != null) Text(store.linkedPhone!, style: const TextStyle(color: AppColors.ink, fontSize: 12.5)),
                ])),
                if (_photoBusy) const Padding(padding: EdgeInsets.only(left: 6), child: AppLogoSpinner(size: 18)),
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
                Row(children: [
                  Expanded(child: Text(_biomeDescription, style: AppType.caption)),
                  const HelpIconButton(topic: HelpTopic.biometric),
                ]),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Fingerprint / face unlock', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                  subtitle: const Text('Unlock with fingerprint or face on this phone.', style: TextStyle(fontSize: 11.5)),
                  value: store.biometricEnabled,
                  onChanged: (v) => _setBiometric(v, store),
                ),
                // Step sounds (owner request 2026-11-20): a short chime every
                // time a pickup, depot drop or handover is filed. Optional —
                // riders who prefer silence switch it off here.
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(Icons.volume_up_outlined, color: AppColors.forest),
                  title: const Text('Step completion sound', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                  subtitle: const Text('Play a short chime when a delivery step is done.', style: TextStyle(fontSize: 11.5)),
                  value: _stepSounds,
                  onChanged: (v) async {
                    await StepSounds.setEnabled(v);
                    if (!mounted) return;
                    setState(() => _stepSounds = v);
                    if (v) await StepSounds.stepDone(); // preview
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(Icons.navigation_outlined, color: AppColors.forest),
                  title: const Text('Turn-by-turn voice', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                  subtitle: const Text('Speak the next turn while navigating. Mute any time in the navigator.', style: TextStyle(fontSize: 11.5)),
                  value: _voiceGuidance,
                  onChanged: (v) async {
                    await StepSounds.setVoiceGuidance(v);
                    if (!mounted) return;
                    setState(() => _voiceGuidance = v);
                  },
                ),
                if (_voiceGuidance)
                  Padding(
                    padding: const EdgeInsets.only(left: 56, right: 8, bottom: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Expanded(
                              child: Text('Voice speed', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                            ),
                            Text(
                              _voiceRate <= 0.35 ? 'Slow' : _voiceRate <= 0.6 ? 'Normal' : 'Fast',
                              style: const TextStyle(fontSize: 11.5, color: AppColors.muted),
                            ),
                          ],
                        ),
                        Slider(
                          value: _voiceRate.clamp(0.2, 1.0),
                          min: 0.2,
                          max: 1.0,
                          divisions: 8,
                          label: _voiceRate.toStringAsFixed(2),
                          onChanged: (v) async {
                            setState(() => _voiceRate = v);
                            await StepSounds.setVoiceRate(v);
                          },
                        ),
                      ],
                    ),
                  ),
                // Staff email (owner 2026-11-26): owner/admin/ops/CFO can enter
                // or change their own address; protected resets stay phone-only.
                if (store.isStaff) ...[
                  StaffEmailCard(phone: store.linkedPhone, email: store.email),
                  const SizedBox(height: 12),
                ],
                const MfaSettingsCard(),
                const SizedBox(height: 12),
                // Offline map (owner 2026-11-26): riders save the city basemap
                // before a route with no signal.
                const OfflineMapTile(),
                const SizedBox(height: 6),
                // Recipient door PIN (owner 2026-11-18): your own 4-digit code
                // shown to the rider at the door — no SMS code for same-city.
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.menu_book_outlined, color: AppColors.forest),
                  title: const Text('How DropOff works — tutorial', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                  subtitle: Text(store.isRider ? '6 quick steps for riders.' : '6 quick steps for senders.', style: const TextStyle(fontSize: 11.5)),
                  onTap: () => TutorialSheet.show(context, senderOnly: !store.isRider, rider: store.isRider),
                ),
                const SizedBox(height: 6),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.pin_outlined, color: AppColors.forest),
                  title: const Text('Door handover PIN', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                  subtitle: Text(
                    store.doorPin != null && store.doorPin!.isNotEmpty
                        ? 'Current PIN: ${store.doorPin}  •  Tap to view, edit, or change it.'
                        : 'Set your own 4-digit door code — recipients show it at handover.',
                    style: const TextStyle(fontSize: 11.5),
                  ),
                  trailing: store.doorPin != null && store.doorPin!.isNotEmpty
                      ? const Icon(Icons.visibility_outlined, size: 18, color: AppColors.muted)
                      : null,
                  onTap: _editDoorPin,
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
              ]))),
            ],
          ] else ...[
            const Text('Link this phone', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20, letterSpacing: -0.2)),
            const SizedBox(height: 6),
            const Row(children: [
              Expanded(child: Text('Your number is your account — no passwords, no emails.', style: AppType.bodyStrong)),
              HelpIconButton(topic: HelpTopic.signIn),
            ]),
            const SizedBox(height: 14),
            TextField(
              controller: _otpPhone,
              keyboardType: TextInputType.phone,
              textCapitalization: TextCapitalization.none,
              decoration: const InputDecoration(labelText: 'Your mobile number', hintText: '0971234567', prefixIcon: Icon(Icons.phone_outlined)),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52), backgroundColor: AppColors.forest),
              onPressed: _otpBusy ? null : _sendOtp,
              icon: _otpBusy
                  ? const AppLogoSpinner(size: 18, color: Colors.white)
                  : const Icon(Icons.sms_outlined),
              label: Text(_otpBusy ? 'Sending…' : (_otpSent ? 'Send a new 6-digit code' : 'Send 6-digit code by SMS'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
            ),
            if (_otpSent) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _otpCode,
                keyboardType: TextInputType.number,
                autofocus: true,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _verifyOtp(),
                decoration: const InputDecoration(labelText: 'Enter the 6-digit SMS code', hintText: '123456', prefixIcon: Icon(Icons.lock_outline)),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50), backgroundColor: AppColors.forest),
                onPressed: _otpBusy ? null : _verifyOtp,
                icon: _otpBusy
                    ? const AppLogoSpinner(size: 18, color: Colors.white)
                    : const Icon(Icons.check_rounded),
                label: Text(_otpBusy ? 'Verifying…' : 'Verify & sign in', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
              ),
            ],
            if (_otpMsg != null) ...[
              const SizedBox(height: 10),
              Text(_otpMsg!, style: const TextStyle(color: AppColors.ink, fontSize: 12.5, height: 1.35)),
            ],
            const SizedBox(height: 20),
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
              const Expanded(child: Text("Don't have an account?", style: TextStyle(color: AppColors.ink, fontSize: 13))),
              TextButton(onPressed: _showCreateAccountSheet, child: const Text('Create account', style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.forest))),
            ]),
            if (_error != null) ...[
              const SizedBox(height: 14),
              Text(_error!, style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w700, fontSize: 13)),
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
                child: Text('Remember me on this device', style: TextStyle(fontSize: 13, color: AppColors.ink)),
              ),
            ]),
            const SizedBox(height: 8),
            FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              // Always tappable — the tap explains what is missing instead of a
              // silently dead button.
              onPressed: _busy ? null : _submit,
              icon: _busy
                  ? const AppLogoSpinner(size: 18)
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
                // Hidden until an error actually mentions verification —
                // one less thing to read on the default sign-in screen.
                if (_showResendVerification)
                  TextButton(
                    onPressed: () => _resendVerification(),
                    child: const Text('Resend verification email'),
                  ),
              ]),
            ],
            const SizedBox(height: 16),
            Text(
              _creating
                  ? 'Phone number = refunds and payouts. Email = the sign-in key.'
                  : 'Signing in restores your plans and booking history.',
              style: AppType.caption,
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
          ],
          if (signedIn) ...[
            const _ReferralCard(),
            const _RecurringCard(),
            Card(
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => const TicketsScreen(),
                )),
                child: const Padding(
                  padding: EdgeInsets.all(16),
                  child: Row(children: [
                    Icon(Icons.support_agent, color: AppColors.forest),
                    SizedBox(width: 12),
                    Expanded(child: Text('Support tickets', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14))),
                    Icon(Icons.chevron_right, color: AppColors.muted),
                  ]),
                ),
              ),
            ),
            const _AdminGate(),
          ],
          KeyedSubtree(
            key: _plansAnchorKey,
            child: const _TiersCard(),
          ),
          const _PackCodeCard(),
          if (!DropOffApi.enabled && !signedIn) ...[
            const SizedBox(height: 26),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                'Offline build: this device was compiled without the server key, so accounts are unavailable. Bookings still save locally.',
                style: AppType.caption,
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ],
        ),
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
            const Text('Pre-load a repeat drop — tap to book it with one tap when due.', style: TextStyle(color: AppColors.ink, fontSize: 13)),
            const SizedBox(height: 14),
            if (errorText != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(errorText, style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w700, fontSize: 12))),
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
          const Row(children: [
            Expanded(child: Text('Weekly/biweekly/monthly — we remember, you tap once.', style: AppType.bodyStrong)),
            HelpIconButton(topic: HelpTopic.recurring),
          ]),
          const SizedBox(height: 10),
          if (_loading)
            const Center(child: Padding(padding: EdgeInsets.symmetric(vertical: 12), child: AppLogoSpinner(size: 22)))
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
                  final ok = await showConfirmSheet(
                    context,
                    title: 'Delete recurring plan?',
                    message: 'This will remove the recurring plan. This cannot be undone.',
                    confirmLabel: 'Delete',
                    danger: true,
                    icon: Icons.delete_outline,
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
    // Include human context: what the code is for and how to use it.
    final text = 'My DropOff referral code: $code\n'
        'Sign up in the app → enter this code and get home pickup to your courier. I earn a 20% promo when your first paid delivery is completed.';
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) setState(() => _copied = true);
    await Future<void>.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _copied = false);
  }

  Future<void> _share() async {
    final code = _data?['code'] as String? ?? '';
    if (code.isEmpty) return;
    final link = 'https://dropoff.carpsosolutions.store/r/$code';
    final text = 'Join me on DropOff — senders get home pickup to their courier: $link';
    await openInApp('https://wa.me/?text=${Uri.encodeComponent(text)}');
  }

  @override
  Widget build(BuildContext context) {
    if (!DropOffApi.enabled) return const SizedBox.shrink();
    final code = _data?['code'] as String?;
    final stats = _data?['stats'] as Map<String, dynamic>?;
    final paid = (stats?['paid'] as num?)?.toInt() ?? (stats?['rewarded'] as num?)?.toInt() ?? 0;
    final signedUp = (stats?['signed_up'] as num?)?.toInt() ?? (stats?['pending'] as num?)?.toInt() ?? 0;
    final qualified = (stats?['qualified'] as num?)?.toInt() ?? 0;
    final rewards = ((_data?['rewards'] as List?) ?? const <dynamic>[])
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList();
    final earned = rewards.where((r) => '${r['status']}' == 'rewarded' && '${r['reward_code'] ?? ''}'.isNotEmpty).toList();
    return Card(
      margin: const EdgeInsets.only(top: 18, bottom: 4),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Invite senders — earn', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
          const SizedBox(height: 4),
          const Row(children: [
            Expanded(child: Text('Invite a sender. You earn a 20% promo after their first paid delivery is completed.', style: AppType.bodyStrong)),
            HelpIconButton(topic: HelpTopic.referralReward),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            if (code != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(color: AppColors.forest, borderRadius: BorderRadius.circular(12)),
                child: Text(code, style: const TextStyle(color: Color(0xFFF6B73C), fontWeight: FontWeight.w900, letterSpacing: 2, fontSize: 16)),
              )
            else
              const SizedBox(width: 140, height: 38, child: Center(child: AppLogoSpinner(size: 18))),
            const SizedBox(width: 10),
            IconButton(tooltip: 'Copy code', icon: Icon(_copied ? Icons.check_rounded : Icons.copy, color: AppColors.forest), onPressed: _copy),
            IconButton(tooltip: 'Share on WhatsApp', icon: const Icon(Icons.share_rounded, color: AppColors.forest), onPressed: _share),
          ]),
          const SizedBox(height: 6),
          Text('$paid paid · $qualified qualified · $signedUp signed up', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
          const SizedBox(height: 2),
          const Text('Status: invited (shared link) → signed up → qualified (first paid delivery) → paid.', style: TextStyle(color: AppColors.muted, fontSize: 11)),
          if (earned.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Text('Your earned codes — use at booking', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
            for (final r in earned)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(color: AppColors.amberSoft, borderRadius: BorderRadius.circular(8)),
                    child: Text('${r['reward_code']} · 20% off',
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: AppColors.forest)),
                  ),
                  IconButton(
                    tooltip: 'Copy reward code',
                    icon: const Icon(Icons.copy, size: 16, color: AppColors.forest),
                    onPressed: () => Clipboard.setData(ClipboardData(text: '${r['reward_code']}')),
                  ),
                ]),
              ),
          ],
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
  // Cached once per mount: switching screens and coming back must never
  // re-open an empty (grey) plan card while a fresh request is in flight
  // (owner bug 2026-11-20: "plans show a gray screen when the user changes
  // screens and comes back").
  late final Future<Map<String, dynamic>?> _plansFuture = _loadPlans();
  String? _busyTier;
  int _usageCycle = 0;
  Map<String, dynamic>? _current;
  static const Map<String, int> _tierRank = {'weekly': 0, 'silver': 1, 'gold': 2, 'platinum': 3};

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
      '06:00': '5:30—7:30 AM',
      '10:00': '10:00–11:30 AM',
      '14:00': '2:00–3:30 PM',
    };
    return list.take(3).map((w) => ranges['$w'] ?? '$w').join(' / ');
  }

  /// Map API errors to honest copy — never a bare "network error" for a
  /// provider-side or server-side rejection.
  String _moneyErrorText(ApiResponse r, String fallback) => moneyErrorText(r, fallback);

  /// Standard "you are about to be prompted" confirmation. Choosing a plan
  /// must never fire a momo prompt with no warning — the rider-facing apps
  /// always show what will happen, the amount and that no money moves until
  /// the user approves it. Returns false when the user cancels.
  Future<bool> _confirmPlanPrompt(String tier, {required bool upgrade}) async {
    final snap = await DropOffApi.plans();
    if (!mounted) return false;
    final models = snap?['plans'] as Map<String, dynamic>?;
    final plan = models?[tier] as Map<String, dynamic>?;
    final fee = plan?['fee_zmw'];
    final price = fee == null ? 'the plan price' : 'K$fee${_cycleUnit(plan)}';
    final ok = await showAppSheet<bool>(
      context,
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.line, borderRadius: BorderRadius.circular(4)))),
        const SizedBox(height: 16),
        Text(upgrade ? 'Upgrade to ${tier.toUpperCase()}?' : 'Start ${tier.toUpperCase()}?', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20)),
        const SizedBox(height: 12),
        Text('This plan costs $price.', style: AppType.bodyStrong),
        const SizedBox(height: 6),
        const Text('Introductory promo price — it will increase within 3–6 months (no later than 1 year). This cycle keeps the current rate.', style: TextStyle(fontSize: 11, color: AppColors.danger, fontWeight: FontWeight.w700, height: 1.35)),
        const SizedBox(height: 10),
        const Text('We will send a mobile-money prompt to your phone. Nothing is charged until you approve it with your PIN.', style: TextStyle(fontSize: 12.5, height: 1.4)),
        const SizedBox(height: 8),
        const Text('The prompt adds our processing fee plus the mobile-money collection fee. Nothing else is charged — riders are salaried and never receive per-item money.', style: TextStyle(fontSize: 11.5, color: AppColors.muted, height: 1.4)),
        const SizedBox(height: 20),
        Row(children: [
          Expanded(child: OutlinedButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Not now'))),
          const SizedBox(width: 10),
          Expanded(child: FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Send momo prompt'))),
        ]),
      ]),
    );
    return ok ?? false;
  }

  Future<void> _chooseTier(String tier) async {
    final store = AppScope.of(context);
    if (!store.linked) {
      AppToast.show(context, 'Sign in first — your plan is tied to your phone.');
      return;
    }
    final currentTier = '${_current?['tier'] ?? ''}';
    final active = '${_current?['status'] ?? ''}' == 'active';
    if (active && currentTier.isNotEmpty && currentTier != tier) {
      final curRank = _tierRank[currentTier] ?? -1;
      final newRank = _tierRank[tier] ?? -1;
      if (newRank < curRank) {
        AppToast.show(context, 'Downgrades apply automatically at your next renewal — nothing to pay now.');
        return;
      }
      if (newRank > curRank) {
        if (!await _confirmPlanPrompt(tier, upgrade: true)) return;
        if (!mounted) return;
        setState(() => _busyTier = tier);
        final up = await DropOffApi.upgradeSubscription(tier);
        if (!mounted) return;
        setState(() => _busyTier = null);
        if (!up.ok) {
          AppToast.show(context, _moneyErrorText(up, 'Could not upgrade'));
          return;
        }
        final extra = ((up.body['amount_zmw'] as num?) ?? 0).toDouble();
        AppToast.show(context, extra > 0
            ? '${tier.toUpperCase()} is live now — approve the K${extra.toStringAsFixed(2)} prorated prompt.'
            : '${tier.toUpperCase()} is live — nothing extra to pay this cycle.');
        setState(() => _usageCycle++);
        _loadCurrent();
        AnalyticsService.instance.track(
          feature: 'subscriptions', action: 'upgrade', context: 'account_tiers',
          meta: {'tier': tier},
        );
        return;
      }
    }
    if (!await _confirmPlanPrompt(tier, upgrade: false)) return;
    if (!mounted) return;
    setState(() => _busyTier = tier);
    final res = await DropOffApi.subscribe(tier: tier);
    if (!res.ok) {
      if (!mounted) return;
      setState(() => _busyTier = null);
      AppToast.show(context, _moneyErrorText(res, 'Could not start the plan'));
      return;
    }
    // Lipila prompt for the plan price; success activates the plan server-side.
    final pay = await DropOffApi.paySubscription();
    if (!mounted) return;
    if (!pay.ok) {
      setState(() => _busyTier = null);
      AppToast.show(context, _moneyErrorText(pay,
          pay.error == 'lipila_init_failed' || pay.error == 'lenco_init_failed'
              ? 'Mobile-money prompt was rejected by the payment provider — payments are down; the plan did not start. Verify your momo balance is enough for the prompt, then tap Pay now again.'
              : 'Could not start the mobile-money prompt'));
      return;
    }
    final paymentId = '${pay.body['payment_id']}';
    var status = 'pending';
    String? failReason;
    for (var attempt = 0; attempt < 20 && status == 'pending'; attempt++) {
      await Future<void>.delayed(const Duration(seconds: 2));
      final st = await DropOffApi.paymentStatus(paymentId);
      status = st.$1 ?? 'pending';
      failReason = st.$2;
    }
    if (!mounted) return;
    setState(() { _busyTier = null; _usageCycle++; });
    _loadCurrent();
    AnalyticsService.instance.track(
      feature: 'subscriptions', action: status == 'success' ? 'subscribe' : 'subscribe_pending',
      context: 'account_tiers',
      meta: {'tier': tier, 'status': status},
    );
    final msg = switch (status) {
      'success' when tier == 'weekly' => 'Weekly Sprint is LIVE — 7 days of items are ready.',
      'success' => '$tier plan is LIVE — your monthly items are ready.',
      'failed' => (failReason == null || failReason.isEmpty)
          ? 'The mobile-money prompt was rejected — verify your momo balance has the funds, then tap Pay now again.'
          : 'Payment failed: $failReason — top up your momo wallet, then tap Pay now again.',
      _ => 'Payment still pending — the plan activates the moment it lands.',
    };
    AppToast.show(context, msg);
    if (paymentId.isNotEmpty && paymentId != 'null' && mounted) {
      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (ctx) => SafeArea(child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Plan receipt', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
            const SizedBox(height: 8),
            Text(status == 'success'
                ? 'Your plan payment is confirmed. Download the receipt for your records.'
                : 'You can download the payment receipt for your records. If payment is still pending, the receipt will show pending until it confirms.',
                style: const TextStyle(fontSize: 14, height: 1.45)),
            const SizedBox(height: 16),
            SizedBox(width: double.infinity, child: FilledButton.icon(
              onPressed: () { Navigator.pop(ctx); Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PlanReceiptScreen(paymentId: paymentId))); },
              icon: const Icon(Icons.receipt_long_outlined),
              label: const Text('View / download receipt'),
            )),
          ]),
        )),
      );
    }
  }

  Future<void> _openPlanReceipts() async {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(child: SizedBox(
        height: MediaQuery.of(ctx).size.height * 0.72,
        child: Column(children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Align(alignment: Alignment.centerLeft,
              child: Text('Receipts', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20))),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Align(alignment: Alignment.centerLeft,
              child: Text('Download receipts for your payments for your records or audit.',
                style: TextStyle(fontSize: 13, color: Color(0xFF5F6B66), height: 1.4))),
          ),
          Expanded(child: FutureBuilder<List<Map<String, dynamic>>>(
            future: DropOffApi.myReceipts(),
            builder: (ctx, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(child: AppLogoSpinner());
              }
              final items = snap.data ?? const <Map<String, dynamic>>[];
              if (items.isEmpty) {
                return const Center(child: Padding(padding: EdgeInsets.all(24),
                  child: Text('No plan receipts yet.', textAlign: TextAlign.center)));
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (ctx, i) {
                  final r = items[i];
                  final plan = (r['plan'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
                  final amounts = (r['amounts'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
                  final status = '${r['status'] ?? ''}'.toLowerCase();
                  final ok = status == 'success';
                  final color = ok ? const Color(0xFF1E7A43) : status == 'pending' ? const Color(0xFFB45309) : const Color(0xFFB3261E);
                  final kind = '${r['kind'] ?? ''}';
                  final name = '${plan['name'] ?? plan['tier'] ?? ''}';
                  final total = amounts['total_zmw'];
                  final totalText = total is num ? 'K${total.toDouble().toStringAsFixed(2)}' : '';
                  final title = switch (kind) {
                    'subscription' => name.isEmpty ? 'Plan payment' : '$name plan',
                    'upgrade' => name.isEmpty ? 'Plan upgrade' : '$name upgrade',
                    'counter_fare' => 'Counter fare payment',
                    'booking_deposit' => 'Booking deposit',
                    'job' => 'Delivery payment',
                    'topup' => 'Top-up',
                    'refund' => 'Refund',
                    _ => 'Payment',
                  };
                  return ListTile(
                    tileColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: Color(0x14000000))),
                    title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: Text('${r['receipt_no'] ?? ''} • ${ok ? 'Paid' : status.toUpperCase()}\n$totalText', style: const TextStyle(height: 1.35)),
                    isThreeLine: true,
                    trailing: Icon(Icons.chevron_right, color: color),
                    onTap: () {
                      final pid = '${r['payment_id'] ?? ''}';
                      if (pid.isEmpty || pid == 'null') return;
                      Navigator.of(ctx).pop();
                      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PlanReceiptScreen(paymentId: pid)));
                    },
                  );
                },
              );
            },
          )),
        ]),
      )),
    );
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
              const Row(children: [
                Expanded(child: Text('7-Day Weekly Sprint or Silver / Gold / Platinum — one momo prompt.', style: AppType.bodyStrong)),
                HelpIconButton(topic: HelpTopic.plansBlurb),
              ]),
              const SizedBox(height: 6),
              const Text('PROMO PRICING — these are introductory rates. Prices will increase at the next review (within 3–6 months, no later than 1 year). Your current cycle keeps this rate.',
                  style: TextStyle(fontSize: 10.5, color: AppColors.danger, fontWeight: FontWeight.w800, height: 1.35)),
              const SizedBox(height: 8),
              _PlanUsageMeter(key: ValueKey(_usageCycle)),
              FutureBuilder<Map<String, dynamic>?>(
                future: _plansFuture,
                builder: (context, snap) {
                  final models = snap.data?['plans'] as Map<String, dynamic>?;
                  if (models == null) {
                    // Never a blank/grey card while loading: a branded spinner
                    // plus the honest copy, on the white card surface.
                    return Container(
                      width: double.infinity,
                      color: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: const Row(children: [
                        AppLogoSpinner(size: 18),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text('Tier prices load when the server is reachable.',
                              style: TextStyle(color: AppColors.muted, fontSize: 12)),
                        ),
                      ]),
                    );
                  }
                  const display = <String, ({String label, String blurb})>{
                    'weekly': (label: 'WEEKLY SPRINT', blurb: '20 items / 7 days — no monthly lock-in'),
                    'silver': (label: 'SILVER', blurb: '10 items / month — low-volume senders'),
                    'gold': (label: 'GOLD', blurb: '25 items / month — weekly shippers'),
                    'platinum': (label: 'PLATINUM', blurb: '50 items / month — daily bulk senders'),
                  };
                  final currentTier = '${_current?['tier'] ?? ''}';
                  final currentActive = '${_current?['status'] ?? ''}' == 'active';
                  return Column(children: [
                    /// Only render tiers an admin has toggled ON —
                    /// a toggled-off plan vanishes from the sender page entirely.
                    for (final entry in display.entries)
                      if (models[entry.key] != null)
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
                                // FULL-WIDTH NAME + WRAPPED BADGES (owner fix
                                // 2026-11-17: "MOST POPULAR / Weekly ... are
                                // ellipsed — fill them up"): the plan name and
                                // the badges used to share one row and squeeze
                                // each other into "WEEKLY SPR…" / "MOST POP…".
                                // The name now owns its own line and the
                                // badges flow on a Wrap below — never truncated.
                                Text(entry.value.label,
                                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: 0.4)),
                                if ((currentActive && currentTier == entry.key) || models[entry.key]?['tag'] != null) ...[
                                  const SizedBox(height: 5),
                                  Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                                    if (currentActive && currentTier == entry.key)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(color: AppColors.forest, borderRadius: BorderRadius.circular(20)),
                                        child: const Text('CURRENT', style: TextStyle(color: Colors.white, fontSize: 8.5, fontWeight: FontWeight.w900, letterSpacing: 0.4)),
                                      ),
                                    if (models[entry.key]?['tag'] != null)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(color: AppColors.amber.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(20)),
                                        child: Text('${models[entry.key]['tag']}', style: const TextStyle(color: Color(0xFF7B5710), fontSize: 9.5, fontWeight: FontWeight.w900, letterSpacing: 0.4)),
                                      ),
                                  ]),
                                ],
                                const SizedBox(height: 4),
                                Text(entry.value.blurb,
                                    style: const TextStyle(color: AppColors.ink, fontSize: 12.5, height: 1.35)),
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
                                      ? const AppLogoSpinner(size: 14)
                                      : Text(
                                          currentActive && currentTier == entry.key
                                              ? 'Renew'
                                              : currentActive && (_tierRank[entry.key] ?? 0) > (_tierRank[currentTier] ?? 0)
                                                  ? 'Upgrade'
                                                  : 'Choose',
                                          textAlign: TextAlign.center,
                                          // THEME-BASED LABEL (owner fix 2026-11-17):
                                          // AppType.callout pins AppColors.ink, which
                                          // overrode the FilledButton's white foreground
                                          // — "Choose"/"Renew"/"Upgrade" read black on
                                          // the forest button. Resolve the color from
                                          // the button theme so it always follows it.
                                          style: AppType.callout.copyWith(
                                            color: Theme.of(context).filledButtonTheme.style?.foregroundColor?.resolve({}) ?? Colors.white,
                                          ),
                                        ),
                                ),
                              ]),
                            ),
                          ]),
                        ),
                        ),
                      ),
                    const SizedBox(height: 4),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: _busyTier != null ? null : _openPlanReceipts,
                        icon: const Icon(Icons.receipt_long_outlined, size: 18),
                        label: const Text('Receipts'),
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
    if (!store.linked) {
      AppToast.show(context, 'Sign in first — the plan attaches to your number.');
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
      AppToast.show(context, '$tier plan activated${end.isEmpty ? '' : ' — runs to $end'}. No payment needed.');
      AnalyticsService.instance.track(
        feature: 'pack_codes', action: 'redeem', context: 'account_pack_code',
        meta: {'tier': tier},
      );
    } else {
      AppToast.show(context, res.error == 'code_not_found'
          ? 'That plan code was not recognised.'
          : res.error == 'code_used'
              ? 'That plan code has already been used.'
              : 'Could not redeem (${res.error}).');
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
            const Row(children: [
              Expanded(child: Text('Bought a plan at a market? Redeem it here.', style: AppType.caption)),
              HelpIconButton(topic: HelpTopic.packCode),
            ]),
            const SizedBox(height: 12),
            TextField(
              controller: _code,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                labelText: 'Plan code',
                hintText: 'DROP-8F2K-19QA',
                prefixIcon: const Icon(Icons.qr_code_2),
                suffixIcon: TextButton(onPressed: _busy ? null : _redeem, child: _busy ? const AppLogoSpinner(size: 14) : const Text('Redeem')),
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
    setState(() => _isAdmin = role == 'admin' || role == 'ops' || role == 'cfo');
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
                Text('Payroll, turnover tax, riders, depot branches, moderation and SMS.', style: AppType.caption),
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
        final dayCap = (plan['cycle_days'] as num?)?.toInt() ?? 30;
        final isDayCycle = dayCap <= 1;
        final cap = isDayCycle
            ? ((plan['parcels_per_day'] as num?)?.toInt() ?? 0)
            : ((plan['parcels_per_month'] as num?)?.toInt() ?? ((plan['parcels_per_day'] as num?)?.toInt() ?? 0));
        final used = (snap.data?['usage_this_period'] as num?)?.toInt() ?? 0;
        final remaining = (snap.data?['remaining_this_period'] as num?)?.toInt() ?? 0;
        if (cap <= 0) return const SizedBox.shrink();
        final tier = '${sub['tier'] ?? ''}'.toUpperCase();
        final renews = '${sub['period_end'] ?? ''}'.split(' ').first;
        return Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(color: AppColors.forest.withValues(alpha: 0.07), borderRadius: BorderRadius.circular(12)),
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
              const SizedBox(width: 6),
              const HelpIconButton(topic: HelpTopic.planCap, size: 16),
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
                  ? 'Cap reached — extra parcels now bill at pay-as-you-go rates.'
                  : 'Each parcel counts as one. Cycle renews $renews.',
              style: AppType.caption,
            ),
          ]),
        );
      },
    );
  }
}

/// Create-account modal — fully self-contained StatefulWidget with its own
/// controllers, error and busy state. Its feedback must never depend on the
/// Account screen's rebuild cycle (the old StatefulBuilder swallowed the
/// sheet's state, so the spinner and errors never appeared and tapping
/// "Create account" silently did nothing).
class _CreateAccountSheet extends StatefulWidget {
  const _CreateAccountSheet();

  @override
  State<_CreateAccountSheet> createState() => _CreateAccountSheetState();
}

class _CreateAccountSheetState extends State<_CreateAccountSheet> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _phone = TextEditingController();
  final _fullName = TextEditingController();
  final _referral = TextEditingController();
  bool _agreed = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // /r/CODE deep link: prefill the referral box on account creation.
    if (AccountScreen.prefillReferral?.isNotEmpty ?? false) {
      _referral.text = AccountScreen.prefillReferral!;
      AccountScreen.prefillReferral = null;
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _phone.dispose();
    _fullName.dispose();
    _referral.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    final digits = _phone.text.replaceAll(RegExp(r'[^0-9]'), '');
    String? problem;
    if (!email.contains('@')) {
      problem = 'Enter a valid email address.';
    } else if (_password.text.length < 8) {
      problem = 'Password must be at least 8 characters.';
    } else if (digits.length < 9 || digits.length > 15) {
      problem = 'Enter a full mobile number — 09..., 097... or +260...';
    } else if (!_agreed) {
      problem = 'Tick the agreement to create the account.';
    }
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() { _busy = true; _error = null; });
    final store = AppScope.of(context);
    final ok = await store.registerEmail(
      email: email,
      password: _password.text,
      phone: _phone.text.trim(),
      fullName: _fullName.text.trim().isEmpty ? null : _fullName.text.trim(),
      remember: false,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      if (_referral.text.trim().isNotEmpty) {
        unawaited(DropOffApi.claimReferral(_referral.text.trim().toUpperCase()));
      }
      Navigator.of(context).pop();
      AppToast.show(context, 'Account created — you are signed in.');
      return;
    }
    setState(() => _error = store.lastAuthError ?? AppStore.authErrorText('unknown'));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Create account', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 19)),
        const SizedBox(height: 4),
        const Row(children: [
          Expanded(child: Text('How sign-in works', style: AppType.bodyStrong)),
          HelpIconButton(topic: HelpTopic.signIn),
        ]),
        const SizedBox(height: 6),
        TextField(controller: _email, keyboardType: TextInputType.emailAddress, autofillHints: const [AutofillHints.email], decoration: const InputDecoration(labelText: 'Email')),
        const SizedBox(height: 12),
        TextField(controller: _password, obscureText: true, autofillHints: const [AutofillHints.password], decoration: const InputDecoration(labelText: 'Password (8+ chars)', helperText: 'At least 8 characters')),
        const SizedBox(height: 12),
        TextField(controller: _phone, keyboardType: TextInputType.phone, autofillHints: const [AutofillHints.telephoneNumber], decoration: const InputDecoration(labelText: 'Mobile money phone', helperText: '09..., 097... or +260... — items addressed to it appear automatically')),
        const SizedBox(height: 12),
        TextField(controller: _fullName, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Full name (optional)')),
        const SizedBox(height: 12),
        TextField(controller: _referral, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'Referral code (optional)', hintText: 'DRP-XXXXX', prefixIcon: Icon(Icons.redeem_rounded))),
        const SizedBox(height: 14),
        Row(children: [
          Checkbox(value: _agreed, onChanged: (v) => setState(() => _agreed = v ?? false), visualDensity: VisualDensity.compact),
          const SizedBox(width: 8),
          Expanded(child: RichText(text: TextSpan(style: const TextStyle(color: AppColors.muted, fontSize: 12), children: [
            const TextSpan(text: 'I agree to the '),
            TextSpan(text: 'Terms of use', style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.forest), recognizer: TapGestureRecognizer()..onTap = () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LegalScreen(title: 'Terms of use', asset: 'assets/legal/terms.md')))),
            const TextSpan(text: ' and '),
            TextSpan(text: 'Privacy policy', style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.forest), recognizer: TapGestureRecognizer()..onTap = () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LegalScreen(title: 'Privacy policy', asset: 'assets/legal/privacy.md')))),
          ]))),
        ]),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(_error!, style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w700, fontSize: 13)),
        ],
        const SizedBox(height: 12),
        SizedBox(width: double.infinity, child: FilledButton.icon(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
          onPressed: _busy ? null : _submit,
          icon: _busy ? const AppLogoSpinner(size: 18, color: Colors.white) : const Icon(Icons.person_add_alt_1),
          label: Text(_busy ? 'Creating...' : 'Create account'),
        )),
      ]),
    );
  }
}

