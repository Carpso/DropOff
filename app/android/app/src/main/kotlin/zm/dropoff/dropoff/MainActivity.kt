package zm.dropoff.dropoff

import io.flutter.embedding.android.FlutterFragmentActivity

// FlutterFragmentActivity (instead of FlutterActivity) is required by
// biometric prompts (local_auth) - the prompt renders as a Fragment.
class MainActivity : FlutterFragmentActivity()
