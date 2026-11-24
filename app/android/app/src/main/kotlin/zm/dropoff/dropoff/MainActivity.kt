package zm.dropoff.dropoff

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// FlutterFragmentActivity (instead of FlutterActivity) is required by
// biometric prompts (local_auth) - the prompt renders as a Fragment.
class MainActivity : FlutterFragmentActivity() {
    companion object {
        private const val PRIVACY_CHANNEL = "zm.dropoff.dropoff/screen_privacy"
        private const val ORDER_ALERT_CHANNEL = "zm.dropoff.dropoff/order_alert"
        private const val EXTRA_ORDER_ACTION = "order_action"
        private const val EXTRA_JOB_REF = "job_ref"

        /** Intent used by the order notification's Accept / Decline / Open actions. */
        @JvmStatic
        fun orderActionIntent(context: Context, action: String, ref: String): Intent =
            Intent(context, MainActivity::class.java).apply {
                putExtra(EXTRA_ORDER_ACTION, action)
                putExtra(EXTRA_JOB_REF, ref)
                addFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP or
                        Intent.FLAG_ACTIVITY_CLEAR_TOP,
                )
            }
    }

    /** Notification action tapped before Flutter was ready to handle it. */
    private var pendingOrderAction: MutableMap<String, String>? = null
    private var orderAlertChannel: MethodChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        captureOrderAction(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        captureOrderAction(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PRIVACY_CHANNEL)
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

        val alertChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, ORDER_ALERT_CHANNEL)
        orderAlertChannel = alertChannel
        alertChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "startRing" -> {
                    val intent = Intent(this, OrderAlertService::class.java).apply {
                        putExtra(OrderAlertService.EXTRA_REF, call.argument<String>("ref") ?: "")
                        putExtra(OrderAlertService.EXTRA_TITLE, call.argument<String>("title") ?: "New delivery")
                        putExtra(OrderAlertService.EXTRA_BODY, call.argument<String>("body") ?: "")
                        putExtra(OrderAlertService.EXTRA_ADDRESS, call.argument<String>("address") ?: "")
                        putExtra(OrderAlertService.EXTRA_ETA, call.argument<String>("eta") ?: "")
                        putExtra(OrderAlertService.EXTRA_FEE, call.argument<String>("fee") ?: "")
                    }
                    OrderAlertService.start(this, intent)
                    result.success(true)
                }
                "stopRing" -> {
                    OrderAlertService.stop(this)
                    result.success(true)
                }
                "pendingAction" -> {
                    val action = pendingOrderAction
                    pendingOrderAction = null
                    result.success(action)
                }
                "batteryOptimizationsIgnored" -> result.success(isIgnoringBatteryOptimizations())
                "requestIgnoreBatteryOptimizations" -> {
                    result.success(requestIgnoreBatteryOptimizations())
                }
                else -> result.notImplemented()
            }
        }
        // A tap may have arrived before the channel existed.
        pendingOrderAction?.let { flushPendingAction() }
    }

    /** Reads an Accept/Decline/Open tap delivered by the order notification. */
    private fun captureOrderAction(intent: Intent?) {
        val action = intent?.getStringExtra(EXTRA_ORDER_ACTION) ?: return
        val ref = intent.getStringExtra(EXTRA_JOB_REF) ?: ""
        intent.removeExtra(EXTRA_ORDER_ACTION)
        pendingOrderAction = hashMapOf("action" to action, "ref" to ref)
        flushPendingAction()
    }

    private fun flushPendingAction() {
        val action = pendingOrderAction ?: return
        val channel = orderAlertChannel ?: return
        channel.invokeMethod("onOrderAction", action)
        pendingOrderAction = null
    }

    private fun isIgnoringBatteryOptimizations(): Boolean = try {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            true
        } else {
            val pm = getSystemService(Context.POWER_SERVICE) as? PowerManager
            pm?.isIgnoringBatteryOptimizations(packageName) == true
        }
    } catch (_: Throwable) {
        true
    }

    /**
     * Riders on Xiaomi/Oppo/Vivo/Samsung builds lose FCM delivery when the app
     * is battery-optimised. Opening the system dialog is the only honest fix —
     * this never changes a setting on the user's behalf.
     */
    private fun requestIgnoreBatteryOptimizations(): Boolean = try {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            false
        } else {
            val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
                .setData(Uri.parse("package:$packageName"))
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(intent)
            true
        }
    } catch (_: Throwable) {
        try {
            startActivity(
                Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )
            true
        } catch (_: Throwable) {
            false
        }
    }
}

