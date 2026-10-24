import SwiftUI
import UIKit
import WebKit

// MARK: - Storage helpers (real cache sizes + clears)

enum AppStorageCleanup {
    static func directorySize(_ url: URL) -> Int64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey], options: [.skipsHiddenFiles]) else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey]),
                  values.isDirectory != true else { continue }
            total += Int64(values.fileSize ?? 0)
        }
        return total
    }

    static func cachesRoot() -> URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    }

    static func voiceCacheBytes() -> Int64 {
        directorySize(VoiceSender.cacheDir)
    }

    static func imageCacheBytes() -> Int64 {
        // Avatar in-memory is tiny; also clear Nuke/URLCache disk if present under Caches.
        let root = cachesRoot()
        var total: Int64 = 0
        for name in ["com.github.kean.Nuke.DataCache", "com.github.kean.Nuke.ImageCache", "avatars"] {
            total += directorySize(root.appendingPathComponent(name, isDirectory: true))
        }
        total += Int64(URLCache.shared.currentDiskUsage)
        return total
    }

    static func linkPreviewCacheBytes() -> Int64 {
        directorySize(cachesRoot().appendingPathComponent("link-previews", isDirectory: true))
    }

    static func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: max(0, bytes), countStyle: .file)
    }

    @MainActor
    static func clearVoiceCache() {
        try? FileManager.default.removeItem(at: VoiceSender.cacheDir)
        try? FileManager.default.createDirectory(at: VoiceSender.cacheDir, withIntermediateDirectories: true)
        UIAccessibility.post(notification: .announcement, argument: "Voice cache cleared")
    }

    @MainActor
    static func clearImageCache() {
        AvatarImageCache.clear()
        URLCache.shared.removeAllCachedResponses()
        let root = cachesRoot()
        for name in ["com.github.kean.Nuke.DataCache", "com.github.kean.Nuke.ImageCache", "avatars"] {
            try? FileManager.default.removeItem(at: root.appendingPathComponent(name, isDirectory: true))
        }
        UIAccessibility.post(notification: .announcement, argument: "Image cache cleared")
    }

    @MainActor
    static func clearLinkPreviewCache() {
        let url = cachesRoot().appendingPathComponent("link-previews", isDirectory: true)
        try? FileManager.default.removeItem(at: url)
        UIAccessibility.post(notification: .announcement, argument: "Link preview cache cleared")
    }

    @MainActor
    static func clearChatMediaCache() {
        clearVoiceCache()
        clearImageCache()
        clearLinkPreviewCache()
        ChatCache.clear()
        UIAccessibility.post(notification: .announcement, argument: "Chat media cache cleared")
    }
}

/// Whether media may auto-download given the current network preference.
enum MediaDownloadPolicy {
    static var mode: MediaAutoDownload {
        MediaAutoDownload(rawValue: UserDefaults.standard.string(forKey: SettingsKey.mediaAutoDownload) ?? "wifi") ?? .wifi
    }

    static var useLessData: Bool {
        UserDefaults.standard.object(forKey: SettingsKey.useLessData) as? Bool ?? false
    }

    /// Call before opportunistic downloads (not user-initiated play/open).
    static func allowsAutoDownload(onWifi: Bool) -> Bool {
        if useLessData { return false }
        switch mode {
        case .never: return false
        case .always: return true
        case .wifi: return onWifi
        }
    }
}

/// Syncs global notification preview style into the App Group for the NSE.
enum NotificationPreviewSync {
    static let globalKey = "hidePreviews.global"

    static func apply(_ style: NotificationPreviewStyle) {
        guard let suite = UserDefaults(suiteName: PreviewPrivacy.appGroup) else { return }
        switch style {
        case .hidden:
            suite.set(true, forKey: globalKey)
        case .nameOnly, .nameMessage:
            suite.set(false, forKey: globalKey)
        }
        suite.set(style.rawValue, forKey: SettingsKey.notificationPreviewStyle)
        UserDefaults.standard.set(style.rawValue, forKey: SettingsKey.notificationPreviewStyle)
    }

    static var current: NotificationPreviewStyle {
        NotificationPreviewStyle(rawValue: UserDefaults.standard.string(forKey: SettingsKey.notificationPreviewStyle) ?? "nameMessage") ?? .nameMessage
    }
}

// MARK: - Hub: Chats

