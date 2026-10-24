import SwiftUI
import AVFoundation
import LiveKit

// MARK: - Shared helpers

enum CommsPermissions {
    @MainActor
    static func microphone(_ privacy: PrivacyPermissions, _ communications: ProductionCommunicationsService) async -> Bool {
        switch privacy.microphone {
        case .authorized: return true
        case .notDetermined: if await privacy.requestMicrophone() { return true }
        default: break
        }
        communications.statusMessage = "Calls need microphone access. Turn it on in iPhone Settings > \(AppConfig.homeScreenName)."
        AppHaptics.warning()
        return false
    }

    @MainActor
    static func camera(_ privacy: PrivacyPermissions, _ communications: ProductionCommunicationsService) async -> Bool {
        switch privacy.camera {
        case .authorized: return true
        case .notDetermined: if await privacy.requestCamera() { return true }
        default: break
        }
        communications.statusMessage = "Video calls need camera access. Turn it on in iPhone Settings > \(AppConfig.homeScreenName)."
        AppHaptics.warning()
        return false
    }
}

/// Reads a message aloud with the speed chosen in Messages settings.
@MainActor
final class MessageReader: ObservableObject {
    static let shared = MessageReader()
    private let synth = AVSpeechSynthesizer()
    var rate: Double {
        let saved = UserDefaults.standard.double(forKey: "comms.readAloudRate")
        return saved == 0 ? 0.5 : saved
    }

    func speak(_ text: String) {
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = Float(min(max(rate, 0.3), 0.7))
        synth.speak(utterance)
    }

    func stop() { synth.stopSpeaking(at: .immediate) }
}

struct CommsStatusBanner: View {
    let text: String
    var body: some View {
        if !text.isEmpty {
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.vertical, 6)
                .accessibilityAddTraits(.updatesFrequently)
        }
    }
}

struct CommsErrorView: View {
    let message: String
    let retry: () async -> Void
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "wifi.exclamationmark").font(.largeTitle).accessibilityHidden(true)
            Text("Couldn't load").font(.headline).accessibilityAddTraits(.isHeader)
            Text(message).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("Retry") { Task { AppHaptics.light(); await retry() } }
                .buttonStyle(.borderedProminent)
                .frame(minHeight: Brand.minTouch)
        }
        .frame(maxWidth: .infinity)
        .padding()
    }
}

// MARK: - Messages tab

struct MessagesTabView: View {
    @EnvironmentObject private var communications: ProductionCommunicationsService
    @EnvironmentObject private var router: TabRouter
    @EnvironmentObject private var privacy: PrivacyPermissions
    @AppStorage(ContentFilter.settingKey) private var filterOffensiveLanguage = true
    @State private var path: [String] = []
    @State private var search = ""
    @State private var composing = false
    @State private var pinned = LocalComms.pinned
    @State private var muted = LocalComms.muted
    @State private var muteUntil = LocalComms.muteUntil
    @State private var archivedAt = LocalComms.archivedAt
    @State private var deletedAt = LocalComms.deletedAt
    @State private var showArchived = false
    @State private var reporting: BlindbanditConversation?
    @State private var confirmDelete: BlindbanditConversation?
    @State private var confirmBlock: BlindbanditConversation?
    @ObservedObject private var folders = ChatFolders.shared
    @State private var folderID: String = "all"

    private var visibleConversations: [BlindbanditConversation] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        let filtered = communications.conversations.filter { c in
            if AppPIN.decoyActive { return false }
            let key = "dm:\(c.id)"
            if let f = folders.folders.first(where: { $0.id == folderID }) {
                if !f.chatKeys.contains(key) { return false }
                if f.hidden && !folders.hiddenUnlocked { return false }
            } else if folders.isHidden(key) { return false }
            if let at = deletedAt[c.id], c.updated_at <= at { return false }
            if let at = archivedAt[c.id], c.updated_at <= at { return showArchived }
            if showArchived { return false }
            guard !q.isEmpty else { return true }
            return (c.other?.handle.lowercased().contains(q) ?? false)
                || (c.other?.display_name.lowercased().contains(q) ?? false)
                || (c.last_message?.body.lowercased().contains(q) ?? false)
        }
        return filtered.sorted { a, b in
            let pa = pinned.contains(a.id), pb = pinned.contains(b.id)
            if pa != pb { return pa }
            return a.updated_at > b.updated_at
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if !communications.pendingMessages.isEmpty {
                    Section("Waiting to send") {
                        ForEach(communications.pendingMessages) { item in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text("To @\(item.handle)").font(.subheadline.bold())
                                    Text(item.body).font(.subheadline).lineLimit(2)
                                }
                                Spacer()
                                Image(systemName: "clock").accessibilityHidden(true)
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityHint("Sends automatically when you're back online")
                            .swipeActions {
                                Button("Discard", role: .destructive) { communications.discardPending(item) }
                            }
                            .accessibilityActions {
                                Button("Discard") { communications.discardPending(item) }
                            }
                        }
                        Button("Send now") { Task { await communications.flushPendingMessages() } }
                    }
                }

