import SwiftUI
import LiveKit

/// Calls and messages between Blindbandit members. Clerk authenticates every request; LiveKit
/// room tokens are minted per call by the server. One shared service lives at the app root so a
/// call keeps running while you move between tabs.
struct ConnectHubView: View {
    @EnvironmentObject private var communications: ProductionCommunicationsService
    @EnvironmentObject private var privacy: PrivacyPermissions
    @EnvironmentObject private var preferences: AppPreferences

    @State private var segment: Segment = .calls
    @State private var callRecipient = ""
    @State private var newMessageRecipient = ""
    @State private var newMessageBody = ""
    @State private var selectedConversation: BlindbanditConversation?
    @State private var replyDraft = ""
    @State private var reportTarget: ReportTarget?
    @State private var blockHandle: String?

    enum Segment: String, CaseIterable { case calls = "Calls", messages = "Messages" }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Section", selection: $segment) {
                ForEach(Segment.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding()

            if !communications.statusMessage.isEmpty {
                Text(communications.statusMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }

            switch segment {
            case .calls: callsPane
            case .messages: messagesPane
            }
        }
        .navigationTitle("Connect")
        .navigationBarTitleDisplayMode(.inline)
        .task { await communications.bootstrap() }
        .onReceive(NotificationCenter.default.publisher(for: .blindbanditCallDeepLinkReceived)) { note in
            guard let callID = note.object as? String else { return }
            segment = .calls
            Task {
                guard await ensureMicrophone() else { return }
                await communications.joinIncomingCall(id: callID)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .blindbanditMessageDeepLinkReceived)) { note in
            segment = .messages
            let conversationID = note.object as? String ?? ""
            Task {
                await communications.refreshConversations()
                if let conversation = communications.conversation(id: conversationID) {
                    selectedConversation = conversation
                    await communications.openConversation(conversation)
                }
            }
        }
        .sheet(item: $reportTarget) { target in
            ReportSheet(target: target) { reason, details in
                await communications.report(targetType: target.type, targetID: target.id, reason: reason, details: details)
            }
        }
        .confirmationDialog(
            "Block @\(blockHandle ?? "")?",
            isPresented: Binding(get: { blockHandle != nil }, set: { if !$0 { blockHandle = nil } }),
            titleVisibility: .visible
        ) {
            Button("Block", role: .destructive) {
                let handle = blockHandle ?? ""
                Task {
                    if await communications.block(handle: handle) { selectedConversation = nil }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("They will no longer be able to message or call you. You can also report them so our team can review.")
        }
    }

    // MARK: Calls

    private var callsPane: some View {
        ScrollView {
            VStack(spacing: 18) {
                if communications.isInCall {
                    activeCallView
                } else {
                    BrandCard {
                        Text("Start a call")
                            .font(.title3.bold())
                            .accessibilityAddTraits(.isHeader)
                        Text("Call another Blindbandit member by their username. Your username is @\(communications.myHandle.isEmpty ? "…" : communications.myHandle).")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        TextField("Blindbandit username", text: $callRecipient)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .textContentType(.username)
                            .padding(12)
                            .frame(minHeight: Brand.minTouch)
                            .background(Color(uiColor: .tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                            .accessibilityHint("For example, mrblindbandit")

                        Button {
                            Task {
                                guard await ensureMicrophone() else { return }
                                await communications.startCall(recipient: callRecipient, video: false)
                            }
                        } label: {
                            Label("Voice call", systemImage: "phone.fill")
                        }
                        .buttonStyle(BrandPrimaryButtonStyle())
                        .disabled(callRecipient.trimmingCharacters(in: .whitespaces).isEmpty)

                        Button {
                            Task {
                                guard await ensureMicrophone(), await ensureCamera() else { return }
                                await communications.startCall(recipient: callRecipient, video: true)
                            }
                        } label: {
                            Label("Video call", systemImage: "video.fill")
                                .frame(maxWidth: .infinity, minHeight: Brand.minTouch)
                        }
                        .buttonStyle(.bordered)
                        .disabled(callRecipient.trimmingCharacters(in: .whitespaces).isEmpty)
                    }

                    BrandCard {
                        Label("Safety", systemImage: "hand.raised.fill")
                            .font(.headline)
                            .accessibilityAddTraits(.isHeader)
                        Text("Only people with a Blindbandit account can call you. In any conversation, open the Safety menu to report or block someone.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding()
        }
    }

    private var activeCallView: some View {
        VStack(spacing: 16) {
            if communications.isVideoCall {
                ZStack(alignment: .bottomTrailing) {
                    Group {
                        if let remote = communications.remoteVideoTrack {
                            SwiftUIVideoView(remote, layoutMode: .fit)
                        } else {
                            ZStack {
                                Color.black
                                Text("Waiting for video from \(communications.callPeerName)")
                                    .font(.headline)
                                    .foregroundStyle(.white)
                                    .multilineTextAlignment(.center)
                                    .padding()
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 320)
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
            }

            BrandCard {
                VStack(spacing: 6) {
                    Text(communications.callPeerName.isEmpty ? "Call" : communications.callPeerName)
                        .font(.title2.bold())
                    Text(communications.callTimeLabel)
                        .font(.title.monospacedDigit())
                    Text(communications.isVideoCall ? "Video call" : "Voice call")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)

                HStack(spacing: 18) {
                    callControl(
                        icon: communications.micEnabled ? "mic.fill" : "mic.slash.fill",
                        label: communications.micEnabled ? "Mute" : "Unmute"
                    ) { communications.toggleMic() }

                    if communications.isVideoCall {
                        callControl(
                            icon: communications.cameraEnabled ? "video.fill" : "video.slash.fill",
                            label: communications.cameraEnabled ? "Turn camera off" : "Turn camera on"
                        ) { communications.toggleCamera() }
                    }

                    callControl(icon: "phone.down.fill", label: "End call", destructive: true) {
                        communications.endCall()
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func callControl(icon: String, label: String, destructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.title2)
                    .frame(width: 60, height: 60)
                    .background(destructive ? Color.red : Color.primary.opacity(0.1), in: Circle())
                    .foregroundStyle(destructive ? .white : .primary)
                Text(label).font(.caption)
            }
        }
        .frame(minWidth: 76, minHeight: 76)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityAddTraits(.isButton)
    }

    // MARK: Messages

    private var messagesPane: some View {
        VStack(spacing: 0) {
            if let conversation = selectedConversation {
                conversationView(conversation)
            } else {
                List {
                    Section("New message") {
                        TextField("Blindbandit username", text: $newMessageRecipient)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        TextField("Message", text: $newMessageBody, axis: .vertical)
                            .lineLimit(1...6)
                        Button {
                            let body = newMessageBody
                            Task {
                                if let id = await communications.sendMessage(recipient: newMessageRecipient, body: body) {
                                    newMessageBody = ""
                                    if let conversation = communications.conversation(id: id) {
                                        selectedConversation = conversation
                                        await communications.openConversation(conversation)
                                    }
                                }
                            }
                        } label: {
                            Label("Send", systemImage: "paperplane.fill")
                        }
                        .disabled(newMessageRecipient.trimmingCharacters(in: .whitespaces).isEmpty || newMessageBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }

                    Section("Conversations") {
                        if communications.isLoading && communications.conversations.isEmpty {
                            ProgressView("Loading conversations")
                        } else if communications.conversations.isEmpty {
                            Text("No conversations yet. Send a message to start one.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(communications.conversations) { conversation in
                                Button {
                                    selectedConversation = conversation
                                    Task { await communications.openConversation(conversation) }
                                } label: {
                                    conversationRow(conversation)
                                }
                                .foregroundStyle(.primary)
                            }
                        }
                    }
                }
                .refreshable { await communications.refreshConversations() }
            }
        }
    }

    private func conversationRow(_ conversation: BlindbanditConversation) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(conversation.other?.display_name ?? conversation.other?.handle ?? "Blindbandit member")
                    .font(.headline)
                if conversation.other?.verified == true {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(Brand.goldDeep)
                        .accessibilityLabel("Verified")
                }
                Spacer()
                Text(Date(timeIntervalSince1970: conversation.updated_at / 1000), style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let last = conversation.last_message {
                Text(last.body)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the conversation")
    }

    private func conversationView(_ conversation: BlindbanditConversation) -> some View {
        let handle = conversation.other?.handle ?? ""
        return VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button {
                    selectedConversation = nil
                    communications.statusMessage = ""
                } label: {
                    Label("Conversations", systemImage: "chevron.left")
                }
                .frame(minHeight: Brand.minTouch)
                Spacer()
                VStack {
                    Text(conversation.other?.display_name ?? "Conversation").font(.headline)
                    if !handle.isEmpty {
                        Text("@\(handle)").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
                Spacer()
                Button {
                    callRecipient = handle
                    segment = .calls
                } label: {
                    Image(systemName: "phone.fill").frame(width: Brand.minTouch, height: Brand.minTouch)
                }
                .accessibilityLabel("Call @\(handle)")
                .disabled(handle.isEmpty)

                Menu {
                    Button {
                        reportTarget = ReportTarget(type: "profile", id: handle, title: "@\(handle)")
                    } label: { Label("Report @\(handle)", systemImage: "exclamationmark.bubble") }
                    Button(role: .destructive) {
                        blockHandle = handle
                    } label: { Label("Block @\(handle)", systemImage: "hand.raised") }
                } label: {
                    Image(systemName: "ellipsis.circle").frame(width: Brand.minTouch, height: Brand.minTouch)
                }
                .accessibilityLabel("Safety options")
                .disabled(handle.isEmpty)
            }
            .padding(.horizontal)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(communications.messages) { message in
                            messageBubble(message, handle: handle)
                                .id(message.id)
                        }
                    }
                    .padding()
                }
                .onChange(of: communications.messages) { _, messages in
                    if let last = messages.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
            .refreshable { await communications.openConversation(conversation) }

            HStack(spacing: 8) {
                TextField("Message @\(handle)", text: $replyDraft, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...5)
                Button {
                    let body = replyDraft
                    replyDraft = ""
                    Task {
                        _ = await communications.sendMessage(recipient: handle, body: body)
                        await communications.openConversation(conversation)
                    }
                } label: {
                    Image(systemName: "paperplane.fill").frame(width: Brand.minTouch, height: Brand.minTouch)
                }
                .accessibilityLabel("Send")
                .disabled(replyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()
            .background(.bar)
        }
    }

    private func messageBubble(_ message: BlindbanditServerMessage, handle: String) -> some View {
        let mine = message.sender_id == communications.myProfileID
        let sent = Date(timeIntervalSince1970: message.created_at / 1000)
        return HStack {
            if mine { Spacer(minLength: 48) }
            VStack(alignment: mine ? .trailing : .leading, spacing: 4) {
                Text(message.body)
                    .padding(12)
                    .background(mine ? Brand.gold.opacity(0.35) : Color.secondary.opacity(0.16), in: RoundedRectangle(cornerRadius: 16))
                Text(sent, style: .time)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !mine { Spacer(minLength: 48) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(mine ? "You" : "@\(handle)"): \(message.body)")
        .accessibilityValue(Text(sent, style: .time))
        .accessibilityActions {
            if !mine {
                Button("Report this message") {
                    reportTarget = ReportTarget(type: "message", id: message.id, title: "this message")
                }
            }
        }
        .contextMenu {
            if !mine {
                Button {
                    reportTarget = ReportTarget(type: "message", id: message.id, title: "this message")
                } label: { Label("Report message", systemImage: "exclamationmark.bubble") }
            }
        }
    }

    // MARK: Permissions (asked only when needed)

    private func ensureMicrophone() async -> Bool {
        switch privacy.microphone {
        case .authorized: return true
        case .notDetermined:
            if await privacy.requestMicrophone() { return true }
        default: break
        }
        communications.statusMessage = "Calls need microphone access. Turn it on in iPhone Settings > Mr. Blindbandit."
        AppHaptics.warning()
        return false
    }

    private func ensureCamera() async -> Bool {
        switch privacy.camera {
        case .authorized: return true
        case .notDetermined:
            if await privacy.requestCamera() { return true }
        default: break
        }
        communications.statusMessage = "Video calls need camera access. Turn it on in iPhone Settings > Mr. Blindbandit."
        AppHaptics.warning()
        return false
    }
}

struct ReportTarget: Identifiable {
    let type: String
    let id: String
    let title: String
}

struct ReportSheet: View {
    let target: ReportTarget
    let submit: (ReportReason, String) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var reason: ReportReason = .harassment
    @State private var details = ""
    @State private var sending = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Reason", selection: $reason) {
                        ForEach(ReportReason.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text("Why are you reporting \(target.title)?")
                }
                Section("Details (optional)") {
                    TextField("What happened?", text: $details, axis: .vertical)
                        .lineLimit(3...8)
                }
                Section {
                    Text("Reports go to the Blindbandit moderation team for review. If someone is in immediate danger, contact local emergency services.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") {
                        sending = true
                        Task {
                            let ok = await submit(reason, details)
                            sending = false
                            if ok { dismiss() }
                        }
                    }
                    .disabled(sending)
                }
            }
        }
    }
}
