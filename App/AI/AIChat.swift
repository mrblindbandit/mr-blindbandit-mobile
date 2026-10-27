import Foundation
import SwiftUI
import EventKit
import Contacts
import MapKit
import PhotosUI
#if canImport(FoundationModels)
import FoundationModels
#endif

/// The permanent "AI" chat. Pinned at the top of Messages, can be cleared but never deleted. History and long-term
/// memory are encrypted on this iPhone (Keychain) and mirrored into a synced iCloud Keychain item (end-to-end encrypted
/// by Apple) so they follow the user to a new iPhone.
@MainActor
final class AIChatStore: ObservableObject {
    static let shared = AIChatStore()
    struct Line: Identifiable, Codable, Equatable { var id = UUID().uuidString; var fromAI: Bool; var text: String; var at = Date().timeIntervalSince1970 }
    struct PendingSend: Identifiable, Equatable { let id = UUID(); let handle: String; let text: String }
    /// Long-term memory: short facts the user shared plus a rolling summary of older turns.
    struct Memory: Codable, Equatable { var facts: [String] = []; var summary = ""; var topics: [String] = []; var summarizedThrough = 0 }

    @Published private(set) var lines: [Line] = []
    @Published private(set) var memory = Memory()
    @Published var pendingSends: [PendingSend] = []
    @Published var thinking = false
    /// Set by "Ask the bigger AI" for the next question.
    var forceCloud = false
    @Published var lastPhoto: UIImage?
    private let account = "aichat.v1"
    private let memoryAccount = "aichat.memory.v1"
    #if canImport(FoundationModels)
    private var sessionBox: AnyObject?
    #endif

    init() {
        lines = Keychain.getCodable([Line].self, account) ?? []
        memory = Keychain.getCodable(Memory.self, memoryAccount) ?? Memory()
    }

    private func save() {
        var keep = lines
        while let d = try? JSONEncoder().encode(keep), d.count > 40_000, !keep.isEmpty { keep.removeFirst() }
        _ = Keychain.setCodable(keep, account, synced: true)
        _ = Keychain.setCodable(memory, memoryAccount, synced: true)
    }

    func append(_ l: Line) { lines.append(l); save() }
    /// Used by AIChatBackup.restore.
    func replaceAll(lines new: [Line], memory mem: Memory) { lines = new; memory = mem; resetSession(); save() }
    func update(_ id: String, text: String) { if let i = lines.firstIndex(where: { $0.id == id }) { lines[i].text = text } }
    func commit() { save() }
    func clear() {
        lines = []; memory = Memory(); resetSession(); save()
        UIAccessibility.post(notification: .announcement, argument: "AI chat and its memory cleared")
    }
    func forget(fact: String) { memory.facts.removeAll { $0 == fact }; save(); resetSession() }
    func remember(_ fact: String) {
        let f = fact.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !f.isEmpty, !memory.facts.contains(f) else { return }
        memory.facts.append(f); if memory.facts.count > 40 { memory.facts.removeFirst() }; save()
    }

    /// Local search corpus: every decrypted message on this device with its sender.
    var corpus: [String] {
        let s = LocalMessageStore.shared.snapshot
        return s.payloads.compactMap { id, p in
            guard let b = p.body ?? p.media?.transcript, !b.isEmpty, !E2EEService.isControl(p) else { return nil }
            return "@\(s.senders[id] ?? "?"): \(b)"
        } + s.notes.map { "Note to self: \($0.body)" }
    }

    static let personality = """
    You are "AI", Kaeleb's friendly assistant living inside the Mr. BlindBandit app. Talk like a warm, casual, upbeat friend: \
    short, natural sentences, a little humor when it fits, never robotic, never preachy. The user is blind and uses VoiceOver, \
    so answers are read aloud: no markdown, no bullet symbols, no emoji spam, no tables; say lists as plain sentences. \
    Be genuinely useful: answer questions, help write and rewrite, summarize chats, translate (including Cebuano/Bisaya and Tagalog), \
    set reminders, look up the calendar, contacts and places, do date and unit math, explain photos, and draft messages. \
    Use the tools whenever they help instead of guessing. Never invent message content; if a search finds nothing, say so. \
    Drafted messages are never sent until the user taps Send, so tell them it's ready to confirm. \
    When the user shares a lasting personal fact or preference, call the remember tool. Everything stays on this iPhone.
    """

    func instructions() -> String {
        var s = AIPersona.forPrivate.prompt() + " " + AIPersonaMode.current.promptAddon
        s += " Today is \(Date().formatted(date: .complete, time: .shortened))."
        if UserDefaults.standard.object(forKey: SettingsKey.aiPreferOnDevice) as? Bool ?? false {
            s += " Prefer on-device tools; escalate to cloud only when asked or when on-device fails."
        } else {
            s += " Prefer Cloud AI (Gemini) when available; use on-device tools offline or when the user asks."
        }
        if !memory.facts.isEmpty { s += " Things you remember about the user: " + memory.facts.joined(separator: "; ") + "." }
        if !memory.summary.isEmpty { s += " Summary of your earlier conversations: " + memory.summary }
        return s
    }

    func resetSession() {
        #if canImport(FoundationModels)
        sessionBox = nil
        #endif
    }

