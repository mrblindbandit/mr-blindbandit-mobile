package net.mrblindbandit.app

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import net.mrblindbandit.app.connect.LocalComms
import net.mrblindbandit.app.security.SecureLocalStore
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.util.UUID

@RunWith(AndroidJUnit4::class)
class SecureStorageInstrumentedTest {
    @Test fun keystoreRoundTripAndTamperRejection() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val namespace = "instrumentation.${UUID.randomUUID()}"
        val store = SecureLocalStore(context, namespace)
        try {
            store.put("message", "private message")
            assertEquals("private message", SecureLocalStore(context, namespace).get("message"))
            val prefs = context.getSharedPreferences("bb_secure_$namespace", Context.MODE_PRIVATE)
            val encoded = prefs.getString("message", null)!!
            assertFalse(encoded.contains("private message"))
            val raw = java.util.Base64.getDecoder().decode(encoded)
            raw[raw.lastIndex] = (raw.last().toInt() xor 1).toByte()
            prefs.edit().putString("message", java.util.Base64.getEncoder().encodeToString(raw)).commit()
            assertThrows(Exception::class.java) { store.get("message") }
        } finally { store.clear() }
    }
    @Test fun accountDraftsRemainSeparateAcrossRestart() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val a = "instrumentation-a-${UUID.randomUUID()}"
        val b = "instrumentation-b-${UUID.randomUUID()}"
        val first = LocalComms(context).apply { bindAccount(a) }
        val second = LocalComms(context).apply { bindAccount(b) }
        try {
            first.setDraft("thread", "Account A draft")
            assertEquals("", second.draft("thread"))
            second.setDraft("thread", "Account B draft")
            assertEquals("Account A draft", LocalComms(context).apply { bindAccount(a) }.draft("thread"))
            assertEquals("Account B draft", LocalComms(context).apply { bindAccount(b) }.draft("thread"))
        } finally { first.clearAll(); second.clearAll() }
    }
}
