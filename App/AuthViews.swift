import SwiftUI
import AuthenticationServices

/// Natural consumer onboarding — Continue with Apple, Google, and email (App Store 4.8).
struct AuthGatewayView: View {
    @ObservedObject var auth: ClerkAuthService
    @EnvironmentObject private var preferences: AppPreferences
    @State private var mode: Mode = .landing
    @FocusState private var focusedField: Field?

    enum Mode { case landing, emailSignIn, emailSignUp }
    enum Field { case email, password, name }

    var body: some View {
        ZStack {
            LinearGradient(colors: [.black, Color(white: 0.12), Color(white: 0.18)], startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 28) {
                    VStack(spacing: 16) {
                        SpinningBrandLogo(size: 120, reduceMotion: preferences.reduceAppMotion)
                        Text("Mr. Blind Bandit")
                            .font(.system(.largeTitle, design: .rounded, weight: .heavy))
                            .foregroundStyle(.white)
                            .accessibilityAddTraits(.isHeader)
                        Text("Music · Creator Tools · Calls · Blindbandit Records")
                            .font(.headline)
                            .foregroundStyle(.white.opacity(0.78))
                            .multilineTextAlignment(.center)
                        Text("Sign in to unlock your studio, calls, and messages.")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.65))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .padding(.top, 36)

                    switch mode {
                    case .landing: landingCards
                    case .emailSignIn: emailForm(isSignUp: false)
                    case .emailSignUp: emailForm(isSignUp: true)
                    }

                    if !auth.statusMessage.isEmpty {
                        Text(auth.statusMessage)
                            .font(.footnote)
                            .foregroundStyle(.yellow)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }

                    legalFooter

                    if !AppConfig.isClerkConfigured {
                        Text("Clerk publishable key missing — add Secrets.local.swift for production auth.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 28)
            }
        }
        .onAppear {
            auth.configure()
            AppHaptics.soft()
        }
    }

    private var landingCards: some View {
        VStack(spacing: 14) {
            // Sign in with Apple first (Guideline 4.8 equivalent prominence)
            SignInWithAppleButton(.continue) { request in
                request.requestedScopes = [.fullName, .email]
            } onCompletion: { result in
                switch result {
                case .success(let authResult):
                    guard let credential = authResult.credential as? ASAuthorizationAppleIDCredential else {
                        auth.statusMessage = "Apple sign-in did not return a usable credential."
                        AppHaptics.warning()
                        return
                    }
                    Task { _ = await auth.beginAppleSignIn(credential: credential) }
                case .failure(let error):
                    auth.statusMessage = "Apple sign-in cancelled or failed: \(error.localizedDescription)"
                    AppHaptics.warning()
                }
            }
            .signInWithAppleButtonStyle(.white)
            .frame(height: 52)
            .accessibilityLabel("Continue with Apple")

            Button {
                AppHaptics.medium()
                Task { _ = await auth.beginGoogleSignIn() }
            } label: {
                Label("Continue with Google", systemImage: "g.circle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
            .buttonStyle(.borderedProminent)
            .tint(.white)
            .foregroundStyle(.black)
            .disabled(auth.busy)
            .accessibilityHint("Signs in with Google through Clerk.")

            Button {
                AppHaptics.selection()
                mode = .emailSignIn
            } label: {
                Label("Continue with email", systemImage: "envelope.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
            .buttonStyle(.bordered)
            .tint(.yellow)
            .disabled(auth.busy)
            .accessibilityHint("Opens email and password sign-in.")

            Button {
                AppHaptics.selection()
                mode = .emailSignUp
            } label: {
                Text("Create an account")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.yellow)
            }

            if auth.busy {
                ProgressView("Working…").tint(.yellow).accessibilityLabel("Signing in")
            }
        }
        .padding(20)
        .background(.ultraThinMaterial.opacity(0.9), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.yellow.opacity(0.28), lineWidth: 1))
    }

    private func emailForm(isSignUp: Bool) -> some View {
        VStack(spacing: 14) {
            Text(isSignUp ? "Create your account" : "Welcome back")
                .font(.title2.bold())
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)

            if isSignUp {
                TextField("Display name", text: $auth.nameDraft)
                    .textContentType(.name)
                    .focused($focusedField, equals: .name)
                    .padding()
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(.white)
                    .accessibilityLabel("Display name")
            }

            TextField("Email", text: $auth.emailDraft)
                .textContentType(.username)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focusedField, equals: .email)
                .padding()
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                .foregroundStyle(.white)
                .accessibilityLabel("Email address")

            SecureField("Password", text: $auth.passwordDraft)
                .textContentType(isSignUp ? .newPassword : .password)
                .focused($focusedField, equals: .password)
                .padding()
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                .foregroundStyle(.white)
                .accessibilityLabel("Password")
                .accessibilityHint("At least 8 characters.")

            Button {
                AppHaptics.medium()
                Task {
                    if isSignUp {
                        _ = await auth.signUpWithEmail(email: auth.emailDraft, password: auth.passwordDraft, name: auth.nameDraft)
                    } else {
                        _ = await auth.signInWithEmail(email: auth.emailDraft, password: auth.passwordDraft)
                    }
                }
            } label: {
                Text(isSignUp ? "Create account" : "Sign in")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
            .buttonStyle(.borderedProminent)
            .tint(.yellow)
            .foregroundStyle(.black)
            .disabled(auth.busy)

            Button(isSignUp ? "Already have an account? Sign in" : "Need an account? Create one") {
                AppHaptics.selection()
                mode = isSignUp ? .emailSignIn : .emailSignUp
            }
            .font(.subheadline)
            .foregroundStyle(.white.opacity(0.8))

            Button("Back") {
                AppHaptics.light()
                mode = .landing
            }
            .foregroundStyle(.yellow)

            if auth.busy { ProgressView().tint(.yellow) }
        }
        .padding(20)
        .background(.ultraThinMaterial.opacity(0.9), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.yellow.opacity(0.28), lineWidth: 1))
    }

    private var legalFooter: some View {
        VStack(spacing: 8) {
            Text("By continuing you agree to the Terms of Use and acknowledge the Privacy Policy.")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.45))
                .multilineTextAlignment(.center)
            HStack(spacing: 16) {
                Link("Privacy Policy", destination: URL(string: "https://mrblindbandit.net/privacy/")!)
                Link("Terms of Use", destination: URL(string: "https://mrblindbandit.net/terms/")!)
            }
            .font(.caption.weight(.semibold))
            .tint(.yellow)
        }
        .padding(.horizontal, 12)
    }
}
