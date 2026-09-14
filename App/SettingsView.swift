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
                    BrandMark(size: 54)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Mr. Blind Bandit").font(.headline)
                        Text(versionText).foregroundStyle(.secondary)
                    }
                }
            }

            Section("Advanced") {
                NavigationLink { AdvancedSettingsView() } label: {
                    Label("Site Keys & API", systemImage: "key.horizontal.fill")
                }
                NavigationLink { Website(path: "/account", title: "Account") } label: {
                    Label("Account & Security", systemImage: "person.crop.circle.badge.checkmark")
                }
                Text("Public client settings can be saved on device. Private owner access is stored in the iOS Keychain, not plain preferences.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Notifications") {
                LabeledContent("Push notifications", value: push.statusText)
                if push.authorizationStatus == .notDetermined {
                    Button("Enable push notifications") { push.requestAuthorization() }.disabled(push.busy)
                } else if push.authorizationStatus == .denied {
                    Button("Open notification settings") { openSystemSettings() }
                } else {
                    Button("Refresh notification registration") { Task { await push.refresh() } }
                }
                if push.busy { ProgressView("Requesting notification permission") }
                if !push.registrationError.isEmpty {
                    Text(push.registrationError).font(.footnote).foregroundStyle(.secondary)
                }
            }

            Section("Creator Tools") {
                NavigationLink { NativeAudioConverterView() } label: {
                    Label("Audio Converter", systemImage: "waveform")
                }
                NavigationLink { NativeArtTrackGeneratorView() } label: {
                    Label("Art Track Generator", systemImage: "play.rectangle.fill")
                }
                Toggle("Dark background for artwork tools", isOn: $preferDarkArtworkBackground)
                Toggle("Haptics", isOn: $hapticsEnabled)
            }

            Section("Camera, Microphone & Files") {
                LabeledContent("Camera", value: privacy.text(for: privacy.camera))
                if privacy.camera == .notDetermined {
                    Button("Allow camera access") { privacy.requestCamera() }
                }
                LabeledContent("Microphone", value: privacy.text(for: privacy.microphone))
                if privacy.microphone == .notDetermined {
                    Button("Allow microphone access") { privacy.requestMicrophone() }
                }
                if privacy.camera == .denied || privacy.microphone == .denied {
                    Button("Open app permissions") { openSystemSettings() }
                }
                Text("Native media tools use the iOS document picker. Website-backed tools can request camera or microphone access only from approved Mr. Blind Bandit domains.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Browser") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Website zoom: \(Int(preferences.pageZoom * 100))%")
                    Slider(value: $preferences.pageZoom, in: 0.75...2.0, step: 0.05)
                        .accessibilityLabel("Website page zoom")
                        .accessibilityValue("\(Int(preferences.pageZoom * 100)) percent")
                }
                Toggle("Pull to refresh", isOn: $preferences.pullToRefresh)
                Toggle("Confirm external links", isOn: $confirmBeforeExternalLinks)
                Button("Clear website cache") { clearCache() }.disabled(clearing)
            }

            Section("Accessibility") {
                Toggle("Announce completed page loads", isOn: $preferences.announcePageLoads)
                Toggle("Reduce app motion", isOn: $preferences.reduceAppMotion)
                Toggle("Keep screen awake while app is open", isOn: $keepScreenAwake)
                    .onChange(of: keepScreenAwake) { _, value in UIApplication.shared.isIdleTimerDisabled = value }
                Button("Open iOS accessibility settings") {
                    UIApplication.shared.open(URL(string: "App-Prefs:ACCESSIBILITY") ?? URL(string: UIApplication.openSettingsURLString)!)
                }
                Text("Native controls use semantic labels, Dynamic Type, system focus order, VoiceOver announcements, and standard iOS dialogs. Web screens retain their semantic accessibility tree.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Privacy & Security") {
                Label("Device authentication enabled", systemImage: "lock.shield.fill")
                Button("Lock app now") { lock.lock() }
                Button("Clear website sessions", role: .destructive) { confirmClearSessions = true }.disabled(clearing)
                Button("Open iOS app settings") { openSystemSettings() }
            }

            Section("App Information") {
                LabeledContent("Name", value: "Mr. Blind Bandit")
                LabeledContent("Version", value: versionText)
                LabeledContent("iOS requirement", value: "iOS 17+")
                LabeledContent("Web engine", value: "Apple WebKit")
                LabeledContent("Native media", value: "AVFoundation")
                LabeledContent("Private token storage", value: "iOS Keychain")
            }
        }
        .navigationTitle("Settings")
        .confirmationDialog("Clear website sessions on this iPhone?", isPresented: $confirmClearSessions, titleVisibility: .visible) {
            Button("Clear sessions", role: .destructive) { clearSessions() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes cookies and website storage used by the in-app browser. Other devices are not affected.")
        }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = keepScreenAwake }
    }

    private func clearCache() {
        clearing = true
        WKWebsiteDataStore.default().removeData(ofTypes: [WKWebsiteDataTypeDiskCache, WKWebsiteDataTypeMemoryCache], modifiedSince: .distantPast) {
            Task { @MainActor in clearing = false }
        }
    }

    private func clearSessions() {
        clearing = true
        WKWebsiteDataStore.default().removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast) {
            Task { @MainActor in
                clearing = false
                lock.lock()
            }
        }
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
