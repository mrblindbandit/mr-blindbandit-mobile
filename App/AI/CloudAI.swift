import Foundation
import SwiftUI

/// Cloud AI (uses server): Gemini-backed `/v1/ai/*` on api.mrblindbandit.net (Workers AI fallback).
/// Nothing is sent unless Cloud AI and that feature are on, and E2EE chat content only when the user invokes a cloud feature on it.
/// Every call falls back to on-device when the server is out of daily quota (429) or not updated yet (404).
@MainActor
enum CloudAI {
    enum Feature: String, CaseIterable, Identifiable {
        case chat, image, transcribe, translate, summaries, linkCheck
        var id: String { rawValue }
        var title: String {
            switch self {
            case .chat: return "Bigger AI for hard questions"
            case .image: return "Image generation (stickers and art)"
            case .transcribe: return "Whisper transcription for long voice notes"
            case .translate: return "Cloud translation for Bisaya and Tagalog"
            case .summaries: return "Cloud summaries"
            case .linkCheck: return "Scam link checks"
            }
        }
        var serverFeature: ServerFeatures.Feature {
            switch self {
            case .chat: return .cloudChat
            case .image: return .cloudImage
            case .transcribe: return .cloudTranscribe
            case .translate: return .cloudTranslate
            case .summaries: return .cloudChat
            case .linkCheck: return .cloudLinkCheck
            }
        }
    }

