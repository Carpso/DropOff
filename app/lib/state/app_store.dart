import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import '../services/secure_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/dropoff_api.dart';
import '../data/analytics_service.dart';
import '../data/push_service.dart';
import '../data/catalog.dart';
import '../ui/keys.dart';
import '../models/booking.dart';

class AppStore extends ChangeNotifier with WidgetsBindingObserver {
  static const _rememberKey = 'dropoff_remember_v1';
  static const _biometricKey = 'dropoff_biometric_v1';
  static const _deviceKey = 'dropoff_device_id_v1';
  static const _shareLocationKey = 'dropoff_share_location_v1';
  static const _accountKey = 'dropoff_acct_v1';

  String _account = 'anon';

  String _scoped(String name) => '${_accountKey}_${_account}_$name';

  String get _bookingsKey => _scoped('bookings');
  String get _ridersKey => _scoped('riders');
  String get _outboxKey => _scoped('outbox');
  String get _recipientsOutboxKey => _scoped('recipients_outbox');
  String get _secureTokenKey => _scoped('jwt');
  String get _fallbackTokenKey => _scoped('jwt_mirror');
  String get _tokenKey => _scoped('jwt_legacy_mirror');
  String get _phoneKey => _scoped('phone');
  String get _emailKey => _scoped('email');

  final List<Booking> _bookings = [];
  final List<Rider> _riders = [];
  final List<Map<String, dynamic>> _outbox = [];
  final List<Map<String, dynamic>> _recipientsOutbox = [];
  bool _ready = false;
  String? _token;
  String? _linkedPhone;
  String? _email;
  String? _role;
  String? _photoUrl;
  String? _fullName;
  bool _superadmin = false;
  /// Live-position broadcasting defaults ON once a rider signs in. The rider
  /// can flip it off any time; it only fires when GPS is granted anyway.
  bool _shareLocationOn = true;
  bool _biometricEnabled = false;
  String _deviceId = 'unknown';

  /// Keystore/keychain on mobile; SharedPreferences(web) / fail-soft mirror(IO).
  final _secureStorage = const SecureStore();

  List<Booking> get bookings => List.unmodifiable(_bookings);
  List<Rider> get riders => List.unmodifiable(_riders);
  bool get ready => _ready;
  Rider get owner => _riders.firstWhere((rider) => rider.isOwner);
  String? get linkedPhone => _linkedPhone;
  String? get email => _email;
  bool get linked => _token != null;

  /// Profile photo the signed-in user uploaded (or a rider selfie). Null = no
  /// photo on file — views fall back to initials.
  String? get photoUrl => _photoUrl;
  String? get fullName => _fullName;

  /// Server role: customer | partner | admin | ops | rider | cfo.
  /// Admin/ops/cfo unlock the Team tab; rider unlocks their personal queue.
  /// `superadmin` is an identity (owner phone / admin key), never a DB role.
  String? get role => _role;
  bool get isStaff => _role == 'admin' || _role == 'ops' || _role == 'cfo';
  bool get isRider => _role == 'rider';
  bool get isTeam => isStaff || isRider;

  /// True only for role=admin (superadmin included — the owner is always
  /// minted as admin by the worker). Only these accounts may create riders.
  bool get isAdminRole => _role == 'admin';

  /// True when the signed-in phone is the app owner's (or the admin key is
  /// configured): unlocks user/role management in the admin console.
  bool get isSuperAdmin => _superadmin;

  /// Whether this rider broadcasts live GPS for the jobs they carry.
  bool get shareLocationOn => _shareLocationOn;