                Section {
                    // Permanent AI chat: always first, no delete swipe; it can only be cleared from inside.
                    NavigationLink { AIChatView() } label: { AIChatRow() }
                        .accessibilityIdentifier("aiChatRow")
                    if !AppPIN.decoyActive {
                        NavigationLink { NotesToSelfView() } label: { NotesToSelfRow() }
                    }
                    Picker("Folder", selection: $folderID) {
                        Text("All chats").tag("all")
                        ForEach(folders.folders) { f in Text(f.name).tag(f.id) }
                    }
                    .onChange(of: folderID) { _, id in
                        if folders.folders.first(where: { $0.id == id })?.hidden == true, !folders.hiddenUnlocked {
                            Task { await folders.unlockHidden(); if !folders.hiddenUnlocked { folderID = "all" } }
                        }
                    }
                    NavigationLink { SmartSearchView() } label: { Label("Smart search", systemImage: "sparkle.magnifyingglass") }
                    NavigationLink { DigestView() } label: { Label("Today's digest", systemImage: "newspaper") }
                }
                Section {
                    if communications.isLoading && communications.conversations.isEmpty {
                        ProgressView("Loading conversations")
                    } else if !communications.loadError.isEmpty && communications.conversations.isEmpty {
                        CommsErrorView(message: communications.loadError) { await communications.bootstrap(force: true) }
                    } else if communications.conversations.isEmpty {
                        VStack(spacing: 10) {
                            Image("BBEmptyInbox").resizable().scaledToFit().frame(maxWidth: 160).accessibilityHidden(true)
                            Text("No conversations yet").font(.headline)
                            Text("Start one with the compose button.").foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                    } else if visibleConversations.isEmpty {
                        Text("No conversations match \"\(search)\".").foregroundStyle(.secondary)
                    } else {
                        ForEach(visibleConversations) { conversation in
                            NavigationLink(value: conversation.id) { row(conversation) }
                                .swipeActions(edge: .leading) {
                                    Button(pinned.contains(conversation.id) ? "Unpin" : "Pin") { togglePin(conversation) }.tint(Brand.goldDeep)
                                }
                                .swipeActions(edge: .trailing) {
                                    Button(muted.contains(conversation.id) ? "Unmute" : "Mute") {
                                        setMute(conversation, nil, unmute: muted.contains(conversation.id))
                                    }
                                    Button("Unread") { communications.markUnread(conversation) }.tint(.blue)
                                }
                                .contextMenu { rowMenu(conversation) }
                                .accessibilityActions { rowMenu(conversation) }
                        }
                    }
                } header: {
                    Text("Conversations").accessibilityAddTraits(.isHeader)
                }
            }
            .safeAreaInset(edge: .top) {
                if !archivedAt.isEmpty {
                    Toggle("Show archived", isOn: $showArchived).padding(.horizontal).font(.subheadline)
                }
            }
            .confirmationDialog("Delete this conversation from this phone?", isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }), titleVisibility: .visible, presenting: confirmDelete) { c in
                Button("Delete", role: .destructive) {
                    deletedAt[c.id] = c.updated_at
                    LocalComms.deletedAt = deletedAt
                    announce("Conversation deleted")
                }
            } message: { _ in Text("It comes back if they message you again.") }
            .confirmationDialog("Block this person?", isPresented: Binding(get: { confirmBlock != nil }, set: { if !$0 { confirmBlock = nil } }), titleVisibility: .visible, presenting: confirmBlock) { c in
                Button("Block", role: .destructive) {
                    Task { if await communications.block(handle: c.other?.handle ?? "") { announce("Blocked") } }
                }
            }
            .confirmationDialog("Why are you reporting this?", isPresented: Binding(get: { reporting != nil }, set: { if !$0 { reporting = nil } }), titleVisibility: .visible, presenting: reporting) { c in
                ForEach(ReportReason.allCases) { reason in
                    Button(reason.rawValue) {
                        Task {
                            if await communications.report(targetType: "conversation", targetID: c.id, reason: reason, details: "") {
                                announce("Reported. Thank you.")
                            }
                        }
                    }
                }
            }
            .task {
                while !Task.isCancelled {
                    expireMutes()
                    try? await Task.sleep(nanoseconds: 20_000_000_000)
                }
            }
            .searchable(text: $search, prompt: "Search conversations")
            .refreshable { await communications.refreshConversations() }
            .navigationTitle("Messages")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { composing = true } label: { Image(systemName: "square.and.pencil") }
                        .accessibilityLabel("New message")
                }
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink { NotificationCenterView() } label: { Image(systemName: "bell") }
                        .accessibilityLabel("Notifications")
                }
            }
            .navigationDestination(for: String.self) { id in
                ConversationThreadView(conversationID: id)
            }
            .sheet(isPresented: $composing) {
                NewMessageSheet { id in
                    composing = false
                    path = [id]
                }
            }
            .safeAreaInset(edge: .bottom) { CommsStatusBanner(text: communications.statusMessage).background(.bar) }
        }
        .task {
            guard !StoreScreenshotMode.isActive else { return }
            await communications.bootstrap()
        }
        .onAppear { openPendingThread() }
        .onChange(of: router.pendingThread) { _, _ in openPendingThread() }
    }

    /// Opens the thread a tapped notification asked for. Tries the conversation id first, then the
    /// sender's handle (older pushes only carry a deep link or from_handle).
    private func openPendingThread() {
        guard let target = router.pendingThread else { return }
        router.pendingThread = nil
        Task {
            await communications.bootstrap()
            if communications.conversation(id: target.id ?? "") == nil { await communications.refreshConversations() }
            if let id = target.id, communications.conversation(id: id) != nil {
                path = [id]
            } else if let handle = target.handle, let match = communications.conversations.first(where: { $0.other?.handle.lowercased() == handle.lowercased() }) {
                path = [match.id]
            } else if let id = target.id, !id.isEmpty {
                // The inbox list may lag behind the push; the thread view loads by id directly.
                path = [id]
            } else if let handle = target.handle, !handle.isEmpty {
                path = ["new:\(handle)"]
            } else {
                communications.statusMessage = "That conversation isn't available any more."
                UIAccessibility.post(notification: .announcement, argument: communications.statusMessage)
            }
        }
    }

    @ViewBuilder
    private func rowMenu(_ conversation: BlindbanditConversation) -> some View {
        let handle = conversation.other?.handle ?? ""
        if muted.contains(conversation.id) {
            Button { setMute(conversation, nil, unmute: true) } label: { Label("Unmute", systemImage: "bell") }
        } else {
            Button("Mute for 15 minutes") { setMute(conversation, 15 * 60) }
            Button("Mute for 1 hour") { setMute(conversation, 3600) }
            Button("Mute for 8 hours") { setMute(conversation, 8 * 3600) }
            Button("Mute for 24 hours") { setMute(conversation, 24 * 3600) }
            Button("Mute until I turn it back on") { setMute(conversation, nil) }
        }
        Button { togglePin(conversation) } label: { Label(pinned.contains(conversation.id) ? "Unpin" : "Pin", systemImage: "pin") }
        if communications.isUnread(conversation) {
            Button { Task { await communications.openConversation(id: conversation.id) }; announce("Marked as read") } label: { Label("Mark as read", systemImage: "envelope.open") }
        } else {
            Button { communications.markUnread(conversation); announce("Marked as unread") } label: { Label("Mark as unread", systemImage: "envelope.badge") }
        }
        if !handle.isEmpty {
            Button { callFromRow(handle, video: false) } label: { Label("Call", systemImage: "phone") }
            Button { callFromRow(handle, video: true) } label: { Label("Video call", systemImage: "video") }
        }
        Button { toggleArchive(conversation) } label: {
            Label(archivedAt[conversation.id] != nil ? "Unarchive" : "Archive", systemImage: "archivebox")
        }
        Button(role: .destructive) { confirmDelete = conversation } label: { Label("Delete", systemImage: "trash") }
        if !handle.isEmpty {
            Button(role: .destructive) { confirmBlock = conversation } label: { Label("Block @\(handle)", systemImage: "hand.raised") }
        }
        Button(role: .destructive) { reporting = conversation } label: { Label("Report", systemImage: "exclamationmark.bubble") }
    }

    private func announce(_ text: String) {
        UIAccessibility.post(notification: .announcement, argument: text)
    }

    private func name(_ c: BlindbanditConversation) -> String {
        c.other?.display_name ?? c.other.map { "@\($0.handle)" } ?? "this conversation"
    }

    private func setMute(_ c: BlindbanditConversation, _ duration: TimeInterval?, unmute: Bool = false) {
        if unmute { LocalComms.unmute(c.id) } else { LocalComms.mute(c.id, for: duration) }
        muteUntil = LocalComms.muteUntil
        muted = LocalComms.muted
        AppHaptics.selection()
        communications.objectWillChange.send()
        if unmute { announce("\(name(c)) unmuted") }
        else if let duration {
            let until = Date().addingTimeInterval(duration).formatted(date: duration >= 12 * 3600 ? .abbreviated : .omitted, time: .shortened)
            announce("\(name(c)) muted until \(until)")
        } else { announce("\(name(c)) muted until you turn it back on") }
    }

    /// Ends expired mute timers and says so.
    private func expireMutes() {
        let expired = LocalComms.expireMutes()
        guard !expired.isEmpty else { return }
        muteUntil = LocalComms.muteUntil
        muted = LocalComms.muted
        communications.objectWillChange.send()
        for id in expired {
            let label = communications.conversation(id: id).map(name) ?? "A conversation"
            announce("\(label) is no longer muted")
        }
    }

    private func toggleArchive(_ c: BlindbanditConversation) {
        if archivedAt[c.id] != nil { archivedAt[c.id] = nil; announce("Unarchived") }
        else { archivedAt[c.id] = c.updated_at; announce("Archived. It comes back when there's a new message.") }
        LocalComms.archivedAt = archivedAt
    }

    private func callFromRow(_ handle: String, video: Bool) {
        Task {
            guard await CommsPermissions.microphone(privacy, communications) else { return }
            if video { _ = await CommsPermissions.camera(privacy, communications) }
            await communications.startCall(recipient: handle, video: video)
        }
    }

    private func togglePin(_ c: BlindbanditConversation) {
        if pinned.contains(c.id) { pinned.remove(c.id) } else { pinned.insert(c.id) }
        LocalComms.pinned = pinned
        AppHaptics.selection()
    }

    private func toggleMute(_ c: BlindbanditConversation) {
        if muted.contains(c.id) { muted.remove(c.id) } else { muted.insert(c.id) }
        LocalComms.muted = muted
        AppHaptics.selection()
        communications.objectWillChange.send()
    }

    private func muteLabel(_ id: String) -> String? {
        guard muted.contains(id) else { return nil }
        guard let until = muteUntil[id], until > 0 else { return "Muted" }
        return "Muted until \(Date(timeIntervalSince1970: until).formatted(date: .omitted, time: .shortened))"
    }

    private func row(_ conversation: BlindbanditConversation) -> some View {
        let unread = communications.isUnread(conversation)
        let name = conversation.other?.display_name ?? conversation.other?.handle ?? "Blindbandit member"
        let preview = conversation.last_message.map { last in
            (last.sender_id == communications.myProfileID ? "You: " : "")
                + (last.sender_id == communications.myProfileID ? last.body : ContentFilter.display(last.body, enabled: filterOffensiveLanguage))
        } ?? ""
        return HStack(alignment: .top, spacing: 10) {
            Circle().fill(unread ? Color.blue : Color.clear).frame(width: 10, height: 10).padding(.top, 6)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    if pinned.contains(conversation.id) { Image(systemName: "pin.fill").font(.caption).accessibilityHidden(true) }
                    Text(name).font(unread ? .headline : .body)
                    if conversation.other?.verified == true {
                        VerifiedBadge().accessibilityHidden(true)
                    }
                    if muted.contains(conversation.id) { Image(systemName: "bell.slash").font(.caption).accessibilityHidden(true) }
                    Spacer()
                    Text(Date(timeIntervalSince1970: conversation.updated_at / 1000), style: .relative)
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text(preview).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([
            unread ? "Unread" : nil,
            pinned.contains(conversation.id) ? "Pinned" : nil,
            name,
            conversation.other?.verified == true ? "Verified" : nil,
            muteLabel(conversation.id),
            preview
        ].compactMap { $0 }.joined(separator: ", "))
        .accessibilityValue(Text(Date(timeIntervalSince1970: conversation.updated_at / 1000), style: .relative))
    }
}

