package net.mrblindbandit.app.security

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import java.security.KeyStore
import java.util.Base64
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

interface SecretStore {
    fun get(name: String): String?
    fun put(name: String, value: String?)
}

/** Keystore-wrapped, authenticated local values. Keys cannot be exported or backed up. */
class SecureLocalStore(context: Context, private val namespace: String) : SecretStore {
    private val prefs = context.applicationContext.getSharedPreferences("bb_secure_$namespace", Context.MODE_PRIVATE)
    private val alias = "bb.local.v1.$namespace"

    @Synchronized private fun key(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey(alias, null) as? SecretKey)?.let { return it }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
            init(KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256).setRandomizedEncryptionRequired(true).build())
        }.generateKey()
    }

    @Synchronized override fun get(name: String): String? {
        val stored = prefs.getString(name, null) ?: return null
        val bytes = Base64.getDecoder().decode(stored)
        require(bytes.size >= 29 && bytes[0] == 1.toByte()) { "Unsupported secure local value" }
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, bytes.copyOfRange(1, 13)))
        cipher.updateAAD("$namespace:$name".toByteArray(Charsets.UTF_8))
        return cipher.doFinal(bytes.copyOfRange(13, bytes.size)).toString(Charsets.UTF_8)
    }

    fun names(): Set<String> = prefs.all.keys
    @Synchronized fun clear() { check(prefs.edit().clear().commit()) }

    /** Synchronous commit is intentional: callers must not discard a plaintext predecessor before durable storage. */
    @Synchronized override fun put(name: String, value: String?) {
        if (value == null) {
            check(prefs.edit().remove(name).commit()) { "Could not remove local value" }
            return
        }
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key())
        cipher.updateAAD("$namespace:$name".toByteArray(Charsets.UTF_8))
        val bytes = byteArrayOf(1) + cipher.iv + cipher.doFinal(value.toByteArray(Charsets.UTF_8))
        check(prefs.edit().putString(name, Base64.getEncoder().encodeToString(bytes)).commit()) { "Could not save local value" }
    }
}
