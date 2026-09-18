package net.mrblindbandit.app.auth

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.clerk.api.Clerk
import com.clerk.api.auth.types.VerificationType
import com.clerk.api.network.serialization.errorMessage
import com.clerk.api.network.serialization.flatMap
import com.clerk.api.network.serialization.onFailure
import com.clerk.api.network.serialization.onSuccess
import com.clerk.api.session.fetchToken
import com.clerk.api.signup.sendCode
import com.clerk.api.signup.verifyCode
import com.clerk.api.sso.OAuthProvider
import com.clerk.api.user.delete
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.withTimeoutOrNull
import net.mrblindbandit.app.config.AppConfig

sealed class AuthState {
    data object Unknown : AuthState()
    data object SignedOut : AuthState()
    data class SignedIn(val displayName: String, val email: String) : AuthState()
}

/** Real Clerk authentication façade. No local fake sessions or reusable server secrets. */
class ClerkAuthService(context: Context) {
    private val appContext = context.applicationContext
    private var configured = false

    var state: AuthState by mutableStateOf(AuthState.Unknown)
        private set
    var busy by mutableStateOf(false)
        private set
    var statusMessage by mutableStateOf("")
    var deletionRequested by mutableStateOf(false)
        private set
    var needsEmailVerification by mutableStateOf(false)
        private set
    var emailDraft by mutableStateOf("")
    var passwordDraft by mutableStateOf("")
    var nameDraft by mutableStateOf("")
    var verificationCodeDraft by mutableStateOf("")

    suspend fun configure() {
        if (configured) {
            refresh()
            return
        }
        if (!AppConfig.isClerkConfigured) {
            state = AuthState.SignedOut
            statusMessage = "Clerk authentication is not configured."
            return
        }
        if (Clerk.isInitialized.value) {
            configured = true
            refresh()
            return
        }
        configured = true
        Clerk.initialize(appContext, publishableKey = AppConfig.clerkPublishableKey)
        val ready = withTimeoutOrNull(10_000) { Clerk.isInitialized.first { it } } ?: false
        if (!ready) {
            state = AuthState.SignedOut
            statusMessage = Clerk.initializationError.value?.localizedMessage ?: "Clerk could not initialize. Check your connection and try again."
            return
        }
        refresh()
    }

    fun refresh() {
        if (!configured || !Clerk.isInitialized.value) {
            state = if (configured) AuthState.Unknown else AuthState.SignedOut
            return
        }
        val user = Clerk.userFlow.value
        if (user == null) {
            state = AuthState.SignedOut
            return
        }
        val email = user.primaryEmailAddress?.emailAddress
            ?: user.emailAddresses?.firstOrNull()?.emailAddress
            ?: ""
        val fullName = listOfNotNull(user.firstName?.trim(), user.lastName?.trim())
            .filter { it.isNotBlank() }
            .joinToString(" ")
        val displayName = fullName.ifBlank { user.username?.takeIf { it.isNotBlank() } ?: email.substringBefore("@").ifBlank { "Blindbandit User" } }
        state = AuthState.SignedIn(displayName, email)
        needsEmailVerification = false
        deletionRequested = false
        statusMessage = ""
    }

    suspend fun continueWithGoogle(): Boolean {
        busy = true
        statusMessage = ""
        return try {
            ensureConfigured()
            if (AppConfig.googleOAuthClientId.isBlank()) {
                statusMessage = "Google sign-in is unavailable because its client ID is not configured."
                false
            } else {
                var ok = false
                Clerk.auth.signInWithOAuth(OAuthProvider.GOOGLE)
                    .onSuccess { ok = true }
                    .onFailure { statusMessage = it.errorMessage }
                refresh()
                if (ok && state is AuthState.SignedIn) {
                    statusMessage = "Signed in with Google."
                    true
                } else {
                    if (statusMessage.isBlank()) statusMessage = "Google authentication finished without an active Clerk session."
                    false
                }
            }
        } catch (e: Exception) {
            statusMessage = e.localizedMessage ?: "Google sign-in failed."
            false
        } finally {
            busy = false
        }
    }