struct ChatsSettingsView: View {
    @AppStorage(SettingsKey.enterKeySends) private var enterKeySends = false
    @AppStorage(SettingsKey.confirmBeforeSend) private var confirmBeforeSend = false
    @AppStorage(SettingsKey.largeMessageBubbles) private var largeBubbles = false
    @AppStorage(SettingsKey.showLinkPreviews) private var linkPreviews = true
    @AppStorage(SettingsKey.mediaAutoDownload) private var mediaAutoDownload = MediaAutoDownload.wifi.rawValue
    @AppStorage(SettingsKey.saveMediaToPhotos) private var saveToPhotos = false
    @AppStorage(SettingsKey.showMediaGallery) private var showMediaGallery = true
    @AppStorage(SettingsKey.archiveMutedChats) private var archiveMuted = false
    @AppStorage(SettingsKey.keepChatsArchived) private var keepArchived = false
    @AppStorage(SettingsKey.chatWallpaper) private var wallpaper = ChatWallpaperOption.none.rawValue
    @AppStorage(SettingsKey.defaultDisappearingSeconds) private var disappearing = 0
    @State private var clearConfirm = false

    var body: some View {
        Form {
            Section {
                Toggle("Return key sends", isOn: $enterKeySends)
                Toggle("Confirm before sending", isOn: $confirmBeforeSend)
                Toggle("Large message bubbles", isOn: $largeBubbles)
                Toggle("Link previews", isOn: $linkPreviews)
            } header: { Text("Composer") }

            Section {
                Picker("Media auto-download", selection: $mediaAutoDownload) {
                    ForEach(MediaAutoDownload.allCases) { Text($0.title).tag($0.rawValue) }
                }
                .accessibilityHint("Controls when photos and voice notes download without you opening them.")
                Toggle("Save media to Photos", isOn: $saveToPhotos)
                    .accessibilityHint("When on, media you save from a chat is also written to the Photos app.")
                Toggle("Show media in gallery", isOn: $showMediaGallery)
                Button("Clear chat media cache", role: .destructive) { clearConfirm = true }
            } header: { Text("Media") } footer: {
                Text("Clearing removes cached voice notes, images and link previews on this iPhone. Encrypted messages stay in the conversation.")
            }

            Section {
                Toggle("Archive muted chats", isOn: $archiveMuted)
                    .accessibilityHint("When on, muted conversations move to Archived automatically.")
                Toggle("Keep chats archived when new message arrives", isOn: $keepArchived)
                    .accessibilityHint("Off: a new message unarchives the chat. On: it stays archived until you open it.")
                Picker("Default chat wallpaper", selection: $wallpaper) {
                    ForEach(ChatWallpaperOption.allCases) { Text($0.title).tag($0.rawValue) }
                }
            } header: { Text("Chat list") }

            Section {
                Picker("Default disappearing messages", selection: $disappearing) {
                    ForEach(ChatSecuritySettings.timerOptions, id: \.seconds) { Text($0.label).tag($0.seconds) }
                }
                .accessibilityHint("Applied as the starting timer when you open a chat that has no timer yet. Per-chat security can override it.")
            } header: { Text("Disappearing messages") } footer: {
                Text("Off by default. Change per conversation under Chat info → Security.")
            }
        }
        .navigationTitle("Chats")
        .confirmationDialog("Clear chat media cache?", isPresented: $clearConfirm, titleVisibility: .visible) {
            Button("Clear cache", role: .destructive) { AppStorageCleanup.clearChatMediaCache() }
            Button("Cancel", role: .cancel) {}
        }
    }
}

// MARK: - Hub: Privacy

struct PrivacySettingsView: View {
    @AppStorage(SettingsKey.lastSeenVisibility) private var lastSeen = LastSeenVisibility.everyone.rawValue
    @AppStorage(SettingsKey.profilePhotoVisibility) private var profilePhoto = "everyone"
    @AppStorage(SettingsKey.sendReadReceipts) private var sendReadReceipts = true
    @AppStorage(SettingsKey.sendTypingIndicators) private var sendTyping = true
    @AppStorage(SettingsKey.announceCallerName) private var announceCaller = true
    @AppStorage(SettingsKey.screenShareWholeScreen) private var wholeScreen = true
    @AppStorage(SettingsKey.requireDeviceUnlock) private var requireUnlock = true
    @EnvironmentObject private var lock: DeviceLock

