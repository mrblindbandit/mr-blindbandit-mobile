package net.mrblindbandit.app.connect

import android.content.Context
import net.mrblindbandit.app.AndroidAppPreferences
import java.util.UUID

object DeviceIdentity {
    @Synchronized fun installationId(context: Context): String {
        val prefs = context.applicationContext.getSharedPreferences(AndroidAppPreferences.FILE, Context.MODE_PRIVATE)
        return prefs.getString("installationId", null)?.takeIf { it.isNotBlank() }
            ?: UUID.randomUUID().toString().also { check(prefs.edit().putString("installationId", it).commit()) }
    }
}
