package net.mrblindbandit.app.connect

import android.util.Log

/**
 * Call-path logs. Never include tokens, certificates, or full app ids.
 * Long opaque strings are stripped so a server error cannot leak a grant into logcat.
 */
internal object CallLog {
    const val TAG = "BlindbanditCall"

    fun i(message: String) {
        Log.i(TAG, sanitize(message))
    }

    fun w(message: String) {
        Log.w(TAG, sanitize(message))
    }

    fun e(message: String, error: Throwable? = null) {
        if (error == null) Log.e(TAG, sanitize(message))
        else Log.e(TAG, sanitize(message), error)
    }

    fun sanitize(message: String): String =
        message.replace(Regex("[A-Za-z0-9_\\-+/=]{24,}"), "…").take(300)
}
