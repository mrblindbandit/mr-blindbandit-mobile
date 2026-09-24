import Foundation
import SwiftUI
import AuthenticationServices
import ClerkKit

enum AuthSessionState: Equatable {
    case unknown
    case signedOut
    case signedIn(displayName: String, email: String)
}

@MainActor
protocol ClerkAuthServing: AnyObject {
    var state: AuthSessionState { get }
    var busy: Bool { get }
    var statusMessage: String { get }
    func configure()
    func refresh() async
    func signInWithEmail(email: String, password: String) async -> Bool
    func signUpWithEmail(email: String, password: String, name: String) async -> Bool
    func verifyPendingEmail(code: String) async -> Bool
    func beginGoogleSignIn() async -> Bool
    func beginAppleSignIn(credential: ASAuthorizationAppleIDCredential) async -> Bool
    func requestAccountDeletion() async -> Bool
    func sessionToken() async throws -> String
    func signOut() async
}

@MainActor
final class ClerkAuthService: ObservableObject, ClerkAuthServing {
    @Published private(set) var state: AuthSessionState = .unknown
    @Published private(set) var busy = false
    @Published var statusMessage = ""
    @Published var emailDraft = ""
    @Published var passwordDraft = ""
    @Published var nameDraft = ""
    @Published var verificationCodeDraft = ""
    @Published private(set) var needsEmailVerification = false
    @Published private(set) var deletionRequested = false

    private var configured = false
    private var authEventsTask: Task<Void, Never>?

    deinit { authEventsTask?.cancel() }

    func configure() {
        guard !configured else { return }
        guard AppConfig.isClerkConfigured else {
            state = .signedOut
            statusMessage = "Clerk authentication is not configured."
            return
        }

        configured = true
        _ = Clerk.configure(publishableKey: AppConfig.clerkPublishableKey)
        authEventsTask = Task { [weak self] in
            guard let self else { return }
            for await _ in Clerk.shared.auth.events {
                if Task.isCancelled { break }
                await self.refresh()
            }
        }
        Task { await refreshWhenReady() }
    }

    private func refreshWhenReady() async {
        _ = await waitUntilClerkIsReady()
        await refresh()
    }

    /// Clerk.configure() starts SDK loading asynchronously. Authentication can be tapped
    /// before that work finishes, especially on a cold launch or slower connection.
    /// Gate every interactive auth action on SDK readiness instead of sending requests
    /// against a client that has not finished loading.
    private func waitUntilClerkIsReady(timeoutAttempts: Int = 80) async -> Bool {
        if !configured { configure() }
        guard configured else { return false }
        if Clerk.shared.isLoaded { return true }

        statusMessage = "Connecting securely…"
        for _ in 0..<timeoutAttempts {
            if Clerk.shared.isLoaded {
                statusMessage = ""
                return true
            }
            try? await Task.sleep(for: .milliseconds(125))
        }
        return fail("Authentication is taking too long to start. Check your connection and try again.")
    }

