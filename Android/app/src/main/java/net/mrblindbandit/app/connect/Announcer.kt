package net.mrblindbandit.app.connect

import android.content.Context
import android.os.Build
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityManager

/** Sends a TalkBack announcement (no-op when no accessibility service is running). */
object Announcer {
    fun announce(context: Context, text: String) {
        if (text.isBlank()) return
        val manager = context.getSystemService(Context.ACCESSIBILITY_SERVICE) as? AccessibilityManager ?: return
        if (!manager.isEnabled) return
        val event = if (Build.VERSION.SDK_INT >= 30) AccessibilityEvent(AccessibilityEvent.TYPE_ANNOUNCEMENT)
        else @Suppress("DEPRECATION") AccessibilityEvent.obtain(AccessibilityEvent.TYPE_ANNOUNCEMENT)
        event.text.add(text)
        event.packageName = context.packageName
        runCatching { manager.sendAccessibilityEvent(event) }
    }
}
