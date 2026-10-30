package net.mrblindbandit.app.connect

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import net.mrblindbandit.app.MainActivity
import net.mrblindbandit.app.R

/**
 * Keeps a voice or video call in the foreground on Android 14+ so microphone capture is allowed
 * to continue. Screen capture is intentionally not a service type.
 */
class CallSessionService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val peer = intent?.getStringExtra(EXTRA_PEER).orEmpty().ifBlank { "Blindbandit" }
        val video = intent?.getBooleanExtra(EXTRA_VIDEO, false) == true
        val notification = notification(this, peer, video)
        try {
            if (Build.VERSION.SDK_INT >= 30) {
                startForeground(NOTIFICATION_ID, notification, types(this, video))
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
            CallLog.i("call foreground service started video=$video")
        } catch (e: Exception) {
            CallLog.e("call foreground service failed ${e.javaClass.simpleName}", e)
            stopSelf()
        }
        return START_NOT_STICKY
    }

    companion object {
        private const val CHANNEL = "call_session"
        private const val NOTIFICATION_ID = 2401
        private const val EXTRA_PEER = "peer"
        private const val EXTRA_VIDEO = "video"

        fun start(context: Context, peer: String, video: Boolean) {
            val mic = ContextCompat.checkSelfPermission(context, android.Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED
            if (!mic) {
                CallLog.w("skip call foreground service: microphone permission missing")
                return
            }
            val intent = Intent(context, CallSessionService::class.java)
                .putExtra(EXTRA_PEER, peer)
                .putExtra(EXTRA_VIDEO, video)
            try {
                ContextCompat.startForegroundService(context, intent)
            } catch (e: Exception) {
                CallLog.e("startForegroundService failed ${e.javaClass.simpleName}", e)
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, CallSessionService::class.java))
        }

        private fun types(context: Context, video: Boolean): Int {
            var types = ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE or ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK
            val camera = video && ContextCompat.checkSelfPermission(context, android.Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED
            if (camera) types = types or ServiceInfo.FOREGROUND_SERVICE_TYPE_CAMERA
            return types
        }

        private fun notification(context: Context, peer: String, video: Boolean): Notification {
            val manager = context.getSystemService(NotificationManager::class.java)
            if (manager?.getNotificationChannel(CHANNEL) == null) {
                manager?.createNotificationChannel(
                    NotificationChannel(CHANNEL, "Ongoing call", NotificationManager.IMPORTANCE_LOW).apply {
                        description = "Shown while a Blindbandit voice or video call is active"
                        setSound(null, null)
                    }
                )
            }
            val open = PendingIntent.getActivity(
                context,
                2402,
                Intent(context, MainActivity::class.java).apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
                    putExtra("call_action", "return")
                },
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
            val kind = if (video) "Video call" else "Voice call"
            return NotificationCompat.Builder(context, CHANNEL)
                .setSmallIcon(R.drawable.ic_notification)
                .setContentTitle(kind)
                .setContentText("In a call with $peer")
                .setCategory(NotificationCompat.CATEGORY_CALL)
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .setContentIntent(open)
                .build()
        }
    }
}
