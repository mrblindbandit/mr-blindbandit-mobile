import SwiftUI
import LiveKit

struct TestProfileOnboardingView: View {
    @EnvironmentObject private var profile: TestProfileStore
    @EnvironmentObject private var communications: LiveKitCommunicationManager

    @State private var username = ""
    @State private var phoneNumber = ""
    @State private var tokenServerID = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 14) {
                        BrandMark(size: 82)
                        Text("Set Up Calling")
                            .font(.largeTitle.bold())
                            .accessibilityAddTraits(.isHeader)
                        Text("Create a lightweight tester identity for native calls and messages.")
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }

                Section("Test Identity") {
                    TextField("Username", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityHint("This is the name other testers will see.")

                    TextField("Phone number", text: $phoneNumber)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                        .accessibilityHint("No SMS confirmation is used in this development build.")

                    Text("The phone number is an unverified development routing ID. It is not used for cellular calling, authentication, or account recovery.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("LiveKit Development") {
                    SecureField("Development token server ID", text: $tokenServerID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Text("Paste the Development Token Server ID from your LiveKit Cloud project. This is for testing only and is not your LiveKit API secret.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button("Continue to Mr. Blind Bandit") {
                        AppHaptics.success()
                        profile.save(username: username,
                                     phoneNumber: phoneNumber,
                                     tokenServerID: tokenServerID)
                        communications.attach(profile: profile)
                        communications.startInbox()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                              TestIdentity.routingKey(for: phoneNumber).isEmpty)
                }
            }
            .navigationTitle("Welcome")
            .onAppear {
                username = profile.username
                phoneNumber = profile.phoneNumber
                tokenServerID = profile.liveKitDevelopmentTokenServerID
            }
        }
    }
}

struct CallingHomeView: View {
    @EnvironmentObject private var profile: TestProfileStore
    @EnvironmentObject private var communications: LiveKitCommunicationManager
    @State private var targetPhone = ""

    private let rows = [
        [("1", ""), ("2", "ABC"), ("3", "DEF")],
        [("4", "GHI"), ("5", "JKL"), ("6", "MNO")],
        [("7", "PQRS"), ("8", "TUV"), ("9", "WXYZ")],
        [("*", ""), ("0", "+"), ("#", "")]
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 6) {
                    Text("Phone")
                        .font(.largeTitle.bold())
                        .accessibilityAddTraits(.isHeader)
                    Text(communications.inboxStatus)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(communications.inboxStatus.contains("Ready") ? Color.green : Color(uiColor: .secondaryLabel))
                    Text("Your test number: \(profile.normalizedPhone)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                TextField("Enter tester phone number", text: $targetPhone)
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
                    .font(.title2.monospacedDigit())
                    .multilineTextAlignment(.center)
                    .padding()
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .accessibilityHint("Enter the phone number configured on another Mr. Blind Bandit test device.")

                VStack(spacing: 12) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        HStack(spacing: 18) {
                            ForEach(Array(row.enumerated()), id: \.offset) { _, key in
                                keypadButton(digit: key.0, letters: key.1)
                            }
                        }
                    }
                }
                .accessibilityElement(children: .contain)

