package net.mrblindbandit.app

import net.mrblindbandit.app.connect.BlindbanditApiEnvelope
import net.mrblindbandit.app.connect.BlindbanditApiException
import net.mrblindbandit.app.connect.normalizeHandle
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class ApiEnvelopeTest {
    @Test fun unwrapsDataObject() {
        val body = """{"success":true,"data":{"id":"profile_1","handle":"mrblindbandit"},"meta":{"request_id":"r"}}"""
        val data = BlindbanditApiEnvelope.unwrap(200, body)
        assertEquals("profile_1", data.getString("id"))
        assertEquals("mrblindbandit", data.getString("handle"))
    }

    @Test fun unwrapsListIntoItems() {
        val data = BlindbanditApiEnvelope.unwrap(200, """{"success":true,"data":{"items":[{"id":"c1"}],"limit":25}}""")
        assertEquals("c1", data.getJSONArray("items").getJSONObject(0).getString("id"))
    }

    @Test fun surfacesServerErrorMessage() {
        val error = assertThrows(BlindbanditApiException::class.java) {
            BlindbanditApiEnvelope.unwrap(401, """{"success":false,"error":{"code":"AUTH_REQUIRED","message":"Sign in with Clerk to continue."}}""")
        }
        assertEquals("AUTH_REQUIRED", error.code)
        assertEquals("Sign in with Clerk to continue.", error.message)
    }

    @Test fun normalizesHandles() {
        assertEquals("mrblindbandit", normalizeHandle("  @MrBlindbandit "))
    }
}
