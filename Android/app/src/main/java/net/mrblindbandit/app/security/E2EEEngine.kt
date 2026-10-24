package net.mrblindbandit.app.security

import android.content.Context
import java.security.KeyFactory
import java.security.KeyPair
import java.security.spec.PKCS8EncodedKeySpec
import java.util.UUID
import org.json.JSONArray
import org.json.JSONObject

/** Account-scoped p256-v1 engine. Commit inbound state only after BOTH GCM tags authenticate. */
class E2EEEngine(private val store: SecretStore) {
    constructor(context: Context, accountId: String) : this(SecureLocalStore(context, "e2ee." + P256Crypto.b64(P256Crypto.sha256(accountId.toByteArray()))))
    private val c get() = P256Crypto
    private var state = store.get("state")?.let(::JSONObject) ?: JSONObject().also { root ->
        root.put("device", UUID.randomUUID().toString().lowercase())
        root.put("sign", encodePair(c.generate())).put("dh", encodePair(c.generate()))
        root.put("spk", encodePair(c.generate())).put("spk_id", 1)
        root.put("inbound", JSONObject()).put("cache", JSONObject()).put("pins", JSONObject())
        root.put("opks", JSONObject()).put("next_opk", 1)
        store.put("state", root.toString())
    }
    val deviceId get() = state.getString("device")
    val signPublic get() = c.unb64(state.getJSONObject("sign").getString("pub"))
    private val dh get() = pair(state.getJSONObject("dh"))
    private fun encodePair(p: KeyPair) = JSONObject().put("priv", c.b64(p.private.encoded)).put("pub", c.b64(c.publicBytes(p.public)))
    private fun pair(o: JSONObject): KeyPair = KeyPair(c.publicKey(c.unb64(o.getString("pub"))), KeyFactory.getInstance("EC").generatePrivate(PKCS8EncodedKeySpec(c.unb64(o.getString("priv")))))
    private fun save(next: JSONObject = state) { store.put("state", next.toString()); state = next }

    fun registration(): JSONObject {
        val pub = c.publicBytes(pair(state.getJSONObject("spk")).public)
        return JSONObject().put("device_id", deviceId).put("device_label", "BlindBandit Android")
            .put("identity_key", c.b64(signPublic + c.publicBytes(dh.public)))
            .put("signed_prekey", c.packed(state.getInt("spk_id"), pub))
            .put("signed_prekey_sig", c.b64(c.sign(pub, pair(state.getJSONObject("sign")).private)))
    }
    val registered get() = state.optBoolean("registered")
    fun markRegistered() { state.put("registered", true); save() }
    /** Store private halves durably before their public halves leave the device. Retry uploads with the same ids. */
    fun pendingPrekeys(): JSONArray {
        val pending = state.optJSONArray("pending_prekeys")
        if (pending != null) return pending
        val keys = state.getJSONObject("opks")
        val out = JSONArray()
        repeat(30) {
            val id = state.getInt("next_opk"); state.put("next_opk", id + 1)
            val p = c.generate(); keys.put(id.toString(), encodePair(p)); out.put(c.packed(id, c.publicBytes(p.public)))
        }
        state.put("pending_prekeys", out); save(); return out
    }
    fun markPrekeysUploaded() { state.remove("pending_prekeys"); save() }
    fun hasEncrypted(handle: String) = state.optJSONObject("encrypted")?.optBoolean(handle.lowercase()) == true
    fun markEncrypted(handle: String) {
        val all = state.optJSONObject("encrypted") ?: JSONObject().also { state.put("encrypted", it) }
        all.put(handle.lowercase(), true); save()
    }
    data class Bundle(val device: String, val sign: ByteArray, val dh: ByteArray, val spkId: Int, val spk: ByteArray, val opk: Pair<Int, ByteArray>?, val handle: String)
    fun bundle(row: JSONObject, handle: String): Bundle {
        val identity = row.optString("identity_key").takeIf { it.isNotBlank() }?.let(c::unb64)
        val sign = identity?.let { require(it.size == 130); it.copyOfRange(0, 65) } ?: c.unb64(row.getString("identity_sign_pub"))
        val dhPub = identity?.copyOfRange(65, 130) ?: c.unb64(row.getString("identity_dh_pub"))
        val spk = row.optJSONObject("signed_prekey")
        val (spkId, spkPub) = if (spk != null) spk.getInt("id") to c.unb64(spk.getString("pub")) else c.unpack(row.getString("signed_prekey"))
        val sig = if (spk != null) spk.getString("sig") else row.getString("signed_prekey_sig")
        require(c.verify(c.unb64(sig), spkPub, sign)) { "Invalid device prekey signature" }
        val opkObject = row.optJSONObject("prekey") ?: row.optJSONObject("one_time_prekey")
        val opk = if (opkObject != null) opkObject.getInt("id") to c.unb64(opkObject.getString("pub"))
            else row.optString("one_time_prekey").takeIf { it.isNotBlank() && it != "null" }?.let(c::unpack)
        val device = row.getString("device_id")
        val pinKey = "$handle:$device"
        val pins = state.getJSONObject("pins")
        val pub = c.b64(sign)
        require(!pins.has(pinKey) || pins.getString(pinKey) == pub) { "Encryption identity changed for @$handle. Verify their device before sending." }
        pins.put(pinKey, pub); save()
        return Bundle(device, sign, dhPub, spkId, spkPub, opk, handle)
    }

