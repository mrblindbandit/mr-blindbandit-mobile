import SwiftUI
import WebKit
import UIKit

struct Settings: View {
    @EnvironmentObject private var lock: DeviceLock
    @EnvironmentObject private var push: PushNotifications
    @EnvironmentObject private var privacy: PrivacyPermissions
    @EnvironmentObject private var preferences: AppPreferences

    @AppStorage("keepScreenAwake") private var keepScreenAwake = false
    @AppStorage("hapticsEnabled") private var hapticsEnabled = true
    @AppStorage("preferDarkArtworkBackground") private var preferDarkArtworkBackground = true
    @AppStorage("confirmBeforeExternalLinks") private var confirmBeforeExternalLinks = false
    @State private var confirmClearSessions = false
    @State private var clearing = false

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.4"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "4"
        return "Version \(version) (\(build))"
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    BrandMark(size: 58)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Mr. Blind Bandit")
                            .font(.headline)
                        Text(versionText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Communications") {
                NavigationLink {
                    CommunicationSettingsView()
                } label: {
                    Label("Calls & Messages", systemImage: "phone.and.waveform")
                }

                LabeledContent("Call ringtone", value: "iOS System Default")
                Toggle("Haptics", isOn: $hapticsEnabled)
                    .onChange(of: hapticsEnabled) { _, value in
                        if value { AppHaptics.success() }
                    }
            }

            Section("Notifications") {
                LabeledContent("Push notifications", value: push.statusText)

                if push.authorizationStatus == .notDetermined {
                    Button("Enable Notifications") {
                        AppHaptics.medium()
                        push.requestAuthorization()
                    }
                    .disabled(push.busy)
                } else if push.authorizationStatus == .denied {
                    Button("Open Notification Settings") {
                        AppHaptics.light()
                        openSystemSettings()
                    }
                } else {
                    Button("Refresh Notification Registration") {
                        AppHaptics.light()
                        Task { await push.refresh() }
                    }
                }

                if push.busy {
                    ProgressView("Requesting permission")
                }
                if !push.registrationError.isEmpty {
                    Text(push.registrationError)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Privacy & Permissions") {
                LabeledContent("Camera", value: privacy.text(for: privacy.camera))
                if privacy.camera == .notDetermined {
                    Button("Allow Camera") {
                        AppHaptics.medium()
                        privacy.requestCamera()
                    }
                }

                LabeledContent("Microphone", value: privacy.text(for: privacy.microphone))
                if privacy.microphone == .notDetermined {
                    Button("Allow Microphone") {
                        AppHaptics.medium()
                        privacy.requestMicrophone()
                    }
                }

                if privacy.camera == .denied || privacy.microphone == .denied {
                    Button("Open App Permissions") {
                        AppHaptics.light()
                        openSystemSettings()
                    }
                }

                NavigationLink { Website(path: "/account", title: "Account") } label: {
                    Label("Account & Security", systemImage: "person.crop.circle.badge.checkmark")
                }

                Button("Lock App Now") {
                    AppHaptics.rigid()
                    lock.lock()
                }
            }

            Section("Creator Tools") {
                NavigationLink { CreatorHubView() } label: {
                    Label("Creator Hub", systemImage: "wand.and.stars")
                }
                NavigationLink { NativeAudioConverterView() } label: {
                    Label("Audio Converter", systemImage: "waveform")
                }
                NavigationLink { NativeArtTrackGeneratorView() } label: {
                    Label("Art Track Generator", systemImage: "play.rectangle.fill")
                }
                Toggle("Dark Artwork Background", isOn: $preferDarkArtworkBackground)
                    .onChange(of: preferDarkArtworkBackground) { _, _ in AppHaptics.selection() }
            }

            Section("Accessibility") {
                Toggle("Announce Completed Page Loads", isOn: $preferences.announcePageLoads)
                    .onChange(of: preferences.announcePageLoads) { _, _ in AppHaptics.selection() }
                Toggle("Reduce App Motion", isOn: $preferences.reduceAppMotion)
                    .onChange(of: preferences.reduceAppMotion) { _, _ in AppHaptics.selection() }
                Toggle("Keep Screen Awake", isOn: $keepScreenAwake)
                    .onChange(of: keepScreenAwake) { _, value in
                        UIApplication.shared.isIdleTimerDisabled = value
                        AppHaptics.selection()
                    }
                Button("Open iOS Accessibility Settings") {
                    AppHaptics.light()
                    UIApplication.shared.open(URL(string: "App-Prefs:ACCESSIBILITY") ?? URL(string: UIApplication.openSettingsURLString)!)
                }
            }

            Section("Web & Data") {
                VStack(alignment: .leading, spacing: 8) {
                    LabeledContent("Website Zoom", value: "\(Int(preferences.pageZoom * 100))%")
                    Slider(value: $preferences.pageZoom, in: 0.75...2.0, step: 0.05)
                        .accessibilityLabel("Website page zoom")
                        .accessibilityValue("\(Int(preferences.pageZoom * 100)) percent")
                        .onChange(of: preferences.pageZoom) { _, _ in AppHaptics.selection() }
                }
                Toggle("Pull to Refresh", isOn: $preferences.pullToRefresh)
                    .onChange(of: preferences.pullToRefresh) { _, _ in AppHaptics.selection() }
                Toggle("Confirm External Links", isOn: $confirmBeforeExternalLinks)
                    .onChange(of: confirmBeforeExternalLinks) { _, _ in AppHaptics.selection() }
                Button("Clear Website Cache") {
                    AppHaptics.warning()
                    clearCache()
                }
                .disabled(clearing)
                Button("Clear Website Sessions", role: .destructive) {
                    AppHaptics.warning()
                    confirmClearSessions = true
                }
                .disabled(clearing)
            }

            Section("Advanced") {
                NavigationLink { AdvancedSettingsView() } label: {
                    Label("Site Keys & API", systemImage: "key.horizontal.fill")
                }
                Button("Open iOS App Settings") {
                    AppHaptics.light()
                    openSystemSettings()
                }
            }

            Section("About") {
                LabeledContent("App", value: "Mr. Blind Bandit")
                LabeledContent("Version", value: versionText)
                LabeledContent("Minimum iOS", value: "iOS 17")
                LabeledContent("Web Engine", value: "WebKit")
                LabeledContent("Native Media", value: "AVFoundation")
                LabeledContent("Calling", value: "LiveKit + CallKit")
            }
        }
        .navigationTitle("Settings")
        .confirmationDialog("Clear website sessions on this iPhone?", isPresented: $confirmClearSessions, titleVisibility: .visible) {
            Button("Clear Sessions", role: .destructive) {
                AppHaptics.heavy()
                clearSessions()
            }
            Button("Cancel", role: .cancel) { AppHaptics.light() }
        } message: {
            Text("This signs out website-backed screens on this iPhone.")
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = keepScreenAwake
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
