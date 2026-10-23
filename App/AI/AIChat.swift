import Foundation
import SwiftUI
import EventKit
#if canImport(FoundationModels)
import FoundationModels
#endif

/// The permanent "AI" chat. Pinned at the top of Messages, can be cleared but never deleted. History is encrypted
/// on this iPhone and mirrored into an iCloud Keychain item (end-to-end encrypted by Apple, keyed to the Apple Account)
/// so it follows the user to a new iPhone.
@MainActor
final class AIChatStore: ObservableObject {
    static let shared = AIChatStore()
    struct Line: Identifiable, Codable, Equatable { var id = UUID().uuidString; var fromAI: Bool; var text: String; var at = Date().timeIntervalSince1970 }
    struct PendingSend: Identifiable, Equatable { let id = UUID(); let handle: String; let text: String }

    @Published private(set) var lines: [Line] = []
    @Published var pendingSends: [PendingSend] = []
    @Published var thinking = false
    private let account = "aichat.v1"

    init() { lines = Keychain.getCodable([Line].self, account) ?? [] }

    private func save() {
        // Keep the newest lines under ~48 KB so the synced keychain item stays small.
        var keep = lines
        while let d = try? JSONEncoder().encode(keep), d.count > 48_000, !keep.isEmpty { keep.removeFirst() }
        _ = Keychain.setCodable(keep, account, synced: true)
    }

    func append(_ l: Line) { lines.append(l); save() }
    func update(_ id: String, text: String) {
        if let i = lines.firstIndex(where: { $0.id == id }) { lines[i].text = text }
    }
    func commit() { save() }
    func clear() { lines = []; save(); UIAccessibility.post(notification: .announcement, argument: "AI chat cleared") }

    /// Local search corpus: every decrypted message cached on this device plus inbox previews.
    var corpus: [String] {
        LocalMessageStore.shared.snapshot.payloads.values.compactMap { p in
            guard let b = p.body, !b.isEmpty else { return nil }
            return b
        }
    }

    func ask(_ q: String) async {
        let question = q.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }
        append(Line(fromAI: false, text: question))
        thinking = true
        UIAccessibility.post(notification: .announcement, argument: "AI is thinking")
        let reply = Line(fromAI: true, text: "")
        lines.append(reply)
        let history = lines.dropLast().suffix(16).map { ($0.fromAI ? "AI: " : "Me: ") + $0.text }
        var final = ""
        #if canImport(FoundationModels)
        if #available(iOS 26, *), OnDeviceAI.isAvailable {
            let tools: [any Tool] = [SearchMyChatsTool(corpus: corpus), FindInChatTool(lines: history),
                                     DraftMessageTool(), ReminderTool(), TranslateTool()]
            let session = LanguageModelSession(tools: tools, instructions: OnDeviceAI.base +
                " You are the user's private on-device assistant. Use tools to search their chats, translate, set reminders, or draft a message to someone (the user confirms before anything is sent). Keep answers short.")
            do {
                for try await snap in session.streamResponse(to: "Conversation so far:\n" + history.joined(separator: "\n") + "\n\nMe: " + question) {
                    final = snap.content
                    update(reply.id, text: final)
                }
            } catch {
                if final.isEmpty { final = "I couldn't answer that on this device." }
            }
        }
        #endif
        if final.isEmpty {
            final = await AIAssistant.answer(.init(question: question, isPrivate: true),
                                             context: .init(chatName: "AI", lines: history, lastPhoto: nil)) { [weak self] p in self?.update(reply.id, text: p) }
        }
        update(reply.id, text: final)
        commit()
        thinking = false
        UIAccessibility.post(notification: .announcement, argument: "AI says: \(final)")
    }

    func confirmSend(_ p: PendingSend, using comms: ProductionCommunicationsService) async {
        pendingSends.removeAll { $0.id == p.id }
        if await comms.sendMessage(recipient: p.handle, body: p.text) != nil {
            append(Line(fromAI: true, text: "Sent to @\(p.handle): \(p.text)"))
        }
    }
}

#if canImport(FoundationModels)
@available(iOS 26, *)
struct SearchMyChatsTool: Tool {
    let name = "searchMyChats"
    let description = "Searches all of the user's decrypted chat messages stored on this iPhone for a word or phrase."
    let corpus: [String]
    @Generable struct Arguments { @Guide(description: "Word or phrase to search for") var query: String }
    func call(arguments: Arguments) async throws -> String {
        let hits = corpus.filter { $0.localizedCaseInsensitiveContains(arguments.query) }
        return hits.isEmpty ? "No messages found." : hits.suffix(10).joined(separator: "\n")
    }
}

@available(iOS 26, *)
struct DraftMessageTool: Tool {
    let name = "draftMessage"
    let description = "Prepares a message to send to someone by @handle. The user must confirm before it is sent."
    @Generable struct Arguments {
        @Guide(description: "Recipient Blindbandit username without @") var handle: String
        @Guide(description: "The message text") var text: String
    }
    func call(arguments: Arguments) async throws -> String {
        await MainActor.run {
            AIChatStore.shared.pendingSends.append(.init(handle: arguments.handle.replacingOccurrences(of: "@", with: ""), text: arguments.text))
        }
        return "Draft ready for @\(arguments.handle). Tell the user to confirm with the Send button."
    }
}

