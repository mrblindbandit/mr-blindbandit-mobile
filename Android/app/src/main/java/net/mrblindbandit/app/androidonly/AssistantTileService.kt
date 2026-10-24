package net.mrblindbandit.app.androidonly

import android.app.PendingIntent
import android.content.Intent
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import net.mrblindbandit.app.MainActivity

/** Quick Settings tile: open AI assistant. Android-only affordance iOS cannot offer. */
class AssistantTileService : TileService() {
    override fun onStartListening() {
        qsTile?.apply {
            label = "AI assistant"
            contentDescription = "Open Mr. BlindBandit AI assistant"
            state = Tile.STATE_INACTIVE
            updateTile()
        }
    }
    override fun onClick() {
        val intent = Intent(this, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            .putExtra("open_assistant", true)
        val pi = PendingIntent.getActivity(this, 42, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        if (Build.VERSION.SDK_INT >= 34) startActivityAndCollapse(pi)
        else {
            @Suppress("DEPRECATION")
            startActivityAndCollapse(intent)
        }
    }
}
