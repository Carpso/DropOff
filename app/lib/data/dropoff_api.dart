// ─────────────────────────────────────────────────────────────────────
// DROPOFF — ownership stamp (do not remove)
// :Godfrey Moses Kalambo:Carpso Solutions:0968551110.
// © 2026 Godfrey Moses Kalambo · Carpso Solutions · Lusaka, Zambia.
// All rights reserved — unauthorised copying, resale or rebranding of
// this source code is prohibited.
// ─────────────────────────────────────────────────────────────────────
import 'dart:async';
import 'dart:convert';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'photo_stamp.dart';

/// REST client for the DropOff Cloudflare Worker (workers/src/index.ts).
///
/// Configuration overrides (e.g. at build time):
///   flutter run --dart-define=DROPOFF_API_URL=https://dropoff-api.<subdomain>.workers.dev \
///     --dart-define=DROPOFF_API_KEY=... --dart-define=DROPOFF_ADMIN_KEY=... (superadmin console only)
///
/// Defaults point at the live Worker so sign-in/register work out of the box;
/// every call still degrades gracefully if the network is down.
class DropOffApi {
  static const String baseUrl = String.fromEnvironment('DROPOFF_API_URL',
      defaultValue: 'https://api.carpsosolutions.store');
  // Second front door: both hosts serve the SAME Worker. If a device/network
  // blocks one (or it is briefly detached), the app silently uses the other —
  // no "can't reach the DropOff API" dead ends (owner 2026-11-18).
  static const String fallbackBaseUrl =
      'https://dropoff-api.godfreymoseskalambo.workers.dev';
  static String? _activeBaseUrl;
  static String get _currentBase => _activeBaseUrl ?? baseUrl;
  static bool _flipToFallback() {
    final other = _currentBase == baseUrl ? fallbackBaseUrl : baseUrl;
    if (other.isEmpty || other == _currentBase) return false;
    _activeBaseUrl = other;
    return true;
  }
  // Header values must be latin-1: a phone whose manufacturer/model contains
  // non-ASCII characters otherwise makes EVERY http call throw in the client
  // (browser works, app dies) — sanitise at the source.
  static String _asciiHeader(String v) => String.fromCharCodes(
      v.codeUnits.where((c) => c >= 32 && c < 127).take(96));
  // SECURITY: the ops/rider service key must NEVER ship inside a store build.
  // It arrives only via --dart-define at build time on trusted rider/operator
  // devices. Without it, customers sign in with the email/OTP JWT and every
  // call degrades to that identity (server rejects bare ops-key requests).
  static const String apiKey = String.fromEnvironment('DROPOFF_API_KEY');
  static const String adminKey = String.fromEnvironment('DROPOFF_ADMIN_KEY');

  /// Fee model mirror of workers/src/fees.ts — the server is authoritative;
  /// these helpers only render the estimate before the job is created.
  ///
  /// MODEL: the customer pays the base + one processing fee. Driver/rider
  /// earnings are NEVER computed here — they live server-side between DropOff
  /// and the driver.
  static const double platformFeePct = 1.0;
  static const double platformFixedFee = 0.48;
  static const double platformMinFee = 3.0;
  static const double momoCollectionFee = 2.5;

  static double round2(double v) => (v * 100).roundToDouble() / 100;

  /// Platform fee: 1% + K0.48 fixed, minimum K3.48.
  static double platformFee(double amount) =>
      platformMinFee + platformFixedFee > round2(amount * platformFeePct / 100) + platformFixedFee
          ? platformMinFee + platformFixedFee
          : round2(amount * platformFeePct / 100) + platformFixedFee;

  /// Processing-only breakdown shown before the job is created — mirrors
  /// collectionFees() in workers/src/fees.ts (customer-visible fields only;
  /// the server strips rider payout before responses leave the Worker).
  static Map<String, double> collectionFees(double base, {double? riderFee}) {
    if (riderFee == null) return {'base': round2(base), 'prompt_total_zmw': round2(base)};
    final platform = platformFee(base);
    final processing = round2(platform + momoCollectionFee);
    return {
      'base': round2(base),
      'processing_fee_zmw': processing,
      'platform_fee_zmw': platform,
      'lipila_fee_zmw': momoCollectionFee,
      'prompt_total_zmw': round2(base + processing),
    };
  }

  static bool get enabled => baseUrl.isNotEmpty; // API usable with JWT auth alone — the ops key is optional
  static bool get adminEnabled => adminKey.isNotEmpty;
  static bool get opsEnabled => apiKey.isNotEmpty; // rider/ops device flows only

  /// JWT from phone-OTP login; set by the app store after /auth/verify.
  static String? token;

  /// GLOBAL AUTH GUARD (owner audit 2026-11-21): the Worker answers 401 for an
  /// expired/revoked JWT. AppStore installs a handler that tries one refresh,
  /// then clears the session with an honest "sign in again" message. Every
  /// response path below reports 401 here — no more zombie signed-in state or
  /// stale cache served after the token died.
  static Future<void> Function()? onAuthFailure;
  static bool _authHandling = false;

  static void _noteAuthFailure(int status) {
    if (status != 401 || onAuthFailure == null || _authHandling) return;
    _authHandling = true;
    onAuthFailure!().whenComplete(() => _authHandling = false);
  }

  /// Coalesces identical in-flight GETs so parallel screens share one request.
  static final _inFlight = <String, Future<Map<String, dynamic>?>>{};
  /// Network-first memory cache: a response is only reused for this tiny window
  /// (double-taps / rebuilds), otherwise we always re-read the DB. Everything is
  /// persisted separately and served only when the network is unreachable.
  static final _memCache = <String, ({Map<String, dynamic> value, DateTime expiry})>{};
  static const Duration _freshWindow = Duration(seconds: 5);
  static const String _cachePrefix = 'dropoff_api_cache:';

  // 15 s: mobile data is slow, and PBKDF2 login + cold D1 can take several
  // seconds. 6 s produced false "something went wrong" on real phones.
  static const Duration _timeout = Duration(seconds: 15);

  /// AI-heavy endpoints (vision/OCR/chat models) get a much longer budget:
  /// the default 15s kills a cold-start image call and surfaces to users as
  /// a confusing "network_error".
  static const Duration _aiTimeout = Duration(seconds: 180);
  /// Mobile-money collects are slow on Zambian networks — give them room.
  static const Duration _paymentTimeout = Duration(seconds: 20);

  /// Offline cache — successful GETs are persisted so the app stays useful
  /// without a connection (screen falls back to the last good response).
  /// Keyed by the signed-in JWT too, so user B can never read user A's cached
  /// data after a logout / account switch on the same device.
  static String _cacheKey(String path, [Map<String, String>? query]) =>
      'dropoff_api_cache:${(token?.length ?? 0)}:${token?.hashCode ?? 0}:$path?${(query ?? const {}).entries.map((e) => '${e.key}=${e.value}').join('&')}';

