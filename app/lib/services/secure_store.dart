// Cross-platform token store. Historically mobile used the device keystore
// via flutter_secure_storage, but:
//  1. the token is ALSO mirrored to SharedPreferences as the resilience
//     fallback (keystore entries die on screen-lock/fingerprint changes);
//  2. flutter_secure_storage's web plugin cannot compile to WebAssembly,
//     which fails `flutter build web` outright.
// The app sandbox is the boundary everywhere: root on Android / jailbroken
// iOS / devtools on web are outside any app-level "encryption at rest".
// One plain store, everywhere - simpler and builds for all platforms.
import 'package:shared_preferences/shared_preferences.dart';

class SecureStore {
  Future<String?> read({required String key}) async =>
      (await SharedPreferences.getInstance()).getString(key);

  Future<void> write({required String key, required String value}) async =>
      (await SharedPreferences.getInstance()).setString(key, value);

  Future<void> delete({required String key}) async =>
      (await SharedPreferences.getInstance()).remove(key);
}