    /// Warms the model when the chat opens so the first answer starts faster.
    func prewarm() {
        #if canImport(FoundationModels)
        if #available(iOS 26, *), OnDeviceAI.isAvailable { (session() as? LanguageModelSession)?.prewarm() }
        #endif
    }

    #if canImport(FoundationModels)
    @available(iOS 26, *)
    func session() -> AnyObject {
        if let s = sessionBox { return s }
        let tools: [any Tool] = AIToolbox.all()
        // Seed the new session with recent turns so context survives relaunches and context resets.
        var prompt = instructions()
        let recent = lines.suffix(8).map { ($0.fromAI ? "AI: " : "User: ") + $0.text }
        if !recent.isEmpty { prompt += " Most recent turns: " + recent.joined(separator: " | ") }
        let s = LanguageModelSession(model: .default, tools: tools, instructions: prompt)
        sessionBox = s
        return s
    }
    #endif

    func ask(_ q: String) async {
        let question = q.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }
        append(Line(fromAI: false, text: question))
        thinking = true
        UIAccessibility.post(notification: .announcement, argument: "AI is thinking")
        if let intent = MusicIntent.parse(question) {
            // Deterministic path: drive MusicKit directly; the model can't refuse it.
            let said = await MusicController.shared.handle(action: intent.action, query: intent.query, kind: intent.kind)
            thinking = false
            append(Line(fromAI: true, text: said))
            UIAccessibility.post(notification: .announcement, argument: said)
            commit()
            return
        }
        // Force live web context when the question clearly needs the internet (Cloud AI / Brave via /v1/ai/search).
        var webContext = ""
        if WebSearch.allowed, WebSearch.needsLiveInfo(question) {
            webContext = await WebSearch.search(question)
            UIAccessibility.post(notification: .announcement, argument: "Searching the web")
        }
        let promptForModel: String
        if webContext.isEmpty {
            promptForModel = question
        } else {
            promptForModel = "Live web results (cite links, do not invent):\n" + webContext + "\n\nUser question: " + question
        }

        let reply = Line(fromAI: true, text: "")
        lines.append(reply)
        var final = ""
        var lastSpoken = 0
        let preferOnDevice = UserDefaults.standard.object(forKey: SettingsKey.aiPreferOnDevice) as? Bool ?? false
        let useCloudPrimary = CloudAI.isOn(.chat) && (!preferOnDevice || forceCloud)

        if useCloudPrimary {
            let history = lines.dropLast(2).suffix(10).map { ($0.fromAI ? "AI: " : "") + $0.text }
            let r = await CloudAI.chat(question, history: history, persona: AIPersona.forPrivate.prompt())
            if case .ok(let text) = r { final = text; lastSpoken = 0; update(reply.id, text: final) }
            else if forceCloud, !CloudAI.isOn(.chat) {
                final = CloudAI.disabledHint
            } else if let n = CloudAI.note(r), forceCloud || preferOnDevice == false {
                // Cloud was primary; keep the note if nothing else lands from on-device fallback.
                final = n
            }
        } else if forceCloud && !CloudAI.isOn(.chat) {
            final = CloudAI.disabledHint
        }

        #if canImport(FoundationModels)
        if #available(iOS 26, *), OnDeviceAI.isAvailable, final.isEmpty || (preferOnDevice && !forceCloud) {
            for attempt in 0..<2 {
                guard let session = session() as? LanguageModelSession else { break }
                do {
                    for try await snap in session.streamResponse(to: promptForModel) {
                        final = snap.content
                        update(reply.id, text: final)
                        if let end = final.lastIndex(where: { ".!?".contains($0) }) {
                            let upto = final.distance(from: final.startIndex, to: end) + 1
                            if upto - lastSpoken > 60 {
                                let chunk = String(final.dropFirst(lastSpoken).prefix(upto - lastSpoken))
                                lastSpoken = upto
                                if !AIVoice.speakReplies { UIAccessibility.post(notification: .announcement, argument: chunk) }
                            }
                        }
                    }
                    break
                } catch LanguageModelSession.GenerationError.exceededContextWindowSize {
                    await summarizeOldTurns(force: true)
                    resetSession()
                    if attempt == 1 { final = "My memory got full there. I saved a summary, so ask me again?" }
                } catch LanguageModelSession.GenerationError.guardrailViolation {
                    final = "I can't help with that one, but I'm happy to try something else."; break
                } catch {
                    if final.isEmpty { final = "Hmm, I couldn't finish that on this iPhone. Try asking another way?" }
                    break
                }
            }
        }
        #endif

        // Escalate to Cloud when on-device was preferred but failed / looks thin, unless Cloud is off.
        if !useCloudPrimary, CloudAI.isOn(.chat), (CloudAI.shouldEscalate(final) || forceCloud || final.isEmpty) {
            let history = lines.dropLast(2).suffix(10).map { ($0.fromAI ? "AI: " : "") + $0.text }
            let r = await CloudAI.chat(question, history: history, persona: AIPersona.forPrivate.prompt())
            if case .ok(let text) = r { final = text; lastSpoken = 0 }
            else if let n = CloudAI.note(r), forceCloud || final.isEmpty {
                final = n + (final.isEmpty ? "" : " " + final)
            }
        }
        forceCloud = false
        if final.isEmpty {
            let history = lines.dropLast().suffix(16).map { ($0.fromAI ? "AI: " : "Me: ") + $0.text }
            final = await AIFallback.answer(question, history: history, corpus: corpus, photo: lastPhoto)
        }
        update(reply.id, text: final)
        commit()
        thinking = false
        let rest = String(final.dropFirst(lastSpoken))
        if AIVoice.speakReplies { AIVoice.shared.say(final) }
        else { UIAccessibility.post(notification: .announcement, argument: lastSpoken == 0 ? "AI says: \(final)" : rest) }
        Task { await summarizeOldTurns(force: false) }
    }

    /// Keeps the context window small: everything older than the last 12 lines is summarized into memory.
    func summarizeOldTurns(force: Bool) async {
        let cutoff = lines.count - 12
        guard cutoff > memory.summarizedThrough + (force ? 0 : 8) else { return }
        let chunk = lines[memory.summarizedThrough..<max(cutoff, memory.summarizedThrough)].map { ($0.fromAI ? "AI: " : "User: ") + $0.text }
        guard !chunk.isEmpty else { return }
        #if canImport(FoundationModels)
        if #available(iOS 26, *), OnDeviceAI.isAvailable {
            if let digest = await AIMemoryDigest.make(previous: memory.summary, turns: chunk) {
                memory.summary = digest.summary
                for f in digest.facts { remember(f) }
            }
            memory.topics = await AIMemoryDigest.tags(memory.summary)
        }
        #endif
        if memory.summary.isEmpty { memory.summary = String(chunk.joined(separator: " ").suffix(600)) }
        memory.summarizedThrough = max(cutoff, memory.summarizedThrough)
        save()
    }

    func confirmSend(_ p: PendingSend, using comms: ProductionCommunicationsService) async {
        pendingSends.removeAll { $0.id == p.id }
        if await comms.sendMessage(recipient: p.handle, body: p.text) != nil {
            append(Line(fromAI: true, text: "Sent to @\(p.handle): \(p.text)"))
            UIAccessibility.post(notification: .announcement, argument: "Sent to @\(p.handle)")
        }
    }
}