    /** Fresh ephemeral sender session per message; interoperates with iOS' receiving chain at n=0. */
    fun encrypt(payload: JSONObject, recipients: List<Bundle>, messageId: String = UUID.randomUUID().toString().lowercase()): JSONObject {
        require(recipients.isNotEmpty() && recipients.size <= 64)
        val cek = c.random(32); val nonce = c.random(12)
        val ad = "bb1:$messageId:$deviceId".toByteArray()
        val ciphertext = c.seal(c.pad(payload.toString().toByteArray()), cek, nonce, ad)
        val entries = JSONArray()
        for (peer in recipients.distinctBy { it.device }.filter { it.device != deviceId }) {
            val ek = c.generate()
            var ikm = c.dh(dh.private, peer.spk) + c.dh(ek.private, peer.dh) + c.dh(ek.private, peer.spk)
            peer.opk?.let { ikm += c.dh(ek.private, it.second) }
            val chain = c.hkdf(ikm, ("BB-X3DH-v1" + deviceId + peer.device).toByteArray())
            val header = JSONObject().put("ek", c.b64(c.publicBytes(ek.public))).put("spk_id", peer.spkId)
                .put("ik", c.b64(c.publicBytes(dh.public))).put("isk", c.b64(signPublic))
            peer.opk?.let { header.put("opk_id", it.first) }
            val wrapNonce = c.random(12)
            entries.put(JSONObject().put("device_id", peer.device).put("handle", peer.handle).put("prekey", header)
                .put("n", 0).put("pn", 0).put("nonce", c.b64(wrapNonce))
                .put("wrapped", c.b64(c.seal(cek, c.step(chain).first, wrapNonce, "bb1".toByteArray() + signPublic + peer.sign))))
        }
        require(entries.length() > 0)
        val env = JSONObject().put("v", 1).put("suite", P256Crypto.SUITE).put("type", "msg").put("sender_device_id", deviceId)
            .put("msg_id", messageId).put("nonce", c.b64(nonce)).put("ciphertext", c.b64(ciphertext)).put("keys", entries)
        cache(state, env, payload); save(); return env
    }
    private fun cache(root: JSONObject, env: JSONObject, payload: JSONObject) {
        root.getJSONObject("cache").put(env.getString("msg_id"), JSONObject().put("payload", payload)
            .put("digest", c.b64(c.sha256(env.getString("ciphertext").toByteArray()))))
    }
    fun decrypt(env: JSONObject, senderProfileId: String): JSONObject {
        require(env.getInt("v") == 1 && env.getString("suite") == P256Crypto.SUITE && env.optString("type", "msg") == "msg")
        val mid = env.getString("msg_id")
        state.getJSONObject("cache").optJSONObject(mid)?.let { cached ->
            require(cached.getString("digest") == c.b64(c.sha256(env.getString("ciphertext").toByteArray()))) { "Modified encrypted message" }
            return cached.getJSONObject("payload")
        }
        val entries = env.getJSONArray("keys")
        val entry = (0 until entries.length()).map { entries.getJSONObject(it) }.firstOrNull { it.getString("device_id") == deviceId }
            ?: error("This message was not encrypted for this device")
        val h = entry.getJSONObject("prekey"); val ek = h.getString("ek"); val sender = env.getString("sender_device_id")
        val next = JSONObject(state.toString())
        val sessionKey = "$sender|$ek"
        val sessions = next.getJSONObject("inbound")
        var session = sessions.optJSONObject(sessionKey)
        var opkId: String? = null
        if (session == null) {
            require(h.getInt("spk_id") == next.getInt("spk_id")) { "Unknown signed prekey" }
            val spk = pair(next.getJSONObject("spk")); val ekPub = c.unb64(ek)
            var ikm = c.dh(spk.private, c.unb64(h.getString("ik"))) + c.dh(dh.private, ekPub) + c.dh(spk.private, ekPub)
            if (h.has("opk_id")) {
                opkId = h.getInt("opk_id").toString()
                ikm += c.dh(pair(next.getJSONObject("opks").getJSONObject(opkId)).private, ekPub)
            }
            val sk = c.hkdf(ikm, ("BB-X3DH-v1" + sender + deviceId).toByteArray())
            session = JSONObject().put("ck", c.b64(sk)).put("n", 0).put("skipped", JSONObject())
        }
        val index = entry.getInt("n"); var n = session.getInt("n")
        require(index >= 0 && index.toLong() - n <= 200) { "Message too far out of order" }
        val skipped = session.getJSONObject("skipped"); val now = System.currentTimeMillis()
        skipped.keys().asSequence().toList().forEach { key -> if (now - skipped.getJSONObject(key).getLong("at") > 7 * 86400_000L) skipped.remove(key) }
        val mk: ByteArray
        if (index < n) {
            mk = c.unb64(skipped.getJSONObject(index.toString()).getString("key")); skipped.remove(index.toString())
        } else {
            var ck = c.unb64(session.getString("ck"))
            while (n < index) {
                val (key, nextKey) = c.step(ck)
                skipped.put((n++).toString(), JSONObject().put("key", c.b64(key)).put("at", now)); ck = nextKey
            }
            val step = c.step(ck); mk = step.first; session.put("ck", c.b64(step.second)).put("n", n + 1)
        }
        while (skipped.length() > 200) skipped.remove(skipped.keys().asSequence().minBy { it.toInt() })
        val sign = h.getString("isk")
        val pinKey = "sender:$senderProfileId:$sender"
        val pins = next.getJSONObject("pins")
        require(!pins.has(pinKey) || pins.getString(pinKey) == sign) { "Sender encryption identity changed" }
        val cek = c.open(c.unb64(entry.getString("wrapped")), mk, c.unb64(entry.getString("nonce")), "bb1".toByteArray() + c.unb64(sign) + signPublic)
        val plain = c.unpad(c.open(c.unb64(env.getString("ciphertext")), cek, c.unb64(env.getString("nonce")), "bb1:$mid:$sender".toByteArray()))
        val payload = JSONObject(plain.toString(Charsets.UTF_8))
        pins.put(pinKey, sign); sessions.put(sessionKey, session)
        opkId?.let { next.getJSONObject("opks").remove(it) }
        cache(next, env, payload); save(next)
        return payload
    }
}