@available(iOS 26, *)
struct ReminderTool: Tool {
    let name = "setReminder"
    let description = "Creates a reminder in the Reminders app."
    @Generable struct Arguments {
        @Guide(description: "What to be reminded about") var title: String
        @Guide(description: "Minutes from now, 0 if no time") var minutesFromNow: Int
    }
    func call(arguments: Arguments) async throws -> String {
        let ok = await ReminderMaker.add(title: arguments.title, minutes: arguments.minutesFromNow)
        return ok ? "Reminder added." : "Reminders access wasn't allowed."
    }
}

@available(iOS 26, *)
struct TranslateTool: Tool {
    let name = "translate"
    let description = "Translates text into a language given as an ISO code like en, ceb, tl, es."
    @Generable struct Arguments {
        @Guide(description: "Text to translate") var text: String
        @Guide(description: "Target language ISO code") var target: String
    }
    func call(arguments: Arguments) async throws -> String {
        await Translator.shared.translateOutgoing(arguments.text, to: arguments.target) ?? arguments.text
    }
}
#endif

enum ReminderMaker {
    static func add(title: String, minutes: Int) async -> Bool {
        let store = EKEventStore()
        guard (try? await store.requestFullAccessToReminders()) == true, let cal = store.defaultCalendarForNewReminders() else { return false }
        let r = EKReminder(eventStore: store)
        r.title = title
        r.calendar = cal
        if minutes > 0 {
            let date = Date().addingTimeInterval(Double(minutes) * 60)
            r.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            r.addAlarm(EKAlarm(absoluteDate: date))
        }
        return (try? store.save(r, commit: true)) != nil
    }
}

struct AIChatView: View {
    @ObservedObject private var store = AIChatStore.shared
    @EnvironmentObject private var comms: ProductionCommunicationsService
    @StateObject private var dictation = LiveDictation()
    @State private var draft = ""
    @State private var confirmClear = false

    var body: some View {
        VStack(spacing: 0) {
            if !OnDeviceAI.isAvailable {
                Text(OnDeviceAI.unavailableReason).font(.callout).padding()
            }
            ScrollViewReader { proxy in
                List {
                    ForEach(store.lines) { line in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(line.fromAI ? "AI" : "You").font(.caption.bold())
                            Text(line.text.isEmpty ? "…" : line.text).textSelection(.enabled)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(line.fromAI ? "AI" : "You"): \(line.text)")
                        .accessibilityAction(named: "Read aloud") { NaturalReader.shared.speak(line.text) }
                        .accessibilityAction(named: "Copy") { UIPasteboard.general.string = line.text }
                        .id(line.id)
                    }
                    ForEach(store.pendingSends) { p in
                        VStack(alignment: .leading) {
                            Text("Send to @\(p.handle)?").font(.headline)
                            Text(p.text)
                            HStack {
                                Button("Send") { Task { await store.confirmSend(p, using: comms) } }.buttonStyle(.borderedProminent)
                                Button("Cancel", role: .cancel) { store.pendingSends.removeAll { $0.id == p.id } }
                            }
                        }
                        .accessibilityElement(children: .contain)
                    }
                    if store.thinking { Text("AI is thinking…").italic() }
                }
                .onChange(of: store.lines.count) { _ in if let l = store.lines.last { proxy.scrollTo(l.id) } }
            }
            HStack {
                Button { Task {
                    if dictation.isListening { dictation.stop(); draft = await OnDeviceAI.cleanDictation(dictation.text) }
                    else { await dictation.start() }
                } } label: { Image(systemName: dictation.isListening ? "stop.circle.fill" : "mic.circle") .font(.title2) }
                .accessibilityLabel(dictation.isListening ? "Stop dictation" : "Dictate")
                TextField("Ask anything. Stays on this iPhone.", text: $draft, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                Button { send() } label: { Image(systemName: "arrow.up.circle.fill").font(.title2) }
                    .accessibilityLabel("Ask AI")
                    .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty || store.thinking)
            }
            .padding()
        }
        .navigationTitle("AI")
        .toolbar {
            Menu {
                Button("Clear AI chat", role: .destructive) { confirmClear = true }
            } label: { Image(systemName: "ellipsis.circle") }.accessibilityLabel("AI chat options")
        }
        .confirmationDialog("Clear the AI chat history on all your devices? The AI chat itself stays.", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear history", role: .destructive) { store.clear() }
        }
        .accessibilityAction(.magicTap) { send() }
        .onChange(of: dictation.text) { t in if dictation.isListening { draft = t } }
    }

    private func send() {
        let q = draft
        draft = ""
        Task { await store.ask(q) }
    }
}

/// Row pinned at the top of the Messages list. It has no delete swipe action.
struct AIChatRow: View {
    @ObservedObject private var store = AIChatStore.shared
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles").font(.title2).frame(width: 44, height: 44)
                .background(Circle().fill(Color.accentColor.opacity(0.15)))
            VStack(alignment: .leading) {
                Text("AI").font(.headline)
                Text(store.lines.last?.text ?? "Your private on-device assistant").font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("AI, pinned, private on-device assistant. " + (store.lines.last.map { "Last: \($0.text)" } ?? ""))
    }
}