                HStack(spacing: 16) {
                    Button {
                        AppHaptics.light()
                        guard !targetPhone.isEmpty else { return }
                        targetPhone.removeLast()
                    } label: {
                        Label("Delete", systemImage: "delete.left.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        AppHaptics.warning()
                        targetPhone = ""
                    } label: {
                        Text("Clear")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }

                HStack(spacing: 16) {
                    Button {
                        communications.startCall(to: targetPhone, video: false)
                    } label: {
                        Label("Voice Call", systemImage: "phone.fill")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .disabled(TestIdentity.routingKey(for: targetPhone).isEmpty)

                    Button {
                        communications.startCall(to: targetPhone, video: true)
                    } label: {
                        Label("Video Call", systemImage: "video.fill")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(TestIdentity.routingKey(for: targetPhone).isEmpty)
                }

                if !communications.lastError.isEmpty {
                    Label(communications.lastError, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityElement(children: .combine)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Label("Development calling", systemImage: "hammer.fill")
                        .font(.headline)
                    Text("For this first test build, both phones must use the same LiveKit Cloud development token server and the receiving app must be running. A production directory, PushKit wake-up, verified identities, and server-issued tokens come next.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
            }
            .padding()
        }
        .refreshable { communications.restartInbox() }
        .navigationTitle("Phone")
    }

    @ViewBuilder
    private func keypadButton(digit: String, letters: String) -> some View {
        Button {
            AppHaptics.keypad()
            if digit == "0", !targetPhone.isEmpty {
                targetPhone.append("0")
            } else {
                targetPhone.append(digit)
            }
        } label: {
            VStack(spacing: 1) {
                Text(digit)
                    .font(.title.bold())
                if !letters.isEmpty {
                    Text(letters)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 74, height: 58)
            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(letters.isEmpty ? digit : "\(digit), \(letters)")
        .accessibilityHint("Adds \(digit) to the phone number")
    }
}

struct MessagesHomeView: View {
    @EnvironmentObject private var communications: LiveKitCommunicationManager
    @State private var targetPhone = ""
    @State private var draft = ""

    private var conversation: [TestMessage] {
        communications.conversation(with: targetPhone)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("Tester phone number", text: $targetPhone)
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
                if !targetPhone.isEmpty {
                    Button("Clear") {
                        AppHaptics.light()
                        targetPhone = ""
                    }
                }
            }
            .padding()
            .background(Color(uiColor: .secondarySystemBackground))

            if TestIdentity.routingKey(for: targetPhone).isEmpty {
                ContentUnavailableView("Choose a tester",
                                       systemImage: "message.fill",
                                       description: Text("Enter the other tester's phone number to send realtime test messages."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(conversation) { message in
                                MessageBubble(message: message)
                                    .id(message.id)
                            }
                        }
                        .padding()
                    }
                    .onChange(of: communications.messages.count) { _, _ in
                        if let id = conversation.last?.id {
                            withAnimation { proxy.scrollTo(id, anchor: .bottom) }
                        }
                    }
                }

                HStack(alignment: .bottom, spacing: 10) {
                    TextField("Message", text: $draft, axis: .vertical)
                        .lineLimit(1...5)
                        .textFieldStyle(.roundedBorder)
                    Button {
                        let body = draft
                        guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                        communications.sendMessage(to: targetPhone, body: body)
                        draft = ""
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title)
                    }
                    .accessibilityLabel("Send message")
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding()
            }
        }
        .navigationTitle("Messages")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Clear local test messages", role: .destructive) {
                        communications.clearMessages()
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("Message options")
            }
        }
    }
}

struct MessageBubble: View {
    let message: TestMessage

    var body: some View {
        HStack {
            if message.isIncoming {
                bubble
                Spacer(minLength: 44)
            } else {
                Spacer(minLength: 44)
                bubble
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(message.isIncoming ? "Message from \(message.senderName)" : "You said"): \(message.body)")
    }

    private var bubble: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(message.body)
            Text(message.sentAt, style: .time)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(message.isIncoming ? Color(uiColor: .secondarySystemBackground) : Color.accentColor.opacity(0.18),
                    in: RoundedRectangle(cornerRadius: 16))
    }
}

struct CallScreen: View {
    @EnvironmentObject private var communications: LiveKitCommunicationManager
    let callID: UUID

    private var call: CallSession? {
        guard communications.currentCall?.id == callID else { return nil }
        return communications.currentCall
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if call?.isVideo == true, let track = communications.remoteVideoTrack {
                LiveKitVideoTrackView(track: track)
                    .ignoresSafeArea()
                    .accessibilityHidden(true)
            }

            VStack(spacing: 24) {
                Spacer()

                VStack(spacing: 8) {
                    BrandMark(size: 80)
                    Text(call?.remoteUsername ?? "Call")
                        .font(.largeTitle.bold())
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                    Text(callStatus)
                        .foregroundStyle(.white.opacity(0.75))
                    if let phone = call?.remotePhone {
                        Text(phone)
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.white.opacity(0.65))
                    }
                }
                .accessibilityElement(children: .combine)

                Spacer()

                if let call {
                    controls(for: call)
                }
            }
            .padding(24)

