// Web token store: SharedPreferences only (flutter_secure_storage's web plugin
// cannot compile to WebAssembly, which breaks `flutter build web`).
import 'package:shared_preferences/shared_preferences.dart';

class SecureStore {
  const SecureStore();

  Future<String?> read({required String key}) async =>
      (await SharedPreferences.getInstance()).getString(key);

  Future<void> write({required String key, required String value}) async =>
      (await SharedPreferences.getInstance()).setString(key, value);

  Future<void> delete({required String key}) async =>
      (await SharedPreferences.getInstance()).remove(key);
}
