import Foundation
import SwiftUI
import AuthenticationServices
import ClerkKit

enum AuthSessionState: Equatable {
    case unknown
    case signedOut
    case signedIn(displayName: String, email: String)
}

enum EmailVerificationMode: Equatable {
    case signIn(email: String)
    case signUp(email: String)

    var email: String {
        switch self {
        case .signIn(let email), .signUp(let email): return email
        }
    }
}

/// Production Clerk authentication façade used by the SwiftUI app.
///
/// Only the Clerk publishable key ships in the client. Session credentials remain in
/// Clerk's Keychain-backed SDK storage and API calls use short-lived Clerk session JWTs.
@MainActor
final class ClerkAuthService: ObservableObject {
    @Published private(set) var state: AuthSessionState = .unknown
    @Published private(set) var busy = false
    @Published var statusMessage = ""
    @Published var emailDraft = ""
    @Published var nameDraft = ""
    @Published var verificationCodeDraft = ""
    @Published private(set) var pendingVerification: EmailVerificationMode?
    @Published private(set) var deletionRequested = false

    private var configured = false
    private var authEventsTask: Task<Void, Never>?

    deinit {
        authEventsTask?.cancel()
    }

    func configure() {
        guard !configured else {
            Task { await refresh() }
            return
        }

        guard AppConfig.isClerkConfigured else {
            state = .signedOut
            statusMessage = "Clerk is not configured on this build."
            return
        }

        let redirect = Clerk.Options.RedirectConfig(
            redirectUrl: AppConfig.oauthCallbackURL.absoluteString,
            callbackUrlScheme: AppConfig.oauthCallbackURLScheme
        )
        _ = Clerk.configure(
            publishableKey: AppConfig.clerkPublishableKey,
            options: .init(redirectConfig: redirect)
        )
        configured = true
        startAuthEventObserver()

        Task {
            do {
                _ = try await Clerk.shared.refreshClient()
                _ = try await Clerk.shared.refreshEnvironment()
            } catch {
                // Cached Clerk state can still be usable offline; refresh() handles it.
            }
            await refresh()
        }
    }

    func refresh() async {
        guard configured else {
            state = AppConfig.isClerkConfigured ? .unknown : .signedOut
            return
        }

        if let user = Clerk.shared.user {
            let email = user.primaryEmailAddress?.emailAddress
                ?? user.emailAddresses.first?.emailAddress
                ?? ""
            let fullName = [user.firstName, user.lastName]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            let displayName = !fullName.isEmpty
                ? fullName
                : (user.username?.isEmpty == false ? user.username! : (email.split(separator: "@").first.map(String.init) ?? "Blindbandit user"))
            state = .signedIn(displayName: displayName, email: email)
            deletionRequested = false
        } else {
            state = .signedOut
        }
    }

    /// Starts Clerk's production email-code sign-in flow.
    func beginEmailSignIn(email: String) async -> Bool {
        await performAuthAction {
            let normalized = normalizeEmail(email)
            guard isValidEmail(normalized) else {
                throw AuthInputError("Enter a valid email address.")
            }
            _ = try await Clerk.shared.auth.signInWithEmailCode(emailAddress: normalized)
            pendingVerification = .signIn(email: normalized)
            verificationCodeDraft = ""
            statusMessage = "We sent a Clerk verification code to \(normalized)."
            return true
        }
    }

    /// Starts Clerk's production email-code account creation flow.
    func beginEmailSignUp(email: String, name: String) async -> Bool {
        await performAuthAction {
            let normalized = normalizeEmail(email)
            guard isValidEmail(normalized) else {
                throw AuthInputError("Enter a valid email address.")
            }

            let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            let parts = cleanName.split(separator: " ", maxSplits: 1).map(String.init)
            let firstName = parts.first
            let lastName = parts.count > 1 ? parts[1] : nil
            let signup = try await Clerk.shared.auth.signUp(
                emailAddress: normalized,
                firstName: firstName,
                lastName: lastName
            )

            let prepared: SignUp
            if signup.unverifiedFields.contains(where: { $0.rawValue == "email_address" }) || signup.status != .complete {
                prepared = try await signup.sendEmailCode()
            } else {
                prepared = signup
            }

            if prepared.status == .complete {
                try await activateSessionIfNeeded(prepared.createdSessionId)
                pendingVerification = nil
                await refresh()
                statusMessage = "Account created."
            } else {
                pendingVerification = .signUp(email: normalized)
                verificationCodeDraft = ""
                statusMessage = "We sent a Clerk verification code to \(normalized)."
            }
            return true
        }
    }

    /// Completes the current Clerk email-code sign-in or sign-up attempt.
    func verifyEmailCode(_ code: String) async -> Bool {
        await performAuthAction {
            let clean = code.trimmingCharacters(in: .whitespacesAndNewlines)
            guard clean.count >= 4 else {
                throw AuthInputError("Enter the verification code from your email.")
            }
            guard let pendingVerification else {
                throw AuthInputError("Start email sign-in again so Clerk can send a new code.")
            }

            switch pendingVerification {
            case .signIn:
                guard let signIn = Clerk.shared.auth.currentSignIn else {
                    throw AuthInputError("The Clerk sign-in attempt expired. Start again.")
                }
                let verified = try await signIn.verifyCode(clean)
                guard verified.status == .complete else {
                    throw AuthInputError("Clerk needs another verification step before sign-in can finish.")
                }
                try await activateSessionIfNeeded(verified.createdSessionId)

            case .signUp:
                guard let signUp = Clerk.shared.auth.currentSignUp else {
                    throw AuthInputError("The Clerk sign-up attempt expired. Start again.")
                }
                let verified = try await signUp.verifyEmailCode(clean)
                guard verified.status == .complete else {
                    throw AuthInputError("Clerk still needs additional account information before sign-up can finish.")
                }
                try await activateSessionIfNeeded(verified.createdSessionId)
            }

            self.pendingVerification = nil
            verificationCodeDraft = ""
            try? await Clerk.shared.refreshClient()
            await refresh()
            statusMessage = "Signed in with Clerk."
            AppHaptics.success()
            return true
        }
    }

