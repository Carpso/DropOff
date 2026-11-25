package zm.dropoff.dropoff

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import android.graphics.Color
import android.media.AudioAttributes
import android.media.Ringtone
import android.media.RingtoneManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat

/**
 * inDrive-style INCOMING ORDER alert (owner 2026-11-24).
 *
 * The FCM order push already wakes the app, but a single notification chime is
 * easy to miss on a bike. This foreground service keeps an alarm ringtone and a
 * vibration pattern LOOPING until the rider accepts, declines, opens the app,
 * or the 60 s window expires — the same "it rings like a call" behaviour riders
 * expect from ride-hailing apps.
 *
 * It also posts an ONGOING notification with Accept / Decline actions, so the
 * rider never has to open the app just to answer the order.
 */
class OrderAlertService : Service() {

    companion object {
        const val EXTRA_REF = "job_ref"
        const val EXTRA_TITLE = "title"
        const val EXTRA_BODY = "body"
        const val EXTRA_ADDRESS = "address"
        const val EXTRA_ETA = "eta"
        const val EXTRA_FEE = "fee"

        const val ACTION_START = "zm.dropoff.dropoff.ORDER_ALERT_START"
        private const val CHANNEL_ID = "dropoff_orders"
        private const val NOTIFICATION_ID = 8801
        /** Ringing longer than this is harassment; the job is still in the queue. */
        private const val RING_TIMEOUT_MS = 60_000L

        /** Starts (or restarts) the ring. Safe to call from the Flutter UI. */
        fun start(context: Context, intent: Intent) {
            intent.setClass(context, OrderAlertService::class.java)
            intent.action = ACTION_START
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
            } catch (_: Throwable) {
                // Some OEMs block background service starts; the notification
                // from Flutter is still posted, so the order is never lost.
            }
        }