            if call?.isVideo == true, let local = communications.localVideoTrack {
                VStack {
                    HStack {
                        Spacer()
                        LiveKitVideoTrackView(track: local)
                            .frame(width: 115, height: 165)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.35)))
                            .accessibilityLabel("Your camera preview")
                    }
                    Spacer()
                }
                .padding()
            }
        }
        .interactiveDismissDisabled()
    }

    private var callStatus: String {
        guard let call else { return "Ending call" }
        switch call.phase {
        case .ringing:
            return call.direction == .incoming ? (call.isVideo ? "Incoming video call" : "Incoming voice call") : "Calling…"
        case .connecting: return "Connecting…"
        case .active: return call.isVideo ? "Video call" : "Voice call"
        }
    }

    @ViewBuilder
    private func controls(for call: CallSession) -> some View {
        if call.phase == .ringing, call.direction == .incoming {
            HStack(spacing: 46) {
                CallActionButton(title: "Decline", systemImage: "phone.down.fill", tint: .red) {
                    communications.requestEnd()
                }
                CallActionButton(title: "Accept", systemImage: call.isVideo ? "video.fill" : "phone.fill", tint: .green) {
                    communications.requestAnswer()
                }
            }
        } else if call.phase == .ringing, call.direction == .outgoing {
            CallActionButton(title: "Cancel", systemImage: "phone.down.fill", tint: .red) {
                communications.requestEnd()
            }
        } else {
            HStack(spacing: 26) {
                CallActionButton(title: communications.microphoneMuted ? "Unmute" : "Mute",
                                 systemImage: communications.microphoneMuted ? "mic.slash.fill" : "mic.fill",
                                 tint: .gray) {
                    communications.toggleMute()
                }
                CallActionButton(title: communications.speakerOn ? "Speaker On" : "Speaker",
                                 systemImage: communications.speakerOn ? "speaker.wave.3.fill" : "speaker.fill",
                                 tint: .gray) {
                    communications.toggleSpeaker()
                }
                if call.isVideo {
                    CallActionButton(title: communications.cameraEnabled ? "Camera On" : "Camera Off",
                                     systemImage: communications.cameraEnabled ? "video.fill" : "video.slash.fill",
                                     tint: .gray) {
                        communications.toggleCamera()
                    }
                }
            }

            CallActionButton(title: "End", systemImage: "phone.down.fill", tint: .red) {
                communications.requestEnd()
            }
        }
    }
}

struct CallActionButton: View {
    let title: String
    let systemImage: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button {
            AppHaptics.medium()
            action()
        } label: {
            VStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.title2.bold())
                    .frame(width: 62, height: 62)
                    .background(tint, in: Circle())
                    .foregroundStyle(.white)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

struct LiveKitVideoTrackView: UIViewRepresentable {
    let track: VideoTrack

    func makeUIView(context: Context) -> VideoView {
        let view = VideoView()
        view.track = track
        return view
    }

    func updateUIView(_ uiView: VideoView, context: Context) {
        uiView.track = track
    }
}

struct MoreHubView: View {
    var body: some View {
        List {
            Section("Communications") {
                NavigationLink {
                    CommunicationSettingsView()
                } label: {
                    Label("Communications Settings", systemImage: "phone.badge.gearshape")
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
            }

            Section("Mr. Blind Bandit") {
                NavigationLink { ProfessionalHome() } label: {
                    Label("Home", systemImage: "house.fill")
                }
                NavigationLink { Settings() } label: {
                    Label("App Settings", systemImage: "gearshape.fill")
                }
            }
        }
        .navigationTitle("More")
    }
}

struct CommunicationSettingsView: View {
    @EnvironmentObject private var profile: TestProfileStore
    @EnvironmentObject private var communications: LiveKitCommunicationManager

    @AppStorage("messageAlertMode") private var messageAlertMode = "sound"
    @State private var username = ""
    @State private var phoneNumber = ""
    @State private var tokenServerID = ""

    var body: some View {
        Form {
            Section("Test Identity") {
                TextField("Username", text: $username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("Phone number", text: $phoneNumber)
                    .keyboardType(.phonePad)
                Text("Phone numbers are unverified routing identifiers in this development build. Changing yours reconnects your personal LiveKit test inbox.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Button("Save & Reconnect") {
                    profile.save(username: username,
                                 phoneNumber: phoneNumber,
                                 tokenServerID: tokenServerID)
                    communications.attach(profile: profile)
                    communications.restartInbox()
                    AppHaptics.success()
                }
                .disabled(username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                          TestIdentity.routingKey(for: phoneNumber).isEmpty)
            }

            Section("LiveKit Development") {
                SecureField("Development token server ID", text: $tokenServerID)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                LabeledContent("Status", value: communications.inboxStatus)
                if !communications.lastError.isEmpty {
                    Text(communications.lastError)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Text("Development token servers are intentionally insecure and must be replaced with a server-issued token endpoint before production release.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Call Sounds") {
                LabeledContent("Incoming ringtone", value: "iOS System Default")
                Text("Apple does not let third-party apps browse your personal iPhone ringtone library. CallKit uses the native system ringtone now; custom Mr. Blind Bandit tones can be bundled with the app later.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Message Alerts") {
                Picker("Message alert", selection: $messageAlertMode) {
                    Text("Sound & haptic").tag("sound")
                    Text("Haptic only").tag("haptic")
                    Text("Silent").tag("silent")
                }
                .onChange(of: messageAlertMode) { _, _ in AppHaptics.selection() }
            }
        }
        .navigationTitle("Communications")
        .onAppear {
            username = profile.username
            phoneNumber = profile.phoneNumber
            tokenServerID = profile.liveKitDevelopmentTokenServerID
        }
    }
}