  Future<void> setShareLocationOn(bool on) async {
    _shareLocationOn = on;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_shareLocationKey, on);
    notifyListeners();
  }

  /// Fingerprint/face gate for this device (Account → Privacy & sign-in).
  bool get biometricEnabled => _biometricEnabled;

  /// This device's stable ID — sent to the Worker with X-Device-Id so every
  /// sign-in session can be listed and revoked individually.
  String get deviceId => _deviceId;

  /// Server-active courier ids (DB). The owner can toggle couriers OFF in the
  /// admin console; null until the first fetch succeeds — offline or unknown,
  /// the full catalog shows so senders are never bricked.
  List<int>? _activeCourierIds;
  List<int>? get activeCourierIds => _activeCourierIds;

  /// Full live rows from /couriers (id, name, city, depot_name, lat, lng…) —
  /// lets screens merge built-in catalog entries with live depots the owner
  /// adds/toggles without an app release.
  List<Map<String, dynamic>>? _activeServerCouriers;
  List<Map<String, dynamic>>? get activeServerCouriers => _activeServerCouriers;

  Future<void> refreshCourierAvailability() async {
    try {
      final rows = await DropOffApi.couriers();
      _activeCourierIds = [
        for (final r in rows)
          if ((r['id'] as num?) != null && (r['id'] as num).toInt() > 0) (r['id'] as num).toInt(),
      ];
      _activeServerCouriers = rows.map((r) => Map<String, dynamic>.from(r)).toList();
    } catch (_) {
      // Offline / API unavailable → keep null (full catalog).
    }
    notifyListeners();
  }

  Future<void> setBiometricEnabled(bool on) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_biometricKey, on);
    _biometricEnabled = on;
    notifyListeners();
  }

  /// Registered once at startup. Keeps the signed-in identity (including the
  /// profile photo) current on EVERY screen — the Task Queue avatar, Home
  /// header, Account, tracking — without waiting for the user to tap a profile
  /// picture or open Account.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _linkedPhone != null && DropOffApi.enabled) {
      unawaited(refreshRole(force: true));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> initialize() async {
    WidgetsBinding.instance.addObserver(this);
    final preferences = await SharedPreferences.getInstance();
    final remember = preferences.getBool(_rememberKey) ?? true;
    _biometricEnabled = preferences.getBool(_biometricKey) ?? false;
    // Account-scoped keys: namespace local state by email AND phone so an
    // old phone-only session can't leak into a newer session on the same
    // device, even when the phone is identical.
    final phone = preferences.getString('dropoff_phone_v1');
    final email = preferences.getString('dropoff_email_v1');
    _account = preferences.getString(_accountKey) ??
        ((email != null && email.isNotEmpty) ? '$email|$phone' : (phone != null && phone.isNotEmpty ? phone : 'anon'));
    if (preferences.getString(_accountKey) == null && _account != 'anon') {
      for (final base in const ['bookings', 'riders', 'outbox', 'token_v1', 'fallback', 'phone', 'email']) {
        final legacy = switch (base) {
          'token_v1' => 'dropoff_token_v1',
          'fallback' => 'dropoff_token_fallback_v1',
          'phone' => 'dropoff_phone_v1',
          'email' => 'dropoff_email_v1',
          _ => 'dropoff_${base}_v1',
        };
        if (preferences.containsKey(legacy)) {
          await preferences.setString(_scoped(base), preferences.getString(legacy)!);
          await preferences.remove(legacy);
        }
      }
      await preferences.setString(_accountKey, _account);
    }
    // Device ID — stays stable across cold starts so "untrust this device"
    // survives. Generated once per install from cryptographic randomness.
    var dev = preferences.getString(_deviceKey);
    if (dev == null) {
      dev = _newDeviceId();
      await preferences.setString(_deviceKey, dev);
    }
    _deviceId = dev;
    _shareLocationOn = preferences.getBool(_shareLocationKey) ?? true;
    DropOffApi.installDeviceId(dev);
    unawaited(DropOffApi.resolveDeviceName());
    unawaited(refreshCourierAvailability());
    if (!remember) {
      // Session-only login: drop any persisted credential on cold start.
      await _secureStorage.delete(key: _secureTokenKey);
      await preferences.remove(_tokenKey);
      await preferences.remove(_fallbackTokenKey);
      await preferences.remove(_phoneKey);
      await preferences.remove(_emailKey);
    }
    _token = await _secureStorage.read(key: _secureTokenKey);
    _token ??= preferences.getString(_fallbackTokenKey); // keystore hiccups happen
    if (_token != null && await _secureStorage.read(key: _secureTokenKey) == null) {
      // Re-seal into the keystore if it's usable again.
      unawaited(_secureStorage.write(key: _secureTokenKey, value: _token!));
    }
    DropOffApi.token = _token;
    DropOffApi.onAuthFailure = handleApiAuthFailure;
    _linkedPhone = preferences.getString(_phoneKey);
    _email = preferences.getString(_emailKey);
    await _reloadAccountCache();
    // Team roster is the server's list (shared across admins/devices) —
    // sync it on every cold start so it never resets to empty on this device.
    if (DropOffApi.enabled) unawaited(syncRidersFromServer());
    _ready = true;
    notifyListeners();
    unawaited(flushOutbox());
    // Rolling session: renew the JWT while the server still vouches for it.
    // A hard-dead token (revoked password reset / idle past grace) wipes the
    // credentials but keeps the user's data and shows the honest sign-in door.
    if (_token != null && DropOffApi.enabled) {
      final out = await DropOffApi.refreshSession();
      if (out['dead'] == true) {
        await unlink();
      } else if (out['renewed'] == true && out['token'] is String) {
        _token = out['token'] as String;
        DropOffApi.token = _token;
        if (remember) {
          await _secureStorage.write(key: _secureTokenKey, value: _token!);
          await preferences.setString(_fallbackTokenKey, _token!);
        }
        // remember == false: renew in memory only, never on disk
      }
    }
    if (DropOffApi.enabled) unawaited(refreshRole());
  }


  /// Pulls the signed-in identity's role from GET /me so the shell can hide
  /// Team/admin surfaces from ordinary sellers and recipients. Runs even
  /// without a JWT: an ops-key device (rider build) resolves role='ops' via
  /// X-Api-Key; a bare session gets role=null (fail closed — staff hidden).
  Future<void> refreshRole({bool force = false}) async {
    if (!DropOffApi.enabled) return;
    final me = await DropOffApi.me(force: force);
    if (me == null) return;
    final next = '${me['role'] ?? ''}';
    final role = next.isEmpty ? null : next;
    final previousRole = _role;
    final sa = me['superadmin'] == true;
    final photo = me['photo_url'] as String?;
    final name = me['full_name'] as String?;
    final email = me['email'] as String?;
    final preferences = await SharedPreferences.getInstance();
    if (role != _role || sa != _superadmin || photo != _photoUrl || name != _fullName || email != _email) {
      _role = role;
      _superadmin = sa;
      _photoUrl = photo;
      _fullName = name;
      if (email != null) {
        _email = email;
        await preferences.setString(_emailKey, email);
      }
      notifyListeners();
    }
    // A rider who just linked this phone MUST be dispatchable. unlink() clears
    // the flag for privacy; re-enable it when the role changes to rider so the
    // presence pings resume and orders keep flowing (owner audit 2026-11-21).
    if (role == 'rider' && previousRole != 'rider' && !_shareLocationOn) {
      await setShareLocationOn(true);
    }
  }

  static bool _authFailureBusy = false;

  /// GLOBAL 401 HANDLER (owner audit 2026-11-21): try one JWT refresh, then
  /// clear the session with an honest message. No stale cache, no zombie
  /// signed-in state, no silently dropped mutation.
  Future<void> handleApiAuthFailure() async {
    if (_authFailureBusy) return;
    _authFailureBusy = true;
    try {
      final out = await DropOffApi.refreshSession();
      if (out['renewed'] == true && out['token'] is String) {
        _token = out['token'] as String;
        DropOffApi.token = _token;
        final prefs = await SharedPreferences.getInstance();
        if (prefs.getBool(_rememberKey) ?? true) {
          await _secureStorage.write(key: _secureTokenKey, value: _token!);
          await prefs.setString(_fallbackTokenKey, _token!);
        }
        return;
      }
      await unlink();
      lastAuthError = 'Your session expired — sign in again.';
      notifyListeners();
      scaffoldMessengerKey.currentState
        ?..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Your session expired — sign in again.')));
    } finally {
      _authFailureBusy = false;
    }
  }

  /// Offline outbox: bookings created without signal are retried here. The
  /// Idempotency-Key is the local booking id, so a retry can never double-book.
  Future<void> _persistOutbox() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_outboxKey, jsonEncode(_outbox));
  }

  Future<void> _enqueueJob(String localId, Map<String, dynamic> payload) async {
    if (_outbox.any((item) => item['local_id'] == localId)) return;
    _outbox.add({'type': 'job', 'local_id': localId, 'payload': payload, 'attempts': 0});
    await _persistOutbox();
  }

  Future<void> flushOutbox() async {
    if (!DropOffApi.enabled || !linked || _outbox.isEmpty) return;
    for (final item in List<Map<String, dynamic>>.from(_outbox)) {
      if (item['type'] != 'job') continue;
      final payload = (item['payload'] as Map).cast<String, dynamic>();
      final res = await DropOffApi.createJob(payload);
      if (res.ok) {
        final index = _bookings.indexWhere((b) => b.id == item['local_id']);
        if (index >= 0) {
          _bookings[index] = _bookings[index].copyWith(
            serverRef: res.body['ref'] as String?,
            promoCode: res.body['promo_code'] as String? ?? _bookings[index].promoCode,
            promoDiscount: (res.body['promo_discount_zmw'] as num?)?.toDouble() ?? _bookings[index].promoDiscount,
          );
          await _saveBookings();
        }
        _outbox.remove(item);
        await _persistOutbox();
        notifyListeners();
      } else if (res.error != 'network_error') {
        // server rejected it (quote missing, expired promo, etc.) — drop it so
        // the outbox can't wedge forever; the user can rebook with feedback.
        _outbox.remove(item);
        await _persistOutbox();
      }
    }
    unawaited(DropOffApi.flushRatingOutbox());
    unawaited(AnalyticsService.instance.flush());
    await flushRecipientsOutbox();
  }

  /// Queue or send a recipient right now, depending on connectivity. Returns
  /// true iff the server (or the outbox) has it.
  Future<bool> saveRecipient({required String name, required String phone, required String city}) async {
    if (!DropOffApi.enabled) return false;
    final payload = {'name': name, 'phone': phone, 'city': city};
    final res = await DropOffApi.saveRecipient(payload);
    if (res.ok) return true;
    if (res.error == 'network_error' || res.error == 'offline_demo_mode') {
      _recipientsOutbox.add(payload);
      await _persistRecipientsOutbox();
      notifyListeners();
      return true; // queued locally — syncs later
    }
    return false;
  }

  Future<void> flushRecipientsOutbox() async {
    if (!DropOffApi.enabled || !linked || _recipientsOutbox.isEmpty) return;
    final remaining = <Map<String, dynamic>>[];
    for (final recipient in List<Map<String, dynamic>>.from(_recipientsOutbox)) {
      final res = await DropOffApi.saveRecipient(recipient);
      if (!res.ok) {
        if (res.error == 'network_error' || res.error == 'offline_demo_mode') remaining.add(recipient);
        // server rejected (e.g. duplicate) — drop it so the outbox doesn't wedge
      }
    }
    if (remaining.length != _recipientsOutbox.length) {
      _recipientsOutbox
        ..clear()
        ..addAll(remaining);
      await _persistRecipientsOutbox();
      notifyListeners();
    }
  }

  Future<void> _persistRecipientsOutbox() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_recipientsOutboxKey, jsonEncode(_recipientsOutbox));
  }

  /// Phone-OTP device link: request the SMS code, then confirm it.
  Future<void> requestOtp(String phone) => DropOffApi.requestOtp(phone);

  Future<bool> confirmOtp(String phone, String code) async {
    final res = await DropOffApi.verifyOtp(phone, code);
    if (res.ok) {
      await _saveSession(token: DropOffApi.token, phone: res.body['phone'] as String? ?? phone, email: null);
      unawaited(PushService.register());
      return true;
    }
    return false;
  }

  /// Email + password account (customer login / first-time registration).
  Future<bool> registerEmail({
    required String email,
    required String password,
    required String phone,
    String? fullName,
    bool remember = true,
  }) async {
    final res = await DropOffApi.registerEmail(
      email: email,
      password: password,
      phone: phone,
      fullName: fullName,
    );
    _captureAuthError(res);
    if (res.ok) {
      await _saveSession(
        token: DropOffApi.token,
        phone: res.body['phone'] as String?,
        email: res.body['email'] as String? ?? email,
        remember: remember,
      );
      unawaited(PushService.register());
      return true;
    }
    return false;
  }

  Future<bool> loginEmail(String email, String password, {bool remember = true}) async {
    final res = await DropOffApi.loginEmail(email, password);
    _captureAuthError(res);
    if (res.ok) {
      await _saveSession(
        token: DropOffApi.token,
        phone: res.body['phone'] as String?,
        email: res.body['email'] as String? ?? email,
        remember: remember,
      );
      unawaited(PushService.register());
      return true;
    }
    return false;
  }

  Future<ApiResponse> forgotPassword(String email) async {
    final res = await DropOffApi.forgotPassword(email);
    _captureAuthError(res);
    return res;
  }

  Future<ApiResponse> resendVerification(String email) async {
    final res = await DropOffApi.resendVerification(email);
    _captureAuthError(res);
    return res;
  }

  Future<void> _saveSession({required String? token, String? phone, String? email, bool remember = true}) async {
    _token = token;
    _linkedPhone = phone ?? _linkedPhone;
    _email = email;
    // Rebind the account namespace to this phone (email fallback) so the
    // misc local caches from this account are read on startup next time.
    final preferences = await SharedPreferences.getInstance();
    if (phone != null && phone.isNotEmpty) {
      _account = phone;
      await preferences.setString(_accountKey, _account);
    } else if (email != null && email.isNotEmpty) {
      _account = email;
      await preferences.setString(_accountKey, _account);
    }
    await _reloadAccountCache();
    await preferences.setBool(_rememberKey, remember);
    if (token != null && remember) {
      await _secureStorage.write(key: _secureTokenKey, value: token);
      await preferences.setString(_tokenKey, token);
      await preferences.setString(_fallbackTokenKey, token);
      if (_linkedPhone != null) await preferences.setString(_phoneKey, _linkedPhone!);
      if (_email != null) await preferences.setString(_emailKey, _email!);
    } else if (token != null && !remember) {
      // Keep the session in memory only — never write credentials to disk.
      await _secureStorage.delete(key: _secureTokenKey);
      await preferences.remove(_tokenKey);
      await preferences.remove(_fallbackTokenKey);
      await preferences.remove(_phoneKey);
      await preferences.remove(_emailKey);
    }
    notifyListeners();
    if (token != null) {
      unawaited(flushOutbox());
      unawaited(refreshRole());
    }
  }

  /// Last auth error message from login/register for inline display.
  String? lastAuthError;

  /// Server's plan decision for the most recent booking ('pack' | 'payg' | null).
  String? lastBookingPlanInclusion;
  String? lastBookingWindowRolled;
  double? lastBookingDueZmw;
  int? lastBookingPlanUsed;
  int? lastBookingPlanCap;
  int? lastBookingParcels;
  /// The SERVER's own prepayment decision (owner directive 2026-11-15): the
  /// booking flow pays only when the server demanded a deposit or the prompt
  /// could not start — never inferred client-side from plan inclusion.
  bool lastBookingDepositRequired = false;
  bool lastBookingDepositInitFailed = false;
  /// ONE PARCEL, ONE CHAT (owner directive 2026-11-17): the server matched
  /// this booking to the sender's own UNPAID booking of the same trip and
  /// returned THAT job instead of minting a duplicate — the app should tell
  /// the sender to finish the payment they already have, not book twice.
  bool lastBookingDeduped = false;
  /// Pickup-strike count on the sender for this booking — kept visible as a
  /// warning only. Bookings are allowed regardless (owner 2026-11-20).
  int? lastBookingStrikes;
  /// The rider the dispatch algorithm picked for the last booking (server
  /// response). Replaces the old hard-coded "Owner" default.
  String? lastBookingAutoRiderName;
  int? lastBookingAutoRiderId;
  String? lastBookingError;
  String? lastBookingErrorDetail;

  void _captureAuthError(ApiResponse res) {
    lastAuthError = res.ok ? null : authErrorText(res.body['error'] as String? ?? '');
  }

  /// Maps a failed login/register/forgot-password response to a human message.
  static String authErrorText(String error) {
    switch (error) {
      case 'invalid_credentials':
        return 'Wrong email or password.';
      case 'unknown_email':
        return 'No DropOff account with that email — create one, or sign in with your phone code instead.';
      case 'wrong_password':
        return 'Wrong password for that email — try again.';
      case 'email_already_registered':
        return 'That email already has an account - sign in instead.';
      case 'phone_already_used':
        return 'That phone number is already linked to an account.';
      case 'password_too_short_min_8':
        return 'Use at least 8 characters for the password.';
      case 'invalid_email':
        return 'Enter a valid email address.';
      case 'network_error':
        return "Can't reach DropOff right now - check your internet connection and try again.";
      case 'too_many_requests':
      case 'too_many_attempts_wait_an_hour':
      case 'too_many_codes_wait_an_hour':
        return 'Too many tries - wait an hour, then retry.';
      case 'session_revoked':
        return 'Your session was revoked - sign in again.';
      case 'account_already_exists':
        return 'An account with those details already exists - sign in instead.';
      case 'internal_error':
        return 'DropOff is having a moment - please try again in a minute.';
      case 'unknown':
      case '':
        return 'Something went wrong. Check your details and retry.';
      default:
        return 'Something went wrong. Check your details and retry.';
    }
  }

  static String _newDeviceId() {
    final now = DateTime.now().microsecondsSinceEpoch;
    final rng = Random.secure();
    final hex = List.generate(8, (_) => rng.nextInt(256)).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    final ts = now.toRadixString(16);
    return 'dev-$ts-$hex';
  }

  Future<void> _reloadAccountCache() async {
    final preferences = await SharedPreferences.getInstance();
    _bookings.clear();
    _riders.clear();
    _outbox.clear();
    try {
      final bookingJson = preferences.getString(_bookingsKey);
      if (bookingJson != null) {
        _bookings.addAll((jsonDecode(bookingJson) as List)
            .map((item) => Booking.fromJson(item as Map<String, dynamic>)));
      }
      final riderJson = preferences.getString(_ridersKey);
      if (riderJson != null) {
        _riders.addAll((jsonDecode(riderJson) as List)
            .map((item) => Rider.fromJson(item as Map<String, dynamic>)));
      }
      final outboxJson = preferences.getString(_outboxKey);
      if (outboxJson != null) {
        _outbox.addAll((jsonDecode(outboxJson) as List).cast<Map<String, dynamic>>());
      }
      final recipientsJson = preferences.getString(_recipientsOutboxKey);
      if (recipientsJson != null) {
        _recipientsOutbox.addAll((jsonDecode(recipientsJson) as List).cast<Map<String, dynamic>>());
      }
    } catch (_) {
      await preferences.remove(_bookingsKey);
      await preferences.remove(_ridersKey);
      await preferences.remove(_outboxKey);
      await preferences.remove(_recipientsOutboxKey);
      _bookings.clear();
      _riders.clear();
      _outbox.clear();
    }
    if (_riders.isEmpty) {
      _riders.add(const Rider(
        id: 'admin',
        name: 'Admin',
        phone: 'Add your phone in team settings',
        vehicle: 'Motorcycle / vehicle',
        isOwner: true,
      ));
    }
  }

  Future<void> unlink() async {
    await PushService.unregister();
    DropOffApi.clearCaches(); // wipes persisted /me /subscriptions cache too
    // Queued offline ratings belong to the signing-out account — discard them
    // rather than let them flush into the next user's session.
    unawaited(DropOffApi.clearRatingOutbox());
    unawaited(AnalyticsService.instance.clearPendingForSignOut());
    final prev = _account;
    _token = null;
    _linkedPhone = null;
    _role = null;
    _photoUrl = null;
    _fullName = null;
    _superadmin = false;
    // A different rider/seller links this phone next — do NOT leak GPS or language.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_shareLocationKey, false);
    _shareLocationOn = false;
    _bookings.clear();
    _riders.clear();
    _outbox.clear();
    _recipientsOutbox.clear();
    DropOffApi.token = null;
    await _secureStorage.delete(key: _secureTokenKey);
    // Biometric enrollment is tied to the account that turned it on — the next
    // account must opt in explicitly, never inherit a pass.
    _biometricEnabled = false;
    await prefs.remove(_biometricKey);
    // Queued offline recipient saves belong with the signing-out account only.
    try {
      await prefs.remove(_recipientsOutboxKey);
    } catch (_) {
      /* best-effort */
    }
    _recipientsOutbox.clear();
    // Remember-me opt-in is per-account — next sign-in must choose fresh.
    await prefs.remove(_rememberKey);
    final preferences = await SharedPreferences.getInstance();
    if (prev != 'anon') {
      // Enumerate every scoped key we track...
      for (final name in const ['bookings', 'riders', 'outbox', 'jwt', 'jwt_mirror', 'jwt_legacy_mirror', 'phone', 'email']) {
        await preferences.remove(_scoped(name));
      }
      // ...then ALSO sweep any residue under the same account prefix — belt and
      // braces so a future scoped key added elsewhere can never linger.
      final prefix = '${_accountKey}_${prev}_';
      for (final key in preferences.getKeys().where((k) => k.startsWith(prefix)).toList()) {
        await preferences.remove(key);
      }
      await preferences.remove(_accountKey);
    }
    _account = 'anon';
    notifyListeners();
  }

  /// Creates the booking locally (the app always works offline). If the
  /// Worker is configured, it is dispatched server-side where *the Worker*
  /// computes the verified pricing. Pricing from the client is never trusted.
  Future<Booking> createBooking({
    required String senderName,
    required String senderPhone,
    required String pickupAddress,
    required String fromCity,
    required String toCity,
    required String courierId,
    required ParcelSize parcelSize,
    required String description,
    required String recipientName,
    required String recipientPhone,
    required String paymentMethod,
    required double riderFee,
    required double? courierFare,
    required double lastMileFee,
    String pickupWindow = 'now',
    String? service,
    String? promoCode,
    required bool roundTrip,
    required String? returnCity,
    required String? returnAddress,
    required double returnLegFee,
    required String? pickupAt,
    int parcels = 1,
    String vehicleClass = 'motorcycle',
    bool needsCar = false,
    String? branch,
    String? parcelPhotoUrl,
    double? pickupLat,
    double? pickupLng,
    // DECLARED VALUE (owner directive 2026-11-17): the parcel's worth in ZMW
    // for the depot counter receipt — NOT a cover value, never marketed as
    // protection.
    double? declaredValueZmw,
  }) async {
    final now = DateTime.now();
    final id = now.microsecondsSinceEpoch.toString();

    // dispatch first (if linked) so the returned booking carries the server ref
    ApiResponse response = const ApiResponse(error: 'offline_demo_mode');
    final jobPayload = <String, dynamic>{
      'idempotency_key': 'job-$id',
      'sender_name': senderName,
      'pickup_address': pickupAddress,
      if (pickupLat != null && pickupLng != null) 'pickup_lat': pickupLat,
      if (pickupLat != null && pickupLng != null) 'pickup_lng': pickupLng,
      'from_city': fromCity,
      // jobs.courier_id is an INTEGER FK → couriers(id). The UI tracks catalog
      // ids ('platinum'…) — send the server id or the INSERT dies with a FK
      // constraint failure (SQLITE_CONSTRAINT_FOREIGNKEY).
      'courier_id': courierServerIdOf(courierId) ?? 1,
      'recipient_name': recipientName,
      'recipient_phone': recipientPhone,
      'dest_city': toCity,
      'dest_leg2': lastMileFee > 0,
      'description': description,
      'parcels': parcels,
      'needs_car': needsCar,
      'vehicle_class': vehicleClass,
      // No cash path — every parcel is prepaid via mobile money at booking,
      // in-line with the worker's prepaid gate (cash is rejected server-side).
      'pay_method': 'mobile_money',
      'weight_class': switch (parcelSize) {
        ParcelSize.small => '0-5kg',
        ParcelSize.medium => '5-15kg',
        ParcelSize.large => '15kg+',
      },
      // Drives the server's size-aware motorcycle caps (10/5/1); weight_class
      // stays for records and quote lookup.
      'parcel_size': switch (parcelSize) {
        ParcelSize.small => 'small',
        ParcelSize.medium => 'medium',
        ParcelSize.large => 'large',
      },
      'service': service ?? 'standard',
      'pickup_window': pickupWindow,
      'pickup_time': pickupWindow,
      if (parcelPhotoUrl != null && parcelPhotoUrl.isNotEmpty) 'parcel_photo_url': parcelPhotoUrl,
      if (declaredValueZmw != null && declaredValueZmw > 0) 'declared_value_zmw': declaredValueZmw,
      if (promoCode != null && promoCode.isNotEmpty) 'promo_code': promoCode.trim().toUpperCase(),
    };
    lastBookingError = null;
    lastBookingErrorDetail = null;
    lastBookingDeduped = false;
    if (DropOffApi.enabled) {
      response = await DropOffApi.createJob(jobPayload);
      if (!response.ok && response.error == 'network_error') {
        await _enqueueJob(id, jobPayload);
      } else if (!response.ok) {
        lastBookingError = response.body['error']?.toString() ?? response.error?.toString();
        lastBookingErrorDetail = response.body['detail']?.toString() ?? response.body['message']?.toString();
      }
    }
    final serverRef = response.body['ref'] as String?;
    final promoApplied = response.body['promo_code'] as String?;
    final promoDiscount = (response.body['promo_discount_zmw'] as num?)?.toDouble();
    // Expose the server's plan decision so the booking screen knows whether to
    // prompt for payment ('pack' = rider fee already inside the subscription).
    lastBookingStrikes = (response.body['strikes'] as num?)?.toInt();
    lastBookingPlanInclusion = response.body['plan_inclusion'] as String?;
    lastBookingWindowRolled = response.body['window_rolled_from'] as String?;
    lastBookingDueZmw = (response.body['prompt_total_zmw'] as num?)?.toDouble();
    lastBookingPlanUsed = (response.body['plan_used'] as num?)?.toInt();
    lastBookingPlanCap = (response.body['plan_cap'] as num?)?.toInt();
    lastBookingParcels = (response.body['parcels'] as num?)?.toInt() ?? parcels;
    lastBookingDepositRequired = (response.body['deposit_required'] as bool?) ?? ((response.body['deposit_required'] as num?)?.toInt() == 1);
    lastBookingDepositInitFailed = (response.body['deposit_init_failed'] as bool?) ?? ((response.body['deposit_init_failed'] as num?)?.toInt() == 1);
    lastBookingDeduped = response.body['deduped'] == true;
    // The algorithm picks the rider (nearest available, load-balanced) — the
    // app NEVER defaults a booking to the owner pseudo-rider (owner directive
    // 2026-11-15). No assignment yet = empty riderId + null riderName.
    final autoAssigned = response.body['auto_assigned'] as Map<String, dynamic>?;
    lastBookingAutoRiderId = (autoAssigned?['rider_id'] as num?)?.toInt();
    lastBookingAutoRiderName = autoAssigned?['rider'] as String?;

    final booking = Booking(
      id: id,
      reference: 'DO-${now.year}-${id.substring(id.length - 6)}',
      createdAt: now,
      senderName: senderName.trim(),
      senderPhone: senderPhone.trim(),
      pickupAddress: pickupAddress.trim(),
      fromCity: fromCity,
      toCity: toCity,
      courierId: courierId,
      parcelSize: parcelSize,
      description: description.trim(),
      recipientName: recipientName.trim(),
      recipientPhone: recipientPhone.trim(),
      paymentMethod: paymentMethod,
      riderFee: riderFee,
      courierFare: courierFare,
      lastMileFee: lastMileFee,
      pickupWindow: pickupWindow,
      serverRef: serverRef,
      promoCode: promoApplied ?? (promoCode?.trim().isEmpty ?? true ? null : promoCode?.trim().toUpperCase()),
      promoDiscount: promoDiscount,
      // Algorithm-assigned rider only (never a default owner): when the server
      // dispatched nobody yet, riderId stays empty and the UI shows
      // "Awaiting rider assignment".
      riderId: lastBookingAutoRiderId != null ? '$lastBookingAutoRiderId' : '',
      riderName: lastBookingAutoRiderName,
      paymentHeld: lastBookingDepositRequired || lastBookingDepositInitFailed,
      roundTrip: roundTrip,
      returnCity: returnCity,
      returnAddress: returnAddress,
      returnLegFee: returnLegFee,
      pickupAt: pickupAt,
      parcels: parcels,
      vehicleClass: vehicleClass,
      branch: branch,
      declaredValueZmw: declaredValueZmw,
    );
    if (lastBookingError != null && lastBookingError != 'network_error') {
      notifyListeners();
      return booking;
    }
    _bookings.insert(0, booking);
    await _saveBookings();
    notifyListeners();
    return booking;
  }

  // Booking stages are AUTOMATED (owner directive 2026-11-15 — manual
  // "Operator: mark" buttons are gone): the server advances a job through
  // rider events, payment settlement and the cron sweeps, and
  // [syncJobsFromServer] mirrors that progress into the local list.

  /// Algorithm-assigned rider lands here after dispatch (owner directive
  /// 2026-11-15): both the roster id and the rider's real name move together,
  /// replacing the old owner-defaulted local assignment.
  /// Manual rider assignment was removed with the "Operator: mark" flow —
  /// [setBookingRider] below is the only rider-write left, fed by the server's
  /// auto-assign response and synced jobs.
  Future<void> setBookingRider(String bookingId, {String? riderId, String? riderName}) async {
    final index = _bookings.indexWhere((booking) => booking.id == bookingId);
    if (index < 0) return;
    _bookings[index] = _bookings[index].copyWith(
      riderId: riderId ?? _bookings[index].riderId,
      riderName: riderName ?? _bookings[index].riderName,
    );
    await _saveBookings();
    notifyListeners();
  }

  /// In-flow prepayment approved — the booking is no longer HELD. The
  /// Pay-now gate and the recipient tracking/share cards unlock immediately
  /// (the next [syncJobsFromServer] confirms with the server's events).
  Future<void> clearPaymentHeld(String bookingId) async {
    final index = _bookings.indexWhere((booking) => booking.id == bookingId);
    if (index < 0 || !_bookings[index].paymentHeld) return;
    _bookings[index] = _bookings[index].copyWith(paymentHeld: false);
    await _saveBookings();
    notifyListeners();
  }

  /// Every staff account sees the SAME roster: created once server-side, it
  /// shows up for every admin on every device. This syncs the local cache
  /// from GET /admin/riders (offline-tolerant: keeps cache on failure).
  Future<void> syncRidersFromServer() async {
    if (!DropOffApi.enabled) return;
    final data = await DropOffApi.get('/admin/riders');
    final list = ((data?['riders'] as List?) ?? const []).cast<Map<String, dynamic>>();
    if (list.isEmpty) return; // keep local cache rather than wiping on an empty read
    _riders
      ..clear()
      ..add(const Rider(
        id: 'admin',
        name: 'Admin',
        phone: 'Add your phone in team settings',
        vehicle: 'Motorcycle / vehicle',
        isOwner: true,
      ));
    for (final r in list) {
      _riders.add(Rider(
        id: '${r['id'] ?? ''}',
        name: '${r['full_name'] ?? ''}',
        phone: '${r['phone'] ?? ''}',
        vehicle: '${r['vehicle'] ?? ''}',
        active: (r['active'] as num?)?.toInt() == 1,
      ));
    }
    await _saveRiders();
    notifyListeners();
  }

  /// Adds a rider/team member SERVER-side first (only admin/superadmin may
  /// create riders): the roster is shared, so this never resets. Returns null
  /// on full success, or an error message when the server rejected the write.
  Future<String?> addRider({required String name, required String phone, required String vehicle, String vehicleClass = 'motorcycle'}) async {
    if (!(isSuperAdmin || isAdminRole)) {
      return 'Only admins can add riders.';
    }
    if (DropOffApi.enabled) {
      final res = await DropOffApi.post('/admin/riders', {
        'phone': phone.trim(),
        'full_name': name.trim(),
        'vehicle': vehicle,
        'vehicle_class': vehicleClass,
      });
      if (!res.ok) {
        if (res.status == 403 || res.error == 'admin_key_required' || res.error == 'forbidden') {
          return 'Only admins can add riders.';
        }
        return 'Could not add the rider (${res.error ?? 'network'}).';
      }
    }
    await syncRidersFromServer();
    return null;
  }

  Future<String?> updateRider(int id, {String? fullName, String? phone, String? vehicle, String? vehicleClass, bool? active}) async {
    if (!(isSuperAdmin || isAdminRole)) return 'Only admins can edit riders.';
    if (DropOffApi.enabled) {
      final body = <String, dynamic>{
        if (fullName != null) 'full_name': fullName.trim(),
        if (phone != null) 'phone': phone.trim(),
        if (vehicle != null) 'vehicle': vehicle.trim(),
        if (vehicleClass != null) 'vehicle_class': vehicleClass.trim(),
        if (active != null) 'active': active,
      };
      final res = await DropOffApi.updateRider(id, body);
      if (!res.ok) {
        return '${res.body['detail'] ?? res.body['error'] ?? 'Could not update rider.'}';
      }
    }
    await syncRidersFromServer();
    return null;
  }

  Future<String?> toggleRider(String id, bool active) async {
    final index = _riders.indexWhere((rider) => rider.id == id);
    if (index < 0 || _riders[index].isOwner) return 'Rider not found.';
    if (!(isSuperAdmin || isAdminRole)) return 'Only admins can change rider status.';
    final numericId = int.tryParse(id);
    if (DropOffApi.enabled && numericId != null) {
      final err = await updateRider(numericId, active: active);
      if (err != null) return err;
      return null;
    }
    _riders[index] = _riders[index].copyWith(active: active);
    await _saveRiders();
    notifyListeners();
    return null;
  }

  /// Conditional, gated deletion: admin-only, requires explicit confirmation,
  /// and is blocked when open local bookings are still assigned to the rider.
  /// Server enforces the final open-jobs condition.
  Future<String?> removeRider(String id, {bool confirm = false}) async {
    final rider = _riders.where((item) => item.id == id).firstOrNull;
    if (rider == null || rider.isOwner) return 'Rider not found.';
    if (!(isSuperAdmin || isAdminRole)) return 'Only admins can remove riders.';
    if (!confirm) return 'Deletion not confirmed.';
    final hasOpen = _bookings.any((b) => b.riderId == id && b.stage < b.timeline.length - 1);
    if (hasOpen) {
      return 'Cannot delete ${rider.name}: they still have open bookings assigned. Reassign/complete those bookings or deactivate the rider instead.';
    }
    final numericId = int.tryParse(id);
    if (DropOffApi.enabled && numericId != null) {
      final res = await DropOffApi.deleteRider(numericId, confirm: true);
      if (!res.ok) {
        return '${res.body['detail'] ?? res.body['error'] ?? 'Could not delete rider.'}';
      }
      await syncRidersFromServer();
      return null;
    }
    _riders.removeWhere((item) => item.id == id);
    for (var i = 0; i < _bookings.length; i++) {
      if (_bookings[i].riderId == id) {
        _bookings[i] = _bookings[i].copyWith(riderId: owner.id);
      }
    }
    await Future.wait([_saveRiders(), _saveBookings()]);
    notifyListeners();
    return null;
  }

  /// Merge server-side jobs (collections, standing orders, ops-created jobs,
  /// anything this account can see via /jobs) into the local list so Bookings
  /// is complete. Best-effort; runs on the Bookings tab open and app start.
  Future<void> syncJobsFromServer() async {
    if (!DropOffApi.enabled) return;
    try {
      final data = await DropOffApi.get('/jobs', {'limit': '100'});
      final rows = (data?['jobs'] as List?)?.cast<Map<String, dynamic>>() ?? const <Map<String, dynamic>>[];
      if (rows.isEmpty) return;
      final refSet = _bookings.map((b) => b.serverRef).where((r) => r != null && r.isNotEmpty).toSet();
      var dirty = false;
      for (final j in rows) {
        final ref = '${j['ref'] ?? ''}';
        if (ref.isEmpty) continue;
        final door = (j['last_mile'] ?? 0) == 1 || ((j['leg2_fee_zmw'] as num?) ?? 0) > 0;
        final stage = _stageFromJobStatus('${j['status']}', door,
            collection: '${j['service'] ?? ''}' == 'collection');
        final existing = _bookings.where((b) => b.serverRef == ref).firstOrNull;
        if (existing != null) {
          final i = _bookings.indexWhere((b) => b.id == existing.id);
          if (i >= 0) {
            final lastEvent = '${j['last_event'] ?? ''}';
            final riderName = j['rider_name'] as String?;
            // PAID BEATS PROMPT EVENTS (owner bug 2026-11-17: "money deducted,
            // screen never flips to success"): a settled prompt leaves the
            // advance_pending event in history (nothing newer may exist), so
            // keying HELD off lastEvent alone held PAID bookings forever.
            // jobs.paid is the settlement truth — never hold a paid parcel.
            final jobPaid = ((j['paid'] as num?)?.toInt() ?? 0) == 1;
            final held = !jobPaid && (lastEvent == 'advance_pending' || lastEvent == 'prepayment_pending');
            var changed = false;
            if (existing.stage < stage) {
              _bookings[i] = _bookings[i].copyWith(stage: stage);
              changed = true;
            }
            // Payment state and the algorithm-assigned rider ride along on
            // every sync so held bookings re-gate their Pay-now/share cards
            // and real rider names replace any placeholder.
            if (lastEvent.isNotEmpty && lastEvent != existing.lastEvent) {
              _bookings[i] = _bookings[i].copyWith(lastEvent: lastEvent, paymentHeld: held);
              changed = true;
            }
            if (riderName != null && riderName.isNotEmpty && riderName != existing.riderName) {
              _bookings[i] = _bookings[i].copyWith(riderName: riderName);
              changed = true;
            }
            final riderPhone = (j['rider_phone'] as String?)?.trim() ?? '';
            if (riderPhone.isNotEmpty && riderPhone != (existing.riderPhone ?? '')) {
              _bookings[i] = _bookings[i].copyWith(riderPhone: riderPhone);
              changed = true;
            }
            if (changed) dirty = true;
          }
          continue;
        }
        if (refSet.contains(ref)) continue;
        _bookings.insert(0, _bookingFromJob(j, stage));
        refSet.add(ref);
        dirty = true;
      }
      if (dirty) {
        await _saveBookings();
        notifyListeners();
      }
    } catch (_) {
      // best-effort — never block the screen on a sync failure
    }
  }

  static int _stageFromJobStatus(String status, bool door, {bool collection = false}) {
    // Collections run DEPOT → RECIPIENT on a 5-step timeline:
    // 0 placed · 1 assigned · 2 rider at depot · 3 collected · 4 delivered.
    if (collection) {
      return switch (status) {
        'rider_assigned' || 'partner_confirmed' => 1,
        'at_depot' || 'counter_recorded' => 2,
        'picked_up' || 'departed' || 'arrived' => 3,
        'delivered' || 'ready_for_collection' => 4,
        _ => 0,
      };
    }
    return switch (status) {
          'rider_assigned' || 'partner_confirmed' => 1,
          'picked_up' => 2,
          'at_depot' => door ? 4 : 3,
          'departed' || 'arrived' => door ? 5 : 4,
          'delivered' || 'ready_for_collection' => door ? 6 : 4,
          _ => 0,
        };
  }

  static DateTime _parseDbDate(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return DateTime.now();
    final normalized = s.contains('T') ? s : s.replaceFirst(' ', 'T');
    final withZone = normalized.endsWith('Z') || normalized.contains('+') ? normalized : '${normalized}Z';
    // Server timestamps are UTC ("Z"); the phone runs CAT (+2). Without
    // toLocal() every booking shows the UTC wall clock — 5:09 instead of
    // 7:09 (owner bug report 2026-11-17).
    final parsed = DateTime.tryParse(withZone) ?? DateTime.now();
    return parsed.isUtc ? parsed.toLocal() : parsed;
  }

  Booking _bookingFromJob(Map<String, dynamic> j, int stage) {
    final weight = '${j['weight_class'] ?? '0-5kg'}';
    final size = switch (weight) {
      '5-15kg' => ParcelSize.medium,
      '15kg+' => ParcelSize.large,
      _ => ParcelSize.small,
    };
    final door = (j['last_mile'] ?? 0) == 1 || ((j['leg2_fee_zmw'] as num?) ?? 0) > 0;
    final timelineMax = door ? 6 : 4;
    final lastEvent = j['last_event'] as String?;
    final riderNameRaw = '${j['rider_name'] ?? ''}'.trim();
    final riderPhoneRaw = '${j['rider_phone'] ?? ''}'.trim();
    return Booking(
      id: 'srv-${j['id']}',
      reference: '${j['ref']}',
      service: '${j['service'] ?? 'standard'}',
      collectionReceiptUrl: '${j['collection_receipt_url'] ?? ''}',
      createdAt: _parseDbDate('${j['created_at'] ?? ''}'),
      senderName: '${j['sender_name'] ?? 'You'}',
      senderPhone: '${j['sender_phone'] ?? ''}',
      pickupAddress: '${j['pickup_address'] ?? ''}',
      fromCity: '${j['from_city'] ?? 'Lusaka'}',
      toCity: '${j['dest_city'] ?? ''}',
      courierId: courierCatalogForServerId((j['courier_id'] as num?)?.toInt() ?? 1),
      parcelSize: size,
      description: '${j['description'] ?? ''}',
      recipientName: '${j['recipient_name'] ?? ''}',
      recipientPhone: '${j['recipient_phone'] ?? ''}',
      paymentMethod: '${j['pay_method'] ?? 'mobile_money'}',
      riderFee: (j['rider_fee_zmw'] as num?)?.toDouble() ?? 0,
      courierFare: null,
      lastMileFee: (j['leg2_fee_zmw'] as num?)?.toDouble() ?? 0,
      pickupWindow: '${j['pickup_window'] ?? 'now'}',
      serverRef: '${j['ref']}',
      stage: stage.clamp(0, timelineMax),
      // Algorithm-assigned rider from the server (never a default owner).
      riderId: '',
      riderName: riderNameRaw.isEmpty ? null : riderNameRaw,
      riderPhone: riderPhoneRaw.isEmpty ? null : riderPhoneRaw,
      // PAID BEATS PROMPT EVENTS (see syncJobsFromServer): never hold a
      // parcel the server has marked paid.
      paymentHeld: ((j['paid'] as num?)?.toInt() ?? 0) != 1 &&
          (lastEvent == 'advance_pending' || lastEvent == 'prepayment_pending'),
      parcels: (j['parcels'] as num?)?.toInt() ?? 1,
      vehicleClass: '${j['vehicle_class'] ?? 'motorcycle'}',
      branch: j['branch'] as String?,
      declaredValueZmw: (j['declared_value_zmw'] as num?)?.toDouble(),
      pickupAt: j['pickup_at'] as String?,
      roundTrip: (j['round_trip'] ?? 0) == 1,
      returnCity: j['return_city'] as String?,
      returnAddress: j['return_address'] as String?,
      returnLegFee: (j['return_leg_fee_zmw'] as num?)?.toDouble() ?? 0,
      promoCode: j['promo_code'] as String?,
      promoDiscount: (j['promo_discount_zmw'] as num?)?.toDouble(),
      lastEvent: j['last_event'] as String?,
      counterReceiptZmw: (j['counter_receipt_zmw'] as num?)?.toDouble(),
      counterReceiptUrl: j['counter_receipt_url'] as String?,
      counterReceiptPaid: (j['counter_receipt_paid'] ?? 0) == 1,
      repromptPaused: (j['reprompt_paused'] ?? 0) == 1 || j['reprompt_paused'] == true,
      counterReceipts: [
        for (final r in (j['counter_receipts'] as List?) ?? [])
          if (r is Map && r['url'] != null)
            ((r['amount_zmw'] as num?)?.toDouble() ?? 0, '${r['url']}')
      ],
    );
  }

  Future<void> _saveBookings() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_bookingsKey, jsonEncode(_bookings.map((item) => item.toJson()).toList()));
  }

  Future<void> _saveRiders() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_ridersKey, jsonEncode(_riders.map((item) => item.toJson()).toList()));
  }
}


