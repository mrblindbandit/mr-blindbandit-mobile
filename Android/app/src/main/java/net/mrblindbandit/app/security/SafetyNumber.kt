package net.mrblindbandit.app.security

import java.math.BigInteger
import java.security.MessageDigest

object SafetyNumber {
    private fun fingerprint(handle: String, pubs: List<ByteArray>): ByteArray {
        val keys = pubs.distinctBy(P256Crypto::b64).sortedWith { a, b ->
            var diff = 0
            for (i in 0 until minOf(a.size, b.size)) { diff = (a[i].toInt() and 255) - (b[i].toInt() and 255); if (diff != 0) break }
            if (diff == 0) a.size - b.size else diff
        }.fold(byteArrayOf()) { all, pub -> all + pub }
        var hash = byteArrayOf(0, 1) + keys + handle.lowercase().toByteArray()
        val digest = MessageDigest.getInstance("SHA-512")
        repeat(5200) { hash = digest.digest(hash + keys) }
        return hash.copyOf(30)
    }
    fun display(myHandle: String, myPubs: List<ByteArray>, theirHandle: String, theirPubs: List<ByteArray>): String {
        val entries = listOf(myHandle.lowercase() to fingerprint(myHandle, myPubs), theirHandle.lowercase() to fingerprint(theirHandle, theirPubs)).sortedBy { it.first }
        return entries.flatMap { (_, bytes) -> bytes.toList().chunked(5).map { part -> (BigInteger(1, part.toByteArray()).mod(BigInteger.valueOf(100000)).toInt()).toString().padStart(5, '0') } }.joinToString(" ")
    }
}
