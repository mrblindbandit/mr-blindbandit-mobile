import SwiftUI
import AVFoundation
import LocalAuthentication
import UserNotifications

/// First-launch permission walkthrough: one screen per permission the app uses, each with a plain
/// reason, Continue (asks iOS) and Skip. Shown once after sign-in; every permission can be changed
/// later in Settings.
struct PermissionsOnboarding: View {
    @EnvironmentObject private var push: PushNotifications
    @EnvironmentObject private var privacy: PrivacyPermissions
    @AppStorage("permissionsOnboardingDone") private var done = false
    @State private var index = 0
    @State private var busy = false
    @AccessibilityFocusState private var titleFocused: Bool

    struct Step: Identifiable {
        let id: String
        let symbol: String
        let title: String
        let reason: String
    }

    static let steps: [Step] = [
        Step(id: "notifications", symbol: "bell.badge.fill", title: "Call and message alerts",
             reason: "Get notified when a Blindbandit member calls or messages you, even when the app is closed."),
        Step(id: "microphone", symbol: "mic.fill", title: "Microphone",
             reason: "Needed for voice and video calls, voice notes and recordings you start in the creator tools."),
        Step(id: "camera", symbol: "video.fill", title: "Camera",
             reason: "Used only when you start or join a video call. You can always join with the camera off."),
        Step(id: "faceid", symbol: "faceid", title: "Face ID",
             reason: "Lets you lock the app with Face ID. The app lock stays off until you turn it on in Settings."),
    ]

    var body: some View {
        let step = Self.steps[index]
        VStack(spacing: 28) {
            Spacer()
            Image(systemName: step.symbol)
                .font(.system(size: 56, weight: .semibold))
                .foregroundStyle(Brand.gold)
                .frame(width: 120, height: 120)
                .background(Image("BBIconTile").resizable())
                .accessibilityHidden(true)
            VStack(spacing: 12) {
                Text(step.title)
                    .font(.title.bold())
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused($titleFocused)
                Text(step.reason)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal)
            Text("Step \(index + 1) of \(Self.steps.count)")
                .font(.footnote).foregroundStyle(.secondary)
            Spacer()
            VStack(spacing: 12) {
                Button {
                    Task { await allow(step) }
                } label: {
                    Text("Continue").font(.headline).frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.borderedProminent)
                .tint(Brand.goldDeep)
                .disabled(busy)
                .accessibilityHint("Asks iPhone for \(step.title.lowercased()) permission")
                Button("Skip") { advance() }
                    .frame(minHeight: 44)
                    .disabled(busy)
                    .accessibilityHint("Continues without this permission. You can change it later in Settings.")
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .onAppear { titleFocused = true }
    }

    private func allow(_ step: Step) async {
        busy = true
        defer { busy = false }
        switch step.id {
        case "notifications": await push.requestAuthorizationAsync()
        case "microphone": _ = await privacy.requestMicrophone()
        case "camera": _ = await privacy.requestCamera()
        case "faceid":
            let context = LAContext()
            if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) {
                _ = try? await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,
                                                      localizedReason: "Allow Face ID so you can lock the app later.")
            }
        default: break
        }
        advance()
    }

    private func advance() {
        if index + 1 < Self.steps.count {
            index += 1
            titleFocused = true
        } else {
            done = true
        }
    }
}
