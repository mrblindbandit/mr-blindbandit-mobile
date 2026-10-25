package net.mrblindbandit.app.connect

import android.content.Context

/**
 * Maps BlindBandit call numbers ↔ handles for the native Dialer.
 * Local SharedPreferences until/alongside server call-number APIs.
 */
class CallNumberDirectory(context: Context) {
    private val prefs = context.applicationContext.getSharedPreferences("bb_call_numbers", Context.MODE_PRIVATE)

    fun normalize(raw: String): String = raw.filter { it in "0123456789*#" }

    var myCallNumber: String
        get() = prefs.getString(MY_KEY, "").orEmpty()
        set(value) {
            prefs.edit().putString(MY_KEY, normalize(value)).apply()
        }

    private fun map(): MutableMap<String, String> {
        val raw = prefs.getString(MAP_KEY, "") ?: ""
        if (raw.isBlank()) return mutableMapOf()
        return raw.split('\n').mapNotNull { line ->
            val i = line.indexOf('=')
            if (i <= 0) null else line.substring(0, i) to line.substring(i + 1)
        }.toMap().toMutableMap()
    }

    private fun saveMap(m: Map<String, String>) {
        prefs.edit().putString(MAP_KEY, m.entries.joinToString("\n") { "${it.key}=${it.value}" }).apply()
    }

    fun assign(number: String, handle: String) {
        val n = normalize(number)
        val h = normalizeHandle(handle)
        if (n.isBlank() || h.isBlank()) return
        val m = map().filterValues { !it.equals(h, ignoreCase = true) }.toMutableMap()
        m[n] = h
        saveMap(m)
    }

    fun unassign(number: String) {
        val m = map()
        m.remove(normalize(number))
        saveMap(m)
    }

    fun numberForHandle(handle: String): String? {
        val h = normalizeHandle(handle)
        return map().entries.firstOrNull { it.value.equals(h, ignoreCase = true) }?.key
    }

    /** Resolve dialed digits to a BlindBandit handle, or null if unknown locally. */
    fun resolve(digits: String): String? {
        val n = normalize(digits)
        if (n.isBlank()) return null
        val m = map()
        m[n]?.let { return it }
        if (n.startsWith("1") && n.length == 11) m[n.drop(1)]?.let { return it }
        m["1$n"]?.let { return it }
        return null
    }

    fun allAssignments(): List<Pair<String, String>> =
        map().entries.sortedBy { it.key }.map { it.key to it.value }

    companion object {
        private const val MAP_KEY = "bb.callNumber.map"
        private const val MY_KEY = "bb.callNumber.mine"
    }
}