struct NewMessageSheet: View {
    @EnvironmentObject private var communications: ProductionCommunicationsService
    @Environment(\.dismiss) private var dismiss
    let opened: (String) -> Void
    @State private var recipient = ""
    @State private var text = ""
    @State private var sending = false
    @State private var note = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("To") {
                    UsernameSearchField(label: "Blindbandit username", text: $recipient)
                }
                Section("Message") {
                    TextField("Message", text: $text, axis: .vertical).lineLimit(2...8)
                }
                if !note.isEmpty { Section { Text(note).foregroundStyle(.secondary) } }
            }
            .navigationTitle("New message")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") { Task { await send() } }
                        .disabled(sending || BlindbanditHandle.normalize(recipient).isEmpty || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func send() async {
        sending = true
        defer { sending = false }
        let handle = BlindbanditHandle.normalize(recipient)
        if await BlindbanditAPI.profileExists(handle: handle) == false {
            note = "There's no Blindbandit member with the username @\(handle). Check the spelling and try again."
            AppHaptics.warning()
            UIAccessibility.post(notification: .announcement, argument: note)
            return
        }
        if let id = await communications.sendMessage(recipient: handle, body: text) {
            opened(id)
        } else if !communications.pendingMessages.isEmpty {
            dismiss()
        } else {
            note = communications.statusMessage
        }
    }
}

struct ConversationThreadView: View {
    let conversationID: String
    @EnvironmentObject private var communications: ProductionCommunicationsService
    @EnvironmentObject private var privacy: PrivacyPermissions
    @EnvironmentObject private var router: TabRouter
    @AppStorage(ContentFilter.settingKey) private var filterOffensiveLanguage = true
    @AppStorage("comms.showReadReceipts") private var showReadReceipts = true
    @State private var draft = ""
    @State private var quoting: BlindbanditServerMessage?
    @State private var search = ""
    @State private var reportTarget: ReportTarget?
    @State private var confirmBlock = false
    @State private var unreadSince: Double?
    @State private var hidden = LocalComms.hiddenMessages
    @State private var reactions = LocalComms.reactions
    @State private var forwarding: String?
    @State private var editing: BlindbanditServerMessage?
    @State private var aiPartial: String?
    @State private var aiPrivate: [(q: String, a: String)] = []
    @State private var smartReplies: [String] = []
    @State private var catchUp: String?
    @State private var scamWarning: String?
    @State private var aiConsent = false
    @State private var pendingAI: AIAssistant.Invocation?
    @State private var showOriginal: Set<String> = []
    @StateObject private var capture = ScreenCaptureMonitor()
    @StateObject private var dictation = LiveDictation()
    @StateObject private var recorder = VoiceRecorder()
    @State private var showInfo = false
    @State private var showPoll = false
    @State private var showCamera = false
    @ObservedObject private var e2ee = E2EEService.shared
    @ObservedObject private var translator = Translator.shared
    @Namespace private var rotorSpace
    @Environment(\.dismiss) private var dismiss
    @FocusState private var composerFocused: Bool

    /// "new:<handle>" opens a fresh thread with someone you haven't messaged yet (from People or a call).
    private var newHandle: String? { conversationID.hasPrefix("new:") ? String(conversationID.dropFirst(4)) : nil }
    private var conversation: BlindbanditConversation? {
        if let newHandle { return communications.conversations.first { $0.other?.handle.lowercased() == newHandle.lowercased() } }
        return communications.conversation(id: conversationID)
    }
    private var handle: String { conversation?.other?.handle ?? newHandle ?? "" }
    private var chatRef: ChatRef { .dm(conversationID: conversation?.id ?? conversationID, handle: handle) }
    private var aiOn: Bool { AISettings.chatAllowed(chatRef.key) }
    private func displayText(_ m: BlindbanditServerMessage) -> String {
        if showOriginal.contains(m.id) || m.sender_id == communications.myProfileID { return m.body }
        return translator.cached(m.id)?.text ?? m.body
    }
    private var recentLines: [String] {
        communications.messages.suffix(30).map { ($0.sender_id == communications.myProfileID ? "Me" : "@\(handle)") + ": " + $0.body }
    }