/// Spoken replies (AVSpeechSynthesizer) and hands-free conversation mode.
@MainActor
final class AIVoice: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    static let shared = AIVoice()
    static var speakReplies: Bool {
        get { UserDefaults.standard.object(forKey: SettingsKey.aiSpeakReplies) as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: SettingsKey.aiSpeakReplies) }
    }
    static var handsFree: Bool { UserDefaults.standard.bool(forKey: "ai.handsFree") }
    private let synth = AVSpeechSynthesizer()
    @Published var speaking = false
    var onDone: (() -> Void)?
    override init() { super.init(); synth.delegate = self }
    func say(_ text: String) {
        synth.stopSpeaking(at: .immediate)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        let u = AVSpeechUtterance(string: text)
        let lang = LanguageID.detect(text) ?? LanguageID.deviceLanguage
        u.voice = NaturalReader.shared.bestVoice(for: lang)
        u.prefersAssistiveTechnologySettings = true
        speaking = true
        synth.speak(u)
    }
    func stop() { synth.stopSpeaking(at: .immediate); speaking = false }
    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) {
        Task { @MainActor in self.speaking = false; self.onDone?() }
    }
}

/// Answers without Apple Intelligence: chat search, OCR, translation, date and unit math, reminders.
enum AIFallback {
    static func answer(_ q: String, history: [String], corpus: [String], photo: UIImage?) async -> String {
        let lower = q.lowercased()
        if (lower.contains("photo") || lower.contains("picture") || lower.contains("image")), let photo {
            return await AIToolbox.describe(photo)
        }
        if lower.hasPrefix("search ") || lower.hasPrefix("find ") {
            let term = q.split(separator: " ", maxSplits: 1).last.map(String.init) ?? q
            return AIToolbox.search(term, corpus: corpus)
        }
        if let conv = AIToolbox.convertUnits(q) { return conv }
        if let d = AIToolbox.dateAnswer(q) { return d }
        if lower.hasPrefix("translate ") {
            let text = String(q.dropFirst(10))
            return await Translator.shared.translateOutgoing(text, to: LanguageID.deviceLanguage == "en" ? "es" : "en") ?? "Translation isn't available for that language yet."
        }
        if lower.hasPrefix("remind me ") {
            return await ReminderMaker.add(title: String(q.dropFirst(10)), minutes: 0) ? "Done! It's in Reminders." : "I need Reminders access for that. You can allow it in Settings."
        }
        return "Hey! My full brain needs Apple Intelligence (iPhone 15 Pro or newer on iOS 26 with Apple Intelligence on). " +
            "Right now I can still search your chats (say \"search\" and a word), read and describe photos, translate (\"translate\" and your text), " +
            "convert units like \"5 miles in km\", do dates like \"days until December 25\", and set reminders (\"remind me\" and what). " + OnDeviceAI.unavailableReason
    }
}

enum ReminderMaker {
    static func add(title: String, minutes: Int, due: Date? = nil) async -> Bool {
        let store = EKEventStore()
        guard (try? await store.requestFullAccessToReminders()) == true, let cal = store.defaultCalendarForNewReminders() else { return false }
        let r = EKReminder(eventStore: store)
        r.title = title
        r.calendar = cal
        let date = due ?? (minutes > 0 ? Date().addingTimeInterval(Double(minutes) * 60) : nil)
        if let date {
            r.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            r.addAlarm(EKAlarm(absoluteDate: date))
        }
        return (try? store.save(r, commit: true)) != nil
    }
}

