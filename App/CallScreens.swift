import AVKit
import LiveKit
import SwiftUI

// MARK: - Container (incoming or active, shown over every tab)

struct CallContainerScreen: View {
    @EnvironmentObject private var communications: ProductionCommunicationsService

    var body: some View {
        Group {
            if let call = communications.incomingCall, !communications.isInCall {
                IncomingCallScreen(call: call)
            } else {
                ActiveCallScreen()
            }
        }
        .interactiveDismissDisabled()
    }
}

enum MagicTapSetting {
    static let key = "calls.magicTapEnds"
}

// MARK: - Incoming

struct IncomingCallScreen: View {
    let call: BlindbanditIncomingCall
    @EnvironmentObject private var communications: ProductionCommunicationsService
    @EnvironmentObject private var privacy: PrivacyPermissions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            ZStack {
                Circle().fill(Brand.gold.opacity(0.25)).frame(width: 170, height: 170)
                    .scaleEffect(pulse && !reduceMotion ? 1.12 : 1)
                if call.group_id != nil {
                    Image(systemName: "person.3.fill")
                        .font(.system(size: 92)).foregroundStyle(Brand.gold)
                } else {
                    ProfileAvatar(urlString: call.from_avatar_url, displayName: call.from_name, size: 120, decorative: true)
                }
            }
            .accessibilityHidden(true)
            VStack(spacing: 8) {
                Text(call.callerLabel).font(.largeTitle.bold()).multilineTextAlignment(.center)
                if !call.from_handle.isEmpty, call.from_name != "@\(call.from_handle)" {
                    Text("@\(call.from_handle)").foregroundStyle(.secondary)
                }
                Text("Incoming \(call.isVideo ? "video" : "voice") call\(call.group_id != nil ? " · group" : "")")
                    .font(.title3).foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Spacer()
            HStack(spacing: 48) {
                bigButton("Decline", icon: "phone.down.fill", color: .red) { communications.declineIncoming() }
                if call.isVideo {
                    bigButton("Answer with voice only", icon: "phone.fill", color: .green.opacity(0.8)) { answer(video: false) }
                }
                bigButton(call.isVideo ? "Answer with video" : "Answer", icon: call.isVideo ? "video.fill" : "phone.fill", color: .green) { answer(video: call.isVideo) }
            }
            .padding(.bottom, 40)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
        .accessibilityAction(.magicTap) { answer(video: call.isVideo) }
        .accessibilityAction(named: "Answer") { answer(video: call.isVideo) }
        .accessibilityAction(named: "Decline") { communications.declineIncoming() }
        .onAppear {
            let announceName = UserDefaults.standard.object(forKey: SettingsKey.announceCallerName) as? Bool ?? true
            let who = announceName ? call.callerLabel : "someone"
            UIAccessibility.post(notification: .screenChanged, argument: "Incoming call from \(who). Two-finger double tap to answer.")
            if !reduceMotion { withAnimation(.easeInOut(duration: 0.9).repeatForever()) { pulse = true } }
        }
    }

    private func answer(video: Bool) {
        if !video { UserDefaults.standard.set(true, forKey: "callkit.answerVoiceOnly") }
        Task {
            guard await CommsPermissions.microphone(privacy, communications) else { return }
            if video { _ = await CommsPermissions.camera(privacy, communications) }
            communications.answerIncoming()
        }
    }

    private func bigButton(_ label: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon).font(.title).foregroundStyle(.white)
                    .frame(width: 76, height: 76).background(color, in: Circle())
                Text(label).font(.caption).multilineTextAlignment(.center).frame(width: 90)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Active call

struct ActiveCallScreen: View {
    @EnvironmentObject private var communications: ProductionCommunicationsService
    @EnvironmentObject private var privacy: PrivacyPermissions
    @EnvironmentObject private var router: TabRouter
    @AppStorage(MagicTapSetting.key) private var magicTapEnds = true
    @State private var pinnedID: String?
    @State private var showChat = false
    @State private var showSafety = false
    @State private var showAdd = false

    private var gridItems: [CallParticipantInfo] {
        var list = communications.participants
        if let pinnedID, let i = list.firstIndex(where: { $0.id == pinnedID }) { list.insert(list.remove(at: i), at: 0) }
        return list
    }

