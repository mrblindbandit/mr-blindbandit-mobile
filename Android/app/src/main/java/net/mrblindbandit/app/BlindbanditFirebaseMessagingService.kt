package net.mrblindbandit.app

import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

/** FCM scaffold — wire token registration to the authenticated backend before production push. */
class BlindbanditFirebaseMessagingService : FirebaseMessagingService() {
    override fun onNewToken(token: String) {
        super.onNewToken(token)
        getSharedPreferences("blindbandit_app", MODE_PRIVATE)
            .edit()
            .putString("fcmToken", token)
            .apply()
    }

    override fun onMessageReceived(message: RemoteMessage) {
        super.onMessageReceived(message)
        // Display notifications via system tray when app is backgrounded; extend for deep links.
    }
}
