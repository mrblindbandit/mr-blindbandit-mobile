package net.mrblindbandit.app.auth

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import net.mrblindbandit.app.config.AppConfig
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

object AccountDeletionService {
    suspend fun deleteBlindbanditData(auth: ClerkAuthService) = withContext(Dispatchers.IO) {
        val token = auth.sessionToken() ?: error("Sign in before deleting your account.")
        val connection = (URL("${AppConfig.API_BASE_URL}/v1/mobile-native/account-data").openConnection() as HttpURLConnection).apply {
            requestMethod = "DELETE"
            setRequestProperty("Authorization", "Bearer $token")
            setRequestProperty("Accept", "application/json")
            setRequestProperty("Content-Type", "application/json")
            connectTimeout = 15_000
            readTimeout = 20_000
            doOutput = true
        }
        connection.outputStream.use {
            it.write(JSONObject().put("confirmation", "DELETE MY BLINDBANDIT DATA").toString().toByteArray(Charsets.UTF_8))
        }
        val status = connection.responseCode
        val stream = if (status in 200..299) connection.inputStream else connection.errorStream
        val text = stream?.bufferedReader()?.use { it.readText() }.orEmpty()
        connection.disconnect()
        if (status !in 200..299) {
            val json = runCatching { JSONObject(text) }.getOrNull()
            val message = json?.optJSONObject("error")?.optString("message").orEmpty().ifBlank { "Account-data deletion returned HTTP $status." }
            error(message)
        }
    }
}
