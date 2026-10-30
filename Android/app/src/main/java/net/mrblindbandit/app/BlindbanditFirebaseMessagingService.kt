package net.mrblindbandit.app

import android.app.ActivityManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.net.Uri
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.app.Person
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import net.mrblindbandit.app.connect.CallLog
import net.mrblindbandit.app.connect.CallSounds
import net.mrblindbandit.app.connect.CallTelecom

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
            payload.callId?.let { CallTelecom.reportEnded(it) }
            sendBroadcast(Intent(ACTION_CALL_ENDED).setPackage(packageName).putExtra("call_id", payload.callId))
            return
        }
        val isCall = payload.isCall
        if (isCall && !prefs.getBoolean("notifyCalls", true)) return
        if (!isCall && !prefs.getBoolean("notifyMessages", true)) return

        val title = message.notification?.title ?: message.data["title"] ?: if (isCall) "Incoming call" else "New message"
        val hidePreview = prefs.getBoolean("hideMessagePreviews", true) || message.data["e2ee"] in setOf("true", "1")
        val body = if (!isCall && hidePreview) "New message" else message.notification?.body ?: message.data["body"].orEmpty()
        val caller = message.data["from_name"] ?: message.data["from_handle"]?.let { "@$it" } ?: title
        if (isCall) {
            CallLog.i("fcm incoming call idPresent=${!payload.callId.isNullOrBlank()} foreground=${isAppForeground()}")
            payload.callId?.let { CallTelecom.reportIncoming(this, it, caller) }
        }
        val foreground = isAppForeground()
        if (isCall && foreground) {
            sendBroadcast(
                Intent(ACTION_INCOMING_CALL).setPackage(packageName)
                    .putExtra("call_id", payload.callId)
                    .putExtra("caller_name", caller)
                    .putExtra("play_ring", true)
            )
            return
        }

        ensureChannels(this)
        val channel = if (isCall) callChannelId(this) else CHANNEL_MESSAGES
        val content = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            action = "net.mrblindbandit.app.OPEN.${payload.key}"
            payload.conversationId?.let { putExtra("conversation_id", it) }
            payload.groupId?.let { putExtra("group_id", it) }
            payload.callId?.let { putExtra("call_id", it) }
            if (isCall) putExtra("caller_name", caller)
        }
        val pending = PendingIntent.getActivity(this, notificationId, content, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val builder = NotificationCompat.Builder(this, channel)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(if (!isCall && hidePreview) "BlindBandit" else title)
            .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
            .setContentText(if (isCall) "$caller is calling" else body)
            .setAutoCancel(true)
            .setTimeoutAfter(if (isCall) 45_000L else 0L)
            .setContentIntent(pending)
            .setCategory(if (isCall) NotificationCompat.CATEGORY_CALL else NotificationCompat.CATEGORY_MESSAGE)
            .setPriority(if (isCall) NotificationCompat.PRIORITY_MAX else NotificationCompat.PRIORITY_DEFAULT)
        if (isCall) {
            val person = Person.Builder().setName(caller).setImportant(true).build()
            builder.setFullScreenIntent(pending, true)
                .setOngoing(true)
                .addPerson(person)
                .setStyle(NotificationCompat.CallStyle.forIncomingCall(person, declineIntent(payload.callId), answerIntent(payload.callId)))
            sendBroadcast(
                Intent(ACTION_INCOMING_CALL).setPackage(packageName)
                    .putExtra("call_id", payload.callId)
                    .putExtra("caller_name", caller)
                    .putExtra("play_ring", false)
            )
        }
        val canNotify = Build.VERSION.SDK_INT < 33 ||
            androidx.core.content.ContextCompat.checkSelfPermission(this, android.Manifest.permission.POST_NOTIFICATIONS) == android.content.pm.PackageManager.PERMISSION_GRANTED
        if (!canNotify) {
            CallLog.w("notification permission missing; incoming call broadcast only")
            return
        }
        try {
            NotificationManagerCompat.from(this).notify(payload.key, notificationId, builder.build())
        } catch (e: SecurityException) {
            CallLog.w("notify failed ${e.javaClass.simpleName}")
        }
    }

    private fun answerIntent(callId: String?): PendingIntent {
        val intent = Intent(this, MainActivity::class.java).apply {
            action = ACTION_ANSWER_CALL
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra("call_id", callId)
            putExtra("call_action", "answer")
        }
        return PendingIntent.getActivity(this, 7101, intent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
    }

    private fun declineIntent(callId: String?): PendingIntent {
        val intent = Intent(this, MainActivity::class.java).apply {
            action = ACTION_DECLINE_CALL
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra("call_id", callId)
            putExtra("call_action", "decline")
        }
        return PendingIntent.getActivity(this, 7102, intent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
    }

    private fun isAppForeground(): Boolean {
        val manager = getSystemService(ActivityManager::class.java) ?: return false
        val mine = manager.runningAppProcesses?.firstOrNull { it.processName == packageName } ?: return false
        return mine.importance == ActivityManager.RunningAppProcessInfo.IMPORTANCE_FOREGROUND
    }

    companion object {
        const val ACTION_CALL_ENDED = "net.mrblindbandit.app.CALL_ENDED"
        const val ACTION_INCOMING_CALL = "net.mrblindbandit.app.INCOMING_CALL"
        const val ACTION_ANSWER_CALL = "net.mrblindbandit.app.ANSWER_CALL"
        const val ACTION_DECLINE_CALL = "net.mrblindbandit.app.DECLINE_CALL"
        const val CHANNEL_MESSAGES = "messages"
        const val CHANNEL_CALLS = "calls"

        fun callChannelId(context: Context): String {
            val name = CallSounds.selectedRingtoneName(context)
            return "calls_$name"
        }

        fun ensureChannels(context: Context) {
            val manager = context.getSystemService(NotificationManager::class.java) ?: return
            manager.createNotificationChannel(NotificationChannel(CHANNEL_MESSAGES, "Messages", NotificationManager.IMPORTANCE_DEFAULT).apply {
                description = "New messages from people on Blindbandit"
            })
            val ringtone = CallSounds.selectedRingtoneName(context)
            val resId = context.resources.getIdentifier(ringtone, "raw", context.packageName)
            val channel = NotificationChannel(callChannelId(context), "Calls", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "Incoming voice and video calls"
                lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
                if (resId != 0) {
                    val uri = Uri.parse("android.resource://${context.packageName}/$resId")
                    val attrs = AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build()
                    setSound(uri, attrs)
                }
            }
            manager.createNotificationChannel(channel)
            if (manager.getNotificationChannel(CHANNEL_CALLS) == null) {
                manager.createNotificationChannel(NotificationChannel(CHANNEL_CALLS, "Calls", NotificationManager.IMPORTANCE_HIGH).apply {
                    description = "Incoming voice and video calls"
                })
            }
        }
    }
}