    suspend fun continueWithEmail(signUp: Boolean): Boolean {
        busy = true
        statusMessage = ""
        return try {
            ensureConfigured()
            val email = emailDraft.trim().lowercase()
            if (!email.contains("@") || passwordDraft.length < 8) {
                statusMessage = "Enter a valid email and a password of at least 8 characters."
                return false
            }

            if (signUp) {
                val names = nameDraft.trim().split(Regex("\\s+"), limit = 2).filter { it.isNotBlank() }
                var prepared = false
                Clerk.auth.signUp {
                    this.email = email
                    this.password = passwordDraft
                    this.firstName = names.firstOrNull()
                    this.lastName = names.getOrNull(1)
                }
                    .flatMap { it.sendCode { this.email = email } }
                    .onSuccess { prepared = true }
                    .onFailure { statusMessage = it.errorMessage }
                refresh()
                if (state is AuthState.SignedIn) {
                    statusMessage = "Account created and signed in."
                    true
                } else if (prepared) {
                    needsEmailVerification = true
                    statusMessage = "We sent a verification code to $email. Enter it to finish creating your account."
                    false
                } else false
            } else {
                var ok = false
                Clerk.auth.signInWithPassword {
                    identifier = email
                    password = passwordDraft
                }
                    .onSuccess { ok = true }
                    .onFailure { statusMessage = it.errorMessage }
                refresh()
                if (ok && state is AuthState.SignedIn) {
                    statusMessage = "Signed in."
                    true
                } else {
                    if (statusMessage.isBlank()) statusMessage = "Clerk needs another verification step before sign-in can finish."
                    false
                }
            }
        } catch (e: Exception) {
            statusMessage = e.localizedMessage ?: "Authentication failed."
            false
        } finally {
            busy = false
        }
    }

    suspend fun verifyPendingEmail(): Boolean {
        busy = true
        statusMessage = ""
        return try {
            ensureConfigured()
            val code = verificationCodeDraft.trim()
            val signUp = Clerk.auth.currentSignUp
            if (code.isBlank() || signUp == null) {
                statusMessage = "Start account creation first, then enter the verification code."
                false
            } else {
                var ok = false
                signUp.verifyCode(code, VerificationType.EMAIL)
                    .onSuccess { ok = true }
                    .onFailure { statusMessage = it.errorMessage }
                refresh()
                if (ok && state is AuthState.SignedIn) {
                    verificationCodeDraft = ""
                    needsEmailVerification = false
                    statusMessage = "Email verified. Your account is ready."
                    true
                } else {
                    if (statusMessage.isBlank()) statusMessage = "Clerk accepted the code but the account still needs another required step."
                    false
                }
            }
        } catch (e: Exception) {
            statusMessage = e.localizedMessage ?: "Email verification failed."
            false
        } finally {
            busy = false
        }
    }

    suspend fun sessionToken(): String? {
        ensureConfigured()
        val session = Clerk.session ?: return null
        var token: String? = null
        session.fetchToken()
            .onSuccess { token = it.jwt }
            .onFailure { statusMessage = it.errorMessage }
        return token
    }

    suspend fun requestAccountDeletion(): Boolean {
        busy = true
        statusMessage = ""
        return try {
            ensureConfigured()
            val user = Clerk.userFlow.value
            if (user == null) {
                statusMessage = "No signed-in Clerk account was found."
                false
            } else {
                AccountDeletionService.deleteBlindbanditData(this)
                var ok = false
                user.delete()
                    .onSuccess { ok = true }
                    .onFailure { statusMessage = it.errorMessage }
                if (ok) {
                    deletionRequested = true
                    state = AuthState.SignedOut
                    statusMessage = "Your Blindbandit account and associated app data were deleted."
                    true
                } else false
            }
        } catch (e: Exception) {
            statusMessage = e.localizedMessage ?: "The account could not be deleted. No partial deletion was reported as complete."
            false
        } finally {
            busy = false
        }
    }

    suspend fun signOut() {
        busy = true
        statusMessage = ""
        try {
            ensureConfigured()
            Clerk.auth.signOut()
                .onFailure { statusMessage = it.errorMessage }
            state = AuthState.SignedOut
            emailDraft = ""
            passwordDraft = ""
            nameDraft = ""
            verificationCodeDraft = ""
            needsEmailVerification = false
            if (statusMessage.isBlank()) statusMessage = "Signed out."
        } catch (e: Exception) {
            statusMessage = e.localizedMessage ?: "Sign out failed."
        } finally {
            busy = false
        }
    }

    private suspend fun ensureConfigured() {
        if (!configured || !Clerk.isInitialized.value) configure()
        if (!Clerk.isInitialized.value) error("Clerk is not initialized.")
    }
}
