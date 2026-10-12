package net.mrblindbandit.app.ui

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.widget.Toast

/**
 * Opens a web URL in a real browser. This app declares an https intent filter for mrblindbandit.net,
 * so a plain ACTION_VIEW can resolve back to this app (and do nothing on the sign-in screen).
 * Pick a browser package explicitly, and always give feedback if nothing can open the link.
 */
fun openInBrowser(context: Context, url: String) {
    val uri = Uri.parse(url)
    val base = Intent(Intent.ACTION_VIEW, uri).addCategory(Intent.CATEGORY_BROWSABLE)
        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    val pm = context.packageManager
    val browserProbe = Intent(Intent.ACTION_VIEW, Uri.parse("https://www.w3.org/")).addCategory(Intent.CATEGORY_BROWSABLE)
    val browserPkg = runCatching {
        @Suppress("DEPRECATION")
        val def = pm.resolveActivity(browserProbe, PackageManager.MATCH_DEFAULT_ONLY)?.activityInfo?.packageName
        @Suppress("DEPRECATION")
        val all = pm.queryIntentActivities(browserProbe, 0).map { it.activityInfo.packageName }
        listOfNotNull(def).plus(all).firstOrNull { it != context.packageName && it != "android" }
    }.getOrNull()
    val attempts = listOfNotNull(browserPkg?.let { Intent(base).setPackage(it) }, Intent.createChooser(base, "Open with").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    for (intent in attempts) {
        try {
            context.startActivity(intent)
            return
        } catch (_: ActivityNotFoundException) {
        } catch (_: SecurityException) {
        }
    }
    Toast.makeText(context, "No browser is available. Visit $url", Toast.LENGTH_LONG).show()
}