    var body: some View {
        VStack(spacing: 12) {
            header
            if communications.participants.count <= 1 && !communications.isVideoCall {
                Spacer()
                if communications.callGroupID == nil {
                    ProfileAvatar(
                        urlString: communications.incomingCall?.from_avatar_url
                            ?? communications.conversations.first(where: { $0.other?.handle.lowercased() == String(communications.callPeerName.dropFirst()).lowercased() })?.other?.avatar_url,
                        displayName: communications.callPeerName.isEmpty ? "Call" : communications.callPeerName,
                        size: 120,
                        decorative: true
                    )
                } else {
                    Image(systemName: "person.3.fill")
                        .font(.system(size: 96)).foregroundStyle(Brand.gold).accessibilityHidden(true)
                }
                Spacer()
            } else {
                grid
            }
            controls
        }
        .padding()
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
        .accessibilityAction(.magicTap) {
            if magicTapEnds { communications.endCall() } else { communications.toggleMic() }
        }
        .accessibilityActions { callActions }
        .sheet(isPresented: $showChat) { InCallChatSheet() }
        .sheet(isPresented: $showAdd) { AddToCallSheet() }
        .sheet(isPresented: $showSafety) {
            NavigationStack { SafetyNumberView(handle: String(communications.callPeerName.dropFirst())) }
        }
    }

    private var header: some View {
        VStack(spacing: 4) {
            Text(communications.callPeerName.isEmpty ? "Call" : communications.callPeerName).font(.title2.bold())
            if !communications.callEncryptionLabel.isEmpty {
                Label(communications.callEncryptionLabel, systemImage: communications.callEncrypted ? "lock.fill" : "lock.open")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(communications.callEncrypted ? Color.green : Color.orange)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(communications.callEncryptionLabel)
                    .accessibilityIdentifier("callEncryptionStatus")
                if communications.callGroupID == nil, communications.callPeerName.hasPrefix("@") {
                    Button("Verify security number") { showSafety = true }
                        .font(.footnote)
                        .accessibilityHint("Opens the security number for this person.")
                }
            }
            HStack(spacing: 8) {
                Text(communications.isOnHold ? "On hold" : communications.isRinging ? "Ringing…" : communications.callTimeLabel)
                    .monospacedDigit()
                QualityBadge(quality: communications.localQuality)
                if communications.callGroupID != nil || communications.participants.count > 2 {
                    Text("\(communications.participants.count) in call")
                }
            }
            .font(.subheadline).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var grid: some View {
        let items = gridItems
        let columns = items.count <= 2 ? [GridItem(.flexible())] : [GridItem(.flexible()), GridItem(.flexible())]
        return ScrollView {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(items) { p in
                    ParticipantTile(info: p, isActiveSpeaker: p.id == communications.activeSpeakerID,
                                    pinned: p.id == pinnedID, locallyMuted: communications.locallyMuted.contains(p.id))
                        .frame(height: items.count <= 2 ? 260 : 190)
                        .accessibilityActions { participantActions(p) }
                        .contextMenu { participantActions(p) }
                }
            }
        }
    }

    @ViewBuilder
    private func participantActions(_ p: CallParticipantInfo) -> some View {
        Button { pinnedID = pinnedID == p.id ? nil : p.id
            UIAccessibility.post(notification: .announcement, argument: pinnedID == nil ? "Unpinned" : "Pinned \(p.name)")
        } label: { Label(pinnedID == p.id ? "Unpin video" : "Pin video", systemImage: "pin") }
        if !p.isLocal {
            Button { communications.toggleLocalMute(participantID: p.id) } label: {
                Label(communications.locallyMuted.contains(p.id) ? "Unmute for me" : "Mute for me", systemImage: "speaker.slash")
            }
            Button {
                router.pendingThread = TabRouter.ThreadTarget(id: nil, handle: BlindbanditHandle.normalize(p.id))
                router.selection = .messages
            } label: { Label("Message \(p.name)", systemImage: "message") }
            Button(role: .destructive) { Task { await communications.removeFromCall(participantID: p.id) } } label: {
                Label("Remove from call", systemImage: "person.fill.xmark")
            }
        }
    }

    @ViewBuilder
    private var callActions: some View {
        Button(communications.micEnabled ? "Mute" : "Unmute") { communications.toggleMic() }
        Button(communications.speakerOn ? "Speaker off" : "Speaker on") { communications.toggleSpeaker() }
        if communications.isVideoCall {
            Button("Flip camera") { communications.switchCamera() }
            Button("Switch to voice only") { communications.downgradeToVoice() }
        } else {
            Button("Switch to video") { upgrade() }
        }
        Button(communications.screenSharing ? "Stop sharing screen" : "Share screen") { communications.toggleScreenShare() }
        Button(communications.captionsOn ? "Turn off live captions" : "Turn on live captions") { communications.toggleCaptions() }
        if let id = communications.activeCallID {
            Button("Share this call over SharePlay") { Task { let s = await SharePlayCalls.share(callID: id, title: "Mr. BlindBandit call"); UIAccessibility.post(notification: .announcement, argument: s) } }
        }
        Button("Add people") { showAdd = true }
        Button(communications.handRaised ? "Lower hand" : "Raise hand") { communications.toggleHand() }
        Button("Open call chat") { showChat = true }
        Button(communications.isOnHold ? "Resume" : "Hold") { communications.setHold(!communications.isOnHold) }
        Button("End call") { communications.endCall() }
    }

    private func upgrade() {
        Task {
            guard await CommsPermissions.camera(privacy, communications) else { return }
            communications.upgradeToVideo()
        }
    }

    @State private var showKeypad = false

    private var controls: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                control(communications.micEnabled ? "mic.fill" : "mic.slash.fill", communications.micEnabled ? "Mute" : "Unmute", selected: !communications.micEnabled) { communications.toggleMic() }
                control("speaker.wave.3.fill", communications.speakerOn ? "Speaker on" : "Speaker", selected: communications.speakerOn) { communications.toggleSpeaker() }
                // RoutePicker is the Bluetooth / AirPods / speaker chooser — labeled clearly for VO.
                RoutePicker().frame(width: 64, height: 64)
                    .accessibilityLabel("Bluetooth and audio route")
                    .accessibilityHint("Choose speaker, Bluetooth headset, or AirPods")
                if communications.isVideoCall {
                    control(communications.cameraEnabled ? "video.fill" : "video.slash.fill", communications.cameraEnabled ? "Camera off" : "Camera on", selected: !communications.cameraEnabled) { communications.toggleCamera() }
                    control("arrow.triangle.2.circlepath.camera", communications.usingFrontCamera ? "Back camera" : "Front camera") { communications.switchCamera() }
                } else {
                    control("video.badge.plus", "Camera") { upgrade() }
                }
            }
            HStack(spacing: 10) {
                control(communications.screenSharing ? "rectangle.on.rectangle.slash" : "rectangle.on.rectangle", communications.screenSharing ? "Stop share" : "Screen share", selected: communications.screenSharing) { communications.toggleScreenShare() }
                control("person.badge.plus", "Add person") { showAdd = true }
                control("circle.grid.3x3.fill", "Keypad") { showKeypad = true }
                control("bubble.left.and.bubble.right.fill", communications.unreadCallChat > 0 ? "Chat, \(communications.unreadCallChat) new" : "Chat") { showChat = true }
                control(communications.captionsOn ? "captions.bubble.fill" : "captions.bubble", communications.captionsOn ? "Captions on" : "Captions", selected: communications.captionsOn) { communications.toggleCaptions() }
            }
            HStack(spacing: 10) {
                control(communications.handRaised ? "hand.raised.fill" : "hand.raised", communications.handRaised ? "Lower hand" : "Raise hand", selected: communications.handRaised) { communications.toggleHand() }
                control(communications.isOnHold ? "play.fill" : "pause.fill", communications.isOnHold ? "Resume" : "Hold", selected: communications.isOnHold) { communications.setHold(!communications.isOnHold) }
                if communications.isVideoCall {
                    control("phone.fill", "Voice only") { communications.downgradeToVoice() }
                }
                control("phone.down.fill", communications.isRinging ? "Cancel" : "End call", destructive: true) { communications.endCall() }
            }
        }
        .padding(.bottom, 8)
        .sheet(isPresented: $showKeypad) { InCallKeypadSheet() }
    }

    private func control(_ icon: String, _ label: String, selected: Bool = false, destructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.title2)
                    .frame(width: 64, height: 64)
                    .background(destructive ? Color.red : (selected ? Color.primary : Color.primary.opacity(0.12)), in: Circle())
                    .foregroundStyle(destructive ? Color.white : (selected ? Color(uiColor: .systemBackground) : Color.primary))
                Text(label).font(.caption2.weight(.semibold)).lineLimit(2).multilineTextAlignment(.center)
            }
            .frame(minWidth: 68, minHeight: 88)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint(destructive ? "Double tap to end the call" : "Double tap to activate")
    }
}

