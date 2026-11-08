/// Cross-platform biometric gate. On web (or anything without local_auth) the
/// stub kicks in: no biometrics offered, never blocking. The io version is
/// compiled only on platforms with dart:io.
library;
export 'device_lock_stub.dart' if (dart.library.io) 'device_lock_io.dart';