    var body: some View {
        Form {
            Section {
                Picker("Last seen & online", selection: $lastSeen) {
                    ForEach(LastSeenVisibility.allCases) { Text($0.title).tag($0.rawValue) }
                }
                .accessibilityHint("Stored on this iPhone for when the server supports last-seen privacy. Not enforced yet.")
                LabeledContent("Profile photo", value: "Everyone")
                    .accessibilityHint("Public profile pictures are visible to contacts and anyone who can see your profile.")
                Toggle("Send read receipts", isOn: $sendReadReceipts)
                    .accessibilityHint("When off, opening a chat does not mark messages read for the other person.")
                Toggle("Send typing indicators", isOn: $sendTyping)
                    .accessibilityHint("When off, others will not see that you are typing.")
            } header: { Text("Who can see") } footer: {
                Text("Profile photos in this build are public by design. Last seen is a local preference until the server ships the matching privacy controls.")
            }

            Section {
                NavigationLink { BlockedAccountsView() } label: {
                    Label("Blocked accounts", systemImage: "hand.raised")
                }
                Text("To export or compare a safety number, open a chat → chat info → Security → Safety number. That verifies end-to-end encryption with that person.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Export safety number help. Open a chat, chat info, Security, Safety number.")
            } header: { Text("Blocked & safety numbers") }

            Section {
                Toggle("Share whole screen in calls", isOn: $wholeScreen)
                    .accessibilityHint("On shares everything on your iPhone using Start Broadcast. Off shares only this app.")
                Toggle("Announce caller name", isOn: $announceCaller)
                    .accessibilityHint("When on, VoiceOver speaks the caller name for incoming calls.")
                Toggle("Require Face ID or passcode to open", isOn: $requireUnlock)
                if requireUnlock {
                    Button("Lock now") { lock.lock() }
                }
            } header: { Text("Calls & app lock") }
        }
        .navigationTitle("Privacy")
    }
}

// MARK: - Hub: Notifications

struct NotificationsSettingsView: View {
    @EnvironmentObject private var push: PushNotifications
    @EnvironmentObject private var auth: ClerkAuthService
    @AppStorage(SettingsKey.notifyMessages) private var notifyMessages = true
    @AppStorage(SettingsKey.notifyGroups) private var notifyGroups = true
    @AppStorage(SettingsKey.notifyCalls) private var notifyCalls = true
    @AppStorage(SettingsKey.notifyMentions) private var notifyMentions = true
    @AppStorage(SettingsKey.notificationPreviewStyle) private var previewStyle = NotificationPreviewStyle.nameMessage.rawValue
    @AppStorage(SettingsKey.notificationSound) private var notifSound = true
    @AppStorage(SettingsKey.notificationVibrate) private var notifVibrate = true
    @AppStorage(SettingsKey.quietHoursEnabled) private var quietOn = false
    @AppStorage(SettingsKey.quietHoursStart) private var quietStart = 22 * 60
    @AppStorage(SettingsKey.quietHoursEnd) private var quietEnd = 7 * 60
    @State private var testMessage = ""
    @State private var sendingTest = false