/// Soft in-call dial pad — announces digits for VO; useful for IVR menus even without carrier DTMF.
struct InCallKeypadSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var digits = ""
    private let keys = [["1","2","3"],["4","5","6"],["7","8","9"],["*","0","#"]]
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text(digits.isEmpty ? " " : digits)
                    .font(.largeTitle.monospacedDigit())
                    .accessibilityLabel(digits.isEmpty ? "No digits entered" : "Digits \(digits.map(String.init).joined(separator: " "))")
                    .accessibilityAddTraits(.updatesFrequently)
                ForEach(keys, id: \.self) { row in
                    HStack(spacing: 20) {
                        ForEach(row, id: \.self) { k in
                            Button {
                                digits.append(k)
                                UIAccessibility.post(notification: .announcement, argument: k == "*" ? "Star" : (k == "#" ? "Pound" : k))
                                AppHaptics.light()
                            } label: {
                                Text(k).font(.title.bold()).frame(width: 72, height: 72)
                                    .background(Color.primary.opacity(0.1), in: Circle())
                            }
                            .accessibilityLabel(k == "*" ? "Star" : (k == "#" ? "Pound" : k))
                        }
                    }
                }
                Spacer()
            }
            .padding()
            .navigationTitle("Keypad")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}

struct QualityBadge: View {
    let quality: ConnectionQuality
    var body: some View {
        let bars: Int = { switch quality { case .excellent: return 3; case .good: return 2; case .poor: return 1; default: return 0 } }()
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<3) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(i < bars ? (bars == 1 ? Color.orange : Color.green) : Color.secondary.opacity(0.3))
                    .frame(width: 4, height: CGFloat(5 + i * 4))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(CallParticipantInfo.label(for: quality))
    }
}