    private var shownMessages: [BlindbanditServerMessage] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        let visible = communications.messages.filter { !hidden.contains($0.id) }
        guard !q.isEmpty else { return visible }
        return visible.filter { $0.body.lowercased().contains(q) }
    }

    var body: some View {
        ChatLockGate(chatKey: chatRef.key) { threadBody }
    }

    private var displayName: String { conversation?.other?.display_name ?? (handle.isEmpty ? "Conversation" : "@\(handle)") }

    private var threadBody: some View {
        VStack(spacing: 0) {
            messageList

            composerArea
        }
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Search this conversation")
        .navigationTitle(conversation?.other?.display_name ?? "Conversation")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Video and voice call sit right in the top bar (not in a menu), like Messages and WhatsApp.
            // The name in the header is the chat settings button (no separate More button).
            ToolbarItem(placement: .principal) {
                Button { showInfo = true } label: {
                    HStack(spacing: 4) {
                        Text(displayName).font(.headline).lineLimit(1)
                        if conversation?.other?.verified == true { VerifiedBadge() }
                        if E2EEService.shared.isVerified(handle) {
                            Image(systemName: "checkmark.shield.fill").foregroundStyle(.green).font(.caption)
                        }
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(displayName)\(conversation?.other?.verified == true ? ", Verified" : "")\(E2EEService.shared.isVerified(handle) ? ", security number verified" : ""), chat settings")
                .accessibilityHint("Double tap to open chat info and settings")
                .accessibilityAddTraits(.isButton)
                .disabled(handle.isEmpty)
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    Task {
                        guard await CommsPermissions.microphone(privacy, communications),
                              await CommsPermissions.camera(privacy, communications) else { return }
                        await communications.startCall(recipient: handle, video: true)
                    }
                } label: { Image(systemName: "video.fill") }
                .accessibilityLabel("Video call @\(handle)")
                .accessibilityHint("Starts a video call right away")
                .disabled(handle.isEmpty || communications.isInCall)

                Button {
                    Task {
                        guard await CommsPermissions.microphone(privacy, communications) else { return }
                        await communications.startCall(recipient: handle, video: false)
                    }
                } label: { Image(systemName: "phone.fill") }
                .onAppear { CallWarmup.preconnect() }
                .accessibilityLabel("Voice call @\(handle)")
                .accessibilityHint("Starts a voice call right away")
                .disabled(handle.isEmpty || communications.isInCall)

            }
        }
        .navigationDestination(isPresented: $showInfo) {
            List {
                Section {
                    HStack { Text(displayName).font(.title3.bold()); if conversation?.other?.verified == true { VerifiedBadge() } }
                        .accessibilityElement(children: .combine).accessibilityAddTraits(.isHeader)
                    if !handle.isEmpty { Text("@\(handle)").foregroundStyle(.secondary) }
                }
                Section("Chat") { moreMenuItems }
                Section("Folders") { FolderAssignMenu(chatKey: chatRef.key) }
                Section("Lock") {
                    Toggle("Lock this chat with Face ID", isOn: Binding(get: { ChatLock.isLocked(chatRef.key) }, set: { ChatLock.set(chatRef.key, $0) }))
                }
                Section("Create") { Button { showInfo = false; showPoll = true } label: { Label("Create poll", systemImage: "chart.bar") } }
            }
            .navigationTitle("Chat info")
        }
        .sheet(isPresented: $showPoll) { PollComposerSheet(chat: chatRef, handle: handle) }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { img in
                Task { let d = await AIToolbox.describe(img); draft = draft.isEmpty ? "" : draft
                    UIAccessibility.post(notification: .announcement, argument: d) }
            }.ignoresSafeArea()
        }
        .task(id: conversation?.id ?? conversationID) {
            draft = LocalComms.draft(for: conversationID)
            if unreadSince == nil, let id = conversation?.id { unreadSince = communications.lastReadStamp[id] ?? 0 }
            if let id = conversation?.id { await communications.openConversation(id: id) }
            else if newHandle == nil { await communications.openConversation(id: conversationID) }
        }
        .onChange(of: draft) { _, value in LocalComms.setDraft(value, for: conversationID) }
        .onChange(of: communications.messages) { _, list in Task { await analyzeIncoming(list) } }
        .onAppear { capture.start(chat: chatRef) }
        .onDisappear { communications.closeConversation(); capture.stop() }
        .confirmationDialog("@AI reads the last 30 messages in this chat on this iPhone to answer. Nothing leaves your device except the answer, if you post it.", isPresented: $aiConsent, titleVisibility: .visible) {
            Button("Allow @AI") { AIAssistant.consentGiven = true; if let r = pendingAI { Task { await runAI(r) } } }
            Button("Cancel", role: .cancel) { pendingAI = nil }
        }
        .sheet(isPresented: Binding(get: { forwarding != nil }, set: { if !$0 { forwarding = nil } })) {
            ForwardSheet(text: forwarding ?? "")
        }
        .sheet(item: $reportTarget) { target in
            ReportSheet(target: target) { reason, details in
                await communications.report(targetType: target.type, targetID: target.id, reason: reason, details: details)
            }
        }
        .confirmationDialog("Block @\(handle)?", isPresented: $confirmBlock, titleVisibility: .visible) {
            Button("Block", role: .destructive) {
                Task { if await communications.block(handle: handle) { dismiss() } }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("They will no longer be able to message or call you. You can unblock them in Settings > Blocked accounts.")
        }
    }

    private func bubbleLabel(_ message: BlindbanditServerMessage, shown: String, mine: Bool, translatedFrom: String?, starred: Bool, encrypted: Bool) -> String {
        var parts: [String] = [mine ? "You: \(shown)" : "@\(handle): \(shown)"]
        if let t = translatedFrom { parts.append("Translated from \(LanguageID.name(t))") }
        if message.edited_at != nil { parts.append("Edited") }
        if starred { parts.append("Starred") }
        if encrypted { parts.append("Encrypted") }
        if let r = reactions[message.id] { parts.append("You reacted \(MessageReactions.name(r))") }
        return parts.joined(separator: ". ")
    }

    @ViewBuilder private var moreMenuItems: some View {
        NavigationLink { SecurityPrivacyView(chat: chatRef, title: "@\(handle)") } label: {
            Label("Security & Privacy", systemImage: "lock.shield")
        }
        NavigationLink { SafetyNumberView(handle: handle) } label: { Label("Verify safety number", systemImage: "qrcode") }
        if aiOn && AISettings.isOn(.catchUp) {
            Button { Task { catchUp = "Summarizing…"; catchUp = await OnDeviceAI.catchUp(chatName: "@\(handle)", lines: recentLines) ?? OnDeviceAI.unavailableReason
                UIAccessibility.post(notification: .announcement, argument: catchUp ?? "") } } label: { Label("Catch me up", systemImage: "text.badge.star") }
        }
        Button { toggleFavorite() } label: {
            Label(LocalComms.favorites.contains(handle) ? "Remove from favorites" : "Add to favorites", systemImage: "star")
        }
        Button {
            reportTarget = ReportTarget(type: "profile", id: handle, title: "@\(handle)")
        } label: { Label("Report @\(handle)", systemImage: "exclamationmark.bubble") }
        Button(role: .destructive) { confirmBlock = true } label: { Label("Block @\(handle)", systemImage: "hand.raised") }
    }

    @ViewBuilder private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    if communications.messages.isEmpty && !communications.loadError.isEmpty {
                        CommsErrorView(message: communications.loadError) {
                            if let c = conversation { await communications.openConversation(c) }
                        }
                    }
                    ForEach(shownMessages) { message in
                        bubble(message).id(message.id)
                            .accessibilityRotorEntry(id: message.id, in: rotorSpace)
                    }
                    if communications.otherTyping && search.isEmpty {
                        TypingIndicatorBubble(name: handle.isEmpty ? "Someone" : "@\(handle)")
                            .id("typing-indicator")
                            .transition(.opacity)
                    }
                }
                .padding()
            }
            .onChange(of: communications.otherTyping) { _, typing in
                if typing, search.isEmpty { withAnimation { proxy.scrollTo("typing-indicator", anchor: .bottom) } }
            }
            .onChange(of: communications.messages) { old, list in
                if let last = list.last, search.isEmpty { proxy.scrollTo(last.id, anchor: .bottom) }
                let me = communications.myProfileID
                for mineNow in list where mineNow.sender_id == me {
                    guard let mineBefore = old.first(where: { $0.id == mineNow.id }),
                          MessageStatus.caption(for: mineBefore, showRead: showReadReceipts) != MessageStatus.caption(for: mineNow, showRead: showReadReceipts)
                    else { continue }
                    let label = MessageStatus.caption(for: mineNow, showRead: showReadReceipts)
                    let isLatest = mineNow.id == list.last(where: { $0.sender_id == me })?.id
                    UIAccessibility.post(notification: .announcement, argument: isLatest ? "Your last message: \(label)" : "Your message \"\(mineNow.body.prefix(40))\": \(label)")
                    if label.hasPrefix("Read") { AppHaptics.soft() }
                }
            }
        }
        .refreshable { if let c = conversation { await communications.openConversation(c) } }
        .accessibilityRotor("Unread messages") {
            ForEach(shownMessages.filter { $0.sender_id != communications.myProfileID && $0.created_at > (unreadSince ?? .infinity) }) { m in
                AccessibilityRotorEntry(Text(m.body), id: m.id, in: rotorSpace)
            }
        }
        .accessibilityRotor("Messages from @\(handle.isEmpty ? "them" : handle)") {
            ForEach(shownMessages.filter { $0.sender_id != communications.myProfileID }) { m in
                AccessibilityRotorEntry(Text(m.body), id: m.id, in: rotorSpace)
            }
        }
        .accessibilityRotor("My messages") {
            ForEach(shownMessages.filter { $0.sender_id == communications.myProfileID }) { m in
                AccessibilityRotorEntry(Text(m.body), id: m.id, in: rotorSpace)
            }
        }
    }

    @ViewBuilder private var composerArea: some View {
        ThreadAIBanners(handle: handle, keyChanged: e2ee.keyChanges.contains(handle.lowercased()),
                        scamWarning: scamWarning, catchUp: $catchUp, aiPartial: aiPartial, aiPrivate: aiPrivate,
                        smartReplies: smartReplies) { draft = $0; composerFocused = true }
        if let e = editing {
            HStack {
                Text("Editing: \(e.body)").font(.caption).lineLimit(1)
                Spacer()
                Button { editing = nil; draft = "" } label: { Image(systemName: "xmark.circle.fill") }.accessibilityLabel("Cancel edit")
            }.padding(.horizontal).padding(.top, 6)
        }
        if let q = quoting {
            HStack {
                Text("Replying to: \(q.body)").font(.caption).lineLimit(1)
                Spacer()
                Button { quoting = nil } label: { Image(systemName: "xmark.circle.fill") }
                    .accessibilityLabel("Cancel reply")
            }
            .padding(.horizontal)
            .padding(.top, 6)
        }
        HStack(spacing: 8) {
            TextField("Message @\(handle)", text: $draft, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...5)
                .focused($composerFocused)
                .onChange(of: composerFocused) { _, f in if f { AIChatStore.shared.prewarm() } }
                .onChange(of: draft) { _, value in
                    if !value.isEmpty { communications.userTyped(in: conversationID) }
                }
                .accessibilityActions {
                    Button(recorder.isRecording ? "Send voice message" : "Record voice message") {
                        Task { await recorder.toggleSend(handle: handle, chat: chatRef, comms: communications) }
                    }
                    Button("Create poll") { showPoll = true }
                    Button("Describe camera") { showCamera = true }
                    Button("Ask AI in this chat") { draft = "@AI " + draft }
                    Button("Ask AI privately") { draft = "/ai " + draft }
                    Button("Insert emoji") { draft += "🙂" }
                    Button(dictation.isListening ? "Stop dictation" : "Dictate") { Task { if dictation.isListening { dictation.stop(); draft = dictation.text } else { await dictation.start() } } }
                    Button("Send silently") { send(silent: true) }
                    Button("Schedule for 1 hour") { schedule(3600) }
                    Button("Chat settings") { showInfo = true }
                }
            ComposerAIMenu(draft: $draft, dictation: dictation, enabled: aiOn)
            VoiceMicButton(handle: handle, chat: chatRef, recorder: recorder)
            Button { send() } label: {
                Image(systemName: "paperplane.fill").frame(width: Brand.minTouch, height: Brand.minTouch)
            }
            .accessibilityLabel(editing == nil ? "Send" : "Save edit")
            .contextMenu {
                Button("Send silently") { send(silent: true) }
                Menu("Schedule") {
                    Button("In 1 hour") { schedule(3600) }
                    Button("Tonight at 8 PM") { schedule(Self.secondsUntil(hour: 20)) }
                    Button("Tomorrow at 9 AM") { schedule(Self.secondsUntil(hour: 9)) }
                }
            }
            .accessibilityAction(named: "Send silently") { send(silent: true) }
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || handle.isEmpty)
        }
        .padding()
        .background(.bar)
    }

    private func unsend(_ message: BlindbanditServerMessage) async {
        do {
            try await e2ee.unsend(chat: chatRef, serverID: message.id, envelopeMsgID: message.client_msg_id)
            hidden.insert(message.id)
            AppHaptics.success()
            UIAccessibility.post(notification: .announcement, argument: "Unsent for everyone")
        } catch {
            let text = (error as? NeedsServerUpdate) != nil ? "Unsend: " + ServerFeatures.needsUpdateText : error.localizedDescription
            communications.statusMessage = text
            UIAccessibility.post(notification: .announcement, argument: text)
        }
    }

    private func toggleFavorite() {
        var favs = LocalComms.favorites
        if favs.contains(handle) { favs.removeAll { $0 == handle } } else { favs.append(handle) }
        LocalComms.favorites = favs
        AppHaptics.success()
        UIAccessibility.post(notification: .announcement, argument: favs.contains(handle) ? "Added to favorites" : "Removed from favorites")
    }

    private static func secondsUntil(hour: Int) -> Int {
        let cal = Calendar.current
        let next = cal.nextDate(after: Date(), matching: DateComponents(hour: hour, minute: 0), matchingPolicy: .nextTime) ?? Date().addingTimeInterval(3600)
        return Int(next.timeIntervalSinceNow)
    }

    private func schedule(_ seconds: Int) {
        let body = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        draft = ""
        LocalMessageStore.shared.mutate { $0.scheduled.append(.init(chatKey: chatRef.key, handle: handle, groupID: nil, body: body, sendAt: Date().addingTimeInterval(Double(seconds)).timeIntervalSince1970, silent: false)) }
        let when = Date().addingTimeInterval(Double(seconds)).formatted(date: .omitted, time: .shortened)
        UIAccessibility.post(notification: .announcement, argument: "Scheduled for \(when)")
        AppHaptics.success()
    }

    private func runAI(_ r: AIAssistant.Invocation) async {
        pendingAI = nil
        aiPartial = "AI is thinking…"
        UIAccessibility.post(notification: .announcement, argument: "AI is thinking")
        let answer = await AIAssistant.answer(r, context: .init(chatName: "@\(handle)", lines: recentLines, lastPhoto: nil)) { p in aiPartial = p }
        aiPartial = nil
        if r.isPrivate {
            aiPrivate.append((r.question, answer))
            UIAccessibility.post(notification: .announcement, argument: "AI, only you can see this: \(answer)")
        } else {
            let p = E2EEPayload(t: "ai", body: answer, ai_via: e2ee.myHandle)
            let sent = try? await e2ee.sendDM(handle: handle, payload: p, chatKey: chatRef.key)
            if sent == nil || sent! == nil { _ = await communications.sendMessage(recipient: handle, body: "🤖 AI (via @\(e2ee.myHandle)): " + answer) }
            UIAccessibility.post(notification: .announcement, argument: "AI via you: \(answer)")
            if let c = conversation { await communications.openConversation(c) }
        }
    }

    private func analyzeIncoming(_ list: [BlindbanditServerMessage]) async {
        let theirs = list.filter { $0.sender_id != communications.myProfileID }
        guard aiOn, let last = theirs.last else { return }
        if AISettings.isOn(.scamWarnings), !LocalComms.favorites.contains(handle), list.filter({ $0.sender_id == communications.myProfileID }).count < 3 {
            let v = await ScamDetector.check(theirs.suffix(5).map(\.body).joined(separator: "\n"))
            scamWarning = v.suspicious ? v.reason : nil
        }
        if AISettings.isOn(.translate) {
            for m in theirs.suffix(20) { _ = await translator.translateIncoming(id: m.id, text: m.body, chatKey: chatRef.key) }
        }
        if AISettings.isOn(.smartReplies), list.last?.id == last.id {
            smartReplies = await OnDeviceAI.smartReplies(lines: Array(recentLines.suffix(10)))
        } else { smartReplies = [] }
    }

    private func send(silent: Bool = false) {
        var body = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if let e = editing {
            editing = nil
            draft = ""
            Task {
                do { try await e2ee.edit(chat: chatRef, serverID: e.id, newText: body, oldMsgID: e.client_msg_id)
                    UIAccessibility.post(notification: .announcement, argument: "Edited")
                    if let c = conversation { await communications.openConversation(c) }
                } catch { communications.statusMessage = (error as? NeedsServerUpdate) != nil ? "Editing: " + ServerFeatures.needsUpdateText : error.localizedDescription
                    UIAccessibility.post(notification: .announcement, argument: communications.statusMessage) }
            }
            return
        }
        if let r = AIAssistant.parse(body) {
            draft = ""
            guard aiOn, AIAssistant.allowed(chatKey: chatRef.key) else {
                UIAccessibility.post(notification: .announcement, argument: "@AI is turned off in this chat"); return
            }
            if !r.isPrivate, !AIAssistant.consentGiven { pendingAI = r; aiConsent = true; return }
            Task { await runAI(r) }
            return
        }
        smartReplies = []
        if let q = quoting {
            let quoted = q.body.split(separator: "\n").prefix(3).map { "> " + $0 }.joined(separator: "\n")
            body = quoted + "\n" + body
        }
        draft = ""
        quoting = nil
        LocalComms.setDraft("", for: conversationID)
        Task { _ = await communications.sendMessage(recipient: handle, body: body, silent: silent)
            if silent { UIAccessibility.post(notification: .announcement, argument: "Sent silently") } }
    }

    private var latestMineID: String? {
        communications.messages.last(where: { $0.sender_id == communications.myProfileID })?.id
    }

    @ViewBuilder
    private func bubble(_ message: BlindbanditServerMessage) -> some View {
        let mine = message.sender_id == communications.myProfileID
        let shown = mine ? message.body : ContentFilter.display(displayText(message), enabled: filterOffensiveLanguage)
        let translatedFrom = (!mine && !showOriginal.contains(message.id)) ? translator.cached(message.id)?.source : nil
        let encrypted = message.decrypted != nil
        let starred = LocalMessageStore.shared.snapshot.starred.contains(message.id)
        let status = MessageStatus.caption(for: message, showRead: showReadReceipts)
        let sentLabel = MessageStatus.stamp(message.created_at)
        VStack(alignment: mine ? .trailing : .leading, spacing: 3) {
            HStack {
                if mine { Spacer(minLength: 48) }
                if let media = message.decrypted?.media,
                   VoiceRowPlayAction.hasPlayableVoiceMedia(media, decryptedType: message.decrypted?.t) {
                    VoiceBubble(media: media, from: mine ? "You" : "@\(handle)", msgID: message.id)
                } else if let poll = message.decrypted?.poll {
                    PollCard(poll: poll, msgID: message.client_msg_id ?? message.id, chat: chatRef, handle: handle, me: e2ee.myHandle)
                } else {
                Text(shown)
                    .padding(12)
                    .background(mine ? Brand.gold.opacity(0.35) : Color.secondary.opacity(0.16), in: RoundedRectangle(cornerRadius: 16))
                    .textSelection(.enabled)
                    .overlay(alignment: mine ? .bottomLeading : .bottomTrailing) {
                        if let r = reactions[message.id] {
                            Text(r).font(.caption).padding(3).background(.regularMaterial, in: Capsule()).offset(y: 10)
                        }
                    }
                }
                if !mine { Spacer(minLength: 48) }
            }
            // Voice bubbles are their own VoiceOver button (double tap = play/pause). When voice,
            // expose children and skip the row label so VO focuses the bubble (label on a .contain
            // parent was swallowing activation). Play stays first in Actions as a fallback.
            .accessibilityElement(children: MessageRowAccessibility.children(isVoice: VoiceRowPlayAction.hasPlayableVoiceMedia(message.decrypted?.media, decryptedType: message.decrypted?.t)))
            .modifier(MessageRowLabelModifier(
                isVoice: VoiceRowPlayAction.hasPlayableVoiceMedia(message.decrypted?.media, decryptedType: message.decrypted?.t),
                label: bubbleLabel(message, shown: shown, mine: mine, translatedFrom: translatedFrom, starred: starred, encrypted: encrypted)))
            .accessibilityActions { messageActions(message, shown: shown, mine: mine) }
            .contextMenu { messageActions(message, shown: shown, mine: mine) }
            // Status is its own element directly under every message, so VoiceOver lands on it next.
            if let lang = translatedFrom {
                Button("Translated from \(LanguageID.name(lang)). Show original") { showOriginal.insert(message.id) }
                    .font(.caption2)
            }
            MessageStatusCaption(text: mine ? status : sentLabel, mine: mine)
        }
        .frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading)
        .accessibilityElement(children: .contain)
    }

    private func react(_ message: BlindbanditServerMessage, _ emoji: String) {
        let removing = reactions[message.id] == emoji
        reactions[message.id] = removing ? nil : emoji
        LocalComms.reactions = reactions
        AppHaptics.light()
        UIAccessibility.post(notification: .announcement, argument: removing ? "Reaction removed" : "Reacted \(MessageReactions.name(emoji))")
        let conv = conversation?.id ?? conversationID
        Task { await BlindbanditAPI.react(conversationID: conv, messageID: message.id, emoji: removing ? nil : emoji) }
    }

    private func showTimes(_ message: BlindbanditServerMessage, mine: Bool) {
        var parts = ["Sent \(MessageStatus.stamp(message.created_at))"]
        if mine {
            if let d = message.delivered_at { parts.append("Delivered \(MessageStatus.stamp(d))") }
            if let r = message.read_at, showReadReceipts { parts.append("Read \(MessageStatus.stamp(r))") }
            else if message.read_at == nil { parts.append("Not read yet") }
        }
        let text = parts.joined(separator: ". ")
        communications.statusMessage = text
        UIAccessibility.post(notification: .announcement, argument: text)
    }

    @ViewBuilder
    private func messageActions(_ message: BlindbanditServerMessage, shown: String, mine: Bool) -> some View {
        if let media = message.decrypted?.media, VoiceRowPlayAction.hasPlayableVoiceMedia(media, decryptedType: message.decrypted?.t) {
            VoiceRowPlayAction(item: .init(id: message.id, media: media, from: mine ? "You" : "@\(handle)", mine: mine))
        }
        Button { quoting = message; composerFocused = true } label: { Label("Reply", systemImage: "arrowshape.turn.up.left") }
        if mine {
            // One tap, no dialog, no time limit (§22.5).
            Button(role: .destructive) { Task { await unsend(message) } } label: { Label("Unsend", systemImage: "arrow.uturn.backward") }
            if message.decrypted != nil {
                Button { editing = message; draft = message.body; composerFocused = true } label: { Label("Edit", systemImage: "pencil") }
            }
        }
        Button { LocalMessageStore.shared.mutate { s in if s.starred.contains(message.id) { s.starred.remove(message.id) } else { s.starred.insert(message.id) } }; AppHaptics.light()
            UIAccessibility.post(notification: .announcement, argument: LocalMessageStore.shared.snapshot.starred.contains(message.id) ? "Starred" : "Unstarred")
        } label: { Label("Star", systemImage: "star") }
        let isPinned = LocalMessageStore.shared.snapshot.pinned[chatRef.key]?.contains(message.id) ?? false
        Button { let k = chatRef.key, ref = chatRef, id = message.id, nowPinned = !isPinned
            LocalMessageStore.shared.mutate { s in var l = s.pinned[k] ?? []; if let i = l.firstIndex(of: id) { l.remove(at: i) } else { l.append(id) }; s.pinned[k] = l }
            AppHaptics.light()
            Task {
                let synced = await SecurityAPI.syncPin(ref, messageID: id, pinned: nowPinned)
                let msg = (nowPinned ? "Pinned" : "Unpinned") + (synced ? "" : " on this iPhone. The server will catch up after its next update.")
                UIAccessibility.post(notification: .announcement, argument: msg)
            }
        } label: { Label(isPinned ? "Unpin" : "Pin", systemImage: isPinned ? "pin.slash" : "pin") }
        if !mine && translator.cached(message.id) != nil {
            Button { if showOriginal.contains(message.id) { showOriginal.remove(message.id) } else { showOriginal.insert(message.id) } } label: {
                Label(showOriginal.contains(message.id) ? "Show translation" : "Show original", systemImage: "character.bubble")
            }
        } else if !mine {
            Button { Task { if let src = LanguageID.detect(message.body), let r = await translator.translate(message.body, from: src, to: LanguageID.deviceLanguage) { translator.store(r, for: message.id) } } } label: { Label("Translate", systemImage: "character.bubble") }
        }
        if AISettings.isOn(.naturalVoices) {
            Button { NaturalReader.shared.speak(shown) } label: { Label("Read aloud with natural voice", systemImage: "waveform") }
        }
        if AISettings.isOn(.actions) {
            ForEach(ActionDetector.detect(message.body), id: \.label) { a in
                Button(a.label) { if let u = a.url { UIApplication.shared.open(u) } else if case .date(let d) = a.kind { Task { _ = await ReminderMaker.add(title: message.body, minutes: max(0, Int(d.timeIntervalSinceNow / 60))) } } }
            }
        }
        Button { UIPasteboard.general.string = shown; AppHaptics.light() } label: { Label("Copy", systemImage: "doc.on.doc") }
        if let link = LinkFinder.links(in: shown).first {
            Button {
                Task { let v = CloudAI.isOn(.linkCheck) ? await CloudAI.checkLink(link) : ScamHeuristic.verdict(link)
                    communications.statusMessage = v; UIAccessibility.post(notification: .announcement, argument: v) }
            } label: { Label("Check link safety", systemImage: "checkmark.shield") }
        }
        ShareLink(item: shown) { Label("Share", systemImage: "square.and.arrow.up") }
        ForEach(MessageReactions.all, id: \.emoji) { r in
            Button { react(message, r.emoji) } label: {
                Text(reactions[message.id] == r.emoji ? "Remove \(r.name)" : "React \(r.name) \(r.emoji)")
            }
        }
        Button { MessageReader.shared.speak(shown) } label: { Label("Read aloud", systemImage: "speaker.wave.2") }
        Button { forwarding = shown } label: { Label("Forward", systemImage: "arrowshape.turn.up.right") }
        Button { showTimes(message, mine: mine) } label: { Label("Show time sent and read", systemImage: "clock") }
        Button(role: .destructive) {
            hidden.insert(message.id)
            LocalComms.hiddenMessages = hidden
            UIAccessibility.post(notification: .announcement, argument: "Deleted for you")
        } label: { Label("Delete for me", systemImage: "trash") }
        if !mine {
            Button { reportTarget = ReportTarget(type: "message", id: message.id, title: "this message") } label: {
                Label("Report message", systemImage: "exclamationmark.bubble")
            }
        }
    }
}

