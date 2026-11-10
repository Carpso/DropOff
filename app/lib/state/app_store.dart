import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui' show Locale;

import 'package:flutter/foundation.dart';
import '../services/secure_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/dropoff_api.dart';
import '../data/analytics_service.dart';
import '../data/push_service.dart';
import '../models/booking.dart';

class AppStore extends ChangeNotifier {
  static const _rememberKey = 'dropoff_remember_v1';
  static const _biometricKey = 'dropoff_biometric_v1';
  static const _deviceKey = 'dropoff_device_id_v1';
  static const _accountKey = 'dropoff_acct_v1';

  String _account = 'anon';

  String _scoped(String name) => '${_accountKey}_${_account}_$name';

  String get _bookingsKey => _scoped('bookings');
  String get _ridersKey => _scoped('riders');
  String get _outboxKey => _scoped('outbox');
  String get _secureTokenKey => _scoped('jwt');
  String get _fallbackTokenKey => _scoped('jwt_mirror');
  String get _tokenKey => _scoped('jwt_legacy_mirror');
  String get _phoneKey => _scoped('phone');
  String get _emailKey => _scoped('email');

  final List<Booking> _bookings = [];
  final List<Rider> _riders = [];
  final List<Map<String, dynamic>> _outbox = [];
  bool _ready = false;
  String? _token;
  String? _linkedPhone;
  String? _email;
  String? _role;
  String? _photoUrl;
  String? _fullName;
  String? _localeCode;
  bool _superadmin = false;
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
  String? get localeCode => _localeCode == null || _localeCode!.isEmpty ? 'en' : _localeCode;
  Locale? get locale => Locale(localeCode ?? 'en');

  /// Server role for the signed-in identity: customer | partner | admin | ops |
  /// rider. Admin/ops unlock the Team tab and the admin console; rider unlocks
  /// a personal rider view (their queue + GPS) via phone-OTP login.
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

  /// Fingerprint/face gate for this device (Account → Privacy & sign-in).
  bool get biometricEnabled => _biometricEnabled;

  /// This device's stable ID — sent to the Worker with X-Device-Id so every
  /// sign-in session can be listed and revoked individually.
  String get deviceId => _deviceId;