/// Plain-Swift implementations shared by the model tools and the no-Apple-Intelligence fallback.
enum AIToolbox {
    static func search(_ query: String, corpus: [String]) -> String {
        let words = query.lowercased().split(separator: " ").map(String.init).filter { $0.count > 2 }
        let hits = corpus.filter { line in
            let l = line.lowercased()
            return l.contains(query.lowercased()) || (!words.isEmpty && words.allSatisfy { l.contains($0) })
        }
        return hits.isEmpty ? "I didn't find any messages about \"\(query)\"." : "Found \(hits.count). " + hits.suffix(10).joined(separator: "\n")
    }

    static func chat(with handle: String, corpus: [String]) -> [String] {
        let h = "@" + handle.replacingOccurrences(of: "@", with: "").lowercased() + ":"
        return corpus.filter { $0.lowercased().hasPrefix(h) }.suffix(40)
    }

    static func describe(_ image: UIImage) async -> String {
        let a = await VisionDescriber.describe(image)
        var s = a.summary.isEmpty ? VisionDescriber.template(a) : a.summary
        if !a.text.isEmpty { s += " Text in it says: \(a.text)" }
        return s
    }

    static func calendar(daysAhead: Int) async -> String {
        let store = EKEventStore()
        guard (try? await store.requestFullAccessToEvents()) == true else { return "I need Calendar access for that. You can allow it in Settings." }
        let start = Calendar.current.startOfDay(for: Date())
        let end = Calendar.current.date(byAdding: .day, value: max(1, daysAhead), to: start) ?? start
        let events = store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: nil))
        if events.isEmpty { return "Nothing on the calendar." }
        return events.prefix(15).map { "\($0.title ?? "Event") \($0.isAllDay ? "all day" : "at") \($0.isAllDay ? "" : $0.startDate.formatted(date: .abbreviated, time: .shortened))\($0.location.map { ", at \($0)" } ?? "")" }
            .joined(separator: ". ")
    }

    static func contacts(_ name: String) async -> String {
        let store = CNContactStore()
        guard (try? await store.requestAccess(for: .contacts)) == true else { return "I need Contacts access for that. You can allow it in Settings." }
        let keys = [CNContactGivenNameKey, CNContactFamilyNameKey, CNContactPhoneNumbersKey, CNContactEmailAddressesKey, CNContactBirthdayKey] as [CNKeyDescriptor]
        let found = (try? store.unifiedContacts(matching: CNContact.predicateForContacts(matchingName: name), keysToFetch: keys)) ?? []
        if found.isEmpty { return "No contact named \(name)." }
        return found.prefix(5).map { c in
            var s = "\(c.givenName) \(c.familyName)"
            if let p = c.phoneNumbers.first?.value.stringValue { s += ", phone \(p)" }
            if let e = c.emailAddresses.first?.value { s += ", email \(e)" }
            if let b = c.birthday, let m = b.month, let d = b.day { s += ", birthday \(m)/\(d)" }
            return s
        }.joined(separator: ". ")
    }

    static func places(_ query: String) async -> String {
        let req = MKLocalSearch.Request()
        req.naturalLanguageQuery = query
        guard let resp = try? await MKLocalSearch(request: req).start() else { return "I couldn't find that place." }
        return resp.mapItems.prefix(5).map { item in
            var s = item.name ?? "Place"
            if let a = item.placemark.title { s += ", \(a)" }
            if let p = item.phoneNumber { s += ", phone \(p)" }
            return s
        }.joined(separator: ". ")
    }

    static func dateAnswer(_ q: String) -> String? {
        let lower = q.lowercased()
        if lower.contains("what time") || lower == "time" { return "It's \(Date().formatted(date: .omitted, time: .shortened))." }
        if lower.contains("what day") || lower.contains("today's date") { return "Today is \(Date().formatted(date: .complete, time: .omitted))." }
        if lower.contains("days until") || lower.contains("how long until") {
            let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
            if let m = detector?.firstMatch(in: q, range: NSRange(q.startIndex..., in: q)), let d = m.date { return dateMath(from: Date(), to: d) }
        }
        return nil
    }

    static func dateMath(from a: Date, to b: Date) -> String {
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: a), to: Calendar.current.startOfDay(for: b)).day ?? 0
        return "\(abs(days)) day\(abs(days) == 1 ? "" : "s") \(days >= 0 ? "until" : "since") \(b.formatted(date: .long, time: .omitted))."
    }

    static func addToDate(days: Int, weeks: Int, months: Int) -> String {
        var c = DateComponents(); c.day = days; c.weekOfYear = weeks; c.month = months
        let d = Calendar.current.date(byAdding: c, to: Date()) ?? Date()
        return d.formatted(date: .complete, time: .omitted)
    }

    static let units: [String: Dimension] = [
        "km": UnitLength.kilometers, "kilometers": UnitLength.kilometers, "mi": UnitLength.miles, "miles": UnitLength.miles, "mile": UnitLength.miles,
        "m": UnitLength.meters, "meters": UnitLength.meters, "ft": UnitLength.feet, "feet": UnitLength.feet, "in": UnitLength.inches, "inches": UnitLength.inches,
        "cm": UnitLength.centimeters, "kg": UnitMass.kilograms, "kilograms": UnitMass.kilograms, "lb": UnitMass.pounds, "lbs": UnitMass.pounds, "pounds": UnitMass.pounds,
        "g": UnitMass.grams, "grams": UnitMass.grams, "oz": UnitMass.ounces, "ounces": UnitMass.ounces,
        "c": UnitTemperature.celsius, "celsius": UnitTemperature.celsius, "f": UnitTemperature.fahrenheit, "fahrenheit": UnitTemperature.fahrenheit,
        "l": UnitVolume.liters, "liters": UnitVolume.liters, "gallons": UnitVolume.gallons, "gal": UnitVolume.gallons, "ml": UnitVolume.milliliters, "cups": UnitVolume.cups,
        "mph": UnitSpeed.milesPerHour, "kph": UnitSpeed.kilometersPerHour, "kmh": UnitSpeed.kilometersPerHour]

    static func convert(_ value: Double, from: String, to: String) -> String? {
        guard let f = units[from.lowercased()], let t = units[to.lowercased()], type(of: f) == type(of: t) else { return nil }
        let r = Measurement(value: value, unit: f).converted(to: t)
        return "\(value.formatted()) \(from) is \(r.value.formatted(.number.precision(.fractionLength(0...2)))) \(to)."
    }

    /// "5 miles in km", "100 f to c".
    static func convertUnits(_ q: String) -> String? {
        let p = q.lowercased().replacingOccurrences(of: "°", with: "").split(separator: " ").map(String.init)
        guard let sep = p.firstIndex(where: { $0 == "in" || $0 == "to" }), sep >= 2, sep + 1 < p.count, let v = Double(p[sep - 2]) else { return nil }
        return convert(v, from: p[sep - 1], to: p[sep + 1])
    }
}