    func refresh() async {
        guard configured else {
            state = .signedOut
            return
        }
        guard let user = Clerk.shared.user else {
            state = .signedOut
            return
        }
        let email = user.primaryEmailAddress?.emailAddress
            ?? user.emailAddresses.first?.emailAddress
            ?? ""
        let joinedName = [user.firstName, user.lastName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let displayName = !joinedName.isEmpty
            ? joinedName
            : (user.username?.isEmpty == false ? user.username! : (email.split(separator: "@").first.map(String.init) ?? "Blindbandit User"))
        state = .signedIn(displayName: displayName, email: email)
        needsEmailVerification = false
        deletionRequested = false
        statusMessage = ""
    }

    func signInWithEmail(email: String, password: String) async -> Bool {
        busy = true
        defer { busy = false }
        guard await waitUntilClerkIsReady() else { return false }
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard trimmed.contains("@"), password.count >= 8 else {
            return fail("Enter a valid email and a password of at least 8 characters.")
        }
        do {
            _ = try await Clerk.shared.auth.signInWithPassword(identifier: trimmed, password: password)
            await refresh()
            if case .signedIn = state {
                statusMessage = "Signed in."
                AppHaptics.success()
                return true
            }
            return fail("Clerk requires another verification step for this account. Complete it in your account settings, then sign in again.")
        } catch {
            return fail(clerkMessage(error, fallback: "Clerk could not sign you in."))
        }
    }

    func signUpWithEmail(email: String, password: String, name: String) async -> Bool {
        busy = true
        defer { busy = false }
        guard await waitUntilClerkIsReady() else { return false }
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard trimmed.contains("@"), password.count >= 8 else {
            return fail("Enter a valid email and a password of at least 8 characters.")
        }
        let components = name.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ", maxSplits: 1).map(String.init)
        do {
            let signUp = try await Clerk.shared.auth.signUp(
                emailAddress: trimmed,
                password: password,
                firstName: components.first,
                lastName: components.count > 1 ? components[1] : nil
            )
            if signUp.createdSessionId != nil {
                await refresh()
                AppHaptics.success()
                return true
            }
            _ = try await signUp.sendEmailCode()
            needsEmailVerification = true
            statusMessage = "We sent a verification code to \(trimmed). Enter it below to finish creating your account."
            AppHaptics.success()
            return false
        } catch {
            return fail(clerkMessage(error, fallback: "Clerk could not create the account."))
        }
    }

    func verifyPendingEmail(code: String) async -> Bool {
        busy = true
        defer { busy = false }
        guard await waitUntilClerkIsReady() else { return false }
        let cleanCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanCode.isEmpty, let signUp = Clerk.shared.auth.currentSignUp else {
            return fail("Start account creation first, then enter the email verification code.")
        }
        do {
            let verified = try await signUp.verifyEmailCode(cleanCode)
            guard verified.createdSessionId != nil else {
                return fail("That code was accepted, but Clerk still needs another required account field.")
            }
            verificationCodeDraft = ""
            needsEmailVerification = false
            await refresh()
            statusMessage = "Email verified. Your account is ready."
            AppHaptics.success()
            return true
        } catch {
            return fail(clerkMessage(error, fallback: "That verification code was not accepted."))
        }
    }

    func beginGoogleSignIn() async -> Bool {
        busy = true
        defer { busy = false }
        guard await waitUntilClerkIsReady() else { return false }
        do {
            _ = try await Clerk.shared.auth.signInWithOAuth(provider: .google, transferable: true)
            await refresh()
            if case .signedIn = state {
                statusMessage = "Signed in with Google."
                AppHaptics.success()
                return true
            }
            return fail("Google authentication completed, but Clerk did not create an active session.")
        } catch {
            return fail(clerkMessage(error, fallback: "Google sign-in was cancelled or failed."))
        }
    }

    func beginAppleSignIn(credential: ASAuthorizationAppleIDCredential) async -> Bool {
        busy = true
        defer { busy = false }
        guard await waitUntilClerkIsReady() else { return false }
        guard let tokenData = credential.identityToken,
              let token = String(data: tokenData, encoding: .utf8),
              !token.isEmpty else {
            return fail("Apple did not return an identity token. Please try again.")
        }
        do {
            _ = try await Clerk.shared.auth.signInWithIdToken(token, provider: .apple, transferable: true)
            await refresh()
            if case .signedIn = state {
                statusMessage = "Signed in with Apple."
                AppHaptics.success()
                return true
            }
            return fail("Apple authentication completed, but Clerk did not create an active session.")
        } catch {
            return fail(clerkMessage(error, fallback: "Sign in with Apple was cancelled or failed."))
        }
    }

    func sessionToken() async throws -> String {
        guard await waitUntilClerkIsReady() else { throw AuthServiceError.sdkNotReady }
        guard let token = try await Clerk.shared.auth.getToken(), !token.isEmpty else {
            throw AuthServiceError.noActiveSession
        }
        return token
    }

    func requestAccountDeletion() async -> Bool {
        busy = true
        defer { busy = false }
        guard await waitUntilClerkIsReady() else { return false }
        do {
            guard let user = Clerk.shared.user else { return fail("No signed-in Clerk account was found.") }
            try await AccountDeletionService.deleteBlindbanditData()
            _ = try await user.delete()
            deletionRequested = true
            state = .signedOut
            statusMessage = "Your Blindbandit account and associated app data were deleted."
            AppHaptics.warning()
            return true
        } catch {
            return fail(clerkMessage(error, fallback: "The account could not be deleted. No partial deletion was reported as complete."))
        }
    }

    func signOut() async {
        busy = true
        defer { busy = false }
        guard await waitUntilClerkIsReady() else { return }
        do {
            try await Clerk.shared.auth.signOut()
            state = .signedOut
            emailDraft = ""
            passwordDraft = ""
            verificationCodeDraft = ""
            needsEmailVerification = false
            statusMessage = "Signed out."
            AppHaptics.soft()
        } catch {
            _ = fail(clerkMessage(error, fallback: "Clerk could not sign you out."))
        }
    }

    private func fail(_ message: String) -> Bool {
        statusMessage = message
        AppHaptics.warning()
        return false
    }

    private func clerkMessage(_ error: Error, fallback: String) -> String {
        let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return message.isEmpty ? fallback : message
    }
}

enum AuthServiceError: LocalizedError {
    case noActiveSession
    case sdkNotReady

    var errorDescription: String? {
        switch self {
        case .noActiveSession: "Sign in with Clerk before using calls or messages."
        case .sdkNotReady: "Authentication is still starting. Please try again."
        }
    }
}
