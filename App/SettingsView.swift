import SwiftUI
import WebKit
import UIKit

/// All app settings, persisted on this device with UserDefaults (@AppStorage / AppPreferences).
struct Settings: View {
    @EnvironmentObject private var lock: DeviceLock
    @EnvironmentObject private var push: PushNotifications
    @EnvironmentObject private var privacy: PrivacyPermissions
    @EnvironmentObject private var preferences: AppPreferences
    @EnvironmentObject private var auth: ClerkAuthService
    @EnvironmentObject private var communications: ProductionCommunicationsService

    @AppStorage(SettingsKey.appearance) private var appearance = AppAppearance.system.rawValue
    @AppStorage(SettingsKey.highContrast) private var highContrast = false
    @AppStorage(SettingsKey.hapticsEnabled) private var hapticsEnabled = true
    @AppStorage(SettingsKey.speechFeedback) private var speechFeedback = false
    @AppStorage(SettingsKey.speechRate) private var speechRate = 1.0
    @AppStorage(SettingsKey.keepScreenAwake) private var keepScreenAwake = false
    @AppStorage(SettingsKey.uiSounds) private var uiSounds = true
    @AppStorage(SettingsKey.startCallsWithCameraOff) private var startCallsWithCameraOff = false
    @AppStorage(SettingsKey.notifyMessages) private var notifyMessages = true
    @AppStorage(SettingsKey.notifyCalls) private var notifyCalls = true
    @AppStorage(SettingsKey.requireDeviceUnlock) private var requireDeviceUnlock = true