// MARK: - Calls tab

struct CallsTabView: View {
    @EnvironmentObject private var communications: ProductionCommunicationsService
    @EnvironmentObject private var privacy: PrivacyPermissions
    @State private var recipient = ""
    @State private var favorites = LocalComms.favorites
    @State private var reportTarget: ReportTarget?
    @State private var missedOnly = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    UsernameSearchField(label: "Blindbandit username", text: $recipient)
                    HStack {
                        Button { call(recipient, video: false) } label: { Label("Voice", systemImage: "phone.fill") }
                            .buttonStyle(.borderedProminent)
                        Button { call(recipient, video: true) } label: { Label("Video", systemImage: "video.fill") }
                            .buttonStyle(.bordered)
                    }
                    .disabled(BlindbanditHandle.normalize(recipient).isEmpty || communications.isInCall)
                } header: {
                    Text("Call someone").accessibilityAddTraits(.isHeader)
                } footer: {
                    Text("Your username is @\(communications.myHandle.isEmpty ? "unknown" : communications.myHandle).")
                }

                if !favorites.isEmpty {
                    Section {
                        ForEach(favorites, id: \.self) { handle in
                            HStack {
                                Text("@\(handle)")
                                Spacer()
                                Button { call(handle, video: false) } label: { Image(systemName: "phone.fill") }
                                    .accessibilityLabel("Voice call @\(handle)")
                                    .buttonStyle(.borderless)
                                Button { call(handle, video: true) } label: { Image(systemName: "video.fill") }
                                    .accessibilityLabel("Video call @\(handle)")
                                    .buttonStyle(.borderless)
                            }
                            .frame(minHeight: Brand.minTouch)
                        }
                        .onDelete { idx in
                            favorites.remove(atOffsets: idx)
                            LocalComms.favorites = favorites
                        }
                    } header: { Text("Favorites").accessibilityAddTraits(.isHeader) }
                }

                Section {
                    Picker("Show", selection: $missedOnly) {
                        Text("All").tag(false)
                        Text("Missed").tag(true)
                    }
                    .pickerStyle(.segmented)
                    let rows = communications.callHistory.filter { !missedOnly || $0.isMissed }
                    if !communications.historyError.isEmpty && communications.callHistory.isEmpty {
                        CommsErrorView(message: communications.historyError) { await communications.refreshCallHistory() }
                    } else if rows.isEmpty {
                        Text(missedOnly ? "No missed calls." : "No calls yet.").foregroundStyle(.secondary)
                    } else {
                        ForEach(rows) { record in historyRow(record) }
                    }
                } header: { Text("Recent calls").accessibilityAddTraits(.isHeader) }
            }
            .navigationTitle("Calls")
            .refreshable { await communications.refreshCallHistory() }
            .safeAreaInset(edge: .bottom) { CommsStatusBanner(text: communications.statusMessage).background(.bar) }
            .sheet(item: $reportTarget) { target in
                ReportSheet(target: target) { reason, details in
                    await communications.report(targetType: target.type, targetID: target.id, reason: reason, details: details)
                }
            }
        }
        .task {
            guard !StoreScreenshotMode.isActive else { return }
            await communications.bootstrap()
            await communications.refreshCallHistory()
            favorites = LocalComms.favorites
        }
        .onAppear { favorites = LocalComms.favorites }
        .onReceive(NotificationCenter.default.publisher(for: .blindbanditCallDeepLinkReceived)) { note in
            guard let callID = note.object as? String else { return }
            Task {
                guard await CommsPermissions.microphone(privacy, communications) else { return }
                await communications.refreshCallHistory()
                await communications.joinIncomingCall(id: callID)
            }
        }
    }

    private func call(_ raw: String, video: Bool) {
        let handle = BlindbanditHandle.normalize(raw)
        Task {
            guard await CommsPermissions.microphone(privacy, communications) else { return }
            if video { guard await CommsPermissions.camera(privacy, communications) else { return } }
            await communications.startCall(recipient: handle, video: video)
        }
    }

    private func historyRow(_ record: BlindbanditCallRecord) -> some View {
        let handle = record.other?.handle ?? ""
        let name = record.other?.display_name ?? (handle.isEmpty ? "Blindbandit member" : "@\(handle)")
        let duration = record.durationSeconds.map { String(format: "%d:%02d", $0 / 60, $0 % 60) }
        return HStack(spacing: 12) {
            Image(systemName: record.isIncoming ? "phone.arrow.down.left" : "phone.arrow.up.right")
                .foregroundStyle(record.isMissed ? .red : .secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.body).foregroundStyle(record.isMissed ? .red : .primary)
                Text("\(record.stateLabel) \(record.isVideo ? "video" : "voice") call\(duration.map { ", \($0)" } ?? "")")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(record.startedAt, style: .relative).font(.caption).foregroundStyle(.secondary)
            if !handle.isEmpty {
                Button { call(handle, video: record.isVideo) } label: { Image(systemName: record.isVideo ? "video.fill" : "phone.fill") }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Call back @\(handle)")
                    .disabled(communications.isInCall)
            }
        }
        .frame(minHeight: Brand.minTouch)
        .accessibilityElement(children: .combine)
        .accessibilityActions {
            if !handle.isEmpty {
                Button("Call back") { call(handle, video: record.isVideo) }
                Button("Report this call") { reportTarget = ReportTarget(type: "call", id: record.id, title: "this call") }
            }
        }
        .contextMenu {
            Button("Report this call") { reportTarget = ReportTarget(type: "call", id: record.id, title: "this call") }
        }
    }
}