  Future<void> setBiometricEnabled(bool on) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_biometricKey, on);
    _biometricEnabled = on;
    notifyListeners();
  }

  Future<void> initialize() async {
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
    DropOffApi.installDeviceId(dev);
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
    _linkedPhone = preferences.getString(_phoneKey);
    _email = preferences.getString(_emailKey);
    _localeCode = preferences.getString(_scoped('locale'));
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

  Future<void> setLocaleCode(String? code) async {
    final normalized = (code == null || code.trim().isEmpty) ? null : code.trim().toLowerCase();
    if (normalized == _localeCode) return;
    _localeCode = normalized;
    final preferences = await SharedPreferences.getInstance();
    if (normalized != null) {
      await preferences.setString(_scoped('locale'), normalized);
    } else {
      await preferences.remove(_scoped('locale'));
    }
    notifyListeners();
    if (DropOffApi.enabled && linked) {
      await DropOffApi.patchMe({'locale_pref': normalized});
    }
  }

  /// Pulls the signed-in identity's role from GET /me so the shell can hide
  /// Team/admin surfaces from ordinary sellers and recipients. Runs even
  /// without a JWT: an ops-key device (rider build) resolves role='ops' via
  /// X-Api-Key; a bare session gets role=null (fail closed — staff hidden).
  Future<void> refreshRole() async {
    if (!DropOffApi.enabled) return;
    final me = await DropOffApi.me();
    if (me == null) return;
    final next = '${me['role'] ?? ''}';
    final role = next.isEmpty ? null : next;
    final sa = me['superadmin'] == true;
    final photo = me['photo_url'] as String?;
    final name = me['full_name'] as String?;
    final email = me['email'] as String?;
    final loc = me['locale_pref'] as String?;
    // The language choice saved ON THIS DEVICE is authoritative: an explicit
    // pick in the picker must never be silently reverted by a /me refresh
    // (cold start, sign-in, photo flows) — otherwise the user is stuck in
    // whatever the server last knew about, e.g. 'ny'. The server only seeds
    // devices that have no choice saved yet.
    final preferences = await SharedPreferences.getInstance();
    final localChoice = preferences.getString(_scoped('locale'));
    final wantedLoc = (localChoice != null && localChoice.isNotEmpty)
        ? localChoice
        : ((loc == null || loc.isEmpty) ? null : loc);
    if (role != _role || sa != _superadmin || photo != _photoUrl || name != _fullName || email != _email || wantedLoc != _localeCode) {
      _role = role;
      _superadmin = sa;
      _photoUrl = photo;
      _fullName = name;
      _localeCode = wantedLoc;
      if (email != null) {
        _email = email;
        await preferences.setString(_emailKey, email);
      }
      if (_localeCode != null) {
        await preferences.setString(_scoped('locale'), _localeCode!);
      } else {
        await preferences.remove(_scoped('locale'));
      }
      notifyListeners();
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
    } catch (_) {
      await preferences.remove(_bookingsKey);
      await preferences.remove(_ridersKey);
      await preferences.remove(_outboxKey);
      _bookings.clear();
      _riders.clear();
      _outbox.clear();
    }
    if (_riders.isEmpty) {
      _riders.add(const Rider(
        id: 'owner',
        name: 'Owner',
        phone: 'Add your phone in team settings',
        vehicle: 'Motorcycle / vehicle',
        isOwner: true,
      ));
    }
  }

  Future<void> unlink() async {
    await PushService.unregister();
    DropOffApi.clearCaches();
    final prev = _account;
    _token = null;
    _linkedPhone = null;
    _role = null;
    _photoUrl = null;
    _fullName = null;
    _superadmin = false;
    _bookings.clear();
    _riders.clear();
    _outbox.clear();
    DropOffApi.token = null;
    await _secureStorage.delete(key: _secureTokenKey);
    final preferences = await SharedPreferences.getInstance();
    if (prev != 'anon') {
      for (final name in const ['bookings', 'riders', 'outbox', 'jwt', 'jwt_mirror', 'jwt_legacy_mirror', 'phone', 'email']) {
        await preferences.remove(_scoped(name));
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
    String? branch,
    String? parcelPhotoUrl,
    double? declaredValueZmw,
    bool coverOptIn = false,
    bool coverTosAccepted = false,
    double? pickupLat,
    double? pickupLng,
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
      'courier_id': courierId,
      'recipient_name': recipientName,
      'recipient_phone': recipientPhone,
      'dest_city': toCity,
      'dest_leg2': lastMileFee > 0,
      'description': description,
      'parcels': parcels,
      'vehicle_class': vehicleClass,
      // No cash path — every parcel is prepaid via mobile money at booking,
      // in-line with the worker's prepaid gate (cash is rejected server-side).
      'pay_method': 'mobile_money',
      'weight_class': switch (parcelSize) {
        ParcelSize.small => '0-5kg',
        ParcelSize.medium => '5-15kg',
        ParcelSize.large => '15kg+',
      },
      'service': service ?? 'standard',
      'pickup_window': pickupWindow,
      'pickup_time': pickupWindow,
      if (parcelPhotoUrl != null && parcelPhotoUrl.isNotEmpty) 'parcel_photo_url': parcelPhotoUrl,
      if (declaredValueZmw != null && declaredValueZmw > 0) 'declared_value_zmw': declaredValueZmw,
      if (coverOptIn) 'cover_opt_in': true,
      if (coverOptIn && coverTosAccepted) 'cover_tos_accepted': true,
      if (coverOptIn && coverTosAccepted) 'cover_tos_version': 'v1-cover-quoted',
      if (promoCode != null && promoCode.isNotEmpty) 'promo_code': promoCode.trim().toUpperCase(),
    };
    lastBookingError = null;
    lastBookingErrorDetail = null;
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
    lastBookingPlanInclusion = response.body['plan_inclusion'] as String?;
    lastBookingWindowRolled = response.body['window_rolled_from'] as String?;
    lastBookingDueZmw = (response.body['prompt_total_zmw'] as num?)?.toDouble();
    lastBookingPlanUsed = (response.body['plan_used'] as num?)?.toInt();
    lastBookingPlanCap = (response.body['plan_cap'] as num?)?.toInt();
    lastBookingParcels = (response.body['parcels'] as num?)?.toInt() ?? parcels;

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
      riderId: owner.id,
      roundTrip: roundTrip,
      returnCity: returnCity,
      returnAddress: returnAddress,
      returnLegFee: returnLegFee,
      pickupAt: pickupAt,
      parcels: parcels,
      vehicleClass: vehicleClass,
      branch: branch,
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

  Future<void> advanceBooking(String id) async {
    final index = _bookings.indexWhere((booking) => booking.id == id);
    if (index < 0 || _bookings[index].stage >= _bookings[index].timeline.length - 1) return;
    _bookings[index] = _bookings[index].copyWith(stage: _bookings[index].stage + 1);
    await _saveBookings();
    notifyListeners();
  }

  Future<void> assignRider(String bookingId, String riderId) async {
    final index = _bookings.indexWhere((booking) => booking.id == bookingId);
    if (index < 0) return;
    _bookings[index] = _bookings[index].copyWith(riderId: riderId);
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
        id: 'owner',
        name: 'Owner',
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
      return 'Only the owner and admins can add riders.';
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
          return 'Only the owner and admins can add riders.';
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

  Future<void> _saveBookings() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_bookingsKey, jsonEncode(_bookings.map((item) => item.toJson()).toList()));
  }

  Future<void> _saveRiders() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_ridersKey, jsonEncode(_riders.map((item) => item.toJson()).toList()));
  }
}