    func cancelEmailVerification() {
        pendingVerification = nil
        verificationCodeDraft = ""
        statusMessage = ""
    }

    func beginGoogleSignIn() async -> Bool {
        await performAuthAction {
            guard AppConfig.isClerkConfigured else {
                throw AuthInputError("Clerk is not configured on this build.")
            }
            let result = try await Clerk.shared.auth.signInWithOAuth(provider: .google)
            switch result {
            case .signIn(let signIn):
                try await activateSessionIfNeeded(signIn.createdSessionId)
                if signIn.status != .complete {
                    throw AuthInputError("Google sign-in needs another Clerk verification step.")
                }
            case .signUp(let signUp):
                try await activateSessionIfNeeded(signUp.createdSessionId)
                if signUp.status != .complete {
                    throw AuthInputError("Google sign-in needs additional account information in Clerk.")
                }
            }
            try? await Clerk.shared.refreshClient()
            await refresh()
            statusMessage = "Signed in with Google through Clerk."
            AppHaptics.success()
            return true
        }
    }

    /// Kept ready for the day Apple auth is enabled in the production Clerk dashboard.
    func beginAppleSignIn(credential: ASAuthorizationAppleIDCredential) async -> Bool {
        await performAuthAction {
            guard AppConfig.enableSignInWithApple else {
                throw AuthInputError("Sign in with Apple is not enabled for this app yet.")
            }
            guard let tokenData = credential.identityToken,
                  let token = String(data: tokenData, encoding: .utf8) else {
                throw AuthInputError("Apple did not return an identity token.")
            }
            let result = try await Clerk.shared.auth.signInWithIdToken(token, provider: .apple)
            switch result {
            case .signIn(let signIn):
                try await activateSessionIfNeeded(signIn.createdSessionId)
            case .signUp(let signUp):
                try await activateSessionIfNeeded(signUp.createdSessionId)
            }
            try? await Clerk.shared.refreshClient()
            await refresh()
            statusMessage = "Signed in with Apple through Clerk."
            return true
        }
    }

    /// Returns a fresh Clerk session JWT for authenticated Platform API calls.
    func sessionToken() async throws -> String {
        guard configured else { throw AuthInputError("Clerk is not configured.") }
        guard let token = try await Clerk.shared.auth.getToken(), !token.isEmpty else {
            throw AuthInputError("Your Clerk session expired. Sign in again.")
        }
        return token
    }

    /// Permanently deletes the active Clerk account when self-delete is enabled.
    func requestAccountDeletion() async -> Bool {
        await performAuthAction {
            guard let user = Clerk.shared.user else {
                throw AuthInputError("No signed-in Clerk account was found.")
            }
            guard user.deleteSelfEnabled else {
                throw AuthInputError("Account deletion is disabled in Clerk. Use Manage account for assistance.")
            }
            _ = try await user.delete()
            deletionRequested = true
            pendingVerification = nil
            state = .signedOut
            statusMessage = "Your Clerk account was deleted."
            AppHaptics.warning()
            return true
        }
    }

    func signOut() async {
        busy = true
        defer { busy = false }
        do {
            if configured {
                try await Clerk.shared.auth.signOut()
            }
            pendingVerification = nil
            verificationCodeDraft = ""
            emailDraft = ""
            nameDraft = ""
            state = .signedOut
            statusMessage = "Signed out."
            AppHaptics.soft()
        } catch {
            statusMessage = readable(error)
            AppHaptics.error()
        }
    }

    private func startAuthEventObserver() {
        authEventsTask?.cancel()
        authEventsTask = Task { [weak self] in
            guard let self else { return }
            for await _ in Clerk.shared.auth.events {
                if Task.isCancelled { return }
                await self.refresh()
            }
        }
    }

    private func activateSessionIfNeeded(_ sessionId: String?) async throws {
        guard let sessionId, !sessionId.isEmpty else { return }
        if Clerk.shared.session?.id != sessionId {
            try await Clerk.shared.auth.setActive(sessionId: sessionId)
        }
    }

    private func performAuthAction(_ action: () async throws -> Bool) async -> Bool {
        guard !busy else { return false }
        busy = true
        statusMessage = ""
        defer { busy = false }
        do {
            return try await action()
        } catch {
            statusMessage = readable(error)
            AppHaptics.error()
            return false
        }
    }

    private func normalizeEmail(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func isValidEmail(_ value: String) -> Bool {
        let pieces = value.split(separator: "@", omittingEmptySubsequences: false)
        return pieces.count == 2 && pieces[0].count > 0 && pieces[1].contains(".")
    }

    private func readable(_ error: Error) -> String {
        if let input = error as? AuthInputError { return input.message }
        let text = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "Authentication failed. Try again." : text
    }
}

private struct AuthInputError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
