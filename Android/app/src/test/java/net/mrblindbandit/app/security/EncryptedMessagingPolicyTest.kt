package net.mrblindbandit.app.security

import kotlinx.coroutines.runBlocking
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class EncryptedMessagingPolicyTest {
    private class Memory : SecretStore {
        private val values = mutableMapOf<String, String>()
        override fun get(name: String) = values[name]
        override fun put(name: String, value: String?) { if (value == null) values.remove(name) else values[name] = value }
    }
    private fun client(): EncryptedMessaging {
        val bob = E2EEEngine(Memory()).registration()
        return EncryptedMessaging(E2EEEngine(Memory()), "alice") { path, _, _ ->
            when {
                path == "/v1/social/keys/bundles/bob" -> JSONObject().put("devices", JSONArray().put(bob))
                path.startsWith("/v1/social/keys/bundles/") -> JSONObject().put("devices", JSONArray())
                path.endsWith("/prekeys/count") -> JSONObject().put("count", 30)
                else -> JSONObject()
            }
        }
    }
    @Test fun mixedLegacyGroupCannotDowngradeEncryptedPeerInEitherOrder() = runBlocking {
        for (handles in listOf(listOf("legacy", "bob"), listOf("bob", "legacy"))) {
            val client = client()
            val payload = JSONObject().put("t", "text").put("body", "hello")
            assertTrue(client.fields(listOf("@BOB"), payload)!!.getBoolean("e2ee"))
            assertThrows(IllegalStateException::class.java) { runBlocking { client.fields(handles, payload) } }
        }
    }
    @Test fun genuinelyLegacyPeerRetainsExistingCompatibility() = runBlocking {
        assertNull(client().fields(listOf("legacy"), JSONObject().put("t", "text").put("body", "hello")))
    }
    @Test fun onlySuccessfullyDecryptedCallControlsReachKeyStore() = runBlocking {
        var registration: JSONObject? = null
        val receiver = EncryptedMessaging(E2EEEngine(Memory()), "bob") { path, _, body ->
            if (path == "/v1/social/keys/devices") registration = body
            JSONObject()
        }
        receiver.bootstrap()
        val sender = E2EEEngine(Memory())
        val key = CallFrameKeys.newKey("call-a")
        val env = sender.encrypt(JSONObject().put("t", "call_key").put("body", key.wire()),
            listOf(sender.bundle(requireNotNull(registration), "bob")))
        val row = JSONObject().put("id", "control-message").put("sender_id", "alice-profile")
            .put("created_at", 1000).put("e2ee", true).put("envelope", env)
        val damaged = JSONObject(row.toString())
        damaged.getJSONObject("envelope").put("ciphertext", P256Crypto.b64(P256Crypto.random(272)))
        assertTrue(receiver.resolve(damaged)!!.decryptFailed)
        assertNull(receiver.callKeys.get("call-a", "alice-profile"))
        assertNull(receiver.resolve(row))
        assertEquals(key.secret, receiver.callKeys.get("call-a", "alice-profile")?.secret)
        assertNull(receiver.callKeys.get("call-a", "another-profile"))
    }

}
