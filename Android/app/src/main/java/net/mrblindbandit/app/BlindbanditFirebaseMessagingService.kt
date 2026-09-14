package net.mrblindbandit.app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.core.app.NotificationCompat
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

class BlindbanditFirebaseMessagingService : FirebaseMessagingService() {
    override fun onNewToken(token: String) {
        getSharedPreferences("blindbandit_app", Context.MODE_PRIVATE)
            .edit()
            .putString("fcmDeviceToken", token)
            .apply()
        // Server registration is intentionally not hard-coded here. The production API
        // should bind this token to the signed-in account over authenticated HTTPS.
    }

    override fun onMessageReceived(message: RemoteMessage) {
        val title = message.notification?.title ?: message.data["title"] ?: "Mr. Blindbandit"
        val body = message.notification?.body ?: message.data["body"] ?: "New update available"
        val rawUrl = message.data["url"]?.takeIf { UrlPolicy.isFirstParty(it) } ?: BuildConfig.WEB_BASE_URL

        val manager = getSystemService(NotificationManager::class.java)
        val channel = NotificationChannel(CHANNEL_ID, "Blindbandit updates", NotificationManager.IMPORTANCE_DEFAULT).apply {
            description = "Music, creator tools, account, community, and label updates"
        }
        manager.createNotificationChannel(channel)

        val intent = Intent(this, MainActivity::class.java).apply {
            data = Uri.parse(rawUrl)
            flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            this,
            rawUrl.hashCode(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setAutoCancel(true)
            .setContentIntent(pendingIntent)
            .build()

        manager.notify((System.currentTimeMillis() and 0x7fffffff).toInt(), notification)
    }

    companion object {
        const val CHANNEL_ID = "blindbandit_updates"
    }
}
