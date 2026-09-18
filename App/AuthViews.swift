import SwiftUI
import AuthenticationServices

/// Production Clerk onboarding — Google OAuth + passwordless email-code sign-in.
struct AuthGatewayView: View {
    @ObservedObject var auth: ClerkAuthService
    @EnvironmentObject private var preferences: AppPreferences
    @State private var mode: Mode = .landing
    @FocusState private var focusedField: Field?

    enum Mode { case landing, emailSignIn, emailSignUp, verifyCode }
    enum Field { case email, name, code }

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
                        Text("Sign in securely with Clerk to use calls and messages.")
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
                    case .verifyCode: verificationForm
                    }

                    if !auth.statusMessage.isEmpty {
                        Text(auth.statusMessage)
                            .font(.footnote)
                            .foregroundStyle(.yellow)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                            .accessibilityAddTraits(.updatesFrequently)
                    }

                    legalFooter

                    if !AppConfig.isClerkConfigured {
                        Text("Clerk publishable key missing. Authentication is unavailable on this build.")
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
            if auth.pendingVerification != nil { mode = .verifyCode }
            AppHaptics.soft()
        }
        .onChange(of: auth.pendingVerification) { _, pending in
            if pending != nil { mode = .verifyCode }
        }
    }

    private var landingCards: some View {
        VStack(spacing: 14) {
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
            .disabled(auth.busy || !AppConfig.isClerkConfigured)
            .accessibilityHint("Signs in with Google using the production Clerk account system.")

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
            .disabled(auth.busy || !AppConfig.isClerkConfigured)
            .accessibilityHint("Clerk emails you a one-time sign-in code. No password is stored by this app.")

            if AppConfig.enableSignInWithApple {
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
            }

            Button {
                AppHaptics.selection()
                mode = .emailSignUp
            } label: {
                Text("Create an account")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.yellow)
            }
            .disabled(auth.busy || !AppConfig.isClerkConfigured)

            if auth.busy {
                ProgressView("Working with Clerk…")
                    .tint(.yellow)
                    .accessibilityLabel("Authenticating with Clerk")
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

            Text("Clerk will send a one-time verification code to your email.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
                .frame(maxWidth: .infinity, alignment: .leading)

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
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focusedField, equals: .email)
                .padding()
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                .foregroundStyle(.white)
                .accessibilityLabel("Email address")

            Button {
                AppHaptics.medium()
                Task {
                    let success: Bool
                    if isSignUp {
                        success = await auth.beginEmailSignUp(email: auth.emailDraft, name: auth.nameDraft)
                    } else {
                        success = await auth.beginEmailSignIn(email: auth.emailDraft)
                    }
                    if success, auth.pendingVerification != nil { mode = .verifyCode }
                }
            } label: {
                Text(isSignUp ? "Create account & send code" : "Send sign-in code")
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
                auth.cancelEmailVerification()
                mode = .landing
            }
            .foregroundStyle(.yellow)

            if auth.busy { ProgressView().tint(.yellow) }
        }
        .padding(20)
        .background(.ultraThinMaterial.opacity(0.9), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.yellow.opacity(0.28), lineWidth: 1))
    }

    private var verificationForm: some View {
        VStack(spacing: 14) {
            Text("Check your email")
                .font(.title2.bold())
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)

            Text("Enter the one-time Clerk code sent to \(auth.pendingVerification?.email ?? auth.emailDraft).")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.72))
                .frame(maxWidth: .infinity, alignment: .leading)

            TextField("Verification code", text: $auth.verificationCodeDraft)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .focused($focusedField, equals: .code)
                .padding()
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                .foregroundStyle(.white)
                .accessibilityLabel("Verification code")

            Button {
                AppHaptics.medium()
                Task { _ = await auth.verifyEmailCode(auth.verificationCodeDraft) }
            } label: {
                Text("Verify & continue")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
            .buttonStyle(.borderedProminent)
            .tint(.yellow)
            .foregroundStyle(.black)
            .disabled(auth.busy || auth.verificationCodeDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Button("Use a different email") {
                AppHaptics.light()
                auth.cancelEmailVerification()
                mode = .emailSignIn
            }
            .foregroundStyle(.yellow)

            if auth.busy { ProgressView("Verifying…").tint(.yellow) }
        }
        .padding(20)
        .background(.ultraThinMaterial.opacity(0.9), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.yellow.opacity(0.28), lineWidth: 1))
        .onAppear { focusedField = .code }
    }

    private var legalFooter: some View {
        VStack(spacing: 8) {
            Text("By continuing you agree to the Terms of Use and acknowledge the Privacy Policy.")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.45))
                .multilineTextAlignment(.center)
            HStack(spacing: 16) {
                Link("Privacy Policy", destination: URL(string: "https://mrblindbandit.net/privacy")!)
                Link("Terms of Use", destination: URL(string: "https://mrblindbandit.net/terms/")!)
            }
            .font(.caption.weight(.semibold))
            .tint(.yellow)
        }
        .padding(.horizontal, 12)
    }
}
