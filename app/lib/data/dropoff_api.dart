import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

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
      defaultValue: 'https://dropoff-api.godfreymoseskalambo.workers.dev');
  // SECURITY: the ops/rider service key must NEVER ship inside a store build.
  // It arrives only via --dart-define at build time on trusted rider/operator
  // devices. Without it, customers sign in with the email/OTP JWT and every
  // call degrades to that identity (server rejects bare ops-key requests).
  static const String apiKey = String.fromEnvironment('DROPOFF_API_KEY');
  static const String adminKey = String.fromEnvironment('DROPOFF_ADMIN_KEY');

  /// Fee model mirror of workers/src/fees.ts — the server is authoritative;
  /// these helpers only render the estimate before the job is created.
  ///
  /// MODEL: the customer pays the base + ONE "processing fee" (platform cut +
  /// momo collection leg). Driver/rider earnings are NEVER computed here —
  /// they live server-side between DropOff and the driver.
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
      Uri.parse('$baseUrl$path').replace(queryParameters: query);

  static String? _deviceId;

  /// The app device id (mirrors AppStore.deviceId). Used in WS handshakes and
  /// when the API client builds non-standard headers.
  static String get deviceId => _deviceId ?? '';

  /// Called by AppStore on init once the stable device id is known.
  static void installDeviceId(String id) => _deviceId = id;

  static Map<String, String> get _headers => {
      'Content-Type': 'application/json',
      if (apiKey.isNotEmpty) 'X-Api-Key': apiKey,
      if (token != null) 'Authorization': 'Bearer $token',
      if (_deviceId != null && _deviceId!.isNotEmpty) 'X-Device-Id': _deviceId!,
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
      return _readCache(cacheKey);
    } catch (_) {
      final mem = _memCache[cacheKey];
      if (mem != null) return mem.value;
      return _readCache(cacheKey);
    }
  }

  static Future<ApiResponse> delete(
    String path, {
    Map<String, dynamic>? body,
    Duration? timeout,
  }) async {
    if (!enabled) return const ApiResponse(error: 'offline_demo_mode');
    try {
      final res = await http
          .delete(_uri(path), headers: _headers, body: jsonEncode(body ?? const {}))
          .timeout(timeout ?? _timeout);
      final decoded = jsonDecode(res.body) as Map<String, dynamic>? ?? const {};
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
  }) async {
    if (!enabled) return const ApiResponse(error: 'offline_demo_mode');
    try {
      final res = await http
          .post(_uri(path),
              headers: {...(admin ? _adminHeaders : _headers), ...?extraHeaders},
              body: jsonEncode(body))
          .timeout(timeout ?? _timeout);
      final decoded = jsonDecode(res.body) as Map<String, dynamic>? ?? const {};
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

  /// Share the rider's current GPS fix for dispatch + live tracking.
  static Future<ApiResponse> riderPing({required String phone, required double lat, required double lng}) async {
    if (!enabled) return const ApiResponse(error: 'offline_demo_mode');
    try {
      final res = await http
          .post(Uri.parse('$baseUrl/rider/ping'), headers: _headers, body: jsonEncode({'phone': phone, 'lat': lat, 'lng': lng}))
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
  static Future<ApiResponse> requestOtp(String phone) => post('/auth/request', {'phone': phone});

  static Future<ApiResponse> verifyOtp(String phone, String code) async {
    final res = await post('/auth/verify', {'phone': phone, 'code': code});
    if (res.ok) token = res.body['token'] as String?;
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
    if (res.ok) token = res.body['token'] as String?;
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

  /// Rider log: status movement for a job. For door deliveries the server
  /// REQUIRES [otp] — the recipient's 4-digit DropOff code — so a parcel
  /// cannot be "delivered" into thin air. [stage] ('pickup' | 'delivery')
  /// files the proof photo against the right leg.
  static Future<ApiResponse> jobEvent({
    required String jobRef,
    String? status,
    String? note,
    String? waybill,
    String? photoUrl,
    String? stage,
    String? otp,
    double? lat,
    double? lng,
  }) =>
      post('/jobs/$jobRef/events', {
        if (status != null) 'status': status,
        if (note != null) 'note': note,
        if (waybill != null) 'waybill': waybill,
        if (photoUrl != null) 'photo_url': photoUrl,
        if (stage != null) 'stage': stage,
        if (otp != null) 'otp': otp,
        if (lat != null) 'lat': lat,
        if (lng != null) 'lng': lng,
      });

  /// AI parcel photo check: compares the seller's booking capture against the
  /// rider's depot/delivery photo. Returns {same_parcel, confidence, note, flagged}.
  /// 409 when either photo is missing — treat as "no check available", not an error.
  static Future<ApiResponse> parcelCheck(String ref) =>
      post('/jobs/$ref/parcel-check', {});

  static Future<Map<String, dynamic>?> jobEvidence(String ref) => get('/jobs/$ref/evidence');
  static Future<Map<String, dynamic>?> slotsSuggest({String? fromCity}) =>
      get('/slots/suggest', {if (fromCity != null && fromCity.isNotEmpty) 'from_city': fromCity});
  static Future<List<Map<String, dynamic>>> recipients() async {
    final data = await get('/recipients');
    return ((data?['recipients'] as List?) ?? const []).cast<Map<String, dynamic>>();
  }
  static Future<ApiResponse> saveRecipient(Map<String, dynamic> r) => post('/recipients', r);
  static Future<ApiResponse> deleteRecipient(int id) => delete('/recipients/$id');
  static Future<ApiResponse> patchMe(Map<String, dynamic> body) => _patchJson('/me', body);

  static Future<ApiResponse> _patchJson(String path, Map<String, dynamic> body) async {
    if (!enabled) return const ApiResponse(error: 'offline_demo_mode');
    try {
      final headers = <String, String>{'Content-Type': 'application/json', ...authHeaders};
      final res = await http.patch(_uri(path), headers: headers, body: jsonEncode(body)).timeout(const Duration(seconds: 20));
      final data = res.body.isEmpty ? <String, dynamic>{} : (jsonDecode(res.body) as Map<String, dynamic>? ?? {});
      return ApiResponse(status: res.statusCode, ok: res.statusCode >= 200 && res.statusCode < 300, body: data);
    } catch (_) {
      return const ApiResponse(error: 'network_error');
    }
  }

  /// Rate one side of a delivery — seller, driver (rider) or courier — with an
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
  // requires_verification + a last-4 phone hint until the viewer proves a
  // participant phone. Signed-in users (sender/recipient) pass via their JWT
  // automatically (in _headers); phone-verified viewers pass via the
  // X-Track-Grant minted by verifyTrack() below.

  /// Grants per token (in-memory only — a fresh app run simply re-verifies).
  static final Map<String, String> _trackGrants = {};

  static String _trackTokenOf(String input) {
    final raw = input.trim();
    return RegExp(r'/track/([A-Za-z0-9_-]+)').firstMatch(raw)?.group(1) ?? raw;
  }

  static Map<String, String> _trackHeaders(String token) => {
        if (_trackGrants[token] != null) 'X-Track-Grant': _trackGrants[token]!,
      };

  /// Live (never cached) tracking fetch — gate vs granted responses must not
  /// be served from a stale snapshot.
  static Future<Map<String, dynamic>?> _trackGet(String path, String token) async {
    if (!enabled) return null;
    try {
      final res = await http
          .get(_uri(path), headers: {..._headers, ..._trackHeaders(token)})
          .timeout(_timeout);
      if (res.statusCode >= 200 && res.statusCode < 300) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Recipient tracking — accepts the SMS link or the bare token. Callers
  /// must treat `requires_verification: true` as "show the phone gate".
  static Future<Map<String, dynamic>?> trackByToken(String input) {
    final token = _trackTokenOf(input);
    return _trackGet('/track/$token', token);
  }

  /// Phone-verification gate: succeeds only for the sender's or recipient's
  /// phone; stores the returned grant for every subsequent /track/* call.
  static Future<Map<String, dynamic>?> verifyTrack(String tokenOrUrl, String phone) async {
    final token = _trackTokenOf(tokenOrUrl);
    final res = await post('/track/$token/verify', {'phone': phone});
    final grant = res.ok ? res.body['grant'] as String? : null;
    if (grant != null) _trackGrants[token] = grant;
    return res.ok ? res.body : null;
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
    return post('/track/$token/chat', {'body': body}, extraHeaders: _trackHeaders(token));
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

  /// One support ticket with all messages.
  static Future<Map<String, dynamic>?> adminSupportThread(int threadId) =>
      getAdmin('/admin/support/threads/$threadId');

  /// Admin/ops reply into a support ticket (same endpoint sellers use).
  static Future<ApiResponse> supportReply(int threadId, String body) =>
      post('/chat/support/$threadId/reply', {'body': body}, admin: true);

  /// {users: [{email, phone, full_name, role, ...}]} — staff can read, superadmin can write.
  static Future<Map<String, dynamic>?> adminUsers() => getAdmin('/admin/users');

  /// Promote/demote an account (customer|admin|partner) — superadmin only.
  static Future<ApiResponse> adminSetUserRole(String email, String role) =>
      post('/admin/users/role', {'email': email, 'role': role}, admin: true);

  /// Delivery IQ: how fast this courier really reaches the depot (p50/p90/avg
  /// minutes from actual pickup→depot times over the last 90 days).
  static Future<Map<String, dynamic>?> iqEta(int courierId, String window) =>
      get('/iq/eta', {'courier_id': '$courierId', 'window': window});

  /// Identity of the signed-in caller: {phone, role}. role 'admin' | 'ops'
  /// unlocks the in-app admin console (owner phone is admin server-side).
  static Future<Map<String, dynamic>?> me() => get('/me');

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
  /// Poll Lipila collect status (call every ~2s up to ~40s).
  static Future<String?> paymentStatus(String paymentId) async =>
      (await get('/payments/$paymentId/status'))?['status'] as String?;

  /// Seller subscription plans (live prices come from /plans; seeded at Silver
  /// K250 / Gold K500 / Platinum K750, Weekly K399 and Daily Rider K49).
  /// Cycle length comes from the plan (1 / 7 / 30 days); every parcel counts
  /// as one — even several in the same trip.
  static Future<Map<String, dynamic>?> plans() => get('/plans');

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
      });

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
    String payMethod = 'mobile_money',
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
        'pay_method': payMethod,
      });

  /// Pay the signed-in seller's plan activation/renewal via Lipila. Poll with
  /// [paymentStatus]; success flips the subscription to active server-side.
  static Future<ApiResponse> paySubscription({String channel = 'merchant'}) =>
      post('/payments', {
        'kind': 'subscription',
        'channel': channel,
        'idempotency_key': 'sub-${DateTime.now().millisecondsSinceEpoch}',
      });

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

  static Future<ApiResponse> assignJob({required String jobRef, required String riderPhone}) =>
      post('/admin/jobs/$jobRef/assign', {'phone': riderPhone}, admin: true);

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
  ///              (sellers see the rider collecting their parcel);
  ///   'kyc'    → uploads/kyc/<phone>/<uuid> — staff or the uploading rider only.
  /// Defaults to the PRIVATE one.
  static Future<ApiResponse> uploadImage(List<int> bytes, String filename, {String kind = 'kyc'}) async {
    if (!enabled) return const ApiResponse(error: 'offline_demo_mode');
    try {
      final req = http.MultipartRequest('POST', _uri('/uploads'))
        ..headers.addAll(authHeaders)
        ..fields['kind'] = kind
        ..files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
      final streamed = await req.send().timeout(const Duration(seconds: 45));
      final res = await http.Response.fromStream(streamed);
      final decoded = jsonDecode(res.body) as Map<String, dynamic>? ?? const {};
      final ok = res.statusCode >= 200 && res.statusCode < 300;
      return ApiResponse(
        status: res.statusCode,
        ok: ok,
        body: decoded,
        error: ok ? null : '${decoded['error'] ?? 'http_${res.statusCode}'}',
      );
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
      post('/rider/profile/ai-face-check', const {});

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

  /* --------------------- admin rider verification -------------------- */
  static Future<Map<String, dynamic>?> adminRiders() => getAdmin('/admin/riders');

  static Future<ApiResponse> adminVerifyRider(int id, {required String status, String? note}) =>
      post('/admin/riders/$id/verify', {'status': status, if (note != null) 'note': note}, admin: true);

  static Future<ApiResponse> adminAiCheckRider(int id) =>
      post('/admin/riders/$id/ai-check', const {}, admin: true);

  /* ------------------------------ AI helpers ------------------------- */
  static Future<ApiResponse> aiAddress(String text) => post('/ai/address', {'text': text});

  static Future<ApiResponse> supportAiDraft(int threadId) =>
      post('/admin/support/threads/$threadId/ai-draft', const {}, admin: true);
}

class ApiResponse {
  final int? status;
  final bool ok;
  final Map<String, dynamic> body;
  final String? error;

  const ApiResponse({this.status, this.ok = false, this.body = const {}, this.error});
}