  static Future<void> _saveCache(String key, String body) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, body);
    } catch (_) {
      // caching is best-effort
    }
  }

  /// Drop every cached response (memory + disk). Called on logout and after any
  /// successful mutation so the next read always reflects the database.
  static void clearCaches() {
    _inFlight.clear();
    _memCache.clear();
    unawaited(_clearPersistedCaches());
  }

  static Future<void> _clearPersistedCaches([List<String>? roots]) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys().where((k) => k.startsWith(_cachePrefix)).toList();
      for (final key in keys) {
        if (roots == null || roots.any(key.contains)) await prefs.remove(key);
      }
    } catch (_) {
      // caching is best-effort
    }
  }

  /// Persisted cache keys that a mutation can invalidate. Unknown paths clear
  /// everything so a stale value can never survive a write.
  static List<String> _affectedRoots(String path) {
    if (path.startsWith('/jobs') || path.startsWith('/rider')) {
      return ['/jobs', '/wallet', '/route', '/batch', '/ratings', '/refer'];
    }
    if (path.startsWith('/ratings')) return ['/ratings', '/couriers'];
    if (path.startsWith('/tickets') || path.startsWith('/chat/support')) return ['/tickets', '/admin/support'];
    if (path.startsWith('/payments') || path.startsWith('/wallet')) return ['/wallet', '/jobs'];
    if (path.startsWith('/recurring')) return ['/recurring'];
    if (path.startsWith('/subscriptions')) return ['/subscriptions', '/wallet', '/plans'];
    if (path.startsWith('/refer')) return ['/refer', '/jobs'];
    if (path.startsWith('/couriers') || path.startsWith('/quotes') || path.startsWith('/admin')) {
      return ['/couriers', '/quotes', '/plans'];
    }
    if (path.startsWith('/push')) return const [];
    return const ['/jobs', '/wallet', '/route', '/batch', '/ratings', '/couriers', '/quotes', '/recurring', '/refer', '/subscriptions', '/plans'];
  }

  /// Invalidate after a successful write: memory is dropped synchronously so the
  /// next read is live; disk is trimmed in the background.
  static void _invalidateAfterMutation(String path) {
    _inFlight.clear();
    _memCache.clear();
    unawaited(_clearPersistedCaches(_affectedRoots(path)));
  }

  static Future<Map<String, dynamic>?> _readCache(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(key);
      if (raw == null) return null;
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  static Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse('$_currentBase$path').replace(queryParameters: query);

  static String? _deviceId;

  /// The app device id (mirrors AppStore.deviceId). Used in WS handshakes and
  /// when the API client builds non-standard headers.
  static String get deviceId => _deviceId ?? '';

  /// Called by AppStore on init once the stable device id is known.
  static void installDeviceId(String id) => _deviceId = id;

  static String? _deviceName;

  /// Resolves the REAL device label once (manufacturer · model · OS, via
  /// device_info_plus) for the X-Device-Name header — security alerts show
  /// the actual handset instead of a fingerprint hash (owner 2026-11-18).
  static Future<void> resolveDeviceName() async {
    if (_deviceName != null) return;
    try {
      final info = await DeviceInfoPlugin().deviceInfo;
      if (info is AndroidDeviceInfo) {
        _deviceName = '${info.manufacturer} ${info.model} · Android ${info.version.release}';
      } else if (info is IosDeviceInfo) {
        _deviceName = 'iPhone · iOS ${info.systemVersion}';
      } else {
        _deviceName = 'DropOff device';
      }
    } catch (_) {
      _deviceName = 'DropOff device';
    }
  }

  static Map<String, String> get _headers => {
      'Content-Type': 'application/json',
      if (apiKey.isNotEmpty) 'X-Api-Key': _asciiHeader(apiKey),
      if (token != null) 'Authorization': 'Bearer $token',
      if (_deviceId != null && _deviceId!.isNotEmpty) 'X-Device-Id': _asciiHeader(_deviceId!),
      if (_deviceName != null && _deviceName!.isNotEmpty) 'X-Device-Name': _asciiHeader(_deviceName!),
    };

  static Map<String, String> get _adminHeaders => {
        ..._headers,
        if (adminKey.isNotEmpty) 'X-Admin-Key': adminKey,
      };

  /// Ops API headers (server-side role='ops'): used for ops endpoints without a linked phone.
  static Map<String, String> get _opsHeaders => {
        'Content-Type': 'application/json',
        'X-Api-Key': apiKey,
      };

  /// GET helper; returns null on failure — first tries the cache-less live call,
  /// then falls back to the last cached copy (offline).
  /// GET helper — network-first: always asks the Worker (coalescing identical
  /// in-flight calls) so data matches the DB; the persisted copy is a fallback
  /// only when the request fails (offline / poor signal).
  static Future<Map<String, dynamic>?> get(String path, [Map<String, String>? query]) async {
    if (!enabled) return null;
    final cacheKey = _cacheKey(path, query);

    // 1) in-flight coalescing: identical GETs hitting at the same time share one request
    if (_inFlight.containsKey(cacheKey)) return _inFlight[cacheKey]!;

    // 2) tiny freshness window only — avoids re-fetching on back-to-back rebuilds
    final mem = _memCache[cacheKey];
    if (mem != null && mem.expiry.isAfter(DateTime.now())) return mem.value;

    final flight = _fetchGet(path, query, cacheKey);
    _inFlight[cacheKey] = flight;
    try { return await flight; } finally { _inFlight.remove(cacheKey); }
  }

  static Future<Map<String, dynamic>?> _fetchGet(
    String path, Map<String, String>? query, String cacheKey,
  ) async {
    try {
      final res = await http.get(_uri(path, query), headers: _headers).timeout(_timeout);
      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body) as Map<String, dynamic>;
        unawaited(_saveCache(cacheKey, res.body));
        _memCache[cacheKey] = (value: decoded, expiry: DateTime.now().add(_freshWindow));
        return decoded;
      }
      // A dead session must NEVER be masked by a cached response.
      if (res.statusCode == 401) {
        _noteAuthFailure(res.statusCode);
        return null;
      }
      return _readCache(cacheKey);
    } catch (_) {
      // Other host, one attempt — then fall back to the on-device cache.
      if (_flipToFallback()) {
        try {
          final res2 = await http.get(_uri(path, query), headers: _headers).timeout(_timeout);
          if (res2.statusCode == 200) {
            final decoded2 = jsonDecode(res2.body) as Map<String, dynamic>;
            unawaited(_saveCache(cacheKey, res2.body));
            _memCache[cacheKey] = (value: decoded2, expiry: DateTime.now().add(_freshWindow));
            return decoded2;
          }
          if (res2.statusCode == 401) {
            _noteAuthFailure(res2.statusCode);
            return null;
          }
        } catch (_) {}
      }
      final mem = _memCache[cacheKey];
      if (mem != null) return mem.value;
      return _readCache(cacheKey);
    }
  }

  static Future<ApiResponse> delete(
    String path, {
    Map<String, dynamic>? body,
    Duration? timeout,
    bool admin = false,
  }) async {
    if (!enabled) return const ApiResponse(error: 'offline_demo_mode');
    try {
      final res = await http
          .delete(_uri(path), headers: admin ? _adminHeaders : _headers, body: jsonEncode(body ?? const {}))
          .timeout(timeout ?? _timeout);
      Map<String, dynamic>? decoded;
      try {
        decoded = jsonDecode(res.body) as Map<String, dynamic>?;
      } catch (_) {
        return ApiResponse(status: res.statusCode, ok: false, body: const {}, error: 'http_${res.statusCode}');
      }
      decoded ??= const {};
      _noteAuthFailure(res.statusCode);
      final ok = res.statusCode >= 200 && res.statusCode < 300;
      if (ok) _invalidateAfterMutation(path);
      return ApiResponse(
        status: res.statusCode,
        ok: ok,
        body: decoded,
        error: res.statusCode >= 400 ? '${decoded['error'] ?? 'http_${res.statusCode}'}' : null,
      );
    } catch (_) {
      return const ApiResponse(error: 'network_error');
    }
  }

  static Future<ApiResponse> post(
    String path,
    Map<String, dynamic> body, {
    bool admin = false,
    Duration? timeout,
    Map<String, String>? extraHeaders,
    int retries = 0,
  }) async {
    ApiResponse res = const ApiResponse(error: 'network_error');
    final attempts = 1 + retries;
    for (var attempt = 0; attempt < attempts; attempt++) {
      if (attempt > 0) await Future.delayed(const Duration(seconds: 2));
      res = await _postOnce(path, body, admin: admin, timeout: timeout, extraHeaders: extraHeaders);
      // Only transport-level failures retry — an HTTP error answer from the
      // server is a definite outcome, never a silent re-fire.
      if (res.error != 'network_error') return res;
    }
    // Secondary front door: if every attempt died at the transport layer,
    // try the SAME request on the other host and stay there for the session.
    if (res.error == 'network_error' && _flipToFallback()) {
      res = await _postOnce(path, body, admin: admin, timeout: timeout, extraHeaders: extraHeaders);
    }
    return res;
  }

  static Future<ApiResponse> _postOnce(
    String path,
    Map<String, dynamic> body, {
    bool admin = false,
    Duration? timeout,
    Map<String, String>? extraHeaders,
  }) async {
    if (!enabled) return const ApiResponse(error: 'offline_demo_mode');
    try {
      final res = await http
          .post(_uri(path),
              headers: {...(admin ? _adminHeaders : _headers), ...?extraHeaders},
              body: jsonEncode(body))
          .timeout(timeout ?? _timeout);
      // A 5xx from the Worker (or a non-JSON edge page) must NOT masquerade as
      // "network error" — clients can only render a truthful message when the
      // status is preserved.
      Map<String, dynamic>? decoded;
      try {
        decoded = jsonDecode(res.body) as Map<String, dynamic>?;
      } catch (_) {
        return ApiResponse(status: res.statusCode, ok: false, body: const {}, error: 'http_${res.statusCode}');
      }
      decoded ??= const {};
      _noteAuthFailure(res.statusCode);
      final ok = res.statusCode >= 200 && res.statusCode < 300;
      if (ok) _invalidateAfterMutation(path);
      return ApiResponse(
        status: res.statusCode,
        ok: ok,
        body: decoded,
        error: res.statusCode >= 400 ? '${decoded['error'] ?? 'http_${res.statusCode}'}' : null,
      );
    } catch (_) {
      return const ApiResponse(error: 'network_error');
    }
  }

  /// GET helper (admin). Calls /admin/* with the best available credentials:
  /// the widest admin key when the build was compiled with DROPOFF_ADMIN_KEY,
  /// otherwise the signed-in JWT (server-side isAdmin decides). Store builds
  /// without the admin key still work for admins via their normal account.
  static Future<Map<String, dynamic>?> getAdmin(String path, [Map<String, String>? query]) async {
    if (!enabled) return null;
    if (adminEnabled) {
      try {
        final res = await http.get(_uri(path, query), headers: _adminHeaders).timeout(_timeout);
        if (res.statusCode != 200) return null;
        return jsonDecode(res.body) as Map<String, dynamic>;
      } catch (_) {
        return null;
      }
    }
    try {
      final res = await http.get(_uri(path, query), headers: _headers).timeout(_timeout);
      if (res.statusCode != 200) return null;
      return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// Rider's full-screen order card: pickup coordinates + every detail, even
  /// on a cold start when the push payload was lost.
  static Future<Map<String, dynamic>?> jobOffer(String ref) =>
      get('/jobs/${Uri.encodeComponent(ref)}/offer');

  /// Best-effort promo lookup for the booking form (public today, advisory only).
  static Future<Map<String, dynamic>?> checkPromo(String code) =>
      get('/promo/check', {'code': code.trim().toUpperCase()});

  /// Batch sweep: scattered pickup points grouped into snake-latbands routes.
  static Future<Map<String, dynamic>?> batchPickup({String? date, int maxStops = 25}) async {
    if (!enabled) return null;
    try {
      final query = <String, String>{'max_stops': '$maxStops', if (date != null) 'date': date};
      final res = await http
          .get(Uri.parse('$baseUrl/batch/pickup').replace(queryParameters: query), headers: _opsHeaders)
          .timeout(_timeout);
      if (res.statusCode != 200) return null;
      return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// Server-generated referral code + personal funnel stats.
  static Future<Map<String, dynamic>?> referralCode() => get('/refer/code');

  /// Claim a referrer's code at sign-up (silent no-op server-side if already tracked).
  static Future<ApiResponse> claimReferral(String code) =>
      post('/refer/claim', {'code': code.trim().toUpperCase()});

  /// Today's pickup route in smart order (nearest-neighbor from the depot hub).
  static Future<Map<String, dynamic>?> routePickup({String? phone}) async {
    if (!enabled) return null;
    try {
      final res = await http
          .get(Uri.parse('$baseUrl/route/pickup${phone != null ? '?phone=${Uri.encodeComponent(phone)}' : ''}'), headers: _opsHeaders)
          .timeout(_timeout);
      if (res.statusCode != 200) return null;
      return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// Share the rider's current GPS fix for dispatch + live tracking. `status`
  /// optionally flips the rider's availability flag (available|on_route).
  static Future<ApiResponse> riderPing({
    required String phone,
    required double lat,
    required double lng,
    String? status,
    double? accuracy,
    DateTime? capturedAt,
  }) async {
    if (!enabled) return const ApiResponse(error: 'offline_demo_mode');
    try {
      final res = await http
          .post(Uri.parse('$baseUrl/rider/ping'), headers: _headers,
              body: jsonEncode({
                'phone': phone, 'lat': lat, 'lng': lng,
                if (status != null) 'status': status,
                if (accuracy != null) 'accuracy': accuracy,
                if (capturedAt != null) 'captured_at': capturedAt.toIso8601String(),
              }))
          .timeout(_timeout);
      return ApiResponse(status: res.statusCode, ok: res.statusCode < 300, body: const {});
    } catch (e) {
      return const ApiResponse(error: 'network_error');
    }
  }

  /// Where is my rider? Used by senders/recipients to open the map live.
  static Future<Map<String, dynamic>?> liveLocation(String jobRef) async {
    if (!enabled) return null;
    try {
      final res = await http.get(Uri.parse('$baseUrl/jobs/$jobRef/live'), headers: _headers).timeout(_timeout);
      if (res.statusCode != 200) return null;
      return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// Look up a single job by server ref (DRO-...). Used by the admin console
  /// search so staff can find any order by its tracking/reference number.
  static Future<Map<String, dynamic>?> job(String ref) async {
    if (!enabled) return null;
    try {
      final res = await http.get(Uri.parse('$baseUrl/jobs/${Uri.encodeComponent(ref)}'), headers: _headers).timeout(_timeout);
      if (res.statusCode != 200) return null;
      return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// Standing orders — recurring parcel plans (weekly/biweekly/monthly).
  static Future<List<Map<String, dynamic>>> recurring() async {
    final data = await get('/recurring');
    return (data?['recurring'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
  }

  static Future<ApiResponse> createRecurring(Map<String, dynamic> plan) =>
      post('/recurring', Map<String, dynamic>.from(plan));

  static Future<ApiResponse> toggleRecurring(int id) => post('/recurring/$id/toggle', const {});

  static Future<ApiResponse> deleteRecurring(int id) => post('/recurring/$id/delete', const {});

  /// Active couriers + partner profiles — falls back to the built-in catalog.

  static Future<List<Map<String, dynamic>>> couriers() async {
    final data = await get('/couriers');
    return (data?['couriers'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
  }

  /// Public courier partner profile (verified rates from the chargebook).
  static Future<Map<String, dynamic>?> courierProfile(int id) => get('/couriers/$id/profile');

  /// Cities the chargebook/partner depots serve — falls back to an empty list
  /// (the app then uses its built-in Zambian towns).
  static Future<List<String>> cities() async {
    final data = await get('/cities');
    return (data?['cities'] as List?)?.cast<String>() ?? const [];
  }

  /// Server-side quotes: verified counter price + rider fee (+ leg-2) for a route.
  static Future<List<Map<String, dynamic>>> quotes({
    required String from,
    required String to,
    String service = 'standard',
  }) async {
    final data = await get('/quotes', {'from': from, 'to': to, 'service': service});
    return (data?['quotes'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
  }

  /// Phone-OTP login. `verify` returns/stores the JWT.
  static Future<ApiResponse> requestOtp(String phone) =>
      // One silent retry rides out a dropped connection mid-tap — the
      // handset either reaches workers.dev this time or the honest
      // network_error is shown instead.
      post('/auth/request', {'phone': phone}, retries: 1);

  /// Server-backed address book (owner 2026-11-18).
  static Future<Map<String, dynamic>?> savedPlaces() => get('/places');
  static Future<ApiResponse> rememberPlace(String label, {double? lat, double? lng}) =>
      post('/places', {'label': label, 'lat': lat, 'lng': lng, 'source': 'app'});

  static Future<ApiResponse> verifyOtp(String phone, String code) async {
    final res = await post('/auth/verify', {'phone': phone, 'code': code});
    if (res.ok && res.body['token'] != null) token = res.body['token'] as String?;
    return res;
  }

  /// Email + password account. `password` >= 8 chars; `phone` is the momo
  /// identity (260XXXXXXXXX). Both `register` and `login` return/store the JWT.
  static Future<ApiResponse> registerEmail({
    required String email,
    required String password,
    required String phone,
    String? fullName,
  }) async {
    final res = await post('/auth/register', {
      'email': email,
      'password': password,
      'phone': phone,
      if (fullName != null && fullName.isNotEmpty) 'full_name': fullName,
    });
    if (res.ok) token = res.body['token'] as String?;
    return res;
  }

  static Future<ApiResponse> loginEmail(String email, String password) async {
    final res = await post('/auth/login', {'email': email, 'password': password});
    if (res.ok && res.body['token'] != null) token = res.body['token'] as String?;
    return res;
  }

  /// Password reset + email verification (links go out by email; when the app
  /// was built without email configured the response contains a dev link).
  static Future<ApiResponse> forgotPassword(String email) =>
      post('/auth/forgot', {'email': email});

  static Future<ApiResponse> resendVerification(String email) =>
      post('/auth/resend-verification', {'email': email});

  /// Create a job. Pricing is computed server-side; `pickupWindow` is one of
  /// 'now', '06:00', '10:00', '14:00'; `payMethod` = mobile_money | cash.
  static Future<ApiResponse> createJob(Map<String, dynamic> job) => post('/jobs', job);

  /// Rider log: minutes waited (sender not ready / depot queue). Server bills
  /// first 10 min free, K2/min after, K50 cap, and returns the updated totals.
  static Future<ApiResponse> logWait({
    required String jobRef,
    required int minutes,
    String? note,
    double? lat,
    double? lng,
  }) =>
      post('/jobs/$jobRef/events', {
        'wait_minutes': minutes,
        if (note != null) 'note': note,
        if (lat != null) 'lat': lat,
        if (lng != null) 'lng': lng,
      });

  /// Rider log: status movement for a job. Deliveries are marked by CAMERA
  /// CAPTURE — the server rejects a rider 'delivered' event without a proof
  /// photo (depot drop or door alike). For door deliveries the server also
  /// REQUIRES [otp] — the recipient's 4-digit DropOff code. [stage]
  /// ('pickup' | 'delivery') files the proof photo against the right leg.
  /// Depot counter flow (owner directive 2026-11-12): riders TRANSCRIBE the
  /// exact amount written on the depot receipt (never quote a fare) and file
  /// two photos — the parcel and the depot receipt. The sender pays that
  /// amount + processing through DropOff; the rider is reimbursed fee-free.
  static Future<ApiResponse> jobEvent({
    required String jobRef,
    String? status,
    String? note,
    String? waybill,
    String? photoUrl,
    String? stage,
    String? otp,
    String? receiptUrl,
    double? receiptAmountZmw,
    List<Map<String, dynamic>>? receipts,
    List<String>? parcelPhotos,
    double? lat,
    double? lng,
    String? branch,
    bool? receiptAmountConfirmed,
  }) =>
      post('/jobs/$jobRef/events', {
        if (status != null) 'status': status,
        if (note != null) 'note': note,
        if (waybill != null) 'waybill': waybill,
        if (photoUrl != null) 'photo_url': photoUrl,
        if (stage != null) 'stage': stage,
        if (otp != null) 'otp': otp,
        if (receiptUrl != null) 'receipt_url': receiptUrl,
        if (receiptAmountZmw != null) 'receipt_amount_zmw': receiptAmountZmw,
        if (receipts != null) 'receipts': receipts,
        if (parcelPhotos != null) 'parcel_photos': parcelPhotos,
        if (lat != null) 'lat': lat,
        if (lng != null) 'lng': lng,
        if (branch != null) 'branch': branch,
        if (receiptAmountConfirmed != null) 'receipt_amount_confirmed': receiptAmountConfirmed,
      });

  /// Verify-only PIN check. Ticks the UI only when the code really matches.
  /// No job step is advanced; the final jobEvent still verifies server-side.
  /// `kind` is 'pickup' (sender code) or 'door' (recipient code / door PIN).
  static Future<ApiResponse> verifyPin(String jobRef, String otp, String kind) =>
      post(
        '/jobs/${Uri.encodeComponent(jobRef)}/verify-pin',
        {'otp': otp, 'kind': kind},
        retries: 1,
        timeout: const Duration(seconds: 12),
      );

  /// AI parcel photo check: compares the sender's booking capture against the
  /// rider's depot/delivery photo. Returns {same_parcel, confidence, note, flagged}.
  /// 409 when either photo is missing — treat as "no check available", not an error.
  static Future<ApiResponse> parcelCheck(String ref) =>
      post('/jobs/$ref/parcel-check', const {}, timeout: _aiTimeout);

  static Future<Map<String, dynamic>?> jobEvidence(String ref) => get('/jobs/$ref/evidence');
  static Future<Map<String, dynamic>?> slotsSuggest({String? fromCity}) =>
      get('/slots/suggest', {if (fromCity != null && fromCity.isNotEmpty) 'from_city': fromCity});
  static Future<List<Map<String, dynamic>>> recipients() async {
    final data = await get('/recipients');
    return ((data?['recipients'] as List?) ?? const []).cast<Map<String, dynamic>>();
  }
  static Future<ApiResponse> saveRecipient(Map<String, dynamic> r) => post('/recipients', r);
  static Future<ApiResponse> deleteRecipient(int id) => delete('/recipients/$id');

  /// Community POI layer (growing map): shared, named pins.
  static Future<List<Map<String, dynamic>>> communityPois(String city) async {
    final data = await get('/pois', {'city': city});
    return ((data?['pois'] as List?) ?? const []).cast<Map<String, dynamic>>();
  }
  static Future<ApiResponse> saveCommunityPoi({required String name, required String city, required double lat, required double lng}) =>
      post('/pois', {'name': name, 'city': city, 'lat': lat, 'lng': lng});
  static Future<ApiResponse> upvoteCommunityPoi(int id) => post('/pois/$id/upvote', const {});
  static Future<ApiResponse> patchMe(Map<String, dynamic> body) => _patchJson('/me', body);

  static Future<ApiResponse> _patchJson(String path, Map<String, dynamic> body) async {
    if (!enabled) return const ApiResponse(error: 'offline_demo_mode');
    try {
      final headers = <String, String>{'Content-Type': 'application/json', ...authHeaders};
      final res = await http.patch(_uri(path), headers: headers, body: jsonEncode(body)).timeout(const Duration(seconds: 20));
      Map<String, dynamic> data;
      try {
        data = res.body.isEmpty ? <String, dynamic>{} : (jsonDecode(res.body) as Map<String, dynamic>? ?? {});
      } catch (_) {
        return ApiResponse(status: res.statusCode, ok: false, body: const {}, error: 'http_${res.statusCode}');
      }
      _noteAuthFailure(res.statusCode);
      return ApiResponse(status: res.statusCode, ok: res.statusCode >= 200 && res.statusCode < 300, body: data,
          error: res.statusCode >= 400 ? '${data['error'] ?? 'http_${res.statusCode}'}' : null);
    } catch (_) {
      return const ApiResponse(error: 'network_error');
    }
  }

  /// Rate one side of a delivery — sender, driver (rider) or courier — with an
  /// optional comment. Resubmitting updates the previous score.
  static Future<ApiResponse> rateJob({
    required String jobRef,
    required String targetType,
    required int stars,
    String? comment,
  }) async {
    final res = await post('/jobs/$jobRef/rate', {
      'target_type': targetType,
      'stars': stars,
      if (comment != null && comment.trim().isNotEmpty) 'comment': comment.trim(),
    });
    if (!res.ok && res.error == 'network_error' && !_flushingRatings) {
      await _queueRating({
        'job_ref': jobRef,
        'target_type': targetType,
        'stars': stars,
        if (comment != null && comment.trim().isNotEmpty) 'comment': comment.trim(),
      });
    }
    return res;
  }

  static const _ratingOutboxKey = 'dropoff_rating_outbox_v1';
  static bool _flushingRatings = false;

  /// Sign-out: discard any queued offline ratings. They were queued by the
  /// previous account; the next signed-in user must not inherit them (they
  /// would flush under a DIFFERENT session for a job they may not own).
  static Future<void> clearRatingOutbox() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_ratingOutboxKey);
    } catch (_) {
      /* best-effort */
    }
  }

  static Future<void> _queueRating(Map<String, dynamic> item) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getString(_ratingOutboxKey) == null
        ? <Map<String, dynamic>>[]
        : (jsonDecode(prefs.getString(_ratingOutboxKey)!) as List)
            .cast<Map<String, dynamic>>();
    list.removeWhere((e) => e['job_ref'] == item['job_ref'] && e['target_type'] == item['target_type']);
    list.add(item);
    await prefs.setString(_ratingOutboxKey, jsonEncode(list));
  }

  /// Retry ratings left while offline. Called from the app store's outbox flush.
  static Future<void> flushRatingOutbox() async {
    if (!enabled || _flushingRatings) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_ratingOutboxKey);
    if (raw == null) return;
    final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    if (list.isEmpty) return;
    _flushingRatings = true;
    final remaining = <Map<String, dynamic>>[];
    try {
      for (final item in list) {
        final res = await post('/jobs/${item['job_ref']}/rate', {
          'target_type': item['target_type'],
          'stars': item['stars'],
          if (item['comment'] != null) 'comment': item['comment'],
        });
        if (!res.ok && res.error == 'network_error') remaining.add(item);
      }
    } finally {
      _flushingRatings = false;
    }
    if (remaining.isEmpty) {
      await prefs.remove(_ratingOutboxKey);
    } else {
      await prefs.setString(_ratingOutboxKey, jsonEncode(remaining));
    }
  }

  /// Ratings already left on a job plus aggregate scores for each target.
  static Future<Map<String, dynamic>?> jobRatings(String jobRef) =>
      get('/jobs/$jobRef/ratings');

  /// Get (or mint) the recipient-facing status/live-location link.
  static Future<Map<String, dynamic>?> trackingLink(String jobRef) async {
    final res = await post('/jobs/$jobRef/tracking-link', {});
    return res.ok ? res.body : null;
  }

  /// POST /auth/refresh — renew the stored JWT while the server still vouches
  /// for it (grace window). Result: {renewed, token} when renewed;
  /// {dead: true} when the token is permanently rejected; { } otherwise
  /// (transient failure - the caller keeps the session).
  static Future<Map<String, dynamic>> refreshSession() async {
    if (!enabled || token == null) return const {'renewed': false, 'dead': false};
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/auth/refresh'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
      ).timeout(_timeout);
      if (res.statusCode == 200) {
        final j = jsonDecode(res.body) as Map<String, dynamic>?;
        final t = j?['token'] as String?;
        return {'renewed': t != null, 'token': t, 'dead': false};
      }
      if (res.statusCode == 401 || res.statusCode == 403) {
        return const {'renewed': false, 'dead': true};
      }
      return const {'renewed': false, 'dead': false};
    } catch (_) {
      return const {'renewed': false, 'dead': false};
    }
  }

  // ---- recipient tracking (verification-gated) ----
  // The shared link alone never opens the parcel: the Worker answers with
  // ACCOUNTS REQUIRED (owner directive): a parcel can only be tracked by a
  // signed-in account whose phone is the sender's or recipient's — the link
  // proves nothing by itself. Signed-in users pass via their JWT (in
  // _headers); everyone else gets requires_account + a last-4 hint. There is
  // deliberately NO phone-OTP / anonymous grant path.

  static String _trackTokenOf(String input) {
    final raw = input.replaceAll(RegExp(r'\s+'), '');
    final m = RegExp(r'(?:track|t)/([A-Za-z0-9_-]{8,})').firstMatch(raw) ??
        RegExp(r'[?&](?:token|code)=([A-Za-z0-9_-]{8,})').firstMatch(raw);
    if (m != null) return m.group(1)!.toLowerCase();
    return raw.toLowerCase();
  }

  /// Tracking lookup with a REAL error code, so a dead connection is never
  /// reported as "wrong code" (owner 2026-11-23).
  static Future<ApiResponse> trackLookup(String input) async {
    if (!enabled) return const ApiResponse(error: 'offline_demo_mode');
    final token = _trackTokenOf(input);
    if (token.length < 8) return const ApiResponse(error: 'invalid_tracking_code');
    try {
      final res = await http.get(_uri('/track/$token'), headers: _headers).timeout(_timeout);
      Map<String, dynamic>? decoded;
      try { decoded = jsonDecode(res.body) as Map<String, dynamic>; } catch (_) {}
      if (res.statusCode >= 200 && res.statusCode < 300) {
        return ApiResponse(status: res.statusCode, ok: true, body: decoded ?? const {});
      }
      return ApiResponse(
        status: res.statusCode,
        ok: false,
        body: decoded ?? const {},
        error: decoded?['error']?.toString() ?? 'http_${res.statusCode}',
      );
    } catch (_) {
      return const ApiResponse(error: 'network_error');
    }
  }

  /// Live (never cached) tracking fetch — the gate response must not be
  /// served from a stale snapshot. Signed-in viewers pass via JWT.
  static Future<Map<String, dynamic>?> _trackGet(String path, String token) async {
    if (!enabled) return null;
    try {
      final res = await http
          .get(_uri(path), headers: _headers)
          .timeout(_timeout);
      if (res.statusCode >= 200 && res.statusCode < 300) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Track by SMS link or bare token. Callers must treat `requires_account`
  /// as "show the account gate". Signed-in participant phones pass via JWT.
  static Future<Map<String, dynamic>?> trackByToken(String input) {
    final token = _trackTokenOf(input);
    return _trackGet('/track/$token', token);
  }

  // ---- chat (job thread / recipient-token thread / support thread) ----

  static Future<Map<String, dynamic>?> jobChat(String jobRef) => get('/jobs/$jobRef/chat');

  static Future<ApiResponse> sendJobChat(String jobRef, String body) =>
      post('/jobs/$jobRef/chat', {'body': body});

  static Future<Map<String, dynamic>?> trackChat(String tokenOrUrl) {
    final token = _trackTokenOf(tokenOrUrl);
    return _trackGet('/track/$token/chat', token);
  }

  static Future<ApiResponse> sendTrackChat(String tokenOrUrl, String body) {
    final token = _trackTokenOf(tokenOrUrl);
    return post('/track/$token/chat', {'body': body});
  }

  /// Open (or create) the support thread; a non-empty [body] is sent as the
  /// first/reply message. Returns the thread with all messages.
  static Future<Map<String, dynamic>?> supportChat({String? body}) =>
      post('/chat/support', {if (body != null && body.trim().isNotEmpty) 'body': body.trim()})
          .then((res) => res.ok ? res.body : null);

  /// Same as [supportChat] but the caller keeps the raw [ApiResponse] so
  /// moderation failures (message_blocked / chat_suspended) are visible.
  static Future<ApiResponse> supportChatSend(String body) =>
      post('/chat/support', {'body': body});

  static Future<Map<String, dynamic>?> chatThreads() => get('/chat/threads');

  // ---- support tickets (parcel chat is gone; support lives here) ------------

  /// All tickets opened by the signed-in phone, newest activity first.
  static Future<Map<String, dynamic>?> tickets() => get('/tickets');

  static Future<ApiResponse> createTicket({
    required String subject,
    required String category,
    required String body,
  }) => post('/tickets', {'subject': subject, 'category': category, 'body': body});

  /// Ticket detail + its message thread.
  static Future<Map<String, dynamic>?> ticket(int id) => get('/tickets/$id');

  static Future<ApiResponse> ticketReply(int id, String body) =>
      post('/tickets/$id/reply', {'body': body});

  /// Customer close / reopen. [status] = open | pending | closed.
  static Future<ApiResponse> ticketStatus(int id, String status) =>
      post('/tickets/$id/status', {'status': status});

  static Future<ApiResponse> adminTicketStatus(int id, String status) =>
      post('/admin/support/threads/$id/status', {'status': status}, admin: true);

  /* ---------------------- chat moderation (UGC safety) ---------------------- */

  /// Report an abusive chat message. [reason] is harassment | spam | other;
  /// [note] is the optional free-text detail. Frequency-capped server-side.
  static Future<ApiResponse> reportChatMessage(int messageId, String reason, {String? note}) =>
      post('/chat/messages/$messageId/report', {'reason': reason, 'note': note ?? ''});

  /// People I have blocked — their chat messages disappear from my views only.
  static Future<List<String>> blockedUsers() async {
    final data = await get('/users/blocks');
    return ((data?['blocks'] as List?) ?? const [])
        .map((r) => '${(r as Map<String, dynamic>)['blocked'] ?? ''}')
        .where((p) => p.isNotEmpty)
        .toList();
  }

  static Future<ApiResponse> blockUser(String phone) =>
      post('/users/blocks', {'phone': phone});

  static Future<ApiResponse> unblockUser(String phone) =>
      delete('/users/blocks/${Uri.encodeComponent(phone)}');

  /// Recipient's auto-claimed parcels: every live parcel addressed to the
  /// signed-in caller's phone, newest first, each with a ready tracking URL.
  static Future<Map<String, dynamic>?> trackIncoming() =>
      enabled ? get('/track/incoming') : Future<Map<String, dynamic>?>.value(null);

  // ---- DropOff Predict -------------------------------------------------------

  /// The seller's next-30-day forecast: expected parcels, peak window/weekday,
  /// trend, and the cheapest plan that covers the forecast (with est. savings).
  static Future<Map<String, dynamic>?> predictSeller() =>
      enabled ? get('/predict/seller') : Future<Map<String, dynamic>?>.value(null);

  /// Ops heatmap: predicted parcels for the next 7 days per depot branch and
  /// pickup window (same weekday+window average of the trailing 8 weeks).
  static Future<Map<String, dynamic>?> adminDemandForecast() => getAdmin('/admin/demand-forecast');

  // ---- staff console: support inbox + user roles ----

  /// Admin/ops view of every support ticket ({threads: [{id, phone, last_message, unread, ...}]}).
  /// Sent with admin headers too: an admin-key-only console device works without a JWT.
  static Future<Map<String, dynamic>?> adminSupportThreads() => getAdmin('/admin/support/threads');
  static Future<Map<String, dynamic>?> adminDeletionRequests() =>
      getAdmin('/admin/support/threads/deletion-requests');

  /// One support ticket with all messages.
  static Future<Map<String, dynamic>?> adminSupportThread(int threadId) =>
      getAdmin('/admin/support/threads/$threadId');

  /// Admin/ops reply into a support ticket (same endpoint senders use).
  static Future<ApiResponse> supportReply(int threadId, String body) =>
      post('/chat/support/$threadId/reply', {'body': body}, admin: true);

  /// Refund / settlement payout ledger (guarded retry engine).
  static Future<Map<String, dynamic>?> adminPayouts() => getAdmin('/admin/payouts');

  static Future<Map<String, dynamic>?> adminMoneyOps() => getAdmin('/admin/money-ops');

  static Future<Map<String, dynamic>?> adminSettings() => getAdmin('/admin/settings');
  static Future<ApiResponse> adminSetSetting(String key, bool enabled) =>
      post('/admin/settings', {'key': key, 'enabled': enabled}, admin: true);

  static String _adminIdempotencyKey(String action) => '$action-${DateTime.now().microsecondsSinceEpoch}';

  static Future<ApiResponse> confirmPayout(int id) =>
      post('/admin/payouts/$id/confirm', {'idempotency_key': _adminIdempotencyKey('confirm-$id')});

  static Future<ApiResponse> payPayoutNow(int id) =>
      post('/admin/payouts/$id/pay-now', {'idempotency_key': _adminIdempotencyKey('paynow-$id')});

  static Future<ApiResponse> retryPayout(int id) =>
      post('/admin/payouts/$id/retry', {'idempotency_key': _adminIdempotencyKey('retry-$id')}, admin: true);

  static Future<Map<String, dynamic>?> adminRecurring({String? phone}) =>
      getAdmin('/admin/recurring', {if (phone != null && phone.trim().isNotEmpty) 'phone': phone.trim()});

  static Future<Map<String, dynamic>?> adminRiderRoster({String? date}) =>
      getAdmin('/admin/riders/roster', {if (date != null && date.trim().isNotEmpty) 'date': date.trim()});

  static Future<ApiResponse> adminCancelRecurring(int id) =>
      post('/recurring/$id/delete', const {}, admin: true);

  /// Staff escape hatch (owner bug 2026-11-23): settle a stuck depot counter
  /// fare with an audit reason so the sender can book again. No money moves.
  static Future<Map<String, dynamic>?> adminCounterFares() => getAdmin('/admin/counter-fares');

  static Future<ApiResponse> adminWaiveCounterFare(String ref, String reason) =>
      post('/admin/jobs/${Uri.encodeComponent(ref)}/waive-counter-fare', {'reason': reason, 'idempotency_key': _adminIdempotencyKey('waive-$ref')}, admin: true);

  /// Re-fire a stuck depot counter-fare momo prompt from the real sender phone.
  /// Returns the provider's raw answer on failure so staff can act on it.
  static Future<ApiResponse> adminSendCounterFarePrompt(String ref, String reason) =>
      post('/admin/jobs/${Uri.encodeComponent(ref)}/counter-fare-prompt', {'reason': reason, 'idempotency_key': _adminIdempotencyKey('prompt-$ref')}, admin: true);

  /// Clear all auto-created/unpaid jobs (status='created' AND paid=0). Admin-only;
  /// used to clear test/demo leftovers so the app launches clean for senders.
  static Future<ApiResponse> adminClearAutoCreated(String reason) =>
      post('/admin/jobs/clear-auto-created', {'reason': reason}, admin: true);

  /// Close a parcel chat: read-only history preserved for everyone.
  static Future<ApiResponse> closeChatThread(int threadId) =>
      post('/chat/threads/$threadId/close', const {});

  /// Pause (true) or resume (false) DropOff's payment reminders for this
  /// booking. USSD pushes already on the handset can't be recalled — this
  /// only stops anything new going out. Sender of the job or staff.
  static Future<ApiResponse> jobPauseReprompt(String jobRef, {bool paused = true}) =>
      post('/jobs/$jobRef/payment/pause-reprompt', {'paused': paused});

  /// Partner joins a job's parcel chat (their courier must be linked).
  static Future<ApiResponse> jobChatJoin(String jobRef) =>
      post('/jobs/$jobRef/chat/join', const {});

  /// Partner-only door probe: {'state': 'joined' | 'join_required'} or null
  /// when the thread is not for this depot (404).
  static Future<Map<String, dynamic>?> jobChatJoinStatus(String jobRef) =>
      get('/jobs/$jobRef/chat/join-status');

  /// User directory. `q` searches name/phone/email, `role` filters, and the
  /// response carries aggregate job/spend/plan/device facts per user so the
  /// admin console can show real detail without an N+1 request storm.
  static Future<Map<String, dynamic>?> adminUsers({
    String? q,
    String? role,
    int limit = 200,
    int offset = 0,
  }) =>
      getAdmin('/admin/users', {
        if (q != null && q.isNotEmpty) 'q': q,
        if (role != null && role.isNotEmpty) 'role': role,
        'limit': '$limit',
        'offset': '$offset',
      });

  /// Owner/admin/ops/CFO can add or change the email on their own account.
  /// A JWT session may only edit its own phone; the superadmin key may pass an
  /// explicit [phone]. A verification link is emailed to the new address.
  static Future<ApiResponse> setStaffEmail(String phone, String email) =>
      post('/admin/users/me/email', {'phone': phone, 'email': email.trim().toLowerCase()}, admin: true);

  /// TOTP MFA (available to every account, opt-in).
  static Future<Map<String, dynamic>?> mfaStatus() => get('/me/mfa');
  static Future<Map<String, dynamic>?> mfaEnroll() => post('/me/mfa/enroll', const {}).then((r) => r.body);
  static Future<ApiResponse> mfaConfirm(String code) => post('/me/mfa/confirm', {'code': code});
  static Future<ApiResponse> mfaDisable(String code) => post('/me/mfa/disable', {'code': code});
  static Future<ApiResponse> mfaVerifyLogin(String challenge, String code) async {
    final res = await post('/auth/mfa/verify-login', {'challenge': challenge, 'code': code});
    if (res.ok && res.body['token'] != null) token = res.body['token'] as String?;
    return res;
  }

  /// Full dossier for one account: jobs, payments, plans, devices, addresses.
  static Future<Map<String, dynamic>?> adminUserDetail(String phone) =>
      getAdmin('/admin/users/${Uri.encodeComponent(phone)}/detail');

  /// Superadmin recovery: mint a password-reset link for a protected account.
  /// The link is texted to the account phone and returned to the admin.
  static Future<ApiResponse> adminUserResetLink(String phone) =>
      post('/admin/users/${Uri.encodeComponent(phone)}/password-reset-link', {}, admin: true);

  /// Last client crashes (deduped per device+stack) for the admin console.
  static Future<Map<String, dynamic>?> adminClientCrashes() => getAdmin('/admin/client-crashes');

  /// Admin map console: every saved place with its owner and pin.
  static Future<Map<String, dynamic>?> adminPlaces({String? phone, String? q}) =>
      getAdmin('/admin/places', {
        if (phone != null && phone.isNotEmpty) 'phone': phone,
        if (q != null && q.isNotEmpty) 'q': q,
      });
  static Future<ApiResponse> adminAddPlace(String phone, String label, double lat, double lng) =>
      post('/admin/places', {'phone': phone, 'label': label, 'lat': lat, 'lng': lng}, admin: true);
  static Future<ApiResponse> adminUpdatePlace(int id, String label, double lat, double lng) =>
      post('/admin/places/$id/update', {'label': label, 'lat': lat, 'lng': lng}, admin: true);
  static Future<ApiResponse> adminDeletePlace(int id) =>
      delete('/admin/places/$id', admin: true);

  /// Synthetic fresh rider_assigned payload for a no-data tracker self-test.
  static Future<Map<String, dynamic>?> adminTrackingPreview() =>
      getAdmin('/admin/tracking-preview');

  /// Live rider pins for the admin fleet map.
  static Future<Map<String, dynamic>?> adminLiveRiders({int minutes = 60}) =>
      getAdmin('/admin/riders/live', {'minutes': '$minutes'});

  /// Admin team codes: generate a single-use free delivery and toggle it.
  static Future<Map<String, dynamic>?> adminPromos() => getAdmin('/admin/promos');
  static Future<ApiResponse> adminGeneratePromo({
    required String audience,
    required int discountPct,
    int uses = 1,
    String? note,
  }) =>
      post('/admin/promos/generate', {
        'audience': audience,
        'discount_pct': discountPct,
        'uses': uses,
        if (note != null) 'note': note,
      }, admin: true);
  static Future<ApiResponse> adminTogglePromo(String code, bool active) =>
      post('/admin/promos/${Uri.encodeComponent(code)}/toggle', {'active': active}, admin: true);

  /// Promote/demote an account. Every non-superadmin role is assignable by an
  /// admin; a partner must also carry a courier_id (its depot console).
  static Future<ApiResponse> adminSetUserRole(String email, String role, {int? courierId}) =>
      post('/admin/users/role', {
        'email': email,
        'role': role,
        if (courierId != null) 'courier_id': courierId,
      }, admin: true);

  /// Delivery IQ: how fast this courier really reaches the depot (p50/p90/avg
  /// minutes from actual pickup→depot times over the last 90 days).
  static Future<Map<String, dynamic>?> iqEta(int courierId, String window) =>
      get('/iq/eta', {'courier_id': '$courierId', 'window': window});

  /// Identity of the signed-in caller: {phone, role, photo_url, full_name}.
  /// role 'admin' | 'ops' unlocks the in-app admin console (owner phone is
  /// admin server-side). `force` drops the tiny in-memory freshness window so
  /// a photo changed on the server (another device / admin) shows up at once.
  static Future<Map<String, dynamic>?> me({bool force = false}) {
    if (force) _memCache.remove(_cacheKey('/me', null));
    return get('/me');
  }

  // ---- admin console (owner / admin key) ----

  static Future<Map<String, dynamic>?> adminStats() => getAdmin('/admin/stats');

  static Future<Map<String, dynamic>?> securityAlerts({bool unacknowledgedOnly = false}) =>
      getAdmin('/security/alerts${unacknowledgedOnly ? '?unacknowledged=1' : ''}');

  static Future<ApiResponse> ackAlert(int id) => post('/security/alerts/$id/ack', {}, admin: true);

  static Future<Map<String, dynamic>?> fraudFlags({String status = 'open'}) =>
      getAdmin('/admin/fraud?status=$status');

  static Future<ApiResponse> reviewFraud(int id, {required String status}) =>
      post('/admin/fraud/$id/review', {'status': status}, admin: true);

  /// Chat-moderation queue: open user reports + chat strike/suspension rows.
  static Future<Map<String, dynamic>?> chatReports({String status = 'open'}) =>
      getAdmin('/admin/chat/reports?status=$status');

  /// Confirm = hide the message from everyone + strike the sender.
  static Future<ApiResponse> reviewChatReport(int id, {required String action}) =>
      post('/admin/chat/reports/$id/review', {'action': action}, admin: true);

  /// Forgive strikes and lift any chat suspension for [phone].
  static Future<ApiResponse> clearChatStrikes(String phone) =>
      post('/admin/chat/strikes/${Uri.encodeComponent(phone)}/clear', const {}, admin: true);

  static Future<ApiResponse> adminSms({required String phone, required String message}) =>
      post('/admin/sms', {'phone': phone, 'message': message}, admin: true);

  static Future<ApiResponse> adminBroadcast({required String audience, required String message}) =>
      post('/admin/sms/broadcast', {'audience': audience, 'message': message}, admin: true);

  /// Marketing push to an audience segment.
  static Future<ApiResponse> adminPushBroadcast({required String audience, required String title, required String body}) =>
      post('/admin/push/broadcast', {'audience': audience, 'title': title, 'message': body}, admin: true);

  static Future<Map<String, dynamic>?> adminPushLog({int limit = 20}) =>
      getAdmin('/admin/push/log?limit=$limit');

  // ---- Rider payroll + ZRA turnover tax (admin console) ----------------------

  /// Payroll rows ({summary, payouts}) — pending/confirmed/paid salary payouts.
  static Future<Map<String, dynamic>?> adminPayroll({String? status, String? kind}) {
    final params = <String>['limit=100', if (status != null && status.isNotEmpty) 'status=$status', if (kind != null && kind.isNotEmpty) 'kind=$kind'];
    return getAdmin('/admin/payroll?${params.join('&')}');
  }

  /// Cron runs this automatically; admins can also trigger it manually.
  static Future<ApiResponse> adminPayrollGenerate({required String kind}) =>
      post('/admin/payroll/generate', {'kind': kind}, admin: true);

  /// Two-signature release: admin confirms intent, superadmin second-click
  /// disburses via Lipila (the owner may collapse both steps in one go).
  static Future<ApiResponse> adminPayrollConfirm(int id) =>
      post('/admin/payroll/$id/confirm', const {}, admin: true);

  static Future<ApiResponse> adminPayrollVoid(int id) =>
      post('/admin/payroll/$id/void', const {}, admin: true);

  /// Raw proof-of-payment HTML for a payout (share as file / print to PDF).
  static Future<Uint8List?> adminPayrollProof(int id) async {
    if (!enabled) return null;
    try {
      final res = await http
          .get(_uri('/admin/payroll/$id/proof'), headers: adminEnabled ? _adminHeaders : _headers)
          .timeout(_timeout);
      if (res.statusCode != 200) return null;
      return res.bodyBytes;
    } catch (_) {
      return null;
    }
  }

  /// Salaries run-rate / payroll cost as the business grows (CFO + owner view).
  static Future<Map<String, dynamic>?> adminPayrollRunrate() => getAdmin('/admin/payroll/runrate');

  /// Public verified team roster — name/vehicle only, no PII or money data.
  static Future<Map<String, dynamic>?> teamRoster() => get('/team');

  /// ZRA turnover-tax ledger ({periods}) — 0% ≤ K2,500 monthly, 5% above,
  /// due by the 14th of the following month; auto-computed by cron.
  static Future<Map<String, dynamic>?> adminTax() => getAdmin('/admin/tax');

  static Future<ApiResponse> adminTaxRefresh({String? yearMonth}) =>
      post('/admin/tax/refresh', yearMonth == null ? const {} : {'year_month': yearMonth}, admin: true);

  static Future<ApiResponse> adminTaxMark(String yearMonth, {required String status, String? note}) =>
      post('/admin/tax/$yearMonth/mark', {'status': status, if (note != null) 'note': note}, admin: true);

  /// Printable ZRA working sheet (HTML) for the 14th submission.
  static Future<Uint8List?> adminTaxReport(String yearMonth) async {
    if (!enabled) return null;
    try {
      final res = await http
          .get(_uri('/admin/tax/$yearMonth/report'), headers: adminEnabled ? _adminHeaders : _headers)
          .timeout(_timeout);
      if (res.statusCode != 200) return null;
      return res.bodyBytes;
    } catch (_) {
      return null;
    }
  }

  /// The linked rider's day as slot-batched task queues (stops, ETAs, totals,
  /// destination branch, target drop-off time).
  static Future<Map<String, dynamic>?> riderQueue(String? phone) {
    final q = phone == null || phone.isEmpty ? '' : '?phone=$phone';
    return get('/rider/queue$q');
  }

  /// Unassigned jobs auto-assign could not place — the claim board. Every
  /// verified rider sees the same list; the first to claim owns the job and it
  /// disappears for everyone else (server-side `rider_id IS NULL` guard).
  static Future<Map<String, dynamic>?> riderAvailable() => get('/rider/available');

  /// Claim one available-order. 409 already_claimed when another rider won.
  static Future<ApiResponse> claimJob(String ref) => post('/jobs/$ref/claim', const {});

  /// SOS: a rider in trouble pings every other rider (high-priority alert).
  static Future<ApiResponse> riderSos({double? lat, double? lng, String? note}) =>
      post('/rider/sos', {
        if (lat != null) 'lat': lat,
        if (lng != null) 'lng': lng,
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      });

  /// inDrive-style answer to an incoming order: acknowledge it (idempotent) or
  /// hand it back to the order board for another rider.
  static Future<ApiResponse> acceptJob(String ref) => post('/jobs/$ref/accept', const {});
  static Future<ApiResponse> declineJob(String ref) => post('/jobs/$ref/decline', const {});

  /// Courier refused the parcel at the depot (first-mile): return leg charged.
  static Future<ApiResponse> rejectAtDepot(String ref, {String? reason}) =>
      post('/jobs/$ref/reject-at-depot', {if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim()});

  /// Transfer an assigned-but-not-collected trip to another rider.
  static Future<ApiResponse> transferJob(String ref, int toRiderId) =>
      post('/jobs/${Uri.encodeComponent(ref)}/transfer', {'to_rider_id': toRiderId});

  /// Live daily stats for the task-queue card: {stats: {total, waiting,
  /// picked, delivered, parcels, earned_zmw}} for the rider's CAT day.
  static Future<Map<String, dynamic>?> riderStats(String? phone) {
    final q = phone == null || phone.isEmpty ? '' : '?phone=$phone';
    return get('/rider/stats$q');
  }

  /// Pace gate + bonus programme for the rider's stats card.
  /// (Also declared below with the other rider helpers — keep one.)
  /// Recipient's own 4-digit door PIN (Lusaka door handover).
  static Future<ApiResponse> setDoorPin(String pin) => post('/me/door-pin', {'pin': pin});
  static Future<ApiResponse> clearDoorPin() => delete('/me/door-pin');

  /// Rider sweep shifts — committed 06:00/10:00/14:00 CAT windows.
  static Future<Map<String, dynamic>?> riderShifts() => get('/rider/shifts');
  static Future<ApiResponse> setRiderShifts({required bool onShift, List<String>? shifts, bool termsAccepted = false}) =>
      post('/rider/shifts', {
        'on_shift': onShift,
        if (shifts != null) 'shifts': shifts,
        'terms_accepted': termsAccepted,
      });

  /// The rider's order waybill — full sheet (contacts, both addresses, depot,
  /// parcels) with every money field stripped server-side.
  static Future<Map<String, dynamic>?> riderWaybill(String ref) =>
      get('/jobs/$ref/waybill');

  /// Re-fires the 4-digit pickup-code SMS (fresh code, both sender and
  /// recipient copies) when the sender never received the booking SMS —
  /// without it the rider cannot verify the pickup at all.
  static Future<ApiResponse> resendPickupPin(String ref) =>
      post('/jobs/$ref/resend-pin', const {});

  /// Rider self-remit and the rider "cash float" list were removed with the
  /// no-COD policy: riders never collect cash at the door. Senders pay in
  /// advance via momo; recipients pay nothing in cash, so the float is gone.

  /// {rider, n, average, reviews: [...]} — the signed-in rider's rating summary.
  static Future<Map<String, dynamic>?> riderReviews() => get('/rider/reviews');

  /// {rider, n, average, reviews: [...]} — see above.

  /// Start a Lipila mobile-money collect for a job against the server total.
  static Future<ApiResponse> pay({
    required String jobRef,
    required String phone,
    String channel = 'merchant',
    String? idempotencyKey,
  }) =>
      post('/payments', {
        'kind': 'job',
        'job_ref': jobRef,
        'phone': phone,
        'channel': channel,
        if (idempotencyKey != null) 'idempotency_key': idempotencyKey,
      }, timeout: _paymentTimeout);

  /// Authoritative check: does this account still owe a depot counter fare?
  /// The booking cache can be stale after an admin waiver, so every pay prompt
  /// verifies here first (owner bug 2026-11-23).
  static Future<Map<String, dynamic>?> counterFareStatus() =>
      get('/counter-fare/status');

  /// Sender missed the momo prompt: request a fresh one without USSD.
  static Future<ApiResponse> repromptCounterFare() => post('/counter-fare/reprompt', const {});

  /// Depot counter fare (owner directive 2026-11-12): pay the EXACT amount
  /// transcribed off the depot receipt + processing. The receipt photo
  /// unlocks on approval and the rider is reimbursed fee-free.
  static Future<ApiResponse> payCounterFare({
    required String jobRef,
    required String phone,
    String? idempotencyKey,
  }) =>
      post('/payments', {
        'kind': 'counter_fare',
        'job_ref': jobRef,
        'phone': phone,
        if (idempotencyKey != null) 'idempotency_key': idempotencyKey,
      }, timeout: _paymentTimeout);
  /// Poll Lipila collect status (call every ~2s up to ~40s). Returns
  /// (status, failReason): failReason carries the telco's own message when a
  /// prompt fails — "User wallet does not have enough money to cover the
  /// payable amount." — so screens can tell the user WHY, not just "failed"
  /// (owner directive 2026-11-17).
  static Future<(String?, String?)> paymentStatus(String paymentId) async {
    final b = await get('/payments/$paymentId/status');
    return (b?['status'] as String?, b?['fail_reason'] as String?);
  }

  static Future<Map<String, dynamic>?> paymentReceipt(String paymentId) async =>
      get('/payments/$paymentId/receipt');

  static Future<List<Map<String, dynamic>>> myPlanReceipts() async {
    final b = await get('/me/plan-receipts');
    final raw = b?['receipts'];
    if (raw is! List) return const <Map<String, dynamic>>[];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList(growable: false);
  }

  static Future<List<Map<String, dynamic>>> myReceipts({String? kind}) async {
    final q = kind == null ? '' : '?kind=${Uri.encodeQueryComponent(kind)}';
    final b = await get('/me/receipts$q');
    final raw = b?['receipts'];
    if (raw is! List) return const <Map<String, dynamic>>[];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList(growable: false);
  }

  /// HELD-PAYMENT WATCH (owner bug 2026-11-17: "I paid but the payment screen
  /// didn't check or poll"): the held-booking screen polls the job's LATEST
  /// payment row — the server re-checks any pending row against Lipila inline,
  /// so a prompt approved late still settles. `phone` on the row is the
  /// transacting number the momo prompt was fired at.
  static Future<Map<String, dynamic>?> latestJobPayment(String jobRef) async =>
      (await get('/jobs/$jobRef/payments'))?['payment'] as Map<String, dynamic>?;

  /// Courier partner desk (role=partner, pinned to the account's courier_id).
  static Future<Map<String, dynamic>?> partnerMe() => get('/partner/me');

  static Future<Map<String, dynamic>?> partnerQuotes() => get('/partner/quotes');

  static Future<Map<String, dynamic>?> partnerRides() => get('/partner/rides');

  static Future<ApiResponse> partnerConfirmRide(String ref, {String? waybill}) =>
      post('/partner/rides/${Uri.encodeComponent(ref)}/confirm', {'waybill': waybill});

  /// Seller subscription plans (live prices come from /plans; seeded at Silver
  /// Silver K250 / Gold K500 / Platinum K750, Weekly Sprint K399.
  /// Cycle length comes from the plan (1 / 7 / 30 days); every parcel counts
  /// as one — even several in the same trip.
  static Future<Map<String, dynamic>?> plans() async {
    final data = await get('/plans');
    final flags = data?['feature_flags'];
    if (flags is Map) featureFlags = Map<String, dynamic>.from(flags);
    return data;
  }

  /// Live owner switches from /plans; default ON until the server says otherwise.
  static Map<String, dynamic> featureFlags = const {};

  static Future<ApiResponse> subscribe({
    required String tier,
    String pickupWindow = '10:00',
    String city = 'Lusaka',
    String? senderName,
  }) =>
      post('/subscriptions', {
        'tier': tier,
        'pickup_window': pickupWindow,
        'city': city,
        if (senderName != null) 'sender_name': senderName,
      }, timeout: _paymentTimeout);

  static Future<Map<String, dynamic>?> subscription([String? phone]) =>
      phone != null ? get('/subscriptions/$phone') : get('/subscriptions');

  /// Redeem a bulk/offline plan code onto the signed-in seller's number.
  /// No payment prompt — the plan was already paid for in bulk.
  static Future<ApiResponse> redeemPackCode(String code) =>
      post('/subscriptions/redeem', {'code': code});

  /// Mid-cycle upgrade: the bigger cap goes live now, the prorated difference
  /// is collected with a Lipila prompt.
  static Future<ApiResponse> upgradeSubscription(String tier) =>
      post('/subscriptions/upgrade', {'tier': tier});

  /// Admin: mint plan codes for offline/agent sale.
  static Future<ApiResponse> generatePackCodes({required String tier, int count = 1, String? note}) =>
      post('/admin/pack-codes', {'tier': tier, 'count': count, if (note != null && note.isNotEmpty) 'note': note}, admin: true);
  static Future<Map<String, dynamic>?> packCodes() => getAdmin('/admin/pack-codes');

  /// Admin plan catalogue (owner console): EVERY tier with its live on/off
  /// state — hidden or not-for-sale packs are included.
  static Future<Map<String, dynamic>?> adminTiers() => getAdmin('/admin/tiers');

  /// Save a plan: full edit (all fields) or a bare {tier, active: 0/1} toggle
  /// — the server keeps the rest of the config untouched on a toggle.
  static Future<ApiResponse> adminSaveTier(Map<String, dynamic> tier) =>
      post('/admin/tiers', tier, admin: true);

  /// All couriers with availability flag (admin console on/off toggle).
  static Future<Map<String, dynamic>?> adminCouriers() => getAdmin('/admin/couriers');
  static Future<ApiResponse> adminCourierToggle(int id, bool active) =>
      post('/admin/couriers', {'id': id, 'active': active ? 1 : 0}, admin: true);

  /// Platform feature flags (owner-flippable without a deploy): door-to-door
  /// service and the tier overage discount. GET is staff-visible; POST is
  /// superadmin-only server-side.
  /// Rider incentive programmes — admin creates/edits with a title, toggles on/off.
  static Future<Map<String, dynamic>?> adminIncentives() => getAdmin('/admin/incentives');

  static Future<ApiResponse> adminSaveIncentive(Map<String, dynamic> programme) =>
      post('/admin/incentives', programme, admin: true);

  static Future<ApiResponse> adminIncentiveToggle(int id, {bool? active}) => post(
        '/admin/incentives/$id/toggle',
        active == null ? const <String, dynamic>{} : {'active': active ? 1 : 0},
        admin: true,
      );

  /// Audit-only strike ledger (booking hold removed 2026-11-20) with job refs.
  static Future<Map<String, dynamic>?> adminBookingStrikes() => getAdmin('/admin/booking-strikes');

  static Future<ApiResponse> clearBookingStrikes(String phone) =>
      post('/admin/booking-strikes/${Uri.encodeComponent(phone)}/clear', const {}, admin: true);

  /// Collection from a courier point to the recipient's door (Lusaka). The
  /// parcel already arrived at the depot; a rider picks it up and runs the
  /// last mile. No counter fare, no branch choice.
  static Future<ApiResponse> createCollection({
    required int courierId,
    required String point,
    required String recipientName,
    required String recipientPhone,
    required String destAddress,
    required String pickupWindow,
    String? senderName,
    String? description,
    int parcels = 1,
    String vehicleClass = 'motorcycle',
    bool needsCar = false,
    String? promoCode,
    String payMethod = 'mobile_money',
    String? parcelSize,
    String? collectionReceiptUrl,
    double? declaredValueZmw,
  }) =>
      post('/collections', {
        'courier_id': courierId,
        'point': point,
        'recipient_name': recipientName,
        'recipient_phone': recipientPhone,
        'dest_address': destAddress,
        'pickup_window': pickupWindow,
        if (senderName != null && senderName.isNotEmpty) 'sender_name': senderName,
        if (description != null && description.isNotEmpty) 'description': description,
        'parcels': parcels,
        'vehicle_class': vehicleClass,
        'needs_car': needsCar,
        if (promoCode != null && promoCode.isNotEmpty) 'promo_code': promoCode,
        'pay_method': payMethod,
        if (collectionReceiptUrl != null && collectionReceiptUrl.isNotEmpty)
          'collection_receipt_url': collectionReceiptUrl,
        if (declaredValueZmw != null && declaredValueZmw > 0) 'declared_value_zmw': declaredValueZmw,
        if (parcelSize != null && parcelSize.isNotEmpty) 'parcel_size': parcelSize,
        if (parcelSize != null && parcelSize.isNotEmpty)
          'weight_class': switch (parcelSize) {
            'small' => '0-5kg',
            'large' => '15kg+',
            _ => '5-15kg',
          },
      });

  /// Pay the signed-in seller's plan activation/renewal via Lipila. Poll with
  /// [paymentStatus]; success flips the subscription to active server-side.
  static Future<ApiResponse> paySubscription({String channel = 'merchant'}) =>
      post('/payments', {
        'kind': 'subscription',
        'channel': channel,
        'idempotency_key': 'sub-${DateTime.now().millisecondsSinceEpoch}',
      }, timeout: _paymentTimeout);

  // ---- superadmin console (pricebook / partners / growth dashboard) ----
  static Future<ApiResponse> upsertCourier(Map<String, dynamic> courier) =>
      post('/admin/couriers', courier, admin: true);

  static Future<ApiResponse> upsertQuote({
    required int courierId,
    required String fromCity,
    required String toCity,
    required String weightClass,
    required String service,
    required double counterPriceZmw,
  }) =>
      post('/admin/quotes', {
        'courier_id': courierId,
        'from_city': fromCity,
        'to_city': toCity,
        'weight_class': weightClass,
        'service': service,
        'counter_price_zmw': counterPriceZmw,
      }, admin: true);

  /// Area-level localities extracted from user-typed addresses (jobs), most-used
  /// first — for the chargebook's location pickers. Area names only, never full
  /// street addresses.
  static Future<List<String>> adminLocalities() async {
    final data = await getAdmin('/admin/localities');
    return ((data?['localities'] as List?) ?? const [])
        .map((e) => '${(e as Map)['name'] ?? ''}'.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  /// Chargebook listing for the ops console (DropOff leg records on file).
  static Future<List<Map<String, dynamic>>> adminQuotes({int courierId = 0}) async {
    final data = await getAdmin('/admin/quotes', {'courier_id': '$courierId'});
    return (data?['quotes'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
  }

  static Future<ApiResponse> upsertRider({
    required String phone,
    required String fullName,
    required String vehicle,
  }) =>
      post('/admin/riders', {'phone': phone, 'full_name': fullName, 'vehicle': vehicle}, admin: true);

  static Future<ApiResponse> updateRider(int id, Map<String, dynamic> body) =>
      _patchJson('/admin/riders/$id', body);

  static Future<ApiResponse> deleteRider(int id, {bool confirm = false}) =>
      delete('/admin/riders/$id', body: {'confirm': confirm});

  /// Admin: soft-delete a booking. The job stays (payments/events kept for audit)
  /// but every user-facing listing excludes it; no real delete exists.
  static Future<ApiResponse> deleteJob(String ref) =>
      post('/admin/jobs/$ref/delete', const {}, admin: true);

  /// Admin: release a legacy canceled ("parked") booking to the claim board.
  static Future<ApiResponse> unparkJob(String ref) =>
      post('/admin/jobs/${Uri.encodeComponent(ref)}/unpark', const {}, admin: true);

  /// Superadmin: remove an auth user (and their device sessions + push tokens).
  /// Owner account is refused server-side.
  static Future<ApiResponse> deleteUser(String phone, {bool confirm = false}) =>
      delete('/admin/users/$phone', body: {'confirm': confirm});

  /// Admin: edit a user's details — the "add email to a number" flow.
  /// Setting an email marks it verified (the admin attests it), so the
  /// account can sign in with password immediately. Admin key's own account
  /// and other admin accounts are refused server-side.
  static Future<ApiResponse> adminUpdateUser(String phone, {String? email, String? fullName}) =>
      post('/admin/users/$phone/update', {
        if (email != null) 'email': email,
        if (fullName != null) 'full_name': fullName,
      }, admin: true);

  /// DISPATCH AUTOMATION (owner directive 2026-11-15): staff never hand-pick a
  /// rider by default — the server's algorithm picks the nearest AVAILABLE,
  /// verified rider with free capacity (ties broken by load).
  // NOTE: assignJob (POST /admin/jobs/:ref/assign) was REMOVED — every dispatch
  // is algorithmic. autoAssignJob is the only rider-assignment call the app
  // makes; it hits the server-side nearestAvailableRider() under the hood.

  /// Returns the server body whether ok or not — callers render `hint` /
  /// `excluded_at_depot` on failures (rider at depot, no riders) instead of a
  /// bare generic failure.
  static Future<Map<String, dynamic>?> autoAssignJob(String jobRef) =>
      post('/jobs/$jobRef/auto-assign', const {}).then((r) => r.body);

  static Future<ApiResponse> payout({
    required String phone,
    required double amountZmw,
    String kind = 'rider_earning',
  }) =>
      post('/admin/payouts', {'phone': phone, 'amount_zmw': amountZmw, 'kind': kind}, admin: true);

  /// Auth headers without Content-Type (multipart sets its own boundary).
  static Map<String, String> get authHeaders => {
        if (apiKey.isNotEmpty) 'X-Api-Key': apiKey,
        if (token != null) 'Authorization': 'Bearer $token',
        if (adminKey.isNotEmpty) 'X-Admin-Key': adminKey,
      };

  /// Upload a photo to the Worker. [kind] selects the storage namespace:
  ///   'selfie' → uploads/selfie/<uuid> — any signed-in user may fetch it
  ///              (senders see the rider collecting their parcel);
  ///   'kyc'    → uploads/kyc/<phone>/<uuid> — staff or the uploading rider only.
  /// Defaults to the PRIVATE one.
  static Future<ApiResponse> uploadImage(List<int> bytes, String filename, {String kind = 'kyc', DateTime? capturedAt}) async {
    if (!enabled) return const ApiResponse(error: 'offline_demo_mode');
    try {
      // EVIDENCE STAMP (owner directive 2026-11-20): every sender/rider photo
      // is burned with the DropOff watermark + exact CAT capture time before
      // it leaves the phone. Re-encoded as JPEG so the stamp is part of the
      // pixels the server stores. Failures fall back to the original bytes.
      //
      // SPEED (owner request 2026-11-20: "quicken photo uploads"): the decode →
      // resize → watermark → JPEG encode runs in a BACKGROUND ISOLATE, and the
      // image is capped at 1600 px on the long side. A modern phone shot is
      // 4000–8000 px (5–10 MB); 1600 px is ~300–500 KB, so the upload itself
      // finishes several times faster while staying crisp evidence.
      var payload = bytes;
      var uploadName = filename;
      final tag = switch (kind) {
        'receipt' => 'RECEIPT',
        'selfie' => 'SELFIE',
        _ => 'EVIDENCE',
      };
      final Uint8List source = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
      Uint8List? stamped;
      if (DropOffApi.featureFlags['photo_stamp_enabled'] != false) {
        try {
          stamped = await compute(_stampInIsolate, _StampJob(source, tag, capturedAt));
        } catch (_) {
          stamped = null; // stamping failed — upload original bytes
        }
      }
      if (stamped != null) {
        payload = stamped;
        final dot = filename.lastIndexOf('.');
        uploadName = '${dot > 0 ? filename.substring(0, dot) : filename}.jpg';
      }
      // Upload with retry: if the stamped version fails (e.g. server rejects
      // the re-encoded bytes), retry once with the original bytes so the photo
      // is never lost.
      ApiResponse? result;
      for (var attempt = 0; attempt < 2; attempt++) {
        final useStamped = attempt == 0 && stamped != null;
        final reqPayload = useStamped ? payload : bytes;
        final reqName = useStamped ? uploadName : filename;
        final req = http.MultipartRequest('POST', _uri('/uploads'))
          ..headers.addAll(authHeaders)
          ..fields['kind'] = kind
          ..files.add(http.MultipartFile.fromBytes('file', reqPayload, filename: reqName));
        final streamed = await req.send().timeout(const Duration(seconds: 90));
        final res = await http.Response.fromStream(streamed);
        final decoded = jsonDecode(res.body) as Map<String, dynamic>? ?? const {};
        _noteAuthFailure(res.statusCode);
        final ok = res.statusCode >= 200 && res.statusCode < 300;
        result = ApiResponse(
          status: res.statusCode,
          ok: ok,
          body: decoded,
          error: ok ? null : '${decoded['error'] ?? 'http_${res.statusCode}'}',
        );
        if (ok || attempt == 1) break;
      }
      return result!;
    } catch (_) {
      return const ApiResponse(error: 'network_error');
    }
  }

  /* ------------------- rider onboarding + targets ------------------- */
  static Future<Map<String, dynamic>?> riderProfile() => get('/rider/profile');

  static Future<ApiResponse> riderProfileSubmit(Map<String, dynamic> body) =>
      post('/rider/profile', body);

  /// rider runs the AI face review on their OWN selfie (KYC). Returns
  /// `{face: {face, single_person, real_photo, document_or_id,
  /// illustration_or_avatar, verdict: pass|review|fail, note}}`.
  static Future<ApiResponse> riderFaceCheck() =>
      post('/rider/profile/ai-face-check', const {}, timeout: _aiTimeout);

  /// Add ONLY a selfie (grandfathered verified riders keep their standing).
  /// Server AI-reviews it inline; a clear fail demotes a verified rider to
  /// pending until an admin re-verifies. Never touches KYC documents.
  static Future<ApiResponse> addRiderPhoto(String photoUrl) =>
      post('/rider/photo', {'photo_url': photoUrl});

  /// ANY signed-in user sets their profile photo (upload via kind=selfie
  /// first). Riders get the same inline AI review as the KYC selfie flow.
  static Future<ApiResponse> addMePhoto(String photoUrl) =>
      post('/me/photo', {'photo_url': photoUrl});

  /// Remove the caller's profile photo (back to initials).
  static Future<ApiResponse> removeMePhoto() =>
      delete('/me/photo');

  static Future<Map<String, dynamic>?> riderTargets() => get('/rider/targets');

  static Future<Map<String, dynamic>?> riderHistory({int limit = 50}) =>
      get('/rider/history', {'limit': '$limit'});

  /* --------------------- admin rider verification -------------------- */
  static Future<Map<String, dynamic>?> adminRiders() => getAdmin('/admin/riders');

  static Future<ApiResponse> adminVerifyRider(int id, {required String status, String? note}) =>
      post('/admin/riders/$id/verify', {'status': status, if (note != null) 'note': note}, admin: true);

  static Future<ApiResponse> adminAiCheckRider(int id) =>
      post('/admin/riders/$id/ai-check', const {}, admin: true, timeout: _aiTimeout);

  /* ------------------------------ AI helpers ------------------------- */
  static Future<ApiResponse> aiAddress(String text) => post('/ai/address', {'text': text}, timeout: _aiTimeout);

  static Future<ApiResponse> supportAiDraft(int threadId) =>
      post('/admin/support/threads/$threadId/ai-draft', const {}, admin: true, timeout: _aiTimeout);
}

class ApiResponse {
  final int? status;
  final bool ok;
  final Map<String, dynamic> body;
  final String? error;

  const ApiResponse({this.status, this.ok = false, this.body = const {}, this.error});
}

/// Arguments for the background photo-stamping isolate (must be sendable).
class _StampJob {
  final Uint8List bytes;
  final String tag;
  final DateTime? capturedAt;
  const _StampJob(this.bytes, this.tag, this.capturedAt);
}

/// Top-level so `compute` can spawn it; returns null when the bytes are not a
/// decodable image (the caller uploads the original unchanged).
Uint8List? _stampInIsolate(_StampJob job) => PhotoStamp.tryApply(job.bytes, tag: job.tag, at: job.capturedAt);

