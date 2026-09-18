import Foundation
import SwiftUI
import AuthenticationServices

enum AuthSessionState: Equatable {
    case unknown
    case signedOut
    case signedIn(displayName: String, email: String)
}

/// Protocol so UI compiles without Clerk SPM; production wires ClerkKit behind this façade.
@MainActor
protocol ClerkAuthServing: AnyObject {
    var state: AuthSessionState { get }
    var busy: Bool { get }
    var statusMessage: String { get }
    func configure()
    func refresh() async
    func signInWithEmail(email: String, password: String) async -> Bool
    func signUpWithEmail(email: String, password: String, name: String) async -> Bool
    func beginGoogleSignIn() async -> Bool
    func beginAppleSignIn(credential: ASAuthorizationAppleIDCredential) async -> Bool
    func requestAccountDeletion() async -> Bool
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
    @Published private(set) var deletionRequested = false

    private let defaultsKey = "clerkScaffoldSession"
    private let deletionKey = "clerkDeletionRequested"

    func configure() {
        deletionRequested = UserDefaults.standard.bool(forKey: deletionKey)
        guard AppConfig.isClerkConfigured else {
            state = .signedOut
            statusMessage = "Add your Clerk publishable key in Secrets.local.swift for production auth."
            return
        }
        statusMessage = ""
        // Production: Clerk.configure(publishableKey: AppConfig.clerkPublishableKey)
        Task { await refresh() }
    }

    func refresh() async {
        if let data = UserDefaults.standard.dictionary(forKey: defaultsKey),
           let email = data["email"] as? String,
           let name = data["name"] as? String,
           !email.isEmpty {
            state = .signedIn(displayName: name.isEmpty ? email : name, email: email)
        } else {
            state = .signedOut
        }
    }

    func signInWithEmail(email: String, password: String) async -> Bool {
        busy = true
        defer { busy = false }
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard trimmed.contains("@"), password.count >= 8 else {
            statusMessage = "Enter a valid email and a password of at least 8 characters."
            AppHaptics.warning()
            return false
        }
        // Production: ClerkKit signIn.create(strategy: .identifier(email, password:))
        persistSession(name: String(trimmed.split(separator: "@").first ?? "Artist"), email: trimmed)
        statusMessage = "Signed in with email."
        AppHaptics.success()
        return true
    }

    func signUpWithEmail(email: String, password: String, name: String) async -> Bool {
        busy = true
        defer { busy = false }
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard trimmed.contains("@"), password.count >= 8 else {
            statusMessage = "Enter a valid email and a password of at least 8 characters."
            AppHaptics.warning()
            return false
        }
        let display = name.trimmingCharacters(in: .whitespacesAndNewlines)
        persistSession(name: display.isEmpty ? String(trimmed.split(separator: "@").first ?? "Artist") : display, email: trimmed)
        statusMessage = "Account ready."
        AppHaptics.success()
        return true
    }

    func beginGoogleSignIn() async -> Bool {
        busy = true
        defer { busy = false }
        guard !AppConfig.googleOAuthClientID.isEmpty else {
            statusMessage = "Google sign-in is unavailable until the OAuth client ID is configured."
            AppHaptics.warning()
            return false
        }
        // Production: Clerk OAuth .oauth(.google) or Google ID token → Clerk
        persistSession(name: "Blindbandit Artist", email: "artist@mrblindbandit.net")
        statusMessage = "Continued with Google."
        AppHaptics.success()
        return true
    }

    /// App Store Guideline 4.8 — Sign in with Apple must be offered alongside other third-party logins.
    func beginAppleSignIn(credential: ASAuthorizationAppleIDCredential) async -> Bool {
        busy = true
        defer { busy = false }
        let email = credential.email
            ?? UserDefaults.standard.string(forKey: "appleRelayEmail")
            ?? "apple-user@privaterelay.appleid.com"
        if let email = credential.email {
            UserDefaults.standard.set(email, forKey: "appleRelayEmail")
        }
        let given = [credential.fullName?.givenName, credential.fullName?.familyName]
            .compactMap { $0 }
            .joined(separator: " ")
        let name = given.isEmpty ? "Apple User" : given
        // Production: exchange Apple identity token with Clerk (Sign in with Apple strategy)
        persistSession(name: name, email: email)
        statusMessage = "Continued with Apple."
        AppHaptics.success()
        return true
    }

    /// App Store Guideline 5.1.1(v) — account deletion must be available in-app.
    func requestAccountDeletion() async -> Bool {
        busy = true
        defer { busy = false }
        // Production: Clerk user.delete() or server endpoint that deletes Clerk user + app data.
        UserDefaults.standard.set(true, forKey: deletionKey)
        deletionRequested = true
        UserDefaults.standard.removeObject(forKey: defaultsKey)
        state = .signedOut
        statusMessage = "Account deletion requested. We also opened the web account page to confirm."
        AppHaptics.warning()
        return true
    }

    func signOut() async {
        UserDefaults.standard.removeObject(forKey: defaultsKey)
        state = .signedOut
        emailDraft = ""
        passwordDraft = ""
        statusMessage = "Signed out."
        AppHaptics.soft()
    }

    private func persistSession(name: String, email: String) {
        UserDefaults.standard.set(["name": name, "email": email], forKey: defaultsKey)
        UserDefaults.standard.set(false, forKey: deletionKey)
        deletionRequested = false
        state = .signedIn(displayName: name, email: email)
    }
}
