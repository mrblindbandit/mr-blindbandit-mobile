package net.mrblindbandit.app.androidonly

import android.app.NotificationChannel
import android.app.NotificationChannelGroup
import android.app.NotificationManager
import android.content.Context
import android.os.Build
import net.mrblindbandit.app.BlindbanditFirebaseMessagingService

/**
 * Extra Android notification channels (iOS has no channel model): AI replies, music, security.
 * Keeps Calls/Messages as defined by BlindbanditFirebaseMessagingService.
 */
object NotificationChannels {
    const val CHANNEL_AI = "ai"
    const val CHANNEL_MUSIC = "music"
    const val CHANNEL_SECURITY = "security"
    const val GROUP_MAIN = "bb_main"

    fun ensure(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val mgr = context.getSystemService(NotificationManager::class.java) ?: return
        BlindbanditFirebaseMessagingService.ensureChannels(context)
        mgr.createNotificationChannelGroup(NotificationChannelGroup(GROUP_MAIN, "Mr. BlindBandit"))
        fun ch(id: String, name: String, importance: Int, desc: String) =
            NotificationChannel(id, name, importance).apply {
                description = desc; group = GROUP_MAIN
            }
        mgr.createNotificationChannel(ch(CHANNEL_AI, "AI assistant", NotificationManager.IMPORTANCE_DEFAULT,
            "Spoken replies and AI status. Not used for chat content."))
        mgr.createNotificationChannel(ch(CHANNEL_MUSIC, "Music", NotificationManager.IMPORTANCE_LOW,
            "YouTube Music control feedback."))
        mgr.createNotificationChannel(ch(CHANNEL_SECURITY, "Security", NotificationManager.IMPORTANCE_HIGH,
            "Encryption passcode and key-change alerts."))
    }
}