        fun stop(context: Context) {
            try {
                context.stopService(Intent(context, OrderAlertService::class.java))
            } catch (_: Throwable) {
            }
        }
    }

    private var ringtone: Ringtone? = null
    private var vibrator: Vibrator? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private val handler = Handler(Looper.getMainLooper())
    private val timeoutStop = Runnable { stopEverything() }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent == null) {
            stopEverything()
            return START_NOT_STICKY
        }
        val ref = intent.getStringExtra(EXTRA_REF) ?: ""
        val title = intent.getStringExtra(EXTRA_TITLE) ?: "New delivery"
        val body = intent.getStringExtra(EXTRA_BODY) ?: "A new order is waiting."
        val address = intent.getStringExtra(EXTRA_ADDRESS) ?: ""
        val eta = intent.getStringExtra(EXTRA_ETA) ?: ""
        val fee = intent.getStringExtra(EXTRA_FEE) ?: ""

        ensureChannel()
        try {
            ServiceCompat.startForeground(
                this,
                NOTIFICATION_ID,
                buildNotification(ref, title, body, address, eta, fee),
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q)
                    android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK
                else 0,
            )
        } catch (_: Throwable) {
            // If the OS refuses the foreground promotion, still try to ring.
        }

        startRinging()
        startVibrating()
        handler.removeCallbacks(timeoutStop)
        handler.postDelayed(timeoutStop, RING_TIMEOUT_MS)
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        handler.removeCallbacks(timeoutStop)
        stopRinging()
        stopVibrating()
        releaseWake()
        super.onDestroy()
    }

    private fun stopEverything() {
        stopRinging()
        stopVibrating()
        releaseWake()
        try {
            ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
        } catch (_: Throwable) {
        }
        stopSelf()
    }

    /* ------------------------------- ringing ------------------------------ */

    private fun startRinging() {
        stopRinging()
        try {
            val uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
                ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
            val r = RingtoneManager.getRingtone(applicationContext, uri) ?: return
            r.audioAttributes = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_ALARM)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                r.isLooping = true
            }
            r.play()
            ringtone = r
        } catch (_: Throwable) {
        }
        // Keep the CPU awake so the ringtone is not starved while the screen is
        // off on aggressive OEM battery managers.
        try {
            if (wakeLock == null) {
                val pm = getSystemService(Context.POWER_SERVICE) as? PowerManager
                wakeLock = pm?.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "DropOff:orderAlert")?.apply {
                    setReferenceCounted(false)
                    acquire(RING_TIMEOUT_MS + 5_000L)
                }
            }
        } catch (_: Throwable) {
        }
    }

    private fun stopRinging() {
        try {
            ringtone?.stop()
        } catch (_: Throwable) {
        }
        ringtone = null
    }

    private fun releaseWake() {
        try {
            if (wakeLock?.isHeld == true) wakeLock?.release()
        } catch (_: Throwable) {
        }
        wakeLock = null
    }

    private fun startVibrating() {
        stopVibrating()
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val manager = getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager
                vibrator = manager?.defaultVibrator
            } else {
                @Suppress("DEPRECATION")
                vibrator = getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
            }
            // 0 = repeat from the start until cancelled.
            val pattern = longArrayOf(0, 900, 450, 900, 450, 1200, 700)
            vibrator?.vibrate(VibrationEffect.createWaveform(pattern, 0))
        } catch (_: Throwable) {
        }
    }

    private fun stopVibrating() {
        try {
            vibrator?.cancel()
        } catch (_: Throwable) {
        }
        vibrator = null
    }

    /* ----------------------------- notification --------------------------- */

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager ?: return
        val existing = manager.getNotificationChannel(CHANNEL_ID)
        if (existing == null) {
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "DropOff — New orders", NotificationManager.IMPORTANCE_HIGH).apply {
                    description = "A new delivery is waiting — opens straight to your Task Queue."
                    enableVibration(true)
                    setBypassDnd(true)
                },
            )
        }
    }

    private fun flags(): Int =
        PendingIntent.FLAG_UPDATE_CURRENT or
            (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0)

    private fun buildNotification(
        ref: String,
        title: String,
        body: String,
        address: String,
        eta: String,
        fee: String,
    ): Notification {
        val openIntent = MainActivity.orderActionIntent(this, "open", ref)
        val openPi = PendingIntent.getActivity(this, 1000, openIntent, flags())
        val acceptPi = PendingIntent.getActivity(this, 1001, MainActivity.orderActionIntent(this, "accept", ref), flags())
        val declinePi = PendingIntent.getActivity(this, 1002, MainActivity.orderActionIntent(this, "decline", ref), flags())

        // Premium, brand-led copy. The old heads-up echoed whatever the push
        // payload said and, with an undecodable large icon, Android labelled
        // the curtain "System". A real logo plus an explicit DropOff title
        // makes it read like a flagship phone's incoming-call screen.
        val stripPrefix = Regex("^DropOff\\s*[-:]\\s*", RegexOption.IGNORE_CASE)
        val cleanBody = body.trim().replace(stripPrefix, "")
        val cleanTitle = title.trim().replace(stripPrefix, "")
        val detail = cleanBody.ifEmpty { cleanTitle.ifEmpty { "Tap accept to claim this delivery." } }
        val summary = if (ref.isNotEmpty()) "Rider  -  $ref" else "DropOff  -  New order"
        val text = buildString {
            append("A new pickup is waiting.\n")
            append(detail).append('\n')
            if (address.isNotEmpty()) append("Pickup  -  ").append(address).append('\n')
            if (eta.isNotEmpty()) append("Arrival  -  ").append(eta).append(" min")
        }.trimEnd()

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_dropoff)
            .setLargeIcon(BitmapFactory.decodeResource(resources, R.drawable.ic_notification_large))
            .setContentTitle("DropOff  -  New order ready")
            .setContentText("A pickup is waiting. Accept to claim it.")
            .setSubText("We carry it to the courier")
            .setTicker("DropOff - New order ready")
            .setStyle(NotificationCompat.BigTextStyle()
                .bigText(text)
                .setBigContentTitle("DropOff  -  New order ready")
                .setSummaryText(summary))
            .setColor(Color.parseColor("#123C32"))
            .setColorized(true)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setOngoing(true)
            .setAutoCancel(false)
            .setOnlyAlertOnce(true)
            .setShowWhen(true)
            .setWhen(System.currentTimeMillis())
            .setFullScreenIntent(openPi, true)
            .setContentIntent(openPi)
            .addAction(0, "Accept", acceptPi)
            .addAction(0, "Decline", declinePi)
            .build()
    }
}
