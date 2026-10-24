package net.mrblindbandit.app.security

import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class EncryptionPasscodeTest {
    @Test fun roundTrip() {
        val plain = """{"device":"abc","sign":{"pub":"x","priv":"y"},"dh":{"pub":"a","priv":"b"}}""".toByteArray()
        val sealed = EncryptionPasscode.seal(plain, "secret12")
        assertTrue(sealed.has("ciphertext"))
        assertEquals(600_000, sealed.getJSONObject("kdf").getInt("iterations"))
        val opened = EncryptionPasscode.open(sealed, "secret12")
        assertNotNull(opened)
        assertArrayEquals(plain, opened)
        assertNull(EncryptionPasscode.open(sealed, "wrongpass"))
    }
    @Test fun validPasscode() {
        assertTrue(EncryptionPasscode.isValid("abc123"))
        assertFalse(EncryptionPasscode.isValid("ab"))
        assertFalse(EncryptionPasscode.isValid("bad pass"))
    }
}
