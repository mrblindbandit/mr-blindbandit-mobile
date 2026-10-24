package net.mrblindbandit.app.androidonly

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import net.mrblindbandit.app.MainActivity
import net.mrblindbandit.app.R

/** Home-screen widget: one tap into Messages. Count is best-effort from shared prefs. */
class UnreadWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        val prefs = context.getSharedPreferences("bb_widget", Context.MODE_PRIVATE)
        val unread = prefs.getInt("unread", 0)
        val label = when {
            unread <= 0 -> "Messages"
            unread == 1 -> "1 unread message"
            else -> "$unread unread messages"
        }
        for (id in ids) {
            val views = RemoteViews(context.packageName, R.layout.widget_unread)
            views.setTextViewText(R.id.widget_title, "Mr. BlindBandit")
            views.setTextViewText(R.id.widget_status, label)
            views.setContentDescription(R.id.widget_root, label)
            val open = PendingIntent.getActivity(
                context, id,
                Intent(context, MainActivity::class.java).putExtra("open_messages", true),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            views.setOnClickPendingIntent(R.id.widget_root, open)
            manager.updateAppWidget(id, views)
        }
    }
    companion object {
        fun setUnread(context: Context, count: Int) {
            context.getSharedPreferences("bb_widget", Context.MODE_PRIVATE).edit().putInt("unread", count.coerceAtLeast(0)).apply()
            val intent = Intent(context, UnreadWidgetProvider::class.java).setAction(AppWidgetManager.ACTION_APPWIDGET_UPDATE)
            context.sendBroadcast(intent)
        }
    }
}
