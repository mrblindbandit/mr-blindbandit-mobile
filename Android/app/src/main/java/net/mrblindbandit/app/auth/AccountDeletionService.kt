package net.mrblindbandit.app.auth

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import net.mrblindbandit.app.config.AppConfig
import net.mrblindbandit.app.connect.BlindbanditApiEnvelope
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

/**
 * Step 1 of in-app account deletion: asks the Blindbandit Platform API
 * (`POST /v1/privacy/delete`) to erase the profile, messages, devices and other app data tied to
 * this Clerk account. Step 2 (deleting the Clerk identity) happens in [ClerkAuthService].
 */
object AccountDeletionService {
    const val WEB_DELETION_URL = "https://mrblindbandit.net/account/delete"

    suspend fun deleteBlindbanditData(auth: ClerkAuthService) = withContext(Dispatchers.IO) {
        val token = auth.sessionToken() ?: error("Sign in before deleting your account.")
        val connection = (URL("${AppConfig.API_BASE_URL}/v1/privacy/delete").openConnection() as HttpURLConnection).apply {
            requestMethod = "POST"
            setRequestProperty("Authorization", "Bearer $token")
            setRequestProperty("Accept", "application/json")
            setRequestProperty("Content-Type", "application/json")
            connectTimeout = 15_000
            readTimeout = 20_000
            doOutput = true
        }
        connection.outputStream.use { it.write(JSONObject().toString().toByteArray(Charsets.UTF_8)) }
        val status = connection.responseCode
        val stream = if (status in 200..299) connection.inputStream else connection.errorStream
        val text = stream?.bufferedReader()?.use { it.readText() }.orEmpty()
        connection.disconnect()
        BlindbanditApiEnvelope.unwrap(status, text)
    }
}