    var body: some View {
        Form {
            Section {
                LabeledContent("System status", value: push.statusText)
                if push.authorizationStatus == .notDetermined {
                    Button("Turn on notifications") { push.requestAuthorization() }.disabled(push.busy)
                } else if push.authorizationStatus == .denied {
                    Button("Open iPhone notification settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                }
            } header: { Text("Permission") }

            Section {
                Toggle("Messages", isOn: $notifyMessages)
                Toggle("Groups", isOn: $notifyGroups)
                Toggle("Calls", isOn: $notifyCalls)
                Toggle("Mentions", isOn: $notifyMentions)
            } header: { Text("Alert types") } footer: {
                Text("These control alerts while you use the app. iPhone Settings still controls banners when the app is closed.")
            }

            Section {
                Picker("Preview style", selection: $previewStyle) {
                    ForEach(NotificationPreviewStyle.allCases) { Text($0.title).tag($0.rawValue) }
                }
                .onChange(of: previewStyle) { _, raw in
                    NotificationPreviewSync.apply(NotificationPreviewStyle(rawValue: raw) ?? .nameMessage)
                }
                Toggle("Sound", isOn: $notifSound)
                Toggle("Vibrate", isOn: $notifVibrate)
            } header: { Text("Preview & feedback") } footer: {
                Text("Hidden previews ask the Notification Service Extension to show a generic alert. Name only hides the message body.")
            }

            Section {
                Toggle("Quiet hours", isOn: $quietOn)
                    .accessibilityHint("Local schedule on this iPhone. During quiet hours, in-app message sounds stay off.")
                if quietOn {
                    Stepper(value: $quietStart, in: 0...(24 * 60 - 1), step: 30) {
                        Text("Starts \(minutesLabel(quietStart))")
                    }
                    Stepper(value: $quietEnd, in: 0...(24 * 60 - 1), step: 30) {
                        Text("Ends \(minutesLabel(quietEnd))")
                    }
                }
            } header: { Text("Quiet hours") }

            Section {
                Button {
                    Task {
                        sendingTest = true
                        switch await TestNotification.send(auth: auth) {
                        case .sentByServer: testMessage = "Test notification sent. It should arrive in a few seconds."
                        case .localFallback(let note), .failed(let note): testMessage = note
                        }
                        sendingTest = false
                    }
                } label: {
                    Label(sendingTest ? "Sending…" : "Send test notification", systemImage: "paperplane.fill")
                }
                .disabled(sendingTest)
                if !testMessage.isEmpty {
                    Text(testMessage).font(.footnote).foregroundStyle(.secondary)
                }
            } header: { Text("Test") }
        }
        .navigationTitle("Notifications")
        .onAppear {
            NotificationPreviewSync.apply(NotificationPreviewStyle(rawValue: previewStyle) ?? .nameMessage)
        }
    }

    private func minutesLabel(_ m: Int) -> String {
        let h = (m / 60) % 24, min = m % 60
        return String(format: "%d:%02d", h, min)
    }
}

// MARK: - Hub: Voice & calls

struct VoiceCallsSettingsView: View {
    @AppStorage(SettingsKey.autoPlayVoice) private var autoPlay = true
    @AppStorage(SettingsKey.listenOnceDefault) private var listenOnce = false
    @AppStorage(SettingsKey.voicePreferEarpiece) private var preferEarpiece = false
    @AppStorage(SettingsKey.startCallsWithCameraOff) private var cameraOff = false
    @AppStorage(MagicTapSetting.key) private var magicTapEnds = true
    @AppStorage(SettingsKey.liveCaptionsDefault) private var captionsDefault = false
    @AppStorage(SettingsKey.uiSounds) private var uiSounds = true
    @AppStorage("ambientUITheme") private var ambient = false
    @AppStorage("selectedRingtone") private var ringtoneID = CallSounds.Ringtone.mrBlindBandit.rawValue
    @AppStorage("selectedNotificationTone") private var textToneID = CallSounds.NotificationTone.message.rawValue
    @ObservedObject private var voice = VoicePlayback.shared
    @State private var showRingtones = false
    @State private var showTextTones = false

    var body: some View {
        Form {
            Section {
                Toggle("Auto-play next voice message", isOn: $autoPlay)
                Toggle("Listen once by default", isOn: $listenOnce)
                Toggle("Prefer earpiece for voice notes", isOn: $preferEarpiece)
                    .accessibilityHint("When on, voice notes start on the earpiece instead of the speaker. Hold to ear still switches.")
                Picker("Default voice speed", selection: Binding(get: { voice.rate }, set: { voice.setRate($0) })) {
                    Text("0.5x").tag(Float(0.5))
                    Text("1x").tag(Float(1))
                    Text("1.5x").tag(Float(1.5))
                    Text("2x").tag(Float(2))
                }
            } header: { Text("Voice messages") }

            Section {
                Toggle("Call and message sounds", isOn: $uiSounds)
                Toggle("Ambient UI sounds", isOn: $ambient)
                Button { showRingtones = true } label: {
                    LabeledContent("Ringtone", value: CallSounds.Ringtone(rawValue: ringtoneID)?.title ?? "Mr. BlindBandit")
                }.foregroundStyle(.primary)
                Button { showTextTones = true } label: {
                    LabeledContent("Text tone", value: CallSounds.NotificationTone(rawValue: textToneID)?.title ?? "Message")
                }.foregroundStyle(.primary)
            } header: { Text("Sounds") }

            Section {
                Toggle("Start video calls with camera off", isOn: $cameraOff)
                Toggle("Magic Tap ends the call", isOn: $magicTapEnds)
                Toggle("Live captions on by default", isOn: $captionsDefault)
                    .accessibilityHint("When on, new calls start with live captions enabled.")
            } header: { Text("Calls") }

            Section {
                if VoiceLog.lastError.isEmpty {
                    Text("No recent voice errors.").foregroundStyle(.secondary)
                } else {
                    Text(VoiceLog.lastError).font(.caption).foregroundStyle(.secondary)
                    Button("Clear voice debug log") { VoiceLog.lastError = "" }
                }
            } header: { Text("Last voice error") }
        }
        .navigationTitle("Voice & calls")
        .sheet(isPresented: $showRingtones) {
            TonePickerSheet(title: "Ringtone", tones: CallSounds.Ringtone.allCases, name: { $0.title },
                            preview: { CallSounds.previewRingtone($0) },
                            save: { CallSounds.selectedRingtone = $0; ringtoneID = $0.rawValue },
                            selection: CallSounds.Ringtone(rawValue: ringtoneID) ?? .mrBlindBandit)
        }
        .sheet(isPresented: $showTextTones) {
            TonePickerSheet(title: "Text tone", tones: CallSounds.NotificationTone.allCases, name: { $0.title },
                            preview: { CallSounds.previewNotification($0) },
                            save: { CallSounds.selectedNotificationTone = $0; textToneID = $0.rawValue },
                            selection: CallSounds.NotificationTone(rawValue: textToneID) ?? .message)
        }
    }
}

// MARK: - Hub: Accessibility extras

struct AccessibilitySettingsView: View {
    @EnvironmentObject private var preferences: AppPreferences
    @AppStorage(SettingsKey.hapticsEnabled) private var haptics = true
    @AppStorage(SettingsKey.speechFeedback) private var speech = false
    @AppStorage(SettingsKey.speechRate) private var speechRate = 1.0
    @AppStorage(SettingsKey.highContrast) private var highContrast = false
    @AppStorage(SettingsKey.keepScreenAwake) private var keepAwake = false
    @AppStorage(SettingsKey.preferLargerControls) private var largerControls = false
    @AppStorage(SettingsKey.reduceTransparency) private var reduceTransparency = false
    @AppStorage(SettingsKey.announceOutgoingSend) private var announceSend = true
    @AppStorage(SettingsKey.announceDelivery) private var announceDelivery = false

    var body: some View {
        Form {
            Section {
                Toggle("Haptic feedback", isOn: $haptics)
                Toggle("Speech feedback", isOn: $speech)
                VStack(alignment: .leading) {
                    Text("Speech rate")
                    Slider(value: $speechRate, in: 0.5...2.0, step: 0.25)
                    .accessibilityValue(speechRateLabel)
                }
                .disabled(!speech)
                Toggle("High contrast", isOn: $highContrast)
                Toggle("Reduce motion", isOn: $preferences.reduceAppMotion)
                Toggle("Reduce transparency", isOn: $reduceTransparency)
                Toggle("Prefer larger controls", isOn: $largerControls)
                Toggle("Announce when pages finish loading", isOn: $preferences.announcePageLoads)
                Toggle("Keep screen awake", isOn: $keepAwake)
                    .onChange(of: keepAwake) { _, v in UIApplication.shared.isIdleTimerDisabled = v }
                VStack(alignment: .leading) {
                    Text("Web page text size: \(Int(preferences.pageZoom * 100))%")
                    Slider(value: $preferences.pageZoom, in: 0.75...2.0, step: 0.05)
                }
            } header: { Text("Display & speech") }

            Section {
                Toggle("Announce outgoing send", isOn: $announceSend)
                    .accessibilityHint("VoiceOver says Sent when a message leaves this iPhone.")
                Toggle("Announce delivery", isOn: $announceDelivery)
                    .accessibilityHint("VoiceOver says Delivered when the server confirms delivery.")
            } header: { Text("Message announcements") }

            Section {
                Link(destination: AppConfig.accessibilityURL) {
                    Label("Accessibility statement", systemImage: "accessibility")
                }
            }
        }
        .navigationTitle("Accessibility")
    }

    private var speechRateLabel: String {
        switch speechRate {
        case ..<0.8: return "Slow"
        case ..<1.2: return "Normal"
        case ..<1.6: return "Fast"
        default: return "Very fast"
        }
    }
}

// MARK: - Hub: Data & storage

struct DataStorageSettingsView: View {
    @AppStorage(SettingsKey.useLessData) private var useLessData = false
    @AppStorage(SettingsKey.mediaAutoDownload) private var mediaAutoDownload = MediaAutoDownload.wifi.rawValue
    @State private var voiceBytes: Int64 = 0
    @State private var imageBytes: Int64 = 0
    @State private var linkBytes: Int64 = 0
    @State private var confirmVoice = false
    @State private var confirmImage = false
    @State private var confirmLink = false
    @State private var confirmAll = false
    @State private var confirmWeb = false
    @State private var clearingWeb = false

    var body: some View {
        Form {
            Section {
                Toggle("Use less data", isOn: $useLessData)
                    .accessibilityHint("Skips automatic media downloads on cellular and Wi-Fi.")
                Picker("Media auto-download", selection: $mediaAutoDownload) {
                    ForEach(MediaAutoDownload.allCases) { Text($0.title).tag($0.rawValue) }
                }
            } header: { Text("Network") }

            Section {
                LabeledContent("Voice cache", value: AppStorageCleanup.formatBytes(voiceBytes))
                Button("Clear voice cache", role: .destructive) { confirmVoice = true }
                LabeledContent("Image cache", value: AppStorageCleanup.formatBytes(imageBytes))
                Button("Clear image cache", role: .destructive) { confirmImage = true }
                LabeledContent("Link preview cache", value: AppStorageCleanup.formatBytes(linkBytes))
                Button("Clear link-preview cache", role: .destructive) { confirmLink = true }
                Button("Clear all media caches", role: .destructive) { confirmAll = true }
            } header: { Text("On this iPhone") } footer: {
                Text("Sizes are approximate. Clearing does not delete your Blindbandit account or message history on the server.")
            }

            Section {
                Button("Clear website data") { confirmWeb = true }.disabled(clearingWeb)
            } header: { Text("Website") } footer: {
                Text("Removes cookies and cache used by pages opened inside the app.")
            }
        }
        .navigationTitle("Data & storage")
        .onAppear(perform: refresh)
        .confirmationDialog("Clear voice cache?", isPresented: $confirmVoice, titleVisibility: .visible) {
            Button("Clear", role: .destructive) { AppStorageCleanup.clearVoiceCache(); refresh() }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Clear image cache?", isPresented: $confirmImage, titleVisibility: .visible) {
            Button("Clear", role: .destructive) { AppStorageCleanup.clearImageCache(); refresh() }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Clear link-preview cache?", isPresented: $confirmLink, titleVisibility: .visible) {
            Button("Clear", role: .destructive) { AppStorageCleanup.clearLinkPreviewCache(); refresh() }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Clear all media caches?", isPresented: $confirmAll, titleVisibility: .visible) {
            Button("Clear all", role: .destructive) { AppStorageCleanup.clearChatMediaCache(); refresh() }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Clear website data?", isPresented: $confirmWeb, titleVisibility: .visible) {
            Button("Clear website data", role: .destructive) { clearWeb() }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func refresh() {
        voiceBytes = AppStorageCleanup.voiceCacheBytes()
        imageBytes = AppStorageCleanup.imageCacheBytes()
        linkBytes = AppStorageCleanup.linkPreviewCacheBytes()
    }

    private func clearWeb() {
        clearingWeb = true
        WKWebsiteDataStore.default().removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast) {
            Task { @MainActor in
                clearingWeb = false
                AppHaptics.success()
                UIAccessibility.post(notification: .announcement, argument: "Website data cleared")
            }
        }
    }
}


// MARK: - Display name editor (PATCH /v1/social/me)

struct DisplayNameEditor: View {
    @EnvironmentObject private var communications: ProductionCommunicationsService
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var busy = false
    @State private var status = ""

    var body: some View {
        Form {
            Section {
                TextField("Display name", text: $name)
                    .textInputAutocapitalization(.words)
                    .disabled(busy)
            } footer: {
                Text("Shown to contacts next to your @username and profile picture. Keep it short for VoiceOver.")
            }
            if !status.isEmpty {
                Section { Text(status).foregroundStyle(.secondary) }
            }
            Section {
                Button(busy ? "Saving…" : "Save display name") { Task { await save() } }
                    .disabled(busy || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .navigationTitle("Display name")
        .onAppear {
            if name.isEmpty { name = communications.myDisplayName }
        }
    }

    private func save() async {
        busy = true
        defer { busy = false }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let profile = try await BlindbanditAPI.updateSocialProfile(["display_name": trimmed])
            await MainActor.run {
                communications.applyMyDisplayName(profile.display_name)
                communications.applyMyAvatarURL(profile.avatar_url)
            }
            status = "Display name updated."
            UIAccessibility.post(notification: .announcement, argument: status)
            dismiss()
        } catch {
            status = "Could not update display name. \(error.localizedDescription)"
            UIAccessibility.post(notification: .announcement, argument: status)
        }
    }
}
