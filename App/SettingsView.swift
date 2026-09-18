import SwiftUI
import WebKit
import UIKit

struct Settings: View {
    @EnvironmentObject private var lock: DeviceLock
    @EnvironmentObject private var push: PushNotifications
    @EnvironmentObject private var privacy: PrivacyPermissions
    @EnvironmentObject private var preferences: AppPreferences
    @EnvironmentObject private var auth: ClerkAuthService

    @AppStorage("keepScreenAwake") private var keepScreenAwake = false
    @AppStorage("hapticsEnabled") private var hapticsEnabled = true
    @AppStorage("preferDarkArtworkBackground") private var preferDarkArtworkBackground = true
    @AppStorage("confirmBeforeExternalLinks") private var confirmBeforeExternalLinks = false
    @State private var confirmClearSessions = false
    @State private var confirmDeleteAccount = false
    @State private var clearing = false

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.5"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "5"
        return "Version \(version) (\(build))"
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    BlindbanditLogoImage(size: 54)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Mr. Blind Bandit").font(.headline)
                        Text(versionText).foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
            }

            Section("Account") {
                switch auth.state {
                case .signedIn(let name, let email):
                    LabeledContent("Signed in", value: name)
                    LabeledContent("Email", value: email)
                    Button("Sign out", role: .destructive) {
                        AppHaptics.warning()
                        Task { await auth.signOut() }
                    }
                default:
                    Text("Not signed in")
                }
                NavigationLink { Website(path: "/account", title: "Account") } label: {
                    Label("Manage account on the web", systemImage: "person.crop.circle.badge.checkmark")
                }
                Button("Delete account…", role: .destructive) {
                    AppHaptics.warning()
                    confirmDeleteAccount = true
                }
                .accessibilityHint("Requests permanent account deletion. Required for App Store compliance.")
                if auth.deletionRequested {
                    Text("A deletion request is on file for this device. Confirm on the website if prompted.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Communications") {
                NavigationLink { ConnectHubView() } label: {
                    Label("Calls, chat & voice notes", systemImage: "phone.and.waveform.fill")
                }
                LabeledContent("LiveKit", value: AppConfig.isLiveKitConfigured ? "Configured" : "Needs URL")
                LabeledContent("Clerk", value: AppConfig.isClerkConfigured ? "Configured" : "Needs publishable key")
                Text("Voice and video use LiveKit with short-lived server tokens. API secrets never ship in the app.")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            Section("Notifications") {
                LabeledContent("Push notifications", value: push.statusText)
                if push.authorizationStatus == .notDetermined {
                    Button("Enable push notifications") {
                        AppHaptics.medium()
                        push.requestAuthorization()
                    }
                    .disabled(push.busy)
                } else if push.authorizationStatus == .denied {
                    Button("Open notification settings") {
                        AppHaptics.light()
                        openSystemSettings()
                    }
                } else {
                    Button("Refresh notification registration") {
                        AppHaptics.light()
                        Task { await push.refresh() }
                    }
                }
                if push.busy { ProgressView("Requesting notification permission") }
                if !push.registrationError.isEmpty {
                    Text(push.registrationError).font(.footnote).foregroundStyle(.secondary)
                }
            }

            Section("Appearance & media") {
                Toggle("Dark background for artwork tools", isOn: $preferDarkArtworkBackground)
                    .onChange(of: preferDarkArtworkBackground) { _, _ in AppHaptics.selection() }
                Toggle("Haptics", isOn: $hapticsEnabled)
                    .onChange(of: hapticsEnabled) { _, value in
                        if value { AppHaptics.success() }
                    }
                NavigationLink { NativeAudioConverterView() } label: {
                    Label("Audio Converter", systemImage: "waveform")
                }
                NavigationLink { NativeArtTrackGeneratorView() } label: {
                    Label("Art Track Generator", systemImage: "play.rectangle.fill")
                }
            }

            Section("Camera, microphone & files") {
                LabeledContent("Camera", value: privacy.text(for: privacy.camera))
                if privacy.camera == .notDetermined {
                    Button("Allow camera access") {
                        AppHaptics.medium()
                        privacy.requestCamera()
                    }
                    .accessibilityHint("Used for video calls and creator uploads you start.")
                }
                LabeledContent("Microphone", value: privacy.text(for: privacy.microphone))
                if privacy.microphone == .notDetermined {
                    Button("Allow microphone access") {
                        AppHaptics.medium()
                        privacy.requestMicrophone()
                    }
                    .accessibilityHint("Used for voice calls, voice notes, and recording tools.")
                }
                if privacy.camera == .denied || privacy.microphone == .denied {
                    Button("Open app permissions") {
                        AppHaptics.light()
                        openSystemSettings()
                    }
                }
                Text("Permissions are requested only when you start a call, voice note, or media action. Website tools request camera or microphone only on approved Mr. Blind Bandit domains.")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            Section("Browser") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Website zoom: \(Int(preferences.pageZoom * 100))%")
                    Slider(value: $preferences.pageZoom, in: 0.75...2.0, step: 0.05)
                        .accessibilityLabel("Website page zoom")
                        .accessibilityValue("\(Int(preferences.pageZoom * 100)) percent")
                        .onChange(of: preferences.pageZoom) { _, _ in AppHaptics.selection() }
                }
                Toggle("Pull to refresh", isOn: $preferences.pullToRefresh)
                    .onChange(of: preferences.pullToRefresh) { _, _ in AppHaptics.selection() }
                Toggle("Confirm external links", isOn: $confirmBeforeExternalLinks)
                    .onChange(of: confirmBeforeExternalLinks) { _, _ in AppHaptics.selection() }
                Button("Clear website cache") {
                    AppHaptics.warning()
                    clearCache()
                }
                .disabled(clearing)
            }

            Section("Accessibility") {
                Toggle("Announce completed page loads", isOn: $preferences.announcePageLoads)
                    .onChange(of: preferences.announcePageLoads) { _, _ in AppHaptics.selection() }
                Toggle("Reduce app motion", isOn: $preferences.reduceAppMotion)
                    .onChange(of: preferences.reduceAppMotion) { _, _ in AppHaptics.selection() }
                Toggle("Keep screen awake while app is open", isOn: $keepScreenAwake)
                    .onChange(of: keepScreenAwake) { _, value in
                        UIApplication.shared.isIdleTimerDisabled = value
                        AppHaptics.selection()
                    }
                Button("Open iOS accessibility settings") {
                    AppHaptics.light()
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Text("Controls use labels, hints, values, Dynamic Type, VoiceOver announcements, and standard focus order. Auth, Connect, Listen, and musician tools are labeled for VoiceOver.")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            Section("Privacy & security") {
                Label("Device authentication enabled", systemImage: "lock.shield.fill")
                Button("Lock app now") {
                    AppHaptics.rigid()
                    lock.lock()
                }
                Button("Clear website sessions", role: .destructive) {
                    AppHaptics.warning()
                    confirmClearSessions = true
                }
                .disabled(clearing)
                Button("Open iOS app settings") {
                    AppHaptics.light()
                    openSystemSettings()
                }
                Link("Privacy Policy", destination: URL(string: "https://mrblindbandit.net/privacy/")!)
                Link("Terms of Use", destination: URL(string: "https://mrblindbandit.net/terms/")!)
                Text("See Privacy Policy for Clerk auth data, LiveKit call media, and push notification tokens.")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            Section("Advanced") {
                NavigationLink { AdvancedSettingsView() } label: {
                    Label("Site Keys & API", systemImage: "key.horizontal.fill")
                }
                Text("Public client settings stay on device. Private owner tokens use the iOS Keychain. Clerk secret keys and LiveKit API secrets never ship in the binary.")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            Section("Legal & compliance") {
                LabeledContent("Export compliance", value: "HTTPS / standard encryption only")
                LabeledContent("Sign in with Apple", value: "Enabled")
                LabeledContent("Account deletion", value: "In-app + web")
                Link("Privacy Policy", destination: URL(string: "https://mrblindbandit.net/privacy/")!)
                Link("Terms of Use", destination: URL(string: "https://mrblindbandit.net/terms/")!)
            }

            Section("App information") {
                LabeledContent("Name", value: "Mr. Blind Bandit")
                LabeledContent("Version", value: versionText)
                LabeledContent("iOS requirement", value: "iOS 17+")
                LabeledContent("Auth", value: "Clerk")
                LabeledContent("Realtime", value: "LiveKit")
                LabeledContent("Web engine", value: "Apple WebKit")
                LabeledContent("Native media", value: "AVFoundation")
                LabeledContent("Private token storage", value: "iOS Keychain")
            }
        }
        .navigationTitle("Settings")
        .confirmationDialog("Clear website sessions on this iPhone?", isPresented: $confirmClearSessions, titleVisibility: .visible) {
            Button("Clear sessions", role: .destructive) {
                AppHaptics.heavy()
                clearSessions()
            }
            Button("Cancel", role: .cancel) { AppHaptics.light() }
        } message: {
            Text("This removes cookies and website storage used by the in-app browser. Other devices are not affected.")
        }
        .confirmationDialog("Delete your Mr. Blind Bandit account?", isPresented: $confirmDeleteAccount, titleVisibility: .visible) {
            Button("Delete account", role: .destructive) {
                AppHaptics.heavy()
                Task {
                    _ = await auth.requestAccountDeletion()
                    if let url = URL(string: "https://mrblindbandit.net/account") {
                        await UIApplication.shared.open(url)
                    }
                }
            }
            Button("Cancel", role: .cancel) { AppHaptics.light() }
        } message: {
            Text("This requests permanent deletion of your account and associated data (App Store Guideline 5.1.1). You will be signed out. Confirm on the website if prompted. This cannot be undone.")
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = keepScreenAwake
            AppHaptics.soft()
        }
    }

    private func clearCache() {
        clearing = true
        WKWebsiteDataStore.default().removeData(ofTypes: [WKWebsiteDataTypeDiskCache, WKWebsiteDataTypeMemoryCache], modifiedSince: .distantPast) {
            Task { @MainActor in
                clearing = false
                AppHaptics.success()
            }
        }
    }

    private func clearSessions() {
        clearing = true
        WKWebsiteDataStore.default().removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast) {
            Task { @MainActor in
                clearing = false
                AppHaptics.success()
                lock.lock()
            }
        }
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
