package net.mrblindbandit.app.security

import java.math.BigInteger
import java.nio.ByteBuffer
import java.security.AlgorithmParameters
import java.security.KeyFactory
import java.security.KeyPair
import java.security.KeyPairGenerator
import java.security.MessageDigest
import java.security.PrivateKey
import java.security.SecureRandom
import java.security.Signature
import java.security.interfaces.ECPublicKey
import java.security.spec.ECGenParameterSpec
import java.security.spec.ECParameterSpec
import java.security.spec.ECPoint
import java.security.spec.ECPrivateKeySpec
import java.security.spec.ECPublicKeySpec
import java.util.Base64
import javax.crypto.Cipher
import javax.crypto.KeyAgreement
import javax.crypto.Mac
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

/** The iOS p256-v1 byte contract, using platform JCA primitives only. */
object P256Crypto {
    const val SUITE = "p256-v1"
    private val params: ECParameterSpec get() = AlgorithmParameters.getInstance("EC").apply {
        init(ECGenParameterSpec("secp256r1"))
    }.getParameterSpec(ECParameterSpec::class.java)
    private fun fixed(n: BigInteger) = n.toByteArray().let { if (it.size > 32) it.takeLast(32).toByteArray() else ByteArray(32 - it.size) + it }
    fun random(size: Int) = ByteArray(size).also { SecureRandom().nextBytes(it) }
    fun b64(bytes: ByteArray): String = Base64.getUrlEncoder().withoutPadding().encodeToString(bytes)
    fun unb64(value: String): ByteArray = Base64.getUrlDecoder().decode(value)
    fun hex(value: String) = value.chunked(2).map { it.toInt(16).toByte() }.toByteArray()
    fun generate(): KeyPair = KeyPairGenerator.getInstance("EC").apply { initialize(ECGenParameterSpec("secp256r1")) }.generateKeyPair()
    fun publicBytes(key: java.security.PublicKey): ByteArray = (key as ECPublicKey).w.let { byteArrayOf(4) + fixed(it.affineX) + fixed(it.affineY) }
    fun privateKey(raw: ByteArray): PrivateKey {
        require(raw.size == 32)
        return KeyFactory.getInstance("EC").generatePrivate(ECPrivateKeySpec(BigInteger(1, raw), params))
    }
    fun publicKey(raw: ByteArray): java.security.PublicKey {
        require(raw.size == 65 && raw[0] == 4.toByte())
        return KeyFactory.getInstance("EC").generatePublic(ECPublicKeySpec(ECPoint(BigInteger(1, raw.copyOfRange(1, 33)), BigInteger(1, raw.copyOfRange(33, 65))), params))
    }
    fun dh(privateKey: PrivateKey, publicBytes: ByteArray): ByteArray = KeyAgreement.getInstance("ECDH").run {
        init(privateKey); doPhase(publicKey(publicBytes), true); generateSecret()
    }
    fun hmac(key: ByteArray, data: ByteArray): ByteArray = Mac.getInstance("HmacSHA256").run {
        init(SecretKeySpec(key, "HmacSHA256")); doFinal(data)
    }
    fun hkdf(ikm: ByteArray, info: ByteArray, salt: ByteArray = ByteArray(32)): ByteArray = hmac(hmac(salt, ikm), info + byteArrayOf(1))
    fun step(chain: ByteArray) = hmac(chain, byteArrayOf(1)) to hmac(chain, byteArrayOf(2))
    fun seal(plain: ByteArray, key: ByteArray, nonce: ByteArray, ad: ByteArray): ByteArray = crypt(Cipher.ENCRYPT_MODE, plain, key, nonce, ad)
    fun open(sealed: ByteArray, key: ByteArray, nonce: ByteArray, ad: ByteArray): ByteArray = crypt(Cipher.DECRYPT_MODE, sealed, key, nonce, ad)
    private fun crypt(mode: Int, data: ByteArray, key: ByteArray, nonce: ByteArray, ad: ByteArray): ByteArray {
        require(key.size == 32 && nonce.size == 12)
        return Cipher.getInstance("AES/GCM/NoPadding").run { init(mode, SecretKeySpec(key, "AES"), GCMParameterSpec(128, nonce)); updateAAD(ad); doFinal(data) }
    }
    fun pad(plain: ByteArray): ByteArray {
        val n = listOf(256, 512, 1024, 2048, 4096).firstOrNull { plain.size < it } ?: ((plain.size + 4096) / 4096 * 4096)
        return plain + byteArrayOf(0x80.toByte()) + ByteArray(n - plain.size - 1)
    }
    fun unpad(plain: ByteArray): ByteArray {
        val last = plain.indexOfLast { it != 0.toByte() }
        require(last >= 0 && plain[last] == 0x80.toByte()) { "Invalid encrypted message padding" }
        return plain.copyOfRange(0, last)
    }
    // CryptoKit uses P1363 r||s. Android's provider uses DER ASN.1 integers.
    fun sign(data: ByteArray, key: PrivateKey): ByteArray {
        val der = Signature.getInstance("SHA256withECDSA").run { initSign(key); update(data); sign() }
        var offset = 2
        require(der[0] == 0x30.toByte() && der[offset++] == 2.toByte())
        val rSize = der[offset++].toInt() and 255
        val r = BigInteger(1, der.copyOfRange(offset, offset + rSize)); offset += rSize
        require(der[offset++] == 2.toByte())
        val sSize = der[offset++].toInt() and 255
        return fixed(r) + fixed(BigInteger(1, der.copyOfRange(offset, offset + sSize)))
    }
    fun verify(signature: ByteArray, data: ByteArray, publicBytes: ByteArray): Boolean = runCatching {
        require(signature.size == 64)
        fun integer(raw: ByteArray): ByteArray = BigInteger(1, raw).toByteArray().let { byteArrayOf(2, it.size.toByte()) + it }
        val ints = integer(signature.copyOfRange(0, 32)) + integer(signature.copyOfRange(32, 64))
        val der = byteArrayOf(0x30, ints.size.toByte()) + ints
        Signature.getInstance("SHA256withECDSA").run { initVerify(publicKey(publicBytes)); update(data); verify(der) }
    }.getOrDefault(false)
    fun packed(id: Int, pub: ByteArray): String { require(pub.size == 65); return b64(ByteBuffer.allocate(4).putInt(id).array() + pub) }
    fun unpack(value: String): Pair<Int, ByteArray> = unb64(value).let { require(it.size == 69); ByteBuffer.wrap(it, 0, 4).int to it.copyOfRange(4, 69) }
    fun sha256(bytes: ByteArray) = MessageDigest.getInstance("SHA-256").digest(bytes)
}
