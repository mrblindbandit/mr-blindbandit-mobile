package net.mrblindbandit.app.androidonly

import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification

/**
 * Optional notification listener so MediaSessionManager can list active sessions (YouTube Music now-playing).
 * User must enable it in system settings; the app never reads other apps' notification text.
 */
class BlindbanditNotificationListener : NotificationListenerService() {
    override fun onNotificationPosted(sbn: StatusBarNotification?) { /* unused */ }
    override fun onNotificationRemoved(sbn: StatusBarNotification?) { /* unused */ }
}
