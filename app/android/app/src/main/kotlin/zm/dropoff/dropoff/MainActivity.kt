package zm.dropoff.dropoff

import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// FlutterFragmentActivity (instead of FlutterActivity) is required by
// biometric prompts (local_auth) - the prompt renders as a Fragment.
class MainActivity : FlutterFragmentActivity() {
    private companion object {
        const val CHANNEL = "zm.dropoff.dropoff/screen_privacy"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method == "setSecure") {
                    val enabled = call.argument<Boolean>("enabled") == true
                    if (enabled) {
                        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    } else {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    }
                    result.success(true)
                } else {
                    result.notImplemented()
                }
            }
    }
}