    @State private var confirmSignOut = false
    @State private var confirmClearSessions = false
    @State private var showDeleteAccount = false
    @State private var clearing = false

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? AppConfig.marketingVersion
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        return build.isEmpty ? "Version \(version)" : "Version \(version) (\(build))"
    }

    var body: some View {
        Form {
            accountSection
            notificationsSection
            accessibilitySection
            audioSection
            appearanceSection
            privacySection
            legalSection
            supportSection
            aboutSection
        }
        .navigationTitle("Settings")
        .confirmationDialog("Sign out of Mr. Blindbandit?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Sign out", role: .destructive) {
                communications.reset()
                Task { await auth.signOut() }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Clear website data on this iPhone?", isPresented: $confirmClearSessions, titleVisibility: .visible) {
            Button("Clear website data", role: .destructive) { clearWebsiteData() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Removes cookies, cache and sign-ins used by pages opened inside the app. Your account is not affected.")
        }
        .sheet(isPresented: $showDeleteAccount) {
            DeleteAccountView()
        }
        .onChange(of: speechFeedback) { _, on in if on { SpeechFeedback.say("Speech feedback on") } }
    }

    // MARK: Sections

    private var accountSection: some View {
        Section("Account & profile") {
            if case .signedIn(let name, let email) = auth.state {
                VStack(alignment: .leading, spacing: 4) {
                    Text(name).font(.headline)
                    if !email.isEmpty { Text(email).foregroundStyle(.secondary) }
                    if !communications.myHandle.isEmpty {
                        Text("@\(communications.myHandle)").foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            NavigationLink { Website(url: AppConfig.accountURL, title: "Profile & account") } label: {
                Label("Edit profile, email and password", systemImage: "person.crop.circle")
            }
            Button {
                confirmSignOut = true
            } label: {
                Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
            }
            Button(role: .destructive) {
                showDeleteAccount = true
            } label: {
                Label("Delete account", systemImage: "trash")
            }
            .accessibilityHint("Permanently deletes your account and data after you confirm.")
        }
    }

    private var notificationsSection: some View {
        Section {
            LabeledContent("Notifications", value: push.statusText)
            if push.authorizationStatus == .notDetermined {
                Button("Turn on notifications") { push.requestAuthorization() }
                    .disabled(push.busy)
            } else if push.authorizationStatus == .denied {
                Button("Open iPhone notification settings") { openSystemSettings() }
            }
            Toggle("New messages", isOn: $notifyMessages)
            Toggle("Incoming calls", isOn: $notifyCalls)
        } header: {
            Text("Notifications")
        } footer: {
            Text("Choose which alerts appear while you use the app. iPhone Settings controls alerts when the app is closed.")
        }
    }

    private var accessibilitySection: some View {
        Section {
            Toggle("Haptic feedback", isOn: $hapticsEnabled)
            Toggle("Speech feedback", isOn: $speechFeedback)
            VStack(alignment: .leading) {
                Text("Speech rate: \(speechRateLabel)")
                Slider(value: $speechRate, in: 0.5...2.0, step: 0.25) {
                    Text("Speech rate")
                } onEditingChanged: { editing in
                    if !editing { SpeechFeedback.say("This is the new speech rate") }
                }
                .accessibilityValue(speechRateLabel)
            }
            .disabled(!speechFeedback)
            Toggle("High contrast", isOn: $highContrast)
            Toggle("Reduce motion", isOn: $preferences.reduceAppMotion)
            Toggle("Announce when pages finish loading", isOn: $preferences.announcePageLoads)
            Toggle("Keep screen awake", isOn: $keepScreenAwake)
                .onChange(of: keepScreenAwake) { _, value in UIApplication.shared.isIdleTimerDisabled = value }
            VStack(alignment: .leading) {
                Text("Web page text size: \(Int(preferences.pageZoom * 100))%")
                Slider(value: $preferences.pageZoom, in: 0.75...2.0, step: 0.05) { Text("Web page text size") }
                    .accessibilityValue("\(Int(preferences.pageZoom * 100)) percent")
            }
            Link(destination: AppConfig.accessibilityURL) {
                Label("Accessibility statement", systemImage: "accessibility")
            }
        } header: {
            Text("Accessibility")
        } footer: {
            Text("Speech feedback reads short confirmations aloud when VoiceOver is off. With VoiceOver on, the app uses VoiceOver announcements instead.")
        }
    }

    private var speechRateLabel: String {
        switch speechRate {
        case ..<0.8: return "Slow"
        case ..<1.2: return "Normal"
        case ..<1.6: return "Fast"
        default: return "Very fast"
        }
    }

    private var audioSection: some View {
        Section {
            Toggle("Call and message sounds", isOn: $uiSounds)
            Toggle("Start video calls with camera off", isOn: $startCallsWithCameraOff)
            LabeledContent("Microphone", value: privacy.text(for: privacy.microphone))
            LabeledContent("Camera", value: privacy.text(for: privacy.camera))
            if privacy.microphone == .denied || privacy.camera == .denied {
                Button("Open iPhone settings") { openSystemSettings() }
            }
        } header: {
            Text("Audio & calls")
        } footer: {
            Text("Calls use echo cancellation and noise suppression. The app asks for the microphone and camera only when you start or join a call.")
        }
    }

    private var appearanceSection: some View {
        Section("Appearance") {
            Picker("Theme", selection: $appearance) {
                ForEach(AppAppearance.allCases) { Text($0.title).tag($0.rawValue) }
            }
            .pickerStyle(.inline)
        }
    }

    private var privacySection: some View {
        Section {
            Toggle("Require Face ID or passcode to open", isOn: $requireDeviceUnlock)
            if requireDeviceUnlock {
                Button("Lock now") { lock.lock() }
            }
            Button("Clear website data") { confirmClearSessions = true }
                .disabled(clearing)
            Link(destination: AppConfig.privacyURL) { Label("Privacy Policy", systemImage: "hand.raised") }
            Link(destination: AppConfig.accountDeletionURL) { Label("Request data deletion on the web", systemImage: "globe") }
        } header: {
            Text("Privacy & data")
        } footer: {
            Text("The app does not track you or show ads. Messages, call records and your profile are stored by Blindbandit Records to provide the service; see the Privacy Policy.")
        }
    }

    private var legalSection: some View {
        Section("Legal") {
            Link("Terms of Use", destination: AppConfig.termsURL)
            Link("Privacy Policy", destination: AppConfig.privacyURL)
            NavigationLink("Open-source licenses") { LicensesView() }
        }
    }

    private var supportSection: some View {
        Section("Support") {
            Link(destination: URL(string: "mailto:\(AppConfig.supportEmail)?subject=Mr.%20Blindbandit%20app%20support")!) {
                Label("Email \(AppConfig.supportEmail)", systemImage: "envelope")
            }
            Link(destination: AppConfig.supportURL) { Label("Help center", systemImage: "questionmark.circle") }
        }
    }

    private var aboutSection: some View {
        Section("About") {
            HStack(spacing: 14) {
                BlindbanditLogoImage(size: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Mr. Blindbandit").font(.headline)
                    Text(versionText).foregroundStyle(.secondary)
                    Text("© Blindbandit Records").font(.footnote).foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func clearWebsiteData() {
        clearing = true
        WKWebsiteDataStore.default().removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast) {
            Task { @MainActor in
                clearing = false
                AppHaptics.success()
                SpeechFeedback.say("Website data cleared")
            }
        }
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

/// Two-step account deletion: explain what is deleted, then require typing DELETE.
struct DeleteAccountView: View {
    @EnvironmentObject private var auth: ClerkAuthService
    @EnvironmentObject private var communications: ProductionCommunicationsService
    @Environment(\.dismiss) private var dismiss
    @State private var confirmation = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Deleting your account permanently removes your sign-in, profile, messages, call history and notification devices. This cannot be undone.")
                } header: {
                    Text("What will be deleted")
                }
                Section {
                    TextField("Type DELETE to confirm", text: $confirmation)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                } footer: {
                    Text("For your security, you may be asked to sign in again first. You can also request deletion at mrblindbandit.net/account/delete.")
                }
                if !auth.statusMessage.isEmpty {
                    Section { Text(auth.statusMessage).foregroundStyle(.secondary) }
                }
                Section {
                    Button(role: .destructive) {
                        Task {
                            if await auth.requestAccountDeletion() {
                                communications.reset()
                                dismiss()
                            }
                        }
                    } label: {
                        if auth.busy { ProgressView() } else { Text("Delete my account permanently") }
                    }
                    .disabled(confirmation.trimmingCharacters(in: .whitespaces).uppercased() != "DELETE" || auth.busy)
                }
            }
            .navigationTitle("Delete account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }
}

struct LicensesView: View {
    private let licenses: [(name: String, license: String, url: String)] = [
        ("LiveKit Swift SDK", "Apache License 2.0", "https://github.com/livekit/client-sdk-swift/blob/main/LICENSE"),
        ("LiveKit WebRTC", "BSD 3-Clause License", "https://github.com/livekit/webrtc-xcframework/blob/main/LICENSE"),
        ("LiveKit UniFFI", "Apache License 2.0", "https://github.com/livekit/livekit-uniffi-xcframework"),
        ("SwiftProtobuf", "Apache License 2.0", "https://github.com/apple/swift-protobuf/blob/main/LICENSE.txt"),
        ("Clerk iOS SDK", "MIT License", "https://github.com/clerk/clerk-ios/blob/main/LICENSE"),
        ("Nuke", "MIT License", "https://github.com/kean/Nuke/blob/main/LICENSE"),
        ("PhoneNumberKit", "MIT License", "https://github.com/marmelroy/PhoneNumberKit/blob/master/LICENSE"),
        ("Swift Concurrency Extras", "MIT License", "https://github.com/pointfreeco/swift-concurrency-extras/blob/main/LICENSE")
    ]

    var body: some View {
        List {
            Section {
                ForEach(licenses, id: \.name) { item in
                    Link(destination: URL(string: item.url)!) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name).font(.headline).foregroundStyle(.primary)
                            Text(item.license).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityHint("Opens the full license text")
                }
            } footer: {
                Text("Mr. Blindbandit is built with these open-source libraries. Thank you to their authors.")
            }
        }
        .navigationTitle("Open-source licenses")
    }
}