struct ParticipantTile: View {
    let info: CallParticipantInfo
    let isActiveSpeaker: Bool
    let pinned: Bool
    let locallyMuted: Bool

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let screen = info.screenTrack {
                    SwiftUIVideoView(screen, layoutMode: .fit)
                } else if let video = info.videoTrack, info.cameraOn {
                    SwiftUIVideoView(video, layoutMode: .fill, mirrorMode: info.isLocal ? .mirror : .off)
                } else {
                    ZStack {
                        Color.secondary.opacity(0.18)
                        Text(initials).font(.largeTitle.bold()).foregroundStyle(Brand.gold)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            HStack(spacing: 6) {
                if !info.micOn || locallyMuted { Image(systemName: "mic.slash.fill").foregroundStyle(.red) }
                if info.handRaised { Image(systemName: "hand.raised.fill").foregroundStyle(.yellow) }
                if pinned { Image(systemName: "pin.fill") }
                Text(info.isLocal ? "You" : info.name).lineLimit(1)
                QualityBadge(quality: info.quality)
            }
            .font(.caption.bold())
            .foregroundStyle(.white)
            .padding(6)
            .background(.black.opacity(0.55), in: Capsule())
            .padding(8)
        }
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(isActiveSpeaker || info.isSpeaking ? Brand.gold : .clear, lineWidth: 4))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(info.accessibilitySummary + (locallyMuted ? ", muted for you" : "") + (pinned ? ", pinned" : ""))
        .accessibilityAddTraits(isActiveSpeaker ? .updatesFrequently : [])
    }

    private var initials: String {
        let words = info.name.replacingOccurrences(of: "@", with: "").split(separator: " ")
        return String(words.prefix(2).compactMap { $0.first }).uppercased()
    }
}

/// System audio-route picker (speaker, AirPods, Bluetooth, CarPlay).
struct RoutePicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.prioritizesVideoDevices = false
        view.tintColor = .label
        return view
    }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}

struct InCallChatSheet: View {
    @EnvironmentObject private var communications: ProductionCommunicationsService
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""

    var body: some View {
        NavigationStack {
            VStack {
                List(communications.callChat) { m in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(m.sender).font(.caption.bold())
                        Text(m.text)
                        Text(m.date, style: .time).font(.caption2).foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
                .overlay { if communications.callChat.isEmpty { Text("No messages in this call yet.").foregroundStyle(.secondary) } }
                HStack {
                    TextField("Message everyone in the call", text: $draft).textFieldStyle(.roundedBorder)
                    Button("Send") { communications.sendCallChat(draft); draft = "" }
                        .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding()
            }
            .navigationTitle("Call chat")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
            .onAppear { communications.unreadCallChat = 0 }
        }
    }
}

struct AddToCallSheet: View {
    @EnvironmentObject private var communications: ProductionCommunicationsService
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [BlindbanditPerson] = []
    @State private var selected: Set<String> = []
    @State private var error = ""

    var body: some View {
        NavigationStack {
            List {
                if !error.isEmpty { Text(error).foregroundStyle(.secondary) }
                ForEach(results) { person in
                    Button {
                        if selected.contains(person.handle) { selected.remove(person.handle) } else { selected.insert(person.handle) }
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(person.display_name)
                                Text("@\(person.handle)").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if selected.contains(person.handle) { Image(systemName: "checkmark").accessibilityHidden(true) }
                        }
                    }
                    .accessibilityLabel("\(person.display_name), @\(person.handle)")
                    .accessibilityAddTraits(selected.contains(person.handle) ? .isSelected : [])
                }
            }
            .searchable(text: $query, prompt: "Search people")
            .task(id: query) { await search() }
            .navigationTitle("Add people")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ring \(selected.count)") {
                        Task { await communications.invite(handles: Array(selected)); dismiss() }
                    }
                    .disabled(selected.isEmpty)
                }
            }
        }
    }

    private func search() async {
        try? await Task.sleep(nanoseconds: 300_000_000)
        do {
            results = try await BlindbanditAPI.directory(query: query, cursor: nil).people
            error = results.isEmpty && !query.isEmpty ? "No one found." : ""
        } catch {
            self.error = error.localizedDescription
        }
    }
}