    /// Master Cloud AI switch. Missing key defaults ON so signed-in users hit live Gemini `/v1/ai/chat`
    /// without hunting Settings (they can still turn it off). Explicit false stays off.
    static var enabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: "ai.cloud.enabled") == nil { return true }
            return UserDefaults.standard.bool(forKey: "ai.cloud.enabled")
        }
        set { UserDefaults.standard.set(newValue, forKey: "ai.cloud.enabled") }
    }
    /// AI Preferences "Allow Cloud AI fallback" — when false, auto-escalate stays off even if Cloud AI is on.
    static var fallbackAllowed: Bool {
        get { UserDefaults.standard.object(forKey: SettingsKey.aiCloudFallback) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: SettingsKey.aiCloudFallback) }
    }
    static func isOn(_ f: Feature) -> Bool { enabled && (UserDefaults.standard.object(forKey: "ai.cloud." + f.rawValue) as? Bool ?? true) }
    static func set(_ f: Feature, _ on: Bool) { UserDefaults.standard.set(on, forKey: "ai.cloud." + f.rawValue) }

    enum Outcome<T> { case ok(T), outOfQuota, needsUpdate, failed(String) }

    private static func call(_ f: Feature, _ path: String, _ body: [String: Any]?, method: String = "POST", timeout: TimeInterval = 12) async -> Outcome<[String: Any]> {
        do {
            let d = try await SecurityAPI.gated(f.serverFeature) {
                try await BlindbanditAPI.request(path, method: method, body: body, timeout: timeout)
            }
            return .ok(SecurityAPI.data(d))
        } catch is NeedsServerUpdate { return .needsUpdate }
        catch let CommunicationsError.server(msg) where msg.contains("429") || msg.lowercased().contains("quota") || msg.lowercased().contains("limit") {
            return .outOfQuota
        } catch let error as URLError where error.code == .timedOut {
            return .failed("Cloud AI timed out")
        } catch { return .failed(error.localizedDescription) }
    }

    static func note<T>(_ o: Outcome<T>) -> String? {
        switch o {
        case .ok: return nil
        case .outOfQuota: return "Cloud AI is out for today, so I used the on-device AI."
        case .needsUpdate: return "Cloud AI: \(ServerFeatures.needsUpdateText). Used the on-device AI."
        case .failed(let e) where e.lowercased().contains("timed out"):
            return "Cloud AI took too long, so I used the on-device AI."
        case .failed: return "Cloud AI didn't answer, so I used the on-device AI."
        }
    }

    /// Shown when Cloud AI is off so the user knows why Gemini was not used.
    static var disabledHint: String {
        "Cloud AI is off. Turn on Cloud AI under Settings → AI (or Security → AI) to use the live Gemini-backed server."
    }

    // POST /v1/ai/chat  {messages:[{role,content}], persona?, stream:false}
    // Server envelope is {success,data:{reply,provider,...}}; SecurityAPI.data unwraps `data`.
    // Gemini can take >12s; use a longer timeout so the live provider is not dropped as a client timeout.
    static func chat(_ question: String, history: [String], persona: String) async -> Outcome<String> {
        guard isOn(.chat) else { return .failed("cloud_off") }
        var msgs: [[String: String]] = [["role": "system", "content": persona]]
        msgs += history.suffix(10).map { $0.hasPrefix("AI: ") ? ["role": "assistant", "content": String($0.dropFirst(4))] : ["role": "user", "content": $0] }
        msgs.append(["role": "user", "content": question])
        var body: [String: Any] = ["messages": msgs, "stream": false]
        // Server accepts optional persona: hood | professional (owner style).
        body["persona"] = AIPersona.forPrivate.rawValue
        switch await call(.chat, "v1/ai/chat", body, timeout: 45) {
        case .ok(let o):
            // Prefer nested-unwrapped reply; also tolerate flat {reply} if the gateway ever changes.
            let r = (o["reply"] ?? o["response"] ?? o["text"]) as? String ?? ""
            if r.isEmpty { return .failed("empty") }
            // Stash last provider for Settings / debug (gemini | workers-ai).
            if let p = o["provider"] as? String { UserDefaults.standard.set(p, forKey: "ai.cloud.lastProvider") }
            return .ok(r)
        case .outOfQuota: return .outOfQuota
        case .needsUpdate: return .needsUpdate
        case .failed(let e): return .failed(e)
        }
    }

    static func summarize(chatName: String, lines: [String]) async -> String? {
        guard isOn(.summaries) else { return nil }
        let q = "Summarize this chat '\(chatName)' in a few plain sentences for a VoiceOver user:\n" + lines.suffix(80).joined(separator: "\n")
        if case .ok(let s) = await chat(q, history: [], persona: AIPersona.professional.prompt()) { return s }
        return nil
    }

    // POST /v1/ai/image {prompt} -> {image_base64 | image (data URL)}
    static func image(_ prompt: String) async -> Outcome<UIImage> {
        switch await call(.image, "v1/ai/image", ["prompt": prompt]) {
        case .ok(let o):
            var b64 = (o["image_base64"] ?? o["image"]) as? String ?? ""
            if let r = b64.range(of: "base64,") { b64 = String(b64[r.upperBound...]) }
            if let d = Data(base64Encoded: b64), let img = UIImage(data: d) { return .ok(img) }
            return .failed("no image")
        case .outOfQuota: return .outOfQuota
        case .needsUpdate: return .needsUpdate
        case .failed(let e): return .failed(e)
        }
    }

    // POST /v1/ai/transcribe {audio_base64, mime} -> {text}
    static func transcribe(_ audio: Data, mime: String = "audio/mp4") async -> Outcome<String> {
        switch await call(.transcribe, "v1/ai/transcribe", ["audio_base64": audio.base64EncodedString(), "mime": mime]) {
        case .ok(let o): return ((o["text"] as? String).map { .ok($0) }) ?? .failed("empty")
        case .outOfQuota: return .outOfQuota
        case .needsUpdate: return .needsUpdate
        case .failed(let e): return .failed(e)
        }
    }

    // POST /v1/ai/translate {text, source?, target} -> {translation}
    static func translate(_ text: String, target: String, source: String? = nil) async -> String? {
        guard isOn(.translate) else { return nil }
        var b: [String: Any] = ["text": text, "target": target]
        if let source { b["source"] = source }
        if case .ok(let o) = await call(.translate, "v1/ai/translate", b) { return (o["translation"] ?? o["text"]) as? String }
        return nil
    }

    // POST /v1/ai/link-check {url} -> {verdict: safe|suspicious|malicious, reason}
    static func checkLink(_ url: URL) async -> String {
        switch await call(.linkCheck, "v1/ai/link-check", ["url": url.absoluteString]) {
        case .ok(let o):
            let v = o["verdict"] as? String ?? "unknown"
            let reason = o["reason"] as? String ?? ""
            return "\(url.host() ?? "Link"): \(v)." + (reason.isEmpty ? "" : " \(reason)")
        case let other:
            // On-device fallback heuristics.
            let local = ScamHeuristic.verdict(url)
            return (note(other) ?? "") + " " + local
        }
    }

    struct Quota {
        var replies: Int?; var images: Int?; var minutes: Int?; var translations: Int?; var resets: String?
        var configured: Bool?; var geminiConfigured: Bool?; var workersConfigured: Bool?
    }

    // GET /v1/ai/quota -> {replies_left,..., gemini_configured, configured}
    static func quota() async -> Quota? {
        guard case .ok(let o) = await call(.chat, "v1/ai/quota", nil, method: "GET") else { return nil }
        func n(_ k: String) -> Int? { (o[k] as? Int) ?? (o[k] as? Double).map { Int($0) } }
        func b(_ k: String) -> Bool? { o[k] as? Bool }
        return Quota(replies: n("replies_left"), images: n("images_left"), minutes: n("transcribe_minutes_left"),
                     translations: n("translations_left"), resets: o["resets_at"] as? String,
                     configured: b("configured"), geminiConfigured: b("gemini_configured"),
                     workersConfigured: b("workers_ai_configured"))
    }

    /// Hard questions get escalated automatically when the on-device model declines or fails.
    /// Requires Cloud AI + chat feature on, and AI Preferences fallback allowed.
    static func shouldEscalate(_ onDevice: String) -> Bool {
        guard isOn(.chat), fallbackAllowed else { return false }
        let l = onDevice.lowercased()
        return onDevice.isEmpty || ["couldn't finish", "i can't help", "i don't know", "not sure", "can't answer", "i couldn't", "try asking another way", "hmm,"].contains { l.contains($0) }
    }
}

