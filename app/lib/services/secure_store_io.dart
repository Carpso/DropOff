// Mobile/desktop token store: device keystore/keychain primary, SharedPreferences
// only as a fail-soft mirror (keystore entries can die on screen-lock/fingerprint
// changes). Web uses SharedPreferences (see secure_store_web.dart).
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SecureStore {
  const SecureStore();

  static const _secure = FlutterSecureStorage();

  Future<String?> read({required String key}) async {
    try {
      final v = await _secure.read(key: key);
      if (v != null && v.isNotEmpty) return v;
    } catch (_) {
      // fall through to mirror
    }
    return (await SharedPreferences.getInstance()).getString(key);
  }

  Future<void> write({required String key, required String value}) async {
    var secureOk = true;
    try {
      await _secure.write(key: key, value: value);
    } catch (_) {
      secureOk = false;
    }
    if (!secureOk) {
      // Last-resort mirror so sessions survive a keystore failure on odd devices.
      await (await SharedPreferences.getInstance()).setString(key, value);
    } else {
      // Keystore is available: keep no plaintext mirror. Clear any stale one.
      await (await SharedPreferences.getInstance()).remove(key);
    }
  }

  Future<void> delete({required String key}) async {
    try {
      await _secure.delete(key: key);
    } catch (_) {
      // mirror may still hold it; delete there too
    }
    await (await SharedPreferences.getInstance()).remove(key);
  }
}
