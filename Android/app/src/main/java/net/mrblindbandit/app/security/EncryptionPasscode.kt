package net.mrblindbandit.app.security

import android.content.Context
import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.SecretKeyFactory
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.PBEKeySpec
import javax.crypto.spec.SecretKeySpec
import org.json.JSONObject

/**
 * iOS EncryptionPasscode parity: PBKDF2-SHA256 600_000 + AES-256-GCM.
 * Seals the Android identity blob (engine state JSON). Cross-platform restore of the private
 * key material is not possible (iOS CryptoKit raw vs Android PKCS8); the server ciphertext format
 * matches so the same passcode UX and /v1/keys/backup route work on both.
 */
object EncryptionPasscode {
    private const val ITERATIONS = 600_000
    private const val PREFS = "bb_e2ee_passcode"

    fun key(handle: String) = "e2ee.passcodeSet.${handle.lowercase()}"
    fun isSet(context: Context, handle: String) =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getBoolean(key(handle), false)
    fun markSet(context: Context, handle: String) =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putBoolean(key(handle), true).apply()
    fun clearSet(context: Context, handle: String) =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putBoolean(key(handle), false).apply()
    fun isValid(p: String) = p.length >= 6 && p.all { it.isLetterOrDigit() }

    fun derive(pass: String, salt: ByteArray): ByteArray {
        val spec = PBEKeySpec(pass.toCharArray(), salt, ITERATIONS, 256)
        return SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256").generateSecret(spec).encoded
    }

    fun seal(identity: ByteArray, pass: String): JSONObject {
        val salt = ByteArray(16).also { SecureRandom().nextBytes(it) }
        val key = SecretKeySpec(derive(pass, salt), "AES")
        val iv = ByteArray(12).also { SecureRandom().nextBytes(it) }
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key, GCMParameterSpec(128, iv))
        val sealed = cipher.doFinal(identity) // ciphertext||tag
        // CryptoKit AES.GCM.SealedBox.combined = nonce||ciphertext||tag
        val combined = iv + sealed
        return JSONObject()
            .put("ciphertext", P256Crypto.b64(combined))
            .put("kdf", JSONObject()
                .put("v", 1)
                .put("alg", "pbkdf2-sha256")
                .put("iterations", ITERATIONS)
                .put("salt", P256Crypto.b64(salt))
                .put("aead", "aes-256-gcm")
                .put("platform", "android"))
    }

    fun open(backup: JSONObject, pass: String): ByteArray? = runCatching {
        var kdf = backup.optJSONObject("kdf")
        if (kdf == null) {
            val s = backup.optString("kdf")
            if (s.isNotBlank()) kdf = JSONObject(s)
        }
        val salt = P256Crypto.unb64(kdf?.getString("salt") ?: return null)
        val combined = P256Crypto.unb64(backup.getString("ciphertext"))
        require(combined.size > 12 + 16)
        val iv = combined.copyOfRange(0, 12)
        val ct = combined.copyOfRange(12, combined.size)
        val key = SecretKeySpec(derive(pass, salt), "AES")
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(128, iv))
        cipher.doFinal(ct)
    }.getOrNull()
}
