import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import '../services/secure_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/dropoff_api.dart';
import '../data/analytics_service.dart';
import '../data/push_service.dart';
import '../models/booking.dart';

class AppStore extends ChangeNotifier {
  static const _bookingsKey = 'dropoff_bookings_v1';
  static const _ridersKey = 'dropoff_riders_v1';
  static const _tokenKey = 'dropoff_token_v1';
  /// Plain-text mirror of the JWT. Android keystore entries die on screen-lock
  /// changes/fingerprint enrollment — this fallback is why "remember me" works.
  static const _fallbackTokenKey = 'dropoff_token_fallback_v1';
  static const _secureTokenKey = 'dropoff_token';
  static const _phoneKey = 'dropoff_phone_v1';
  static const _emailKey = 'dropoff_email_v1';
  static const _outboxKey = 'dropoff_outbox_v1';
  static const _rememberKey = 'dropoff_remember_v1';
  static const _biometricKey = 'dropoff_biometric_v1';
  static const _deviceKey = 'dropoff_device_id_v1';

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
  bool _superadmin = false;
  bool _biometricEnabled = false;
  String _deviceId = 'unknown';

  /// Keystore/keychain on mobile; SharedPreferences mirror on web.
  final _secureStorage = SecureStore();

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

  /// Server role for the signed-in identity: customer | partner | admin | ops |
  /// rider. Admin/ops unlock the Team tab and the admin console; rider unlocks
  /// a personal rider view (their queue + GPS) via phone-OTP login.
  String? get role => _role;
  bool get isStaff => _role == 'admin' || _role == 'ops';
  bool get isRider => _role == 'rider';
  bool get isTeam => isStaff || isRider;

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
  Future<void> refreshRole() async {
    if (!DropOffApi.enabled) return;
    final me = await DropOffApi.me();
    final next = '${me?['role'] ?? ''}';
    final role = next.isEmpty ? null : next;
    final sa = me?['superadmin'] == true;
    final photo = me?['photo_url'] as String?;
    final name = me?['full_name'] as String?;
    if (role != _role || sa != _superadmin || photo != _photoUrl || name != _fullName) {
      _role = role;
      _superadmin = sa;
      _photoUrl = photo;
      _fullName = name;
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
    final preferences = await SharedPreferences.getInstance();
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

  Future<void> unlink() async {
    await PushService.unregister();
    DropOffApi.clearCaches();
    _token = null;
    _linkedPhone = null;
    _role = null;
    _photoUrl = null;
    _fullName = null;
    _superadmin = false;
    DropOffApi.token = null;
    await _secureStorage.delete(key: _secureTokenKey);
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_tokenKey);
    await preferences.remove(_fallbackTokenKey);
    await preferences.remove(_phoneKey);
    await preferences.remove(_emailKey);
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
  }) async {
    final now = DateTime.now();
    final id = now.microsecondsSinceEpoch.toString();

    // dispatch first (if linked) so the returned booking carries the server ref
    ApiResponse response = const ApiResponse(error: 'offline_demo_mode');
    final jobPayload = <String, dynamic>{
      'idempotency_key': 'job-$id',
      'sender_name': senderName,
      'pickup_address': pickupAddress,
      'from_city': fromCity,
      'courier_id': courierId,
      'recipient_name': recipientName,
      'recipient_phone': recipientPhone,
      'dest_city': toCity,
      'dest_leg2': lastMileFee > 0,
      'description': description,
      'parcels': parcels,
      'vehicle_class': vehicleClass,
      'pay_method': switch (paymentMethod) {
        'Cash at pickup' => 'cash',
        _ => 'mobile_money',
      },
      'weight_class': switch (parcelSize) {
        ParcelSize.small => '0-5kg',
        ParcelSize.medium => '5-15kg',
        ParcelSize.large => '15kg+',
      },
      'service': service ?? 'standard',
      'pickup_window': pickupWindow,
      'pickup_time': pickupWindow,
      if (promoCode != null && promoCode.isNotEmpty) 'promo_code': promoCode.trim().toUpperCase(),
    };
    if (DropOffApi.enabled) {
      response = await DropOffApi.createJob(jobPayload);
      if (!response.ok && response.error == 'network_error') {
        await _enqueueJob(id, jobPayload);
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

  /// Adds a rider to the local roster and mirrors it server-side.
  /// Returns null on full success (or offline demo mode), or an error message
  /// when the server rejected the write (e.g. 403 — caller is not staff), so
  /// the UI can say the rider exists on THIS device only.
  Future<String?> addRider({required String name, required String phone, required String vehicle, String vehicleClass = 'motorcycle'}) async {
    _riders.add(Rider(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: name.trim(),
      phone: phone.trim(),
      vehicle: vehicle,
    ));
    await _saveRiders();
    notifyListeners();
    // Server mirror (pricing class matters for truck/van runs). Plain post
    // carries the ops key (rider device) or the owner JWT.
    if (DropOffApi.enabled) {
      final res = await DropOffApi.post('/admin/riders', {
        'phone': phone.trim(),
        'full_name': name.trim(),
        'vehicle': vehicle,
        'vehicle_class': vehicleClass,
      });
      if (!res.ok) {
        return res.error == 'admin_key_required' || res.error == 'forbidden'
            ? 'Saved on this device only — the server requires a staff account to sync riders.'
            : 'Saved on this device only — server sync failed (${res.error ?? 'network'}).';
      }
    }
    return null;
  }

  Future<void> toggleRider(String id, bool active) async {
    final index = _riders.indexWhere((rider) => rider.id == id);
    if (index < 0 || _riders[index].isOwner) return;
    _riders[index] = _riders[index].copyWith(active: active);
    await _saveRiders();
    notifyListeners();
  }

  Future<void> removeRider(String id) async {
    final rider = _riders.where((item) => item.id == id).firstOrNull;
    if (rider == null || rider.isOwner) return;
    _riders.removeWhere((item) => item.id == id);
    for (var i = 0; i < _bookings.length; i++) {
      if (_bookings[i].riderId == id) {
        _bookings[i] = _bookings[i].copyWith(riderId: owner.id);
      }
    }
    await Future.wait([_saveRiders(), _saveBookings()]);
    notifyListeners();
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