#if canImport(FoundationModels)
@available(iOS 26, *)
@Generable struct AIMemoryDigestOutput {
    @Guide(description: "Two to four sentence summary of everything discussed, merged with the previous summary") var summary: String
    @Guide(description: "Lasting facts or preferences the user shared about themselves, each under 12 words", .maximumCount(6)) var facts: [String]
}

@available(iOS 26, *)
@Generable struct AITopicTags {
    @Guide(description: "Topic tags", .maximumCount(5)) var tags: [String]
}

enum AIMemoryDigest {
    @available(iOS 26, *)
    static func make(previous: String, turns: [String]) async -> AIMemoryDigestOutput? {
        let s = LanguageModelSession(instructions: "Summarize a conversation between a user and their assistant for long-term memory. Plain sentences.")
        return try? await s.respond(to: "Previous summary: \(previous)\nNew turns:\n" + turns.joined(separator: "\n"), generating: AIMemoryDigestOutput.self).content
    }

    /// Uses the content-tagging adapter to label memory topics.
    @available(iOS 26, *)
    static func tags(_ text: String) async -> [String] {
        guard !text.isEmpty else { return [] }
        let model = SystemLanguageModel(useCase: .contentTagging)
        guard case .available = model.availability else { return [] }
        let s = LanguageModelSession(model: model)
        return (try? await s.respond(to: text, generating: AITopicTags.self).content.tags) ?? []
    }
}

@available(iOS 26, *)
extension AIToolbox {
    static func all() -> [any Tool] {
        [SearchMyChatsTool(), ReadChatTool(), DraftMessageTool(), ReminderTool(), CalendarTool(), ContactsTool(), PlacesTool(),
         TranslateTool(), DescribePhotoTool(), DateMathTool(), UnitConvertTool(), RememberTool(), NoteToSelfTool(), WeatherTool(), MusicTool()] + (WebSearch.allowed ? [WebSearchTool()] : [])
    }
}

@available(iOS 26, *)
struct SearchMyChatsTool: Tool {
    let name = "searchMyChats"
    let description = "Searches all of the user's decrypted chat messages and notes stored on this iPhone."
    @Generable struct Arguments { @Guide(description: "Words to search for") var query: String }
    func call(arguments: Arguments) async throws -> String {
        let c = await MainActor.run { AIChatStore.shared.corpus }
        return AIToolbox.search(arguments.query, corpus: c)
    }
}

@available(iOS 26, *)
struct ReadChatTool: Tool {
    let name = "readChat"
    let description = "Returns recent messages from one person by @handle so you can summarize or answer about that chat."
    @Generable struct Arguments { @Guide(description: "Username without @") var handle: String }
    func call(arguments: Arguments) async throws -> String {
        let c = await MainActor.run { AIChatStore.shared.corpus }
        let lines = AIToolbox.chat(with: arguments.handle, corpus: c)
        return lines.isEmpty ? "No messages from @\(arguments.handle) on this iPhone." : lines.joined(separator: "\n")
    }
}

@available(iOS 26, *)
struct DraftMessageTool: Tool {
    let name = "draftMessage"
    let description = "Prepares a message to send to someone by @handle. The user must tap Send to confirm."
    @Generable struct Arguments {
        @Guide(description: "Recipient Blindbandit username without @") var handle: String
        @Guide(description: "The message text, written in the user's voice") var text: String
    }
    func call(arguments: Arguments) async throws -> String {
        await MainActor.run {
            AIChatStore.shared.pendingSends.append(.init(handle: arguments.handle.replacingOccurrences(of: "@", with: ""), text: arguments.text))
        }
        return "Draft ready for @\(arguments.handle). Ask the user to confirm with the Send button."
    }
}

