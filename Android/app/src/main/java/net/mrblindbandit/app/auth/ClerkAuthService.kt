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

/** Clerk authentication façade. Sessions come only from Clerk; no reusable server secrets ship in the app. */
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
            statusMessage = "Sign-in is temporarily unavailable. Please update the app or try again later."
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
            statusMessage = Clerk.initializationError.value?.localizedMessage ?: "Sign-in could not start. Check your connection and try again."
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
            run {
                var ok = false
                Clerk.auth.signInWithOAuth(OAuthProvider.GOOGLE)
                    .onSuccess { ok = true }
                    .onFailure { statusMessage = it.errorMessage }
                refresh()
                if (ok && state is AuthState.SignedIn) {
                    statusMessage = "Signed in with Google."
                    true
                } else {
                    if (statusMessage.isBlank()) statusMessage = "Google sign-in was cancelled or did not finish. Please try again."
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
                    if (statusMessage.isBlank()) statusMessage = "This account needs one more verification step. Finish it at mrblindbandit.net/account, then sign in again."
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
                    if (statusMessage.isBlank()) statusMessage = "That code was accepted, but your account needs one more detail. Finish it at mrblindbandit.net/account."
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
                statusMessage = "You are not signed in. Sign in and try again."
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
        if (!Clerk.isInitialized.value) error("Sign-in is still starting. Please try again.")
    }
}