// MARK: - Blocked accounts and notifications

struct BlockedAccountsView: View {
    @EnvironmentObject private var communications: ProductionCommunicationsService
    @State private var loaded = false

    var body: some View {
        List {
            if !loaded {
                ProgressView("Loading blocked accounts")
            } else if communications.blockedProfiles.isEmpty {
                Text("You haven't blocked anyone.").foregroundStyle(.secondary)
            } else {
                ForEach(communications.blockedProfiles) { profile in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(profile.display_name ?? "@\(profile.handle)")
                            Text("@\(profile.handle)").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Unblock") { Task { _ = await communications.unblock(handle: profile.handle) } }
                            .buttonStyle(.bordered)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityAction(named: "Unblock") { Task { _ = await communications.unblock(handle: profile.handle) } }
                }
            }
        }
        .navigationTitle("Blocked accounts")
        .refreshable { await communications.refreshBlocked() }
        .task {
            await communications.refreshBlocked()
            loaded = true
        }
    }
}

struct NotificationCenterView: View {
    @State private var items: [BlindbanditSocialNotification] = []
    @State private var error = ""
    @State private var loading = true

    var body: some View {
        List {
            if loading {
                ProgressView("Loading notifications")
            } else if !error.isEmpty && items.isEmpty {
                CommsErrorView(message: error) { await load() }
            } else if items.isEmpty {
                Text("You're all caught up.").foregroundStyle(.secondary)
            } else {
                ForEach(items) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title).font(item.isRead ? .body : .headline)
                        if !item.detail.isEmpty { Text(item.detail).font(.subheadline).foregroundStyle(.secondary) }
                        if item.created_at > 0 {
                            Text(Date(timeIntervalSince1970: item.created_at / 1000), style: .relative).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel((item.isRead ? "" : "Unread, ") + item.title + ". " + item.detail)
                }
            }
        }
        .navigationTitle("Notifications")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Mark all read") {
                    Task {
                        try? await BlindbanditAPI.markSocialNotificationsRead()
                        AppHaptics.success()
                        await load()
                    }
                }
                .disabled(items.allSatisfy { $0.isRead })
            }
        }
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        do {
            items = try await BlindbanditAPI.socialNotifications()
            error = ""
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }
}

