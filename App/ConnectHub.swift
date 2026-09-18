import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// Connect — LiveKit voice/video + 1:1 DMs over reliable data packets.
struct ConnectHubView: View {
    @StateObject private var livekit = LiveKitService()
    @EnvironmentObject private var preferences: AppPreferences
    @EnvironmentObject private var privacy: PrivacyPermissions
    @State private var segment: Segment = .calls
    @State private var openThreadId: String?
    @State private var newPeerName = ""
    @State private var showNewThread = false

    enum Segment: String, CaseIterable { case calls = "Calls", messages = "Messages" }

    var body: some View {
        VStack(spacing: 0) {
            if livekit.usingScaffoldToken || (livekit.connectionState == .connected && livekit.hasScaffoldToken) {
                Text("TEST SCAFFOLD — temporary LiveKit token (not production)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(Color.yellow)
                    .overlay(ShimmerOverlay(reduceMotion: preferences.reduceAppMotion))
                    .accessibilityLabel("Test scaffold temporary LiveKit token")
            }

            Picker("Connect", selection: $segment) {
                ForEach(Segment.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding()
            .accessibilityLabel("Connect sections")

            switch segment {
            case .calls: callsPane
            case .messages:
                if let id = openThreadId, let thread = livekit.threadStore.thread(id: id) {
                    ConversationView(livekit: livekit, threadId: thread.id) {
                        openThreadId = nil
                        livekit.activeThreadId = nil
                    }
                } else {
                    threadsPane
                }
            }
        }
        .background(Color(uiColor: .systemBackground))
        .navigationTitle("Connect")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                BlindbanditLogoImage(size: 28)
                    .accessibilityLabel("Blindbandit Records")
            }
        }
        .onAppear {
            AppHaptics.soft()
            livekit.threadStore.load()
        }
        .sheet(isPresented: $showNewThread) {
            NavigationStack {
                Form {
                    TextField("Peer display name", text: $newPeerName)
                    Button("Start chat") {
                        let name = newPeerName.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !name.isEmpty else { return }
                        let peerId = name.lowercased().replacingOccurrences(of: " ", with: "-")
                        let t = livekit.threadStore.ensureThread(peerId: peerId, peerName: name)
                        openThreadId = t.id
                        showNewThread = false
                        newPeerName = ""
                        Task { await livekit.ensureMessagingConnected() }
                    }
                }
                .navigationTitle("New message")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showNewThread = false }
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }

    private var callsPane: some View {
        ScrollView {
            VStack(spacing: 20) {
                ZStack {
                    ZStack {
                        Image("CallBackgroundGold")
                            .resizable()
                            .scaledToFill()
                            .frame(height: 220)
                            .clipShape(RoundedRectangle(cornerRadius: 28))
                            .overlay(RoundedRectangle(cornerRadius: 28).fill(Color.black.opacity(0.45)))
                        RoundedRectangle(cornerRadius: 28)
                            .stroke(Color.yellow.opacity(0.25), lineWidth: 1)
                            .frame(height: 220)
                    }
                    .frame(height: 220)
                    VStack(spacing: 12) {
                        if livekit.isInCall {
                            ZStack {
                                CallPulseRings(active: true, reduceMotion: preferences.reduceAppMotion)
                                    .frame(width: 140, height: 140)
                                SpinningBrandLogo(size: 88, reduceMotion: preferences.reduceAppMotion)
                            }
                            Text(livekit.isVideoCall ? "Video call" : "Voice call")
                                .font(.title2.bold()).foregroundStyle(.white)
                            Text(livekit.callTimeLabel)
                                .font(.title.monospacedDigit()).foregroundStyle(.yellow)
                                .accessibilityLabel("Call duration \(livekit.callTimeLabel)")
                            Text(livekit.participants.joined(separator: " · "))
                                .font(.caption).foregroundStyle(.white.opacity(0.7))
                        } else {
                            BlindbanditLogoImage(size: 96)
                            Text("Studio line")
                                .font(.title2.bold()).foregroundStyle(.white)
                            Text(livekit.isConfigured
                                 ? (livekit.hasScaffoldToken ? "Ready — TEST SCAFFOLD token configured" : "Ready (needs scaffold or server token)")
                                 : "Add LIVEKIT_URL + scaffold token in Secrets.local.swift")
                                .font(.subheadline).foregroundStyle(.white.opacity(0.7))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                    }
                }
                .accessibilityElement(children: .combine)

                if !livekit.statusMessage.isEmpty {
                    Text(livekit.statusMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityAddTraits(.updatesFrequently)
                }

                HStack(spacing: 12) {
                    Button {
                        AppHaptics.medium()
                        ensureMic {
                            Task { await livekit.connect(asVideo: false) }
                        }
                    } label: {
                        Label("Voice call", systemImage: "phone.fill")
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                    }
                    .buttonStyle(PressableScaleButtonStyle())
                    .buttonStyle(.borderedProminent)
                    .tint(.yellow)
                    .foregroundStyle(.black)
                    .disabled(livekit.isInCall)
                    .accessibilityHint("Starts a LiveKit voice call using the scaffold or server token.")

                    Button {
                        AppHaptics.medium()
                        if privacy.camera == .notDetermined { privacy.requestCamera() }
                        ensureMic {
                            Task { await livekit.connect(asVideo: true) }
                        }
                    } label: {
                        Label("Video call", systemImage: "video.fill")
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.black)
                    .disabled(livekit.isInCall)
                    .accessibilityHint("Starts a LiveKit video call.")
                }

                if livekit.isInCall {
                    HStack(spacing: 16) {
                        callControl(icon: livekit.micEnabled ? "mic.fill" : "mic.slash.fill",
                                    label: livekit.micEnabled ? "Mute" : "Unmute") {
                            livekit.toggleMic()
                        }
                        if livekit.isVideoCall {
                            callControl(icon: livekit.cameraEnabled ? "video.fill" : "video.slash.fill",
                                        label: livekit.cameraEnabled ? "Camera off" : "Camera on") {
                                livekit.toggleCamera()
                            }
                        }
                        callControl(icon: "phone.down.fill", label: "End", destructive: true) {
                            livekit.endCallKeepMessaging()
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Room").font(.headline).accessibilityAddTraits(.isHeader)
                    LabeledContent("Name", value: livekit.roomName)
                    LabeledContent("State", value: livekit.connectionState.rawValue)
                    LabeledContent("Token", value: livekit.tokenSourceLabel)
                    LabeledContent("Server", value: livekit.isConfigured ? "LiveKit Cloud" : "Not configured")
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
            }
            .padding()
        }
    }

    private var threadsPane: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(spacing: 8) {
                    if livekit.threadStore.threads.isEmpty {
                        Image("EmptyStateCastle")
                            .resizable()
                            .scaledToFill()
                            .frame(height: 120)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .overlay(alignment: .bottom) {
                                Text("Start a studio DM")
                                    .font(.caption.weight(.semibold))
                                    .padding(6)
                                    .background(.ultraThinMaterial, in: Capsule())
                                    .padding(8)
                            }
                            .accessibilityLabel("Empty conversations illustration")
                    }
                    Text("Direct messages").font(.headline)
                }
                Spacer()
                Button { showNewThread = true } label: {
                    Image(systemName: "square.and.pencil")
                }
                .accessibilityLabel("New message")
            }
            .padding(.horizontal)
            .padding(.bottom, 8)

            Button {
                Task { await livekit.ensureMessagingConnected() }
            } label: {
                Label(
                    livekit.connectionState == .connected
                        ? (livekit.usingScaffoldToken ? "Messaging online — TEST SCAFFOLD" : "Messaging online")
                        : "Connect messaging room",
                    systemImage: livekit.connectionState == .connected ? "checkmark.circle.fill" : "antenna.radiowaves.left.and.right"
                )
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
            .buttonStyle(.bordered)
            .padding(.horizontal)
            .disabled(livekit.connectionState == .connecting)

            List {
                ForEach(livekit.threadStore.threads) { thread in
                    Button {
                        openThreadId = thread.id
                        livekit.activeThreadId = thread.id
                        Task {
                            await livekit.ensureMessagingConnected()
                            if let t = livekit.threadStore.thread(id: thread.id) {
                                await livekit.markRead(thread: t)
                            }
                        }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(thread.peerName).font(.headline)
                                Text(thread.preview)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Text(thread.updatedAt, style: .time)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .accessibilityLabel("\(thread.peerName): \(thread.preview)")
                }
            }
            .listStyle(.plain)
        }
    }

    private func callControl(icon: String, label: String, destructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.title2)
                    .frame(width: 56, height: 56)
                    .background(destructive ? Color.red.opacity(0.9) : Color.primary.opacity(0.08), in: Circle())
                    .foregroundStyle(destructive ? .white : .primary)
                Text(label).font(.caption2)
            }
        }
        .accessibilityLabel(label)
        .frame(minWidth: 64, minHeight: 64)
    }

    private func ensureMic(_ action: @escaping () -> Void) {
        if privacy.microphone == .notDetermined {
            privacy.requestMicrophone()
        }
        action()
    }
}

// MARK: - Conversation

private struct ConversationView: View {
    @ObservedObject var livekit: LiveKitService
    let threadId: String
    var onBack: () -> Void

    @EnvironmentObject private var preferences: AppPreferences
    @EnvironmentObject private var privacy: PrivacyPermissions
    @State private var draft = ""
    @State private var holdOrigin: CGPoint?
    @State private var cancellingHold = false
    @State private var photoItem: PhotosPickerItem?
    @State private var showFileImporter = false
    @FocusState private var focused: Bool

    private var thread: DMThread? { livekit.threadStore.thread(id: threadId) }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onBack) { Label("Back", systemImage: "chevron.left") }
                Spacer()
                Text(thread?.peerName ?? "Chat").font(.headline)
                Spacer()
                Color.clear.frame(width: 60, height: 1)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            if let typing = livekit.peerTypingName {
                Text("\(typing) is typing…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .accessibilityAddTraits(.updatesFrequently)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(thread?.messages ?? []) { message in
                            bubble(message).id(message.id)
                        }
                    }
                    .padding()
                }
                .onChange(of: thread?.messages.count ?? 0) { _, _ in
                    if let last = thread?.messages.last {
                        withAnimation(preferences.reduceAppMotion ? nil : .easeOut) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            composer
        }
        .onAppear {
            livekit.activeThreadId = threadId
            Task {
                await livekit.ensureMessagingConnected()
                if let t = thread { await livekit.markRead(thread: t) }
            }
        }
        .onChange(of: photoItem) { _, item in
            guard let item, let t = thread else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    let url = FileManager.default.temporaryDirectory.appendingPathComponent("img-\(UUID().uuidString).jpg")
                    try? data.write(to: url)
                    await livekit.sendAttachment(fileURL: url, mime: "image/jpeg", thread: t)
                }
                photoItem = nil
            }
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.item], allowsMultipleSelection: false) { result in
            guard let t = thread, case .success(let urls) = result, let url = urls.first else { return }
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            Task { await livekit.sendAttachment(fileURL: url, mime: "application/octet-stream", thread: t) }
        }
    }

    private var composer: some View {
        VStack(spacing: 8) {
            if livekit.isRecordingVoiceNote {
                HStack {
                    Image(systemName: "waveform")
                    Text(cancellingHold ? "Release to cancel" : "Recording… swipe up to cancel")
                        .font(.caption.weight(.semibold))
                    Spacer()
                }
                .foregroundStyle(cancellingHold ? .red : .primary)
                .padding(.horizontal)
            }

            HStack(spacing: 8) {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Image(systemName: "photo").frame(width: 40, height: 40)
                }
                .accessibilityLabel("Attach image")

                Button { showFileImporter = true } label: {
                    Image(systemName: "paperclip").frame(width: 40, height: 40)
                }
                .accessibilityLabel("Attach file")

                TextField("Message", text: $draft, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)
                    .focused($focused)
                    .accessibilityLabel("Message field")
                    .onChange(of: draft) { _, value in
                        guard let t = thread else { return }
                        Task { await livekit.sendTyping(thread: t, isTyping: !value.isEmpty) }
                    }

                Button {
                    guard let t = thread else { return }
                    let text = draft
                    draft = ""
                    Task {
                        await livekit.sendDMText(text, thread: t)
                        await livekit.sendTyping(thread: t, isTyping: false)
                    }
                } label: {
                    Image(systemName: "paperplane.fill").frame(width: 44, height: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(.yellow)
                .foregroundStyle(.black)
                .accessibilityLabel("Send message")
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                holdToTalk
            }
            .padding(.horizontal)
            .padding(.bottom, 10)
        }
        .background(.bar)
    }

    private var holdToTalk: some View {
        Image(systemName: livekit.isRecordingVoiceNote ? "mic.fill" : "mic.circle.fill")
            .font(.title2)
            .foregroundStyle(livekit.isRecordingVoiceNote ? (cancellingHold ? .red : .yellow) : .primary)
            .frame(width: 48, height: 48)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if holdOrigin == nil {
                            holdOrigin = value.startLocation
                            cancellingHold = false
                            if privacy.microphone == .notDetermined { privacy.requestMicrophone() }
                            livekit.startVoiceNote()
                        } else if let origin = holdOrigin {
                            cancellingHold = (origin.y - value.location.y) > 60
                        }
                    }
                    .onEnded { _ in
                        if cancellingHold {
                            livekit.cancelVoiceNote()
                        } else if let t = thread {
                            livekit.stopVoiceNoteAndSend(thread: t)
                        } else {
                            livekit.cancelVoiceNote()
                        }
                        holdOrigin = nil
                        cancellingHold = false
                    }
            )
            .accessibilityLabel("Hold to record voice note")
            .accessibilityHint("Press and hold to record, release to send, swipe up to cancel.")
    }

    private func bubble(_ message: DMMessage) -> some View {
        HStack {
            if message.isLocal { Spacer(minLength: 40) }
            VStack(alignment: message.isLocal ? .trailing : .leading, spacing: 4) {
                Text(message.senderName)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Group {
                    switch message.kind {
                    case .voiceNote:
                        Button {
                            if let url = message.voiceNoteURL { livekit.playVoiceNote(url) }
                        } label: {
                            Label("Voice note — tap to play", systemImage: "waveform").padding(10)
                        }
                    case .attachment:
                        attachmentPreview(message)
                    default:
                        Text(message.body).padding(10)
                    }
                }
                .background(message.isLocal ? Color.yellow.opacity(0.25) : Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 14))

                if message.isLocal {
                    Text(receiptLabel(message.receipt))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Status \(receiptLabel(message.receipt))")
                }
            }
            if !message.isLocal { Spacer(minLength: 40) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(message.senderName): \(message.body)")
    }

    @ViewBuilder
    private func attachmentPreview(_ message: DMMessage) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let path = message.localFilePath,
               let ui = UIImage(contentsOfFile: path),
               (message.attachmentMime ?? "").hasPrefix("image") {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 200, maxHeight: 160)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            Label(message.attachmentName ?? message.body, systemImage: "doc.fill")
                .padding(8)
        }
        .padding(6)
    }

    private func receiptLabel(_ r: MessageReceipt) -> String {
        switch r {
        case .sending: return "Sending…"
        case .sent: return "Sent ✓"
        case .delivered: return "Delivered ✓✓"
        case .read: return "Read ✓✓"
        }
    }
}
