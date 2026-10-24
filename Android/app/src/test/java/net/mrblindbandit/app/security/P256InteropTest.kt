package net.mrblindbandit.app.security

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class P256InteropTest {
    private val c = P256Crypto
    private fun vectors() = JSONObject(requireNotNull(javaClass.classLoader!!.getResourceAsStream("p256-v1.json")).bufferedReader().use { it.readText() })
    @Test fun iosVectorDhKdfSignaturesAndEnvelope() {
        val v = vectors(); val a = v.getJSONObject("keys").getJSONObject("alice"); val b = v.getJSONObject("keys").getJSONObject("bob")
        val ad = c.privateKey(c.hex(a.getString("dh_priv_hex"))); val ek = c.privateKey(c.hex(a.getString("ek_priv_hex")))
        val spk = c.unb64(b.getString("spk_pub")); val opk = c.unb64(b.getString("opk_pub"))
        val dh1 = c.dh(ad, spk); val dh2 = c.dh(ek, c.unb64(b.getString("dh_pub"))); val dh3 = c.dh(ek, spk); val dh4 = c.dh(ek, opk)
        val x = v.getJSONObject("x3dh")
        listOf(dh1, dh2, dh3, dh4).forEachIndexed { i, bytes -> assertEquals(x.getString("dh${i+1}"), c.b64(bytes)) }
        val sk = c.hkdf(dh1 + dh2 + dh3 + dh4, c.unb64(x.getString("info")))
        assertEquals(x.getString("sk"), c.b64(sk))
        assertTrue(c.verify(c.unb64(b.getString("spk_sig")), spk, c.unb64(b.getString("sign_pub"))))
        val m = v.getJSONObject("message"); val env = m.getJSONObject("envelope"); val entry = env.getJSONArray("keys").getJSONObject(0)
        val wrapAd = "bb1".toByteArray() + c.unb64(a.getString("sign_pub")) + c.unb64(b.getString("sign_pub"))
        val cek = c.open(c.unb64(entry.getString("wrapped")), c.step(sk).first, c.unb64(entry.getString("nonce")), wrapAd)
        assertEquals(m.getString("cek"), c.b64(cek))
        val plain = c.unpad(c.open(c.unb64(env.getString("ciphertext")), cek, c.unb64(env.getString("nonce")), m.getString("content_ad").toByteArray()))
        assertEquals(m.getString("payload_json"), plain.toString(Charsets.UTF_8))
        assertEquals(env.getString("ciphertext"), c.b64(c.seal(c.pad(plain), cek, c.unb64(env.getString("nonce")), m.getString("content_ad").toByteArray())))
    }
    private class Memory : SecretStore {
        val values = mutableMapOf<String, String>()
        override fun get(name: String) = values[name]
        override fun put(name: String, value: String?) { if (value == null) values.remove(name) else values[name] = value }
    }
    @Test fun engineRoundTripRestartTamperAndPrekeyConsumption() {
        val aStore = Memory(); val bStore = Memory()
        val alice = E2EEEngine(aStore); var bob = E2EEEngine(bStore)
        val registration = bob.registration().put("one_time_prekey", bob.pendingPrekeys().getString(0))
        val bundle = alice.bundle(registration, "bob")
        val payload = JSONObject().put("t", "text").put("body", "Kumusta 🌍")
        val env = alice.encrypt(payload, listOf(bundle))
        val damaged = JSONObject(env.toString()).put("ciphertext", c.b64(c.random(272)))
        assertThrows(Exception::class.java) { bob.decrypt(damaged, "alice") }
        assertEquals("Kumusta 🌍", bob.decrypt(env, "alice").getString("body"))
        bob = E2EEEngine(bStore)
        assertEquals("Kumusta 🌍", bob.decrypt(env, "alice").getString("body"))
        assertThrows(Exception::class.java) { bob.decrypt(damaged, "alice") }
        // A changed signing identity on the same registered device is rejected.
        val changed = JSONObject(registration.toString()).put("identity_key", alice.registration().getString("identity_key"))
        assertThrows(Exception::class.java) { alice.bundle(changed, "bob") }
    }
    @Test fun safetyNumberMatchesIos() {
        val v = vectors(); val keys = v.getJSONObject("keys")
        assertEquals(v.getJSONObject("safety_number").getString("display"), SafetyNumber.display("alice", listOf(c.unb64(keys.getJSONObject("alice").getString("sign_pub"))), "bob", listOf(c.unb64(keys.getJSONObject("bob").getString("sign_pub")))))
    }
    @Test fun attachmentMatchesIosDigestAndRejectsTamper() {
        val a = vectors().getJSONObject("attachment")
        val plain = ByteArray(a.getInt("plain_len")) { (it * 7).toByte() }
        val sealed = AttachmentCrypto.seal(plain, c.unb64(a.getString("key")), c.unb64(a.getString("base_nonce")))
        assertEquals(a.getInt("blob_len"), sealed.blob.size)
        assertArrayEquals(c.hex(a.getString("sha256_hex")), sealed.digest)
        assertArrayEquals(plain, AttachmentCrypto.open(sealed.blob, sealed.key, sealed.nonce, plain.size, sealed.digest))
        sealed.blob[0] = (sealed.blob[0].toInt() xor 1).toByte()
        assertThrows(IllegalArgumentException::class.java) { AttachmentCrypto.open(sealed.blob, sealed.key, sealed.nonce, plain.size, sealed.digest) }
    }
    @Test fun paddingBoundariesAndAadTamper() {
        val v = vectors().getJSONArray("padding")
        for (i in 0 until v.length()) { val row = v.getJSONObject(i); val plain = ByteArray(row.getInt("len")) { 42 }; assertEquals(row.getInt("padded_len"), c.pad(plain).size); assertArrayEquals(plain, c.unpad(c.pad(plain))) }
        val key = c.random(32); val nonce = c.random(12); val ct = c.seal(byteArrayOf(1), key, nonce, byteArrayOf(3))
        assertThrows(Exception::class.java) { c.open(ct, key, nonce, byteArrayOf(4)) }
        assertThrows(IllegalArgumentException::class.java) { c.unpad(ByteArray(256)) }
    }
}
