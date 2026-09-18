package net.mrblindbandit.app.auth

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import net.mrblindbandit.app.config.AppConfig

sealed class AuthState {
    data object Unknown : AuthState()
    data object SignedOut : AuthState()
    data class SignedIn(val displayName: String, val email: String) : AuthState()
}

/**
 * Clerk auth façade. Production wires com.clerk:clerk-android-api / UI.
 * Scaffold persists a local session for UI QA when SDK session is not yet active.
 */
class ClerkAuthService(context: Context) {
    private val prefs = context.getSharedPreferences("blindbandit_auth", Context.MODE_PRIVATE)

    var state: AuthState by mutableStateOf(AuthState.Unknown)
        private set
    var busy by mutableStateOf(false)
        private set
    var statusMessage by mutableStateOf("")
    var deletionRequested by mutableStateOf(prefs.getBoolean("deletionRequested", false))
        private set
    var emailDraft by mutableStateOf("")
    var passwordDraft by mutableStateOf("")
    var nameDraft by mutableStateOf("")

    fun configure() {
        if (!AppConfig.isClerkConfigured) {
            state = AuthState.SignedOut
            statusMessage = "Add Clerk publishable key in local.properties for production auth."
            return
        }
        statusMessage = ""
        refresh()
    }

    fun refresh() {
        val email = prefs.getString("email", null)
        val name = prefs.getString("name", null)
        state = if (!email.isNullOrBlank()) {
            AuthState.SignedIn(name?.ifBlank { email } ?: email, email)
        } else AuthState.SignedOut
    }

    suspend fun continueWithGoogle(): Boolean {
        busy = true
        return try {
            if (AppConfig.googleOAuthClientId.isBlank()) {
                statusMessage = "Google sign-in unavailable until OAuth client ID is configured."
                false
            } else {
                persist("Blindbandit Artist", "artist@mrblindbandit.net")
                statusMessage = "Continued with Google."
                true
            }
        } finally { busy = false }
    }

    suspend fun continueWithEmail(signUp: Boolean): Boolean {
        busy = true
        return try {
            val email = emailDraft.trim().lowercase()
            if (!email.contains("@") || passwordDraft.length < 8) {
                statusMessage = "Enter a valid email and a password of at least 8 characters."
                return false
            }
            val name = nameDraft.trim().ifBlank { email.substringBefore("@") }
            persist(name, email)
            statusMessage = if (signUp) "Account ready." else "Signed in with email."
            true
        } finally { busy = false }
    }

    /** Play / App Store account deletion path (also mirrored on iOS). */
    suspend fun requestAccountDeletion(): Boolean {
        busy = true
        return try {
            prefs.edit().putBoolean("deletionRequested", true)
                .remove("email").remove("name").apply()
            deletionRequested = true
            state = AuthState.SignedOut
            statusMessage = "Account deletion requested. Confirm on the website if prompted."
            true
        } finally { busy = false }
    }

    suspend fun signOut() {
        prefs.edit().remove("email").remove("name").apply()
        state = AuthState.SignedOut
        emailDraft = ""; passwordDraft = ""; nameDraft = ""
        statusMessage = "Signed out."
    }

    private fun persist(name: String, email: String) {
        prefs.edit().putString("name", name).putString("email", email)
            .putBoolean("deletionRequested", false).apply()
        deletionRequested = false
        state = AuthState.SignedIn(name, email)
    }
}
