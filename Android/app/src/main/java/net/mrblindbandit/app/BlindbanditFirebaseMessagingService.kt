package net.mrblindbandit.app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

/**
 * Receives Blindbandit call and message alerts from Firebase Cloud Messaging. The token is stored
 * locally and registered with the Blindbandit API by MainActivity once the user is signed in.
 */
class BlindbanditFirebaseMessagingService : FirebaseMessagingService() {
    override fun onNewToken(token: String) {
        super.onNewToken(token)
        getSharedPreferences(AndroidAppPreferences.FILE, MODE_PRIVATE).edit().putString("fcmToken", token).apply()
    }

    override fun onMessageReceived(message: RemoteMessage) {
        super.onMessageReceived(message)
        val prefs = getSharedPreferences(AndroidAppPreferences.FILE, MODE_PRIVATE)
        val payload = net.mrblindbandit.app.connect.PushPayload.parse(message.data)
        val notificationId = payload.key.hashCode()
        if (payload.endsCall) {
            NotificationManagerCompat.from(this).cancel(payload.key, notificationId)
            // App-scoped broadcast: other apps cannot forge a call-end event.
            sendBroadcast(Intent(ACTION_CALL_ENDED).setPackage(packageName).putExtra("call_id", payload.callId))
            return
        }
        val isCall = payload.isCall
        if (isCall && !prefs.getBoolean("notifyCalls", true)) return
        if (!isCall && !prefs.getBoolean("notifyMessages", true)) return

        val title = message.notification?.title ?: message.data["title"] ?: if (isCall) "Incoming call" else "New message"
        val hidePreview = prefs.getBoolean("hideMessagePreviews", true) || message.data["e2ee"] in setOf("true", "1")
        val body = if (!isCall && hidePreview) "New message" else message.notification?.body ?: message.data["body"].orEmpty()
        val link = message.data["url"] ?: message.data["deep_link"]?.let { if (it.startsWith("/")) "https://mrblindbandit.net$it" else it }

        ensureChannels(this)
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            if (link != null && UrlPolicy.isFirstParty(link)) data = Uri.parse(link)
            action = "net.mrblindbandit.app.OPEN.${payload.key}"
            payload.conversationId?.let { putExtra("conversation_id", it) }
            payload.groupId?.let { putExtra("group_id", it) }
            payload.callId?.let { putExtra("call_id", it) }
        }
        val pending = PendingIntent.getActivity(this, notificationId, intent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val notification = NotificationCompat.Builder(this, if (isCall) CHANNEL_CALLS else CHANNEL_MESSAGES)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(if (!isCall && hidePreview) "BlindBandit" else title)
            .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
            .setContentText(body)
            .setAutoCancel(true)
            .setTimeoutAfter(if (isCall) 45_000L else 0L)
            .setContentIntent(pending)
            .setCategory(if (isCall) NotificationCompat.CATEGORY_CALL else NotificationCompat.CATEGORY_MESSAGE)
            .setPriority(if (isCall) NotificationCompat.PRIORITY_HIGH else NotificationCompat.PRIORITY_DEFAULT)
            .build()
        val canNotify = android.os.Build.VERSION.SDK_INT < 33 ||
            androidx.core.content.ContextCompat.checkSelfPermission(this, android.Manifest.permission.POST_NOTIFICATIONS) == android.content.pm.PackageManager.PERMISSION_GRANTED
        if (!canNotify) return
        try {
            NotificationManagerCompat.from(this).notify(payload.key, notificationId, notification)
        } catch (_: SecurityException) {
            // Permission was revoked between the check and the post.
        }
    }

    companion object {
        const val ACTION_CALL_ENDED = "net.mrblindbandit.app.CALL_ENDED"
        const val CHANNEL_MESSAGES = "messages"
        const val CHANNEL_CALLS = "calls"

        fun ensureChannels(context: Context) {
            val manager = context.getSystemService(NotificationManager::class.java) ?: return
            manager.createNotificationChannel(NotificationChannel(CHANNEL_MESSAGES, "Messages", NotificationManager.IMPORTANCE_DEFAULT).apply {
                description = "New messages from people on Blindbandit"
            })
            manager.createNotificationChannel(NotificationChannel(CHANNEL_CALLS, "Calls", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "Incoming voice and video calls"
            })
        }
    }
}