struct MessagesSettingsView: View {
    @AppStorage("comms.readAloudRate") private var rate: Double = 0.5
    @AppStorage("comms.showReadReceipts") private var showReadReceipts = true
    @AppStorage(SettingsKey.confirmBeforeSend) private var confirmBeforeSend = false
    @AppStorage(SettingsKey.largeMessageBubbles) private var largeBubbles = false
    @AppStorage(SettingsKey.showLinkPreviews) private var linkPreviews = true
    @AppStorage(SettingsKey.autoPlayVoice) private var autoPlayVoice = true
    @AppStorage(SettingsKey.listenOnceDefault) private var listenOnce = false
    @AppStorage(MagicTapSetting.key) private var magicTapEnds = true
    @ObservedObject private var e2ee = E2EEService.shared
    @ObservedObject private var voice = VoicePlayback.shared

    var body: some View {
        Form {
            Section {
                Slider(value: $rate, in: 0.3...0.7, step: 0.05) { Text("Read-aloud speed") }
                    .accessibilityValue("\(Int(rate * 200)) percent")
                Button("Preview") { MessageReader.shared.speak("This is how messages will sound when read aloud.") }
            } header: { Text("Read aloud").accessibilityAddTraits(.isHeader) }
            Section {
                Toggle("Show read receipts", isOn: $showReadReceipts)
                    .onChange(of: showReadReceipts) { _, _ in AppHaptics.selection() }
                    .accessibilityHint("When off, messages you send show Sent or Delivered instead of Read on this iPhone.")
                Toggle("Confirm before sending", isOn: $confirmBeforeSend)
                Toggle("Large message bubbles", isOn: $largeBubbles)
                Toggle("Link previews", isOn: $linkPreviews)
            } header: { Text("Receipts & composer").accessibilityAddTraits(.isHeader) } footer: {
                Text("Each message you send shows Sent, then Delivered once the server confirms delivery, then Read. Hiding your own read status from others needs a server setting that is not available yet.")
            }
            Section {
                Toggle("Auto-play next voice message", isOn: $autoPlayVoice)
                Toggle("Listen once by default", isOn: $listenOnce)
                Picker("Voice playback speed", selection: Binding(
                    get: { voice.rate },
                    set: { voice.setRate($0) }
                )) {
                    Text("1x").tag(Float(1))
                    Text("1.5x").tag(Float(1.5))
                    Text("2x").tag(Float(2))
                }
            } header: { Text("Voice messages").accessibilityAddTraits(.isHeader) }
            Section {
                Toggle("Magic Tap ends the call", isOn: $magicTapEnds)
                NavigationLink { EncryptionPasscodeView() } label: {
                    Label(EncryptionPasscode.isSet(e2ee.myHandle) ? "Encryption passcode" : "Create encryption passcode", systemImage: "key.fill")
                }
                LabeledContent("Encryption", value: e2ee.ready ? "On, iCloud Keychain" : "Setting up")
            } header: { Text("Calls & encryption").accessibilityAddTraits(.isHeader) }
            Section {
                NavigationLink { BlockedAccountsView() } label: { Label("Blocked accounts", systemImage: "hand.raised") }
                NavigationLink { AppSecurityView() } label: { Label("Security and encryption", systemImage: "lock.shield") }
                NavigationLink { AISettingsView() } label: { Label("AI", systemImage: "sparkles") }
            } header: { Text("Safety").accessibilityAddTraits(.isHeader) }
            if !VoiceLog.lastError.isEmpty {
                Section {
                    Text(VoiceLog.lastError).font(.caption).foregroundStyle(.secondary)
                    Button("Clear voice debug log") { VoiceLog.lastError = "" }
                } header: { Text("Voice message debug").accessibilityAddTraits(.isHeader) }
            }
        }
        .navigationTitle("Messages & calls")
    }
}

