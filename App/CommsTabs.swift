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
    @AppStorage(ContentFilter.settingKey) private var filterOffensiveLanguage = true
    @State private var path: [String] = []
    @State private var search = ""
    @State private var composing = false
    @State private var pinned = LocalComms.pinned
    @State private var muted = LocalComms.muted

    private var visibleConversations: [BlindbanditConversation] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        let filtered = communications.conversations.filter { c in
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
                                    Button(muted.contains(conversation.id) ? "Unmute" : "Mute") { toggleMute(conversation) }
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
        .onReceive(NotificationCenter.default.publisher(for: .blindbanditMessageDeepLinkReceived)) { note in
            let id = note.object as? String ?? ""
            Task {
                await communications.refreshConversations()
                if communications.conversation(id: id) != nil { path = [id] }
            }
        }
    }

    @ViewBuilder
    private func rowMenu(_ conversation: BlindbanditConversation) -> some View {
        Button(pinned.contains(conversation.id) ? "Unpin" : "Pin") { togglePin(conversation) }
        Button(muted.contains(conversation.id) ? "Unmute" : "Mute") { toggleMute(conversation) }
        Button("Mark as unread") { communications.markUnread(conversation) }
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
                        Image(systemName: "checkmark.seal.fill").foregroundStyle(Brand.goldDeep).accessibilityHidden(true)
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
            muted.contains(conversation.id) ? "Muted" : nil,
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
    @State private var draft = ""
    @State private var quoting: BlindbanditServerMessage?
    @State private var search = ""
    @State private var reportTarget: ReportTarget?
    @State private var confirmBlock = false
    @Environment(\.dismiss) private var dismiss
    @FocusState private var composerFocused: Bool

    private var conversation: BlindbanditConversation? { communications.conversation(id: conversationID) }
    private var handle: String { conversation?.other?.handle ?? "" }

    private var shownMessages: [BlindbanditServerMessage] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return communications.messages }
        return communications.messages.filter { $0.body.lowercased().contains(q) }
    }

    var body: some View {
        VStack(spacing: 0) {
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
                        }
                    }
                    .padding()
                }
                .onChange(of: communications.messages) { _, list in
                    if let last = list.last, search.isEmpty { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
            .refreshable { if let c = conversation { await communications.openConversation(c) } }

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
                Button { send() } label: {
                    Image(systemName: "paperplane.fill").frame(width: Brand.minTouch, height: Brand.minTouch)
                }
                .accessibilityLabel("Send")
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || handle.isEmpty)
            }
            .padding()
            .background(.bar)
        }
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Search this conversation")
        .navigationTitle(conversation?.other?.display_name ?? "Conversation")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    Task {
                        guard await CommsPermissions.microphone(privacy, communications) else { return }
                        router.selection = .calls
                        await communications.startCall(recipient: handle, video: false)
                    }
                } label: { Image(systemName: "phone.fill") }
                .accessibilityLabel("Voice call @\(handle)")
                .disabled(handle.isEmpty || communications.isInCall)

                Menu {
                    Button {
                        Task {
                            guard await CommsPermissions.microphone(privacy, communications),
                                  await CommsPermissions.camera(privacy, communications) else { return }
                            router.selection = .calls
                            await communications.startCall(recipient: handle, video: true)
                        }
                    } label: { Label("Video call", systemImage: "video.fill") }
                    Button { toggleFavorite() } label: {
                        Label(LocalComms.favorites.contains(handle) ? "Remove from favorites" : "Add to favorites", systemImage: "star")
                    }
                    Button {
                        reportTarget = ReportTarget(type: "profile", id: handle, title: "@\(handle)")
                    } label: { Label("Report @\(handle)", systemImage: "exclamationmark.bubble") }
                    Button(role: .destructive) { confirmBlock = true } label: { Label("Block @\(handle)", systemImage: "hand.raised") }
                } label: { Image(systemName: "ellipsis.circle") }
                .accessibilityLabel("More options")
                .disabled(handle.isEmpty)
            }
        }
        .task(id: conversationID) {
            draft = LocalComms.draft(for: conversationID)
            if let c = conversation { await communications.openConversation(c) }
        }
        .onChange(of: draft) { _, value in LocalComms.setDraft(value, for: conversationID) }
        .onDisappear { communications.closeConversation() }
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

    private func toggleFavorite() {
        var favs = LocalComms.favorites
        if favs.contains(handle) { favs.removeAll { $0 == handle } } else { favs.append(handle) }
        LocalComms.favorites = favs
        AppHaptics.success()
        UIAccessibility.post(notification: .announcement, argument: favs.contains(handle) ? "Added to favorites" : "Removed from favorites")
    }

    private func send() {
        var body = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if let q = quoting {
            let quoted = q.body.split(separator: "\n").prefix(3).map { "> " + $0 }.joined(separator: "\n")
            body = quoted + "\n" + body
        }
        draft = ""
        quoting = nil
        LocalComms.setDraft("", for: conversationID)
        Task { _ = await communications.sendMessage(recipient: handle, body: body) }
    }

    private func receipt(for message: BlindbanditServerMessage) -> String {
        message.read_at != nil ? "Read" : "Sent"
    }

    @ViewBuilder
    private func bubble(_ message: BlindbanditServerMessage) -> some View {
        let mine = message.sender_id == communications.myProfileID
        let sent = Date(timeIntervalSince1970: message.created_at / 1000)
        let shown = mine ? message.body : ContentFilter.display(message.body, enabled: filterOffensiveLanguage)
        let isLastMine = mine && communications.messages.last(where: { $0.sender_id == communications.myProfileID })?.id == message.id
        HStack {
            if mine { Spacer(minLength: 48) }
            VStack(alignment: mine ? .trailing : .leading, spacing: 4) {
                Text(shown)
                    .padding(12)
                    .background(mine ? Brand.gold.opacity(0.35) : Color.secondary.opacity(0.16), in: RoundedRectangle(cornerRadius: 16))
                    .textSelection(.enabled)
                HStack(spacing: 4) {
                    Text(sent, style: .time)
                    if isLastMine { Text("· \(receipt(for: message))") }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            if !mine { Spacer(minLength: 48) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(mine ? "You" : "@\(handle)"): \(shown)")
        .accessibilityValue(Text(sent, style: .time) + Text(isLastMine ? ", \(receipt(for: message))" : ""))
        .accessibilityActions { messageActions(message, shown: shown, mine: mine) }
        .contextMenu { messageActions(message, shown: shown, mine: mine) }
    }

    @ViewBuilder
    private func messageActions(_ message: BlindbanditServerMessage, shown: String, mine: Bool) -> some View {
        Button { quoting = message; composerFocused = true } label: { Label("Reply", systemImage: "arrowshape.turn.up.left") }
        Button { UIPasteboard.general.string = shown; AppHaptics.light() } label: { Label("Copy", systemImage: "doc.on.doc") }
        ShareLink(item: shown) { Label("Share", systemImage: "square.and.arrow.up") }
        Button { MessageReader.shared.speak(shown) } label: { Label("Read aloud", systemImage: "speaker.wave.2") }
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

// MARK: - Active call (shown over every tab while a call is live)

struct ActiveCallScreen: View {
    @EnvironmentObject private var communications: ProductionCommunicationsService

    var body: some View {
        VStack(spacing: 20) {
            if communications.isVideoCall {
                ZStack(alignment: .bottomTrailing) {
                    Group {
                        if let remote = communications.remoteVideoTrack {
                            SwiftUIVideoView(remote, layoutMode: .fit)
                        } else {
                            ZStack {
                                Color.black
                                Text(communications.isRinging ? "Ringing…" : "Waiting for video")
                                    .font(.headline).foregroundStyle(.white)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: Brand.corner))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(communications.remoteVideoTrack == nil ? "Waiting for the other person's video" : "Video from \(communications.callPeerName)")
                    if let local = communications.localVideoTrack, communications.cameraEnabled {
                        SwiftUIVideoView(local, layoutMode: .fill, mirrorMode: .mirror)
                            .frame(width: 96, height: 128)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .padding(10)
                            .accessibilityLabel("Your camera preview")
                    }
                }
            } else {
                Spacer()
                Image(systemName: "person.crop.circle.fill").font(.system(size: 96)).foregroundStyle(Brand.gold).accessibilityHidden(true)
            }

            VStack(spacing: 6) {
                Text(communications.callPeerName.isEmpty ? "Call" : communications.callPeerName).font(.title.bold())
                Text(communications.isRinging ? "Ringing…" : communications.callTimeLabel).font(.title2.monospacedDigit())
                Text(communications.isVideoCall ? "Video call" : "Voice call").foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            if !communications.isVideoCall { Spacer() }

            HStack(spacing: 16) {
                control(communications.micEnabled ? "mic.fill" : "mic.slash.fill", communications.micEnabled ? "Mute" : "Unmute", selected: !communications.micEnabled) {
                    communications.toggleMic()
                }
                control("speaker.wave.3.fill", communications.speakerOn ? "Speaker on" : "Speaker", selected: communications.speakerOn) {
                    communications.toggleSpeaker()
                }
                if communications.isVideoCall {
                    control(communications.cameraEnabled ? "video.fill" : "video.slash.fill", communications.cameraEnabled ? "Camera off" : "Camera on", selected: !communications.cameraEnabled) {
                        communications.toggleCamera()
                    }
                }
                control("phone.down.fill", communications.isRinging ? "Cancel" : "End", destructive: true) {
                    communications.endCall()
                }
            }
            .padding(.bottom)
        }
        .padding()
        .background(Color(uiColor: .systemBackground))
    }

    private func control(_ icon: String, _ label: String, selected: Bool = false, destructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.title2)
                    .frame(width: 64, height: 64)
                    .background(destructive ? Color.red : (selected ? Color.primary : Color.primary.opacity(0.12)), in: Circle())
                    .foregroundStyle(destructive ? Color.white : (selected ? Color(uiColor: .systemBackground) : Color.primary))
                Text(label).font(.caption)
            }
        }
        .frame(minWidth: 72, minHeight: 80)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
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

    var body: some View {
        Form {
            Section {
                Slider(value: $rate, in: 0.3...0.7, step: 0.05) { Text("Read-aloud speed") }
                    .accessibilityValue("\(Int(rate * 200)) percent")
                Button("Preview") { MessageReader.shared.speak("This is how messages will sound when read aloud.") }
            } header: { Text("Read aloud").accessibilityAddTraits(.isHeader) }
            Section {
                NavigationLink { BlockedAccountsView() } label: { Label("Blocked accounts", systemImage: "hand.raised") }
            } header: { Text("Safety").accessibilityAddTraits(.isHeader) }
        }
        .navigationTitle("Messages & calls")
    }
}