@available(iOS 26, *)
struct ReminderTool: Tool {
    let name = "setReminder"
    let description = "Creates a reminder in the Reminders app."
    @Generable struct Arguments {
        @Guide(description: "What to be reminded about") var title: String
        @Guide(description: "Minutes from now, 0 if no time or if a date is given") var minutesFromNow: Int
        @Guide(description: "Optional date and time in ISO 8601 like 2026-10-24T09:00:00, empty if none") var dateISO: String
    }
    func call(arguments: Arguments) async throws -> String {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime, .withDashSeparatorInDate]; f.timeZone = .current
        let ok = await ReminderMaker.add(title: arguments.title, minutes: arguments.minutesFromNow, due: f.date(from: arguments.dateISO))
        return ok ? "Reminder added." : "Reminders access wasn't allowed."
    }
}

@available(iOS 26, *)
struct CalendarTool: Tool {
    let name = "lookUpCalendar"
    let description = "Lists the user's calendar events from today for a number of days."
    @Generable struct Arguments { @Guide(description: "How many days ahead, 1 for today", .range(1...31)) var days: Int }
    func call(arguments: Arguments) async throws -> String { await AIToolbox.calendar(daysAhead: arguments.days) }
}

@available(iOS 26, *)
struct ContactsTool: Tool {
    let name = "lookUpContact"
    let description = "Finds a person in the iPhone Contacts and returns phone, email and birthday."
    @Generable struct Arguments { @Guide(description: "Person's name") var name: String }
    func call(arguments: Arguments) async throws -> String { await AIToolbox.contacts(arguments.name) }
}

@available(iOS 26, *)
struct PlacesTool: Tool {
    let name = "findPlace"
    let description = "Searches Apple Maps for a place, business or address and returns names, addresses and phone numbers."
    @Generable struct Arguments { @Guide(description: "What to find, like 'coffee near Cebu IT Park'") var query: String }
    func call(arguments: Arguments) async throws -> String { await AIToolbox.places(arguments.query) }
}

@available(iOS 26, *)
struct TranslateTool: Tool {
    let name = "translate"
    let description = "Translates text on device into a language given as an ISO code like en, ceb (Cebuano/Bisaya), tl (Tagalog), es."
    @Generable struct Arguments {
        @Guide(description: "Text to translate") var text: String
        @Guide(description: "Target language ISO code") var target: String
    }
    func call(arguments: Arguments) async throws -> String {
        await Translator.shared.translateOutgoing(arguments.text, to: arguments.target) ?? arguments.text
    }
}

@available(iOS 26, *)
struct DescribePhotoTool: Tool {
    let name = "describePhoto"
    let description = "Describes the photo the user attached in this AI chat and reads any text in it."
    @Generable struct Arguments { @Guide(description: "What the user wants to know about the photo") var question: String }
    func call(arguments: Arguments) async throws -> String {
        guard let img = await MainActor.run(body: { AIChatStore.shared.lastPhoto }) else { return "No photo is attached. Ask the user to add one with the Photo button." }
        return await AIToolbox.describe(img)
    }
}

@available(iOS 26, *)
struct DateMathTool: Tool {
    let name = "dateMath"
    let description = "Date math: days between today and a date, or the date after adding days, weeks or months."
    @Generable struct Arguments {
        @Guide(description: "Target date in ISO 8601 (YYYY-MM-DD), empty when adding instead") var dateISO: String
        @Guide(description: "Days to add, 0 if none") var addDays: Int
        @Guide(description: "Weeks to add, 0 if none") var addWeeks: Int
        @Guide(description: "Months to add, 0 if none") var addMonths: Int
    }
    func call(arguments: Arguments) async throws -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        if let d = f.date(from: String(arguments.dateISO.prefix(10))) { return AIToolbox.dateMath(from: Date(), to: d) }
        return AIToolbox.addToDate(days: arguments.addDays, weeks: arguments.addWeeks, months: arguments.addMonths)
    }
}

@available(iOS 26, *)
struct UnitConvertTool: Tool {
    let name = "convertUnits"
    let description = "Converts length, weight, temperature, volume and speed units, like miles to km or F to C."
    @Generable struct Arguments {
        var value: Double
        @Guide(description: "From unit, like mi, km, lb, kg, f, c, l, gal, mph") var from: String
        @Guide(description: "To unit") var to: String
    }
    func call(arguments: Arguments) async throws -> String {
        AIToolbox.convert(arguments.value, from: arguments.from, to: arguments.to) ?? "I can't convert \(arguments.from) to \(arguments.to)."
    }
}

@available(iOS 26, *)
struct RememberTool: Tool {
    let name = "remember"
    let description = "Saves a lasting fact or preference about the user to long-term memory on this iPhone."
    @Generable struct Arguments { @Guide(description: "Short fact, like 'Prefers Bisaya replies'") var fact: String }
    func call(arguments: Arguments) async throws -> String {
        await MainActor.run { AIChatStore.shared.remember(arguments.fact) }
        return "Saved to memory."
    }
}

@available(iOS 26, *)
struct NoteToSelfTool: Tool {
    let name = "saveNoteToSelf"
    let description = "Saves a note in the user's encrypted Notes to self chat."
    @Generable struct Arguments { var text: String }
    func call(arguments: Arguments) async throws -> String {
        await MainActor.run { NotesToSelf.add(arguments.text) }
        return "Saved to Notes to self."
    }
}
#endif

