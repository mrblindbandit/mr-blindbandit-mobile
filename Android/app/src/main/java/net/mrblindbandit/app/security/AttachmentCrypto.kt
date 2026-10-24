package net.mrblindbandit.app.security

import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import java.security.MessageDigest

/** iOS-compatible 64-KiB AES-GCM attachment segments with Padmé padding. */
object AttachmentCrypto {
    const val MAX_SIZE = 20 * 1024 * 1024
    private const val SEGMENT = 65536
    data class Sealed(val blob: ByteArray, val key: ByteArray, val nonce: ByteArray, val digest: ByteArray, val size: Int)
    fun paddedSize(n: Int): Int {
        require(n in 0..MAX_SIZE)
        if (n <= 1) return n
        val exponent = 31 - Integer.numberOfLeadingZeros(n)
        val significant = 32 - Integer.numberOfLeadingZeros(exponent)
        val z = (exponent - significant).coerceAtLeast(0)
        val mask = (1 shl z) - 1
        return (n + mask) and mask.inv()
    }
    private fun nonce(base: ByteArray, i: Int): ByteArray {
        require(base.size == 12)
        return base.copyOfRange(0, 4) + ByteBuffer.allocate(8).putLong(ByteBuffer.wrap(base, 4, 8).long xor i.toLong()).array()
    }
    private fun ad(i: Int) = "bb-att-v1".toByteArray() + ByteBuffer.allocate(4).putInt(i).array()
    fun seal(plain: ByteArray, key: ByteArray = P256Crypto.random(32), baseNonce: ByteArray = P256Crypto.random(12)): Sealed {
        val padded = plain.copyOf(paddedSize(plain.size)); val output = ByteArrayOutputStream()
        var offset = 0; var i = 0
        while (offset < padded.size) {
            val end = minOf(offset + SEGMENT, padded.size)
            output.write(P256Crypto.seal(padded.copyOfRange(offset, end), key, nonce(baseNonce, i), ad(i)))
            offset = end; i++
        }
        val blob = output.toByteArray()
        return Sealed(blob, key, baseNonce, P256Crypto.sha256(blob), plain.size)
    }
    fun open(blob: ByteArray, key: ByteArray, baseNonce: ByteArray, plainSize: Int, digest: ByteArray): ByteArray {
        val paddedSize = paddedSize(plainSize)
        val expected = paddedSize + ((paddedSize + SEGMENT - 1) / SEGMENT) * 16
        require(blob.size == expected && MessageDigest.isEqual(P256Crypto.sha256(blob), digest)) { "Attachment integrity check failed" }
        val out = ByteArrayOutputStream(); var offset = 0; var i = 0
        while (offset < blob.size) {
            val end = minOf(offset + SEGMENT + 16, blob.size)
            out.write(P256Crypto.open(blob.copyOfRange(offset, end), key, nonce(baseNonce, i), ad(i)))
            offset = end; i++
        }
        return out.toByteArray().copyOf(plainSize)
    }
}
