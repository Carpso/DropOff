// Cross-platform token store. Mobile/desktop use the device keystore/keychain
// (flutter_secure_storage) with SharedPreferences as a fail-soft mirror; web uses
// SharedPreferences because flutter_secure_storage's web plugin breaks wasm builds.
export 'secure_store_io.dart' if (dart.library.html) 'secure_store_web.dart';