struct AIChatView: View {
    @ObservedObject private var store = AIChatStore.shared
    @ObservedObject private var voice = AIVoice.shared
    @EnvironmentObject private var comms: ProductionCommunicationsService
    private var shownLines: [AIChatStore.Line] { AppPIN.decoyActive ? [] : store.lines }
    @StateObject private var dictation = LiveDictation()
    @State private var draft = ""
    @State private var confirmClear = false
    @State private var photoItem: PhotosPickerItem?
    @State private var showMemory = false
    @State private var silenceTask: Task<Void, Never>?
    @State private var webPage: IdentifiedURL?
    @State private var imagePrompt: IdentifiedPrompt?
    @AppStorage("ai.speakReplies") private var speakReplies = false
    @AppStorage("ai.handsFree") private var handsFree = false

    var body: some View {
        VStack(spacing: 0) {
            if !OnDeviceAI.isAvailable {
                Text("Basic mode. " + OnDeviceAI.unavailableReason).font(.callout).padding()
            }
            ScrollViewReader { proxy in
                List {
                    if shownLines.isEmpty {
                        Text("Hey Kaeleb! I'm your AI buddy. Ask me anything, have me write or translate something, catch you up on a chat, set a reminder, or describe a photo. It all stays on this iPhone.")
                    }
                    ForEach(shownLines) { line in
                        aiBubble(line).id(line.id)
                            .listRowSeparator(.hidden)
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
                    if store.thinking {
                        HStack(spacing: 8) { AIAvatar(); Text("AI is typing…").font(.caption).foregroundStyle(.secondary) }
                            .listRowSeparator(.hidden)
                            .accessibilityElement(children: .ignore).accessibilityLabel("AI is typing")
                    }
                }
                .listStyle(.plain)
                .onChange(of: store.lines.count) { _, _ in if let l = store.lines.last { proxy.scrollTo(l.id) } }
            }
            if store.lastPhoto != nil {
                HStack {
                    Label("Photo attached", systemImage: "photo")
                    Spacer()
                    Button("Remove") { store.lastPhoto = nil }
                }.padding(.horizontal).font(.caption)
            }
            HStack(spacing: 8) {
                TextField("Message AI", text: $draft, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...5)
                    .accessibilityActions {
                        Button(dictation.isListening ? "Stop dictation and send" : "Dictate") { toggleListening() }
                        Button(speakReplies ? "Stop speaking replies" : "Speak replies") { speakReplies.toggle() }
                        Button("Clear AI chat") { confirmClear = true }
                        if CloudAI.isOn(.chat) { Button("Ask the bigger AI") { askBigger() } }
                        if WebSearch.allowed { Button("Search the web") { searchWeb() } }
                        if CloudAI.isOn(.image) { Button("Make an image") { makeImage() } }
                    }
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Image(systemName: "photo").frame(width: Brand.minTouch, height: Brand.minTouch)
                }
                .accessibilityLabel("Attach photo")
                Button { toggleListening() } label: {
                    Image(systemName: dictation.isListening ? "stop.circle.fill" : "mic.fill").frame(width: Brand.minTouch, height: Brand.minTouch)
                }
                .accessibilityLabel(dictation.isListening ? "Stop dictation and send" : "Dictate")
                Button { send() } label: {
                    Image(systemName: "paperplane.fill").frame(width: Brand.minTouch, height: Brand.minTouch)
                }
                .accessibilityLabel("Send")
                .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty || store.thinking)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .safeAreaInset(edge: .top, spacing: 0) { NowPlayingBar() }
        .sheet(item: $webPage) { SafariView(url: $0.url).ignoresSafeArea() }
        .sheet(item: $imagePrompt) { CloudImageSheet(prompt: $0.text) }
        .navigationTitle("AI")
        .toolbar {
            Menu {
                Toggle("Speak replies", isOn: $speakReplies)
                Toggle("Hands-free conversation", isOn: $handsFree)
                Button("What AI remembers") { showMemory = true }
                if CloudAI.isOn(.chat) { Button("Ask the bigger AI") { askBigger() } }
                if WebSearch.allowed { Button("Search the web") { searchWeb() } }
                if CloudAI.isOn(.image) { Button("Make an image") { makeImage() } }
                Button("Clear AI chat", role: .destructive) { confirmClear = true }
            } label: { Image(systemName: "gearshape") }.accessibilityLabel("AI chat settings")
        }
        .sheet(isPresented: $showMemory) { AIMemoryView() }
        .confirmationDialog("Clear the AI chat history and memory on all your devices? The AI chat itself stays.", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear history", role: .destructive) { store.clear() }
        }
        .accessibilityAction(.magicTap) { if draft.isEmpty { toggleListening() } else { send() } }
        .onChange(of: dictation.text) { _, t in
            guard dictation.isListening else { return }
            draft = t
            // Hands-free: stop and send after 1.6 s of silence.
            silenceTask?.cancel()
            if handsFree { silenceTask = Task { try? await Task.sleep(nanoseconds: 1_600_000_000); if !Task.isCancelled { await finishListening() } } }
        }
        .onChange(of: photoItem) { _, item in
            Task {
                if let d = try? await item?.loadTransferable(type: Data.self), let img = UIImage(data: d) {
                    store.lastPhoto = img
                    UIAccessibility.post(notification: .announcement, argument: "Photo attached. Ask me about it.")
                }
            }
        }
        .onAppear {
            store.prewarm()
            voice.onDone = { if AIVoice.handsFree { Task { await dictation.start() } } }
        }
        .onDisappear { voice.onDone = nil; if dictation.isListening { dictation.stop() } }
    }

    /// Same bubble, alignment and status-line layout as a regular conversation; the AI is just the other person.
    private func aiBubble(_ line: AIChatStore.Line) -> some View {
        let mine = !line.fromAI
        let stamp = Date(timeIntervalSince1970: line.at).formatted(date: .omitted, time: .shortened)
        let answered = mine && store.lines.drop(while: { $0.id != line.id }).dropFirst().contains { $0.fromAI }
        let status = mine ? (answered ? "Read \(stamp)" : "Sent \(stamp)") : stamp
        return VStack(alignment: mine ? .trailing : .leading, spacing: 3) {
            HStack(alignment: .bottom, spacing: 6) {
                if mine { Spacer(minLength: 48) } else { AIAvatar() }
                Text(line.text.isEmpty ? "…" : line.text)
                    .padding(12)
                    .background(mine ? Brand.gold.opacity(0.35) : Color.secondary.opacity(0.16), in: RoundedRectangle(cornerRadius: 16))
                    .textSelection(.enabled)
                if !mine { Spacer(minLength: 48) }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(mine ? "You" : "AI"): \(line.text)")
            .accessibilityActions {
                Button("Read aloud") { AIVoice.shared.say(line.text) }
                Button("Copy") { UIPasteboard.general.string = line.text }
                ForEach(LinkFinder.links(in: line.text), id: \.self) { u in
                    Button("Open link \(u.host() ?? u.absoluteString)") { webPage = IdentifiedURL(url: u) }
                }
            }
            .contextMenu {
                Button("Read aloud") { AIVoice.shared.say(line.text) }
                Button("Copy") { UIPasteboard.general.string = line.text }
            }
            if !mine {
                ForEach(LinkFinder.links(in: line.text), id: \.self) { u in
                    Button { webPage = IdentifiedURL(url: u) } label: {
                        Label(u.host() ?? u.absoluteString, systemImage: "safari").font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Open link \(u.host() ?? u.absoluteString)")
                    .padding(.leading, 36)
                }
            }
            MessageStatusCaption(text: status, mine: mine)
        }
        .frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading)
        .accessibilityElement(children: .contain)
    }

    private func askBigger() {
        guard !draft.trimmingCharacters(in: .whitespaces).isEmpty else {
            UIAccessibility.post(notification: .announcement, argument: "Type your question first"); return
        }
        store.forceCloud = true
        send()
    }

    private func searchWeb() {
        let q = draft.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else {
            UIAccessibility.post(notification: .announcement, argument: "Type what to search first"); return
        }
        if !q.lowercased().contains("search") {
            draft = "Search the web for: " + q
        }
        send()
    }

    private func makeImage() {
        let p = draft.trimmingCharacters(in: .whitespaces)
        guard !p.isEmpty else { UIAccessibility.post(notification: .announcement, argument: "Describe the image first"); return }
        draft = ""
        imagePrompt = IdentifiedPrompt(text: p)
    }

    private func toggleListening() {
        Task {
            if dictation.isListening { await finishListening() }
            else { voice.stop(); await dictation.start() }
        }
    }

    private func finishListening() async {
        silenceTask?.cancel()
        dictation.stop()
        let text = await OnDeviceAI.cleanDictation(dictation.text)
        draft = text
        if !text.isEmpty { send() }
    }

    private func send() {
        let q = draft
        draft = ""
        Task { await store.ask(q) }
    }
}

struct AIMemoryView: View {
    @ObservedObject private var store = AIChatStore.shared
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section("Facts") {
                    if store.memory.facts.isEmpty { Text("Nothing yet. Tell me things like \"remember I prefer Bisaya\".") }
                    ForEach(store.memory.facts, id: \.self) { f in
                        Text(f).accessibilityAction(named: "Forget") { store.forget(fact: f) }
                            .swipeActions { Button("Forget", role: .destructive) { store.forget(fact: f) } }
                    }
                }
                Section("Summary of earlier chats") { Text(store.memory.summary.isEmpty ? "None yet." : store.memory.summary) }
                if !store.memory.topics.isEmpty { Section("Topics") { Text(store.memory.topics.joined(separator: ", ")) } }
            }
            .navigationTitle("AI memory")
            .toolbar { Button("Done") { dismiss() } }
        }
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
                Text((AppPIN.decoyActive ? nil : store.lines.last)?.text ?? "Your private on-device assistant").font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("AI, pinned, private on-device assistant. " + ((AppPIN.decoyActive ? nil : store.lines.last).map { "Last: \($0.text)" } ?? ""))
    }
}


/// The AI's avatar, shown like any contact's.
struct AIAvatar: View {
    var body: some View {
        Image(systemName: "sparkles")
            .font(.caption.bold())
            .foregroundStyle(.black)
            .frame(width: 30, height: 30)
            .background(Brand.gold, in: Circle())
            .accessibilityHidden(true)
    }
}

struct IdentifiedPrompt: Identifiable { let id = UUID(); let text: String }
