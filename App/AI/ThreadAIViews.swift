import SwiftUI

/// Banners above the composer: key change, scam warning, catch-up summary, @AI streaming and private answers, smart replies.
struct ThreadAIBanners: View {
    let handle: String
    let keyChanged: Bool
    let scamWarning: String?
    @Binding var catchUp: String?
    let aiPartial: String?
    let aiPrivate: [(q: String, a: String)]
    let smartReplies: [String]
    let useReply: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if keyChanged {
                NavigationLink { SafetyNumberView(handle: handle) } label: {
                    Label("Security number with @\(handle) changed. Verification was reset. Tap to verify.", systemImage: "exclamationmark.shield.fill")
                }
                .foregroundStyle(.orange)
            }
            if let w = scamWarning {
                Label("Be careful: \(w)", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
                    .accessibilityAddTraits(.isStaticText)
            }
            if let c = catchUp {
                HStack(alignment: .top) {
                    Text(c).font(.callout)
                    Spacer()
                    Button { catchUp = nil } label: { Image(systemName: "xmark.circle") }.accessibilityLabel("Dismiss summary")
                }
                .padding(8).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
            }
            ForEach(Array(aiPrivate.enumerated()), id: \.offset) { _, item in
                VStack(alignment: .leading) {
                    Text("AI, only you can see this").font(.caption.bold())
                    Text(item.a)
                }
                .padding(8).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
                .accessibilityElement(children: .combine)
            }
            if let p = aiPartial {
                Text(p).italic().accessibilityLabel("AI is answering: \(p)")
            }
            if !smartReplies.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(smartReplies, id: \.self) { r in
                            Button(r) { useReply(r) }.buttonStyle(.bordered)
                                .accessibilityLabel("Suggested reply: \(r)")
                        }
                    }
                }
            }
        }
        .padding(.horizontal)
    }
}

/// Mic (voice-first compose) + rewrite menu next to the composer.
struct ComposerAIMenu: View {
    @Binding var draft: String
    @ObservedObject var dictation: LiveDictation
    let enabled: Bool

    var body: some View {
        Menu {
            if AISettings.isOn(.voiceCompose) {
                Button(dictation.isListening ? "Stop dictation" : "Dictate") { Task {
                    if dictation.isListening {
                        dictation.stop()
                        draft = enabled ? await OnDeviceAI.cleanDictation(dictation.text) : dictation.text
                        NaturalReader.shared.speak(draft)
                    } else { await dictation.start() }
                } }
            }
            if enabled, AISettings.isOn(.rewrite), !draft.isEmpty {
                ForEach(OnDeviceAI.Tone.allCases, id: \.self) { tone in
                    Button(tone.rawValue) { Task {
                        if let r = await OnDeviceAI.rewrite(draft, tone: tone) { draft = r; UIAccessibility.post(notification: .announcement, argument: "Rewritten: \(r)") }
                        else { UIAccessibility.post(notification: .announcement, argument: OnDeviceAI.unavailableReason) }
                    } }
                }
            }
            if !draft.isEmpty { Button("Read my message back") { NaturalReader.shared.speak(draft) } }
        } label: {
            Image(systemName: dictation.isListening ? "mic.fill" : "sparkles").frame(width: Brand.minTouch, height: Brand.minTouch)
        }
        .accessibilityLabel(dictation.isListening ? "Dictating. Open to stop" : "Compose tools: dictate, rewrite, read back")
        .onChange(of: dictation.text) { _, t in if dictation.isListening { draft = t } }
    }
}

/// Sends scheduled messages when they come due (checked on the inbox poll timer while the app is open).
@MainActor
enum ScheduledSender {
    static func flushDue(_ comms: ProductionCommunicationsService) async {
        let now = Date().timeIntervalSince1970
        let due = LocalMessageStore.shared.snapshot.scheduled.filter { $0.sendAt <= now }
        guard !due.isEmpty else { return }
        LocalMessageStore.shared.mutate { s in s.scheduled.removeAll { $0.sendAt <= now } }
        for m in due {
            if let h = m.handle { _ = await comms.sendMessage(recipient: h, body: m.body) }
            else if let g = m.groupID { try? await BlindbanditAPI.sendGroupMessage(id: g, body: m.body) }
        }
    }
}
