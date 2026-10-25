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
    @AppStorage("ambientUITheme") private var ambientUITheme = false
    @State private var showingRingtones = false
    @State private var showingTextTones = false
    @State private var testNotificationMessage = ""
    @State private var sendingTest = false
    @AppStorage("selectedRingtone") private var ringtoneID = CallSounds.Ringtone.mrBlindBandit.rawValue
    @AppStorage("selectedNotificationTone") private var textToneID = CallSounds.NotificationTone.message.rawValue
    @AppStorage(SettingsKey.startCallsWithCameraOff) private var startCallsWithCameraOff = false
    @AppStorage(SettingsKey.notifyMessages) private var notifyMessages = true
    @AppStorage(SettingsKey.notifyCalls) private var notifyCalls = true
    @AppStorage(SettingsKey.requireDeviceUnlock) private var requireDeviceUnlock = true
    @AppStorage(ContentFilter.settingKey) private var filterOffensiveLanguage = true
    @AppStorage(SettingsKey.confirmBeforeSend) private var confirmBeforeSend = false
    @AppStorage(SettingsKey.enterKeySends) private var enterKeySends = false
    @AppStorage(SettingsKey.largeMessageBubbles) private var largeMessageBubbles = false
    @AppStorage(SettingsKey.showLinkPreviews) private var showLinkPreviews = true
    @AppStorage(SettingsKey.autoPlayVoice) private var autoPlayVoice = true
    @AppStorage(SettingsKey.listenOnceDefault) private var listenOnceDefault = false
    @AppStorage(MagicTapSetting.key) private var magicTapEndsCall = true
    @ObservedObject private var e2ee = E2EEService.shared

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
        ScrollViewReader { proxy in
            settingsForm
                .onAppear {
                    guard StoreScreenshotMode.isActive, StoreScreenshotMode.screen == "accessibility" else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        proxy.scrollTo("accessibility", anchor: .top)
                    }
                }
        }
    }

    private var settingsForm: some View {
        Form {
            accountSection
            Section("Settings") {
                NavigationLink { ChatsSettingsView() } label: {
                    Label("Chats", systemImage: "bubble.left.and.bubble.right")
                }
                NavigationLink { PrivacySettingsView() } label: {
                    Label("Privacy", systemImage: "hand.raised")
                }
                NavigationLink { NotificationsSettingsView() } label: {
                    Label("Notifications", systemImage: "bell")
                }
                NavigationLink { VoiceCallsSettingsView() } label: {
                    Label("Voice & calls", systemImage: "phone")
                }
                NavigationLink { AccessibilitySettingsView().id("accessibility") } label: {
                    Label("Accessibility", systemImage: "accessibility")
                }
                NavigationLink { DataStorageSettingsView() } label: {
                    Label("Data & storage", systemImage: "internaldrive")
                }
                NavigationLink { AppSecurityView() } label: {
                    Label("Security & encryption", systemImage: "lock.shield")
                }
                NavigationLink { AppearanceExtrasSettingsView() } label: {
                    Label("Appearance extras", systemImage: "paintbrush")
                }
                NavigationLink { AdvancedNetworkSettingsView() } label: {
                    Label("Advanced & network", systemImage: "gearshape.2")
                }
                NavigationLink { BlindExtrasSettingsView() } label: {
                    Label("Blind-first extras", systemImage: "eye")
                }
                NavigationLink { BanditFeedSettingsView() } label: {
                    Label("Bandit Feed", systemImage: "flame")
                }
                NavigationLink { AIPreferencesSettingsView() } label: {
                    Label("AI", systemImage: "sparkles")
                }
                NavigationLink { PrivacyExtrasSettingsView() } label: {
                    Label("Privacy extras", systemImage: "eye.slash")
                }
                NavigationLink { NotificationCategoriesSettingsView() } label: {
                    Label("Notification categories", systemImage: "bell.badge")
                }
                NavigationLink { AppearanceLanguageSettingsView() } label: {
                    Label("Appearance & language", systemImage: "globe")
                }
                NavigationLink {
                    Form { ExtraFeatures220SettingsSection() }
                        .navigationTitle("Apple & Continuity")
                } label: {
                    Label("Apple & Continuity", systemImage: "apple.logo")
                }
                NavigationLink { SecurityExtrasSettingsView() } label: {
                    Label("Security extras", systemImage: "lock.rotation")
                }
                NavigationLink { MessagesSettingsView() } label: {
                    Label("Messages extras", systemImage: "text.bubble")
                }
                NavigationLink { NotesToSelfView() } label: {
                    Label("Note to self", systemImage: "note.text")
                }
            }
            appearanceSection
            safetySection
            legalSection
            supportSection
            aboutSection
        }
        .navigationTitle("Settings")
        .confirmationDialog("Sign out of \(AppConfig.appDisplayName)?", isPresented: $confirmSignOut, titleVisibility: .visible) {
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
        Group {
        ProfilePictureEditor()
        Section("Account & profile") {
            if case .signedIn(let name, let email) = auth.state {
                VStack(alignment: .leading, spacing: 4) {
                    Text(name).font(.headline)
                    if !email.isEmpty { Text(email).foregroundStyle(.secondary) }
                    if !communications.myHandle.isEmpty {
                        Text("@\(communications.myHandle)").foregroundStyle(.secondary)
                    }
                    if !communications.myDisplayName.isEmpty {
                        Text(communications.myDisplayName).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            NavigationLink { DisplayNameEditor() } label: {
                Label("Edit display name", systemImage: "person.text.rectangle")
            }
            NavigationLink("Edit username") { UsernameEditor().navigationTitle("Username") }
            NavigationLink { NativeProfileView(handle: "", isMe: true) } label: {
                Label("Open native profile", systemImage: "person.crop.circle.fill")
            }
            NavigationLink { NativeProfileView(handle: "", isMe: true) } label: {
                Label("Edit email and password on the web", systemImage: "person.crop.circle")
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
    }

    private var encryptionSection: some View {
        Section {
            NavigationLink { AppSecurityView() } label: {
                Label("Security and encryption", systemImage: "lock.shield")
            }
            NavigationLink { EncryptionPasscodeView() } label: {
                Label(EncryptionPasscode.isSet(e2ee.myHandle) ? "Change encryption passcode" : "Create encryption passcode", systemImage: "key.fill")
            }
            LabeledContent("Message encryption", value: e2ee.ready ? "On" : "Setting up")
            LabeledContent("iCloud Keychain", value: IdentityStore.shared.restoredFromICloud ? "Restored on this iPhone" : (IdentityStore.shared.exportIdentity() == nil ? "No keys yet" : "Synced"))
            LabeledContent("This device", value: IdentityStore.shared.deviceID ?? "Not registered")
        } header: {
            Text("Encryption")
        } footer: {
            Text("Your identity key syncs through iCloud Keychain. An encryption passcode adds a recoverable server backup. Forgot passcode prefers iCloud restore over resetting keys.")
        }
    }

    private var messagesSection: some View {
        Section {
            NavigationLink { MessagesSettingsView() } label: {
                Label("Messages & calls settings", systemImage: "bubble.left.and.bubble.right")
            }
            Toggle("Confirm before sending", isOn: $confirmBeforeSend)
            Toggle("Return key sends", isOn: $enterKeySends)
            Toggle("Large message bubbles", isOn: $largeMessageBubbles)
            Toggle("Link previews", isOn: $showLinkPreviews)
            Toggle("Auto-play next voice message", isOn: $autoPlayVoice)
                .accessibilityHint("When on, finishing a received voice note starts the next unplayed one.")
            Toggle("Listen once by default", isOn: $listenOnceDefault)
                .accessibilityHint("New voice notes you record can be heard only once by the other person.")
            Toggle("Magic Tap ends the call", isOn: $magicTapEndsCall)
                .accessibilityHint("Two-finger double tap during a call. Off: Magic Tap mutes instead.")
        } header: {
            Text("Messages & calls")
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
            Button {
                Task {
                    sendingTest = true
                    switch await TestNotification.send(auth: auth) {
                    case .sentByServer: testNotificationMessage = "Test notification sent. It should arrive in a few seconds."
                    case .localFallback(let note), .failed(let note): testNotificationMessage = note
                    }
                    sendingTest = false
                }
            } label: {
                Label(sendingTest ? "Sending test notification…" : "Send test notification", systemImage: "paperplane.fill")
            }
            .disabled(sendingTest)
            if !testNotificationMessage.isEmpty {
                Text(testNotificationMessage).font(.footnote).foregroundStyle(.secondary)
            }
            Toggle("New messages", isOn: $notifyMessages)
            Toggle("Incoming calls", isOn: $notifyCalls)
            Toggle("Share whole screen in calls", isOn: Binding(get: { UserDefaults.standard.object(forKey: "screenShare.wholeScreen") as? Bool ?? true },
                                                                set: { UserDefaults.standard.set($0, forKey: "screenShare.wholeScreen") }))
                .accessibilityHint("On shares everything on your iPhone using Start Broadcast. Off shares only this app.")
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
            Toggle("Ambient UI sounds", isOn: $ambientUITheme)
                .accessibilityHint("Uses soft bell versions of the call and message sounds")
            Button { showingRingtones = true } label: {
                LabeledContent("Ringtone", value: CallSounds.Ringtone(rawValue: ringtoneID)?.title ?? CallSounds.Ringtone.mrBlindBandit.title)
            }
            .foregroundStyle(.primary)
            Button { showingTextTones = true } label: {
                LabeledContent("Text tone", value: CallSounds.NotificationTone(rawValue: textToneID)?.title ?? "Message")
            }
            .foregroundStyle(.primary)
            Toggle("Start video calls with camera off", isOn: $startCallsWithCameraOff)
            LabeledContent("Microphone", value: privacy.text(for: privacy.microphone))
            LabeledContent("Camera", value: privacy.text(for: privacy.camera))
            if privacy.microphone == .denied || privacy.camera == .denied {
                Button("Open iPhone settings") { openSystemSettings() }
            }
        } header: {
            Text("Audio & calls")
        } footer: {
            Text("Calls use echo cancellation and noise suppression. The microphone and camera are used only during calls and recordings you start.")
        }
        .sheet(isPresented: $showingRingtones) {
            TonePickerSheet(title: "Ringtone", tones: CallSounds.Ringtone.allCases, name: { $0.title },
                            preview: { CallSounds.previewRingtone($0) },
                            save: { CallSounds.selectedRingtone = $0; ringtoneID = $0.rawValue },
                            selection: CallSounds.Ringtone(rawValue: ringtoneID) ?? .mrBlindBandit)
        }
        .sheet(isPresented: $showingTextTones) {
            TonePickerSheet(title: "Text tone", tones: CallSounds.NotificationTone.allCases, name: { $0.title },
                            preview: { CallSounds.previewNotification($0) },
                            save: { CallSounds.selectedNotificationTone = $0; textToneID = $0.rawValue },
                            selection: CallSounds.NotificationTone(rawValue: textToneID) ?? .message)
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

    private var safetySection: some View {
        Section {
            Toggle("Filter offensive language", isOn: $filterOffensiveLanguage)
                .accessibilityHint("Masks profanity and slurs in messages from other people.")
            Link(destination: AppConfig.communityGuidelinesURL) { Label("Community guidelines", systemImage: "person.3") }
            Link(destination: AppConfig.trustAndSafetyURL) { Label("Trust & Safety Center", systemImage: "shield.lefthalf.filled") }
            Link(destination: AppConfig.reportContentURL) { Label("Report content on the web", systemImage: "exclamationmark.bubble") }
            Link(destination: URL(string: "mailto:safety@mrblindbandit.net?subject=Safety%20report")!) {
                Label("Email safety@mrblindbandit.net", systemImage: "envelope.badge.shield.half.filled")
            }
        } header: {
            Text("Safety")
        } footer: {
            Text("In a conversation, use the Safety menu to report or block someone. Reports go to Blindbandit moderators, and blocking stops messages and calls between you.")
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
            Link(destination: URL(string: "mailto:\(AppConfig.supportEmail)?subject=Mr.%20BlindBandit%20Mobile%20support")!) {
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
                    Text(AppConfig.appDisplayName).font(.headline)
                    Text(versionText).foregroundStyle(.secondary)
                    Text("TestFlight builds include the latest features before App Store release.").font(.footnote).foregroundStyle(.secondary)
                    Text("© Blindbandit Records").font(.footnote).foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            Link(destination: AppConfig.webBaseURL) { Label("Open website", systemImage: "globe") }
            Link(destination: URL(string: "mailto:\(AppConfig.supportEmail)")!) {
                Label("Email support", systemImage: "envelope")
            }
            NavigationLink("Open-source licenses") { LicensesView() }
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
        ("Agora RTC SDK (iOS)", "Agora SDK License", "https://www.agora.io/en/license/"),
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
                Text("\(AppConfig.appDisplayName) is built with these open-source libraries. Thank you to their authors.")
            }
        }
        .navigationTitle("Open-source licenses")
    }
}
