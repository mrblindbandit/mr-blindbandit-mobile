import SwiftUI

/// Production Connect hub. Calls and messages use Clerk-authenticated API requests;
/// LiveKit room tokens are minted by the server and never embedded in the app.
struct ConnectHubView: View {
    @StateObject private var communications = ProductionCommunicationsService()
    @EnvironmentObject private var privacy: PrivacyPermissions
    @EnvironmentObject private var preferences: AppPreferences

    @State private var segment: Segment = .calls
    @State private var callRecipient = ""
    @State private var newMessageRecipient = ""
    @State private var newMessageBody = ""
    @State private var selectedConversation: BlindbanditConversation?
    @State private var replyDraft = ""
    @State private var keypadDigits = ""

    enum Segment: String, CaseIterable { case calls = "Calls", messages = "Messages", keypad = "Keypad" }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Connect", selection: $segment) {
                ForEach(Segment.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding()
            .accessibilityLabel("Calls, Messages, or Keypad")

            if !communications.statusMessage.isEmpty {
                Text(communications.statusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                    .accessibilityAddTraits(.updatesFrequently)
            }

            switch segment {
            case .calls: callsPane
            case .messages: messagesPane
            case .keypad: keypadPane
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
        .task { await communications.bootstrap() }
        .onReceive(NotificationCenter.default.publisher(for: .blindbanditCallDeepLinkReceived)) { note in
            guard let callID = note.object as? String else { return }
            segment = .calls
            Task { await communications.joinIncomingCall(id: callID) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .blindbanditMessageDeepLinkReceived)) { _ in
            segment = .messages
            Task { await communications.refreshConversations() }
        }
        .onAppear { AppHaptics.soft() }
    }

    private var callsPane: some View {
        ScrollView {
            VStack(spacing: 18) {
                callStatusCard

                if !communications.isInCall {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Call someone").font(.headline).accessibilityAddTraits(.isHeader)
                        TextField("Email address or Blindbandit username", text: $callRecipient)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.emailAddress)
                            .textContentType(.emailAddress)
                            .accessibilityHint("Enter the exact email address on their Blindbandit account, or their username.")

                        HStack(spacing: 12) {
                            Button {
                                ensureMicrophone {
                                    Task { await communications.startCall(recipient: callRecipient, video: false) }
                                }
                            } label: {
                                Label("Voice call", systemImage: "phone.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.yellow)
                            .foregroundStyle(.black)

                            Button {
                                ensureCameraAndMicrophone {
                                    Task { await communications.startCall(recipient: callRecipient, video: true) }
                                }
                            } label: {
                                Label("Video call", systemImage: "video.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                        }
                        .controlSize(.large)
                    }
                    .padding()
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
                } else {
                    inCallControls
                }

                VStack(alignment: .leading, spacing: 8) {
                    Label("Production communications", systemImage: "checkmark.shield.fill")
                        .font(.headline)
                    Text("Clerk authenticates the user. The Blindbandit API resolves the recipient and creates the call. LiveKit credentials are short-lived and minted server-side for that call room.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
            }
            .padding()
        }
    }

    private var callStatusCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28)
                .fill(Color.black)
                .frame(height: 220)
            VStack(spacing: 12) {
                if communications.isInCall {
                    CallPulseRings(active: true, reduceMotion: preferences.reduceAppMotion)
                        .frame(width: 92, height: 92)
                    Text(communications.callPeerName.isEmpty ? "Blindbandit call" : communications.callPeerName)
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                    Text(communications.callTimeLabel)
                        .font(.title.monospacedDigit())
                        .foregroundStyle(.yellow)
                    Text(communications.isVideoCall ? "Video call" : "Voice call")
                        .foregroundStyle(.white.opacity(0.7))
                } else {
                    BlindbanditLogoImage(size: 96)
                    Text("Blindbandit Calling")
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                    Text("Call registered users by email or username")
                        .foregroundStyle(.white.opacity(0.72))
                }
            }
            .multilineTextAlignment(.center)
            .padding()
        }
        .accessibilityElement(children: .combine)
    }

    private var inCallControls: some View {
        VStack(spacing: 14) {
            HStack(spacing: 18) {
                callControl(
                    icon: communications.micEnabled ? "mic.fill" : "mic.slash.fill",
                    label: communications.micEnabled ? "Mute" : "Unmute"
                ) { communications.toggleMic() }

                if communications.isVideoCall {
                    callControl(
                        icon: communications.cameraEnabled ? "video.fill" : "video.slash.fill",
                        label: communications.cameraEnabled ? "Camera off" : "Camera on"
                    ) { communications.toggleCamera() }
                }

                callControl(icon: "phone.down.fill", label: "End", destructive: true) {
                    communications.endCall()
                }
            }
            Button("Open keypad") {
                segment = .keypad
                AppHaptics.selection()
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    private var messagesPane: some View {
        VStack(spacing: 0) {
            if let conversation = selectedConversation {
                conversationView(conversation)
            } else {
                newMessageComposer
                Divider()
                HStack {
                    Text("Conversations").font(.headline)
                    Spacer()
                    Button {
                        Task { await communications.refreshConversations() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("Refresh conversations")
                }
                .padding()

                if communications.isLoading {
                    ProgressView("Loading messages")
                    Spacer()
                } else if communications.conversations.isEmpty {
                    ContentUnavailableView(
                        "No conversations yet",
                        systemImage: "message",
                        description: Text("Send a message to a registered user's email address or username.")
                    )
                } else {
                    List(communications.conversations) { conversation in
                        Button {
                            selectedConversation = conversation
                            Task { await communications.openConversation(conversation) }
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Text(conversation.other?.display_name ?? conversation.other?.handle ?? "Blindbandit user")
                                        .font(.headline)
                                    if conversation.other?.verified == true {
                                        Image(systemName: "checkmark.seal.fill").foregroundStyle(.blue)
                                    }
                                }
                                Text(conversation.last_message?.body ?? "No messages yet")
                                    .lineLimit(1)
                                    .foregroundStyle(.secondary)
                                if let time = conversation.last_message?.created_at {
                                    Text(Date(timeIntervalSince1970: time / 1000), style: .relative)
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .listStyle(.plain)
                }
            }
        }
    }

    private var newMessageComposer: some View {
        VStack(spacing: 10) {
            TextField("Recipient email or username", text: $newMessageRecipient)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.emailAddress)
            TextField("Message", text: $newMessageBody, axis: .vertical)
                .lineLimit(1...4)
            Button {
                let body = newMessageBody
                Task {
                    if let id = await communications.sendMessage(recipient: newMessageRecipient, body: body) {
                        newMessageBody = ""
                        if let conversation = communications.conversations.first(where: { $0.id == id }) {
                            selectedConversation = conversation
                        }
                    }
                }
            } label: {
                Label("Send message", systemImage: "paperplane.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.yellow)
            .foregroundStyle(.black)
            .disabled(newMessageRecipient.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || newMessageBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding()
    }

    private func conversationView(_ conversation: BlindbanditConversation) -> some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    selectedConversation = nil
                    communications.statusMessage = ""
                } label: { Label("Back", systemImage: "chevron.left") }
                Spacer()
                VStack {
                    Text(conversation.other?.display_name ?? "Conversation").font(.headline)
                    Text("@\(conversation.other?.handle ?? "user")").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    callRecipient = conversation.other?.handle ?? ""
                    segment = .calls
                } label: { Image(systemName: "phone.fill") }
                .accessibilityLabel("Call this person")
            }
            .padding()

            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(communications.messages) { message in
                        let mine = message.sender_id == communications.myProfileID
                        HStack {
                            if mine { Spacer(minLength: 50) }
                            VStack(alignment: mine ? .trailing : .leading, spacing: 4) {
                                Text(message.body)
                                    .padding(10)
                                    .background(mine ? Color.yellow.opacity(0.28) : Color.secondary.opacity(0.16), in: RoundedRectangle(cornerRadius: 14))
                                Text(Date(timeIntervalSince1970: message.created_at / 1000), style: .time)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            if !mine { Spacer(minLength: 50) }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding()
            }
            .refreshable { await communications.openConversation(conversation) }

            HStack(spacing: 8) {
                TextField("Message", text: $replyDraft, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)
                Button {
                    let body = replyDraft
                    replyDraft = ""
                    Task {
                        _ = await communications.sendMessage(recipient: conversation.other?.handle ?? "", body: body)
                        await communications.openConversation(conversation)
                    }
                } label: { Image(systemName: "paperplane.fill") }
                    .buttonStyle(.borderedProminent)
                    .tint(.yellow)
                    .foregroundStyle(.black)
                    .accessibilityLabel("Send reply")
                    .disabled(replyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()
            .background(.bar)
        }
    }

    private var keypadPane: some View {
        ScrollView {
            VStack(spacing: 18) {
                Text("Keypad")
                    .font(.largeTitle.bold())
                    .accessibilityAddTraits(.isHeader)

                TextField("Email, username, or keypad entry", text: $callRecipient)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.emailAddress)
                    .multilineTextAlignment(.center)
                    .font(.title3.monospaced())
                    .padding()
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))

                Text(keypadDigits.isEmpty ? "Enter digits" : keypadDigits)
                    .font(.title.monospacedDigit())
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel(keypadDigits.isEmpty ? "No keypad digits entered" : "Keypad entry \(keypadDigits)")

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 18), count: 3), spacing: 18) {
                    ForEach(["1","2","3","4","5","6","7","8","9","*","0","#"], id: \.self) { key in
                        Button {
                            keypadDigits.append(key)
                            callRecipient = keypadDigits
                            AppHaptics.light()
                        } label: {
                            Text(key)
                                .font(.title.bold())
                                .frame(width: 72, height: 72)
                                .background(Color.primary.opacity(0.08), in: Circle())
                        }
                        .accessibilityLabel("Key \(key)")
                    }
                }
                .padding(.horizontal, 24)

                HStack(spacing: 28) {
                    Button {
                        if !keypadDigits.isEmpty {
                            keypadDigits.removeLast()
                            callRecipient = keypadDigits
                        }
                    } label: {
                        Image(systemName: "delete.left.fill").font(.title2)
                    }
                    .accessibilityLabel("Delete last digit")

                    Button {
                        ensureMicrophone {
                            Task { await communications.startCall(recipient: callRecipient, video: false) }
                        }
                    } label: {
                        Image(systemName: "phone.fill")
                            .font(.title)
                            .foregroundStyle(.white)
                            .frame(width: 76, height: 76)
                            .background(Color.green, in: Circle())
                    }
                    .accessibilityLabel("Call")
                    .disabled(callRecipient.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || communications.isInCall)

                    Button {
                        keypadDigits = ""
                        callRecipient = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill").font(.title2)
                    }
                    .accessibilityLabel("Clear keypad")
                }

                Text("For registered Blindbandit users, calling by exact email address or username is supported. The keypad is also available during calls for familiar phone-style controls.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .padding()
        }
    }

    private func callControl(icon: String, label: String, destructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.title2)
                    .frame(width: 58, height: 58)
                    .background(destructive ? Color.red : Color.primary.opacity(0.08), in: Circle())
                    .foregroundStyle(destructive ? .white : .primary)
                Text(label).font(.caption)
            }
        }
        .frame(minWidth: 72, minHeight: 72)
        .accessibilityLabel(label)
    }

    private func ensureMicrophone(_ action: @escaping () -> Void) {
        if privacy.microphone == .denied || privacy.microphone == .restricted {
            communications.statusMessage = "Microphone permission is required for voice calls. Enable it in iOS Settings."
            AppHaptics.warning()
            return
        }
        if privacy.microphone == .notDetermined { privacy.requestMicrophone() }
        action()
    }

    private func ensureCameraAndMicrophone(_ action: @escaping () -> Void) {
        if privacy.camera == .denied || privacy.microphone == .denied {
            communications.statusMessage = "Camera and microphone permissions are required for video calls."
            AppHaptics.warning()
            return
        }
        if privacy.camera == .notDetermined { privacy.requestCamera() }
        ensureMicrophone(action)
    }
}