// MARK: - Message status and typing

/// Launched only by UI tests (-UITestMessageStatus): an outgoing and an incoming row built from the
/// same pieces the thread uses, so the status element's position and focus can be checked without an account.
struct MessageStatusUITestView: View {
    var body: some View {
        let now = Date().timeIntervalSince1970 * 1000
        VStack(spacing: 10) {
            VStack(alignment: .trailing, spacing: 3) {
                Text("Hello from the test").padding(12)
                    .background(Brand.gold.opacity(0.35), in: RoundedRectangle(cornerRadius: 16))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("You: Hello from the test")
                    .accessibilityIdentifier("outgoing-message")
                MessageStatusCaption(text: MessageStatus.caption(sent: now - 60_000, delivered: now - 30_000, read: nil, showRead: true), mine: true)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .accessibilityElement(children: .contain)
            VStack(alignment: .leading, spacing: 3) {
                Text("Reply").padding(12).background(Color.secondary.opacity(0.16), in: RoundedRectangle(cornerRadius: 16))
                    .accessibilityElement(children: .ignore).accessibilityLabel("@friend: Reply")
                MessageStatusCaption(text: MessageStatus.stamp(now), mine: false)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .contain)
            TypingIndicatorBubble(name: "@friend")
        }
        .padding()
    }
}

/// The small line under a message ("Delivered 2:34 PM"). A separate VoiceOver element that
/// updates in place when receipts change.
struct MessageStatusCaption: View {
    let text: String
    let mine: Bool
    var body: some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(mine ? .trailing : .leading, 6)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(text)
            .accessibilityIdentifier(mine ? "message-status" : "message-time")
            .accessibilityAddTraits(.updatesFrequently)
    }
}

enum MessageStatus {
    /// "Sent", "Delivered", "Read 5:08 AM", "Read Yesterday 9:14 PM", "Read Mon 9:14 PM" or "Read Oct 3, 9:14 PM".
    static func caption(for message: BlindbanditServerMessage, showRead: Bool, now: Date = Date()) -> String {
        if message.id.hasPrefix("local-") { return "Sending…" }
        return caption(sent: message.created_at, delivered: message.delivered_at, read: message.read_at, showRead: showRead, now: now)
    }

    /// "Sent 2:33 PM", "Delivered 2:34 PM" or "Read 5:08 AM", in the device's time zone.
    static func caption(sent: Double, delivered: Double?, read: Double?, showRead: Bool, now: Date = Date()) -> String {
        if showRead, let read { return "Read " + stamp(read, now: now) }
        if let at = delivered ?? read { return "Delivered " + stamp(at, now: now) }
        return "Sent " + stamp(sent, now: now)
    }

    /// Groups: "Read by Sam, Ana 5:08 AM", "Read by 3 5:08 AM", else delivered/sent.
    static func groupCaption(for m: BlindbanditGroupMessage, now: Date = Date()) -> String {
        if m.read_count > 0 || !m.read_by.isEmpty || m.read_at != nil {
            let who = !m.read_by.isEmpty && m.read_by.count <= 3 ? m.read_by.joined(separator: ", ") : "\(max(m.read_count, m.read_by.count))"
            let time = m.read_at.map { " " + stamp($0, now: now) } ?? ""
            return (who == "0" ? "Read" : "Read by \(who)") + time
        }
        return caption(sent: m.created_at, delivered: m.delivered_at, read: nil, showRead: false, now: now)
    }

    /// Local-time label for a server millisecond timestamp, including the day when it isn't today.
    static func stamp(_ millis: Double, now: Date = Date(), calendar: Calendar = .current, locale: Locale = .current) -> String {
        let date = Date(timeIntervalSince1970: millis / 1000)
        let time = DateFormatter()
        time.locale = locale
        time.timeZone = calendar.timeZone
        time.dateStyle = .none
        time.timeStyle = .short
        let clock = time.string(from: date)
        if calendar.isDate(date, inSameDayAs: now) { return clock }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "Yesterday \(clock)"
        }
        let day = DateFormatter()
        day.locale = locale
        day.timeZone = calendar.timeZone
        if let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day, days < 7, days > 0 {
            day.setLocalizedDateFormatFromTemplate("EEE")
        } else {
            day.setLocalizedDateFormatFromTemplate("MMMd")
        }
        return "\(day.string(from: date)), \(clock)"
    }
}

/// Animated three-dot "typing" bubble. Still dots when Reduce Motion is on.
struct TypingIndicatorBubble: View {
    let name: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase = 0

    var body: some View {
        HStack {
            HStack(spacing: 5) {
                ForEach(0..<3) { i in
                    Circle()
                        .fill(Color.secondary)
                        .frame(width: 8, height: 8)
                        .opacity(reduceMotion ? 0.7 : (phase == i ? 1 : 0.35))
                        .scaleEffect(reduceMotion ? 1 : (phase == i ? 1.15 : 0.9))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.secondary.opacity(0.16), in: Capsule())
            Spacer(minLength: 48)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name) is typing")
        .accessibilityIdentifier("typing-indicator")
        .task(id: reduceMotion) {
            guard !reduceMotion else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 380_000_000)
                withAnimation(.easeInOut(duration: 0.3)) { phase = (phase + 1) % 3 }
            }
        }
    }
}


enum MessageReactions {
    static let all: [(emoji: String, name: String)] = [("❤️", "heart"), ("👍", "thumbs up"), ("😂", "laugh")]
    static func name(_ emoji: String) -> String { all.first { $0.emoji == emoji }?.name ?? emoji }
}

/// Sends a copy of a message to someone else.
struct ForwardSheet: View {
    let text: String
    @EnvironmentObject private var communications: ProductionCommunicationsService
    @Environment(\.dismiss) private var dismiss
    @State private var recipient = ""
    @State private var sending = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Message") { Text(text) }
                Section("Send to") {
                    UsernameSearchField(label: "Blindbandit username", text: $recipient)
                    ForEach(communications.conversations.prefix(8)) { c in
                        if let h = c.other?.handle {
                            Button { recipient = h } label: { Text("\(c.other?.display_name ?? h) (@\(h))") }
                                .accessibilityAddTraits(BlindbanditHandle.normalize(recipient) == h ? .isSelected : [])
                        }
                    }
                }
            }
            .navigationTitle("Forward")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(sending ? "Sending…" : "Send") {
                        sending = true
                        Task {
                            if await communications.sendMessage(recipient: recipient, body: text) != nil {
                                UIAccessibility.post(notification: .announcement, argument: "Forwarded")
                                dismiss()
                            }
                            sending = false
                        }
                    }
                    .disabled(sending || BlindbanditHandle.normalize(recipient).isEmpty)
                }
            }
        }
    }
}


enum MessageRowAccessibility {
    static func children(isVoice: Bool) -> AccessibilityChildBehavior { isVoice ? .contain : .ignore }
    static func exposesChildren(isVoice: Bool) -> Bool { isVoice }
    /// First VoiceOver Actions rotor name on a voice row (Play, or Pause when that note is current + playing).
    static func voicePlayActionName(isPlayingCurrent: Bool) -> String { VoiceRowPlayAction.actionName(isPlayingCurrent: isPlayingCurrent) }
}

/// Applies an accessibilityLabel only for non-voice rows. Voice rows must not label the container
/// or VoiceOver treats the whole HStack as one non-activating element.
struct MessageRowLabelModifier: ViewModifier {
    let isVoice: Bool
    let label: String
    func body(content: Content) -> some View {
        if isVoice { content } else { content.accessibilityLabel(label) }
    }
}
