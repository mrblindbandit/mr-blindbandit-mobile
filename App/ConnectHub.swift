import SwiftUI

/// Connect tab — voice calls, video calls, messaging, voice notes (LiveKit scaffolding).
struct ConnectHubView: View {
    @StateObject private var livekit = LiveKitService()
    @EnvironmentObject private var preferences: AppPreferences
    @EnvironmentObject private var privacy: PrivacyPermissions
    @State private var draft = ""
    @State private var selected: Segment = .calls

    enum Segment: String, CaseIterable { case calls = "Calls", chat = "Chat", voiceNotes = "Voice notes" }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Connect", selection: $selected) {
                ForEach(Segment.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding()
            .accessibilityLabel("Connect sections")

            switch selected {
            case .calls: callsPane
            case .chat: chatPane
            case .voiceNotes: voiceNotesPane
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
        .onAppear { AppHaptics.soft() }
    }

    private var callsPane: some View {
        ScrollView {
            VStack(spacing: 20) {
                ZStack {
                    RoundedRectangle(cornerRadius: 28)
                        .fill(LinearGradient(colors: [.black, Color(white: 0.16)], startPoint: .top, endPoint: .bottom))
                        .frame(height: 220)
                    VStack(spacing: 12) {
                        if livekit.isInCall {
                            SpinningBrandLogo(size: 88, reduceMotion: preferences.reduceAppMotion)
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
                            Text(livekit.isConfigured ? "Ready to connect via LiveKit" : "Configure LiveKit URL to go live")
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
                        ensureMicThen { Task { await livekit.connect(asVideo: false) } }
                    } label: {
                        Label("Voice call", systemImage: "phone.fill")
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.yellow)
                    .foregroundStyle(.black)
                    .disabled(livekit.isInCall)
                    .accessibilityHint("Starts a LiveKit voice call.")

                    Button {
                        AppHaptics.medium()
                        ensureMicThen {
                            if privacy.camera == .notDetermined { privacy.requestCamera() }
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
                        callControl(icon: livekit.micEnabled ? "mic.fill" : "mic.slash.fill", label: livekit.micEnabled ? "Mute" : "Unmute") {
                            livekit.toggleMic()
                        }
                        if livekit.isVideoCall {
                            callControl(icon: livekit.cameraEnabled ? "video.fill" : "video.slash.fill", label: livekit.cameraEnabled ? "Camera off" : "Camera on") {
                                livekit.toggleCamera()
                            }
                        }
                        callControl(icon: "phone.down.fill", label: "End call", destructive: true) {
                            livekit.disconnect()
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Room").font(.headline).accessibilityAddTraits(.isHeader)
                    LabeledContent("Name", value: livekit.roomName)
                    LabeledContent("State", value: livekit.connectionState.rawValue)
                    LabeledContent("Server", value: livekit.isConfigured ? "LiveKit Cloud" : "Not configured")
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
            }
            .padding()
        }
    }

    private var chatPane: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(livekit.messages.filter { !$0.isVoiceNote || true }) { message in
                            chatBubble(message)
                                .id(message.id)
                        }
                    }
                    .padding()
                }
                .onChange(of: livekit.messages.count) { _, _ in
                    if let last = livekit.messages.last {
                        withAnimation(preferences.reduceAppMotion ? nil : .easeOut) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            HStack(spacing: 10) {
                TextField("Message", text: $draft, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)
                    .accessibilityLabel("Message field")
                Button {
                    livekit.sendText(draft)
                    draft = ""
                } label: {
                    Image(systemName: "paperplane.fill")
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(.yellow)
                .foregroundStyle(.black)
                .accessibilityLabel("Send message")
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()
            .background(.bar)
        }
    }

    private var voiceNotesPane: some View {
        VStack(spacing: 18) {
            Text("Record a voice note and drop it into the studio chat.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                if livekit.isRecordingVoiceNote {
                    livekit.stopVoiceNoteAndSend()
                } else {
                    ensureMicThen { livekit.startVoiceNote() }
                }
            } label: {
                Label(
                    livekit.isRecordingVoiceNote ? "Stop & send voice note" : "Record voice note",
                    systemImage: livekit.isRecordingVoiceNote ? "stop.circle.fill" : "waveform.circle.fill"
                )
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
            }
            .buttonStyle(.borderedProminent)
            .tint(livekit.isRecordingVoiceNote ? .red : .yellow)
            .foregroundStyle(livekit.isRecordingVoiceNote ? .white : .black)
            .accessibilityHint(livekit.isRecordingVoiceNote ? "Stops recording and sends the note." : "Starts recording a voice note.")

            if livekit.isRecordingVoiceNote {
                WaveformLoader(reduceMotion: preferences.reduceAppMotion)
                Text("Recording…")
                    .font(.headline)
                    .accessibilityAddTraits(.updatesFrequently)
            }

            List {
                ForEach(livekit.messages.filter(\.isVoiceNote)) { note in
                    Button {
                        if let url = note.voiceNoteURL { livekit.playVoiceNote(url) }
                    } label: {
                        Label(note.body, systemImage: "play.circle.fill")
                    }
                    .accessibilityLabel("Play voice note from \(note.sender)")
                }
            }
            .listStyle(.plain)
        }
        .padding()
    }

    private func chatBubble(_ message: ChatMessage) -> some View {
        HStack {
            if message.isLocal { Spacer(minLength: 40) }
            VStack(alignment: message.isLocal ? .trailing : .leading, spacing: 4) {
                Text(message.sender)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                if message.isVoiceNote {
                    Label("Voice note — tap to play", systemImage: "waveform")
                        .padding(10)
                        .background(message.isLocal ? Color.yellow.opacity(0.25) : Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 14))
                        .onTapGesture {
                            if let url = message.voiceNoteURL { livekit.playVoiceNote(url) }
                        }
                } else {
                    Text(message.body)
                        .padding(10)
                        .background(message.isLocal ? Color.yellow.opacity(0.25) : Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 14))
                }
            }
            if !message.isLocal { Spacer(minLength: 40) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(message.sender): \(message.body)")
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

    private func ensureMicThen(_ action: @escaping () -> Void) {
        if privacy.microphone == .notDetermined {
            privacy.requestMicrophone()
        }
        action()
    }
}