enum ScamHeuristic {
    static func verdict(_ u: URL) -> String {
        let h = (u.host() ?? "").lowercased()
        var flags: [String] = []
        if u.scheme == "http" { flags.append("not encrypted") }
        if h.range(of: #"^\d+\.\d+\.\d+\.\d+$"#, options: .regularExpression) != nil { flags.append("raw IP address") }
        if h.hasPrefix("xn--") || h.contains(".xn--") { flags.append("look-alike characters") }
        if ["bit.ly", "tinyurl.com", "t.co", "is.gd", "cutt.ly"].contains(h) { flags.append("shortened link hides the real site") }
        if ["gcash", "paypal", "apple", "bdo", "bpi", "metrobank", "maya"].contains(where: { h.contains($0) }) && h.split(separator: ".").count > 3 { flags.append("brand name in a long unusual address") }
        return flags.isEmpty ? "On this iPhone: no obvious warning signs." : "On this iPhone: be careful, " + flags.joined(separator: ", ") + "."
    }
}

struct CloudAISection: View {
    @State private var enabled = CloudAI.enabled
    @State private var refresh = 0
    @State private var quota: CloudAI.Quota?
    var body: some View {
        Section {
            Toggle("Cloud AI (uses server)", isOn: $enabled)
                .onChange(of: enabled) { _, v in
                    CloudAI.enabled = v
                    if v { CloudAI.fallbackAllowed = true }
                    Task { quota = await CloudAI.quota() }
                }
            if enabled {
                ForEach(CloudAI.Feature.allCases) { f in
                    Toggle(f.title, isOn: Binding(get: { _ = refresh; return CloudAI.isOn(f) }, set: { CloudAI.set(f, $0); refresh += 1 }))
                }
                if let q = quota {
                    Text(quotaText(q)).accessibilityLabel("Cloud AI left today: " + quotaText(q))
                } else {
                    Text("Checking what's left today…").foregroundStyle(.secondary)
                }
                if let last = UserDefaults.standard.string(forKey: "ai.cloud.lastProvider"), !last.isEmpty {
                    Text("Last reply provider: \(last)").font(.caption).foregroundStyle(.secondary)
                        .accessibilityLabel("Last Cloud AI reply used \(last)")
                }
            }
        } header: { Text("Cloud AI").accessibilityAddTraits(.isHeader) } footer: {
            Text("On by default for signed-in use. When on, only what you ask a cloud feature to handle is sent to api.mrblindbandit.net (Gemini when configured, Workers AI fallback). Encrypted chats are never sent unless you pick a cloud action on them. When the daily allowance runs out, the on-device AI takes over. Turn this off anytime.")
        }
        .task { if enabled { quota = await CloudAI.quota() } }
    }
    private func quotaText(_ q: CloudAI.Quota) -> String {
        var parts: [String] = []
        if q.geminiConfigured == true { parts.append("Gemini ready") }
        else if q.configured == true { parts.append("Cloud AI ready") }
        else if q.configured == false { parts.append("Cloud AI not configured on server") }
        if let r = q.replies { parts.append("\(r) replies left today") }
        if let i = q.images { parts.append("\(i) images left today") }
        if let m = q.minutes { parts.append("\(m) transcription minutes") }
        return parts.isEmpty ? "Quota unavailable" : parts.joined(separator: ", ")
    }
}

/// "Make an image" result sheet.
struct CloudImageSheet: View {
    let prompt: String
    @State private var image: UIImage?
    @State private var status = "Making your image…"
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if let image {
                    Image(uiImage: image).resizable().scaledToFit()
                        .accessibilityLabel("Generated image: \(prompt)")
                    ShareLink(item: Image(uiImage: image), preview: SharePreview(prompt, image: Image(uiImage: image))) {
                        Label("Share or send image", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    ProgressView(status).accessibilityLabel(status)
                }
            }
            .padding()
            .navigationTitle("Image")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .task {
            switch await CloudAI.image(prompt) {
            case .ok(let img): image = img; UIAccessibility.post(notification: .announcement, argument: "Image ready")
            case let o: status = CloudAI.note(o)?.replacingOccurrences(of: " so I used the on-device AI.", with: ".")
                .replacingOccurrences(of: " Used the on-device AI.", with: "") ?? "Couldn't make the image."
                UIAccessibility.post(notification: .announcement, argument: status)
            }
        }
    }
}
