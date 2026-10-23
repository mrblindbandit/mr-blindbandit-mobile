import SwiftUI
import UIKit
import LocalAuthentication
import CoreImage.CIFilterBuiltins

/// Chat info > Security & Privacy (SPEC §22: all 14 items). Shared settings sync through the server when the
/// route exists; otherwise the control is disabled with "Needs server update" and on-device settings still work.
struct SecurityPrivacyView: View {
    let chat: ChatRef
    let title: String
    var isAdmin = true
    @EnvironmentObject private var communications: ProductionCommunicationsService
    @ObservedObject private var e2ee = E2EEService.shared
    @State private var s = ChatSecuritySettings()
    @State private var loaded = false
    @State private var serverMissing = false
    @State private var status = ""
    @State private var confirmClear = false
    @State private var confirmDeleteMine = false
    @State private var exportURL: URL?
    @State private var aiAllowed = true
    @State private var mentionAllowed = true
    @State private var localLock = false

    private var handle: String? { if case .dm(_, let h) = chat { return h }; return nil }

    var body: some View {
        Form {
            if serverMissing {
                Section { Label(ServerFeatures.needsUpdateText + ": chat settings are stored on this iPhone until the server is updated.", systemImage: "exclamationmark.icloud") }
            }
            // 2. E2EE status / verify
            Section {
                HStack {
                    Label(e2ee.ready && !e2ee.plaintextPeers.contains(handle ?? "-") ? "End-to-end encrypted" : "Not encrypted yet",
                          systemImage: e2ee.ready ? "lock.fill" : "lock.open")
                    Spacer()
                    if let h = handle, e2ee.isVerified(h) { Text("Verified").foregroundStyle(.green) }
                }
                .accessibilityElement(children: .combine)
                if let h = handle {
                    NavigationLink { SafetyNumberView(handle: h) } label: { Label("Verify safety number", systemImage: "qrcode") }
                    if e2ee.keyChanges.contains(h.lowercased()) {
                        Label("@\(h)'s safety number changed. Verify before sending.", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    }
                }
                Toggle("End-to-end encryption", isOn: Binding(get: { s.e2ee }, set: { v in s.e2ee = v; e2ee.setE2EE(v, chatKey: chat.key); patch(["e2ee": v]) }))
                    .disabled(!isAdmin)
            } header: { Text("Encryption").accessibilityAddTraits(.isHeader) } footer: {
                Text(e2ee.ready ? "Messages are locked with keys that only your devices and theirs have. Keys sync with iCloud Keychain so a new iPhone restores automatically." :
                        "Encryption turns on automatically once the server supports it. \(ServerFeatures.shared.isAvailable(.keys) ? "" : ServerFeatures.needsUpdateText)")
            }

            // 3. Disappearing timers, 4. relay-only
            Section {
                Picker("Disappearing messages", selection: Binding(get: { s.disappearing_seconds }, set: { v in s.disappearing_seconds = v; patch(["disappearing_seconds": v]) })) {
                    ForEach(ChatSecuritySettings.timerOptions, id: \.seconds) { Text($0.label).tag($0.seconds) }
                }
                .disabled(!isAdmin)
                Toggle("Relay-only (never stored on the server)", isOn: Binding(get: { s.no_store }, set: { v in s.no_store = v; patch(["no_store": v]) }))
                    .disabled(!isAdmin || !s.e2ee)
                    .accessibilityHint("Messages pass through the server only until your devices pick them up, then they're deleted.")
            } header: { Text("Messages").accessibilityAddTraits(.isHeader) }

            // 6. Screenshot alerts, 9. link previews, 10. metadata, 11. view once
            Section {
                Toggle("Screenshot and recording alerts", isOn: sec(\.screenshot_alerts, "screenshot_alerts"))
                Toggle("Block link previews", isOn: sec(\.block_link_previews, "block_link_previews"))
                Toggle("Strip photo location and metadata", isOn: sec(\.strip_photo_metadata, "strip_photo_metadata"))
                Toggle("Allow view-once photos and listen-once voice", isOn: sec(\.allow_view_once, "allow_view_once"))
            } header: { Text("Chat protections").accessibilityAddTraits(.isHeader) }

            // 7. Face ID lock, 8. hide previews, 12. receipts/typing
            Section {
                Toggle("Lock this chat with Face ID", isOn: Binding(get: { localLock }, set: { v in
                    localLock = v; ChatLock.set(chat.key, v); s.my.chat_lock = v; patch(["my": ["chat_lock": v]])
                }))
                Toggle("Hide notification previews", isOn: my(\.hide_previews, "hide_previews"))
                Toggle("Send read receipts", isOn: my(\.read_receipts, "read_receipts"))
                Toggle("Send typing indicator", isOn: my(\.typing, "typing"))
                Toggle("Auto-translate", isOn: my(\.translate, "translate"))
                Toggle("Mute notification sound", isOn: my(\.mute_sound, "mute_sound"))
            } header: { Text("Just for me").accessibilityAddTraits(.isHeader) }

            Section {
                Toggle(chat.isGroup ? "Allow AI in this group (admin)" : "Allow AI in this chat", isOn: Binding(get: { s.allow_ai }, set: { v in
                    s.allow_ai = v; patch(["allow_ai": v]); applyServerAI()
                    if chat.isGroup { Task { await sendAIPolicy(v) } }
                }))
                .disabled(chat.isGroup && !isAdmin)
                .accessibilityHint("Saved for everyone in this chat. When off, summaries, smart replies and @AI stay off here.")
                Toggle("On-device AI in this chat", isOn: Binding(get: { aiAllowed }, set: { v in aiAllowed = v; AISettings.setChat(chat.key, v) }))
                    .disabled(!s.allow_ai)
                Toggle(chat.isGroup ? "Allow @AI for everyone (admin)" : "Allow @AI", isOn: Binding(get: { mentionAllowed }, set: { v in
                    mentionAllowed = v
                    AIAssistant.setAllowed(v, chatKey: chat.key)
                    if chat.isGroup { Task { await sendAIPolicy(v) } }
                }))
                .disabled(chat.isGroup && !isAdmin)
            } header: { Text("On-device AI").accessibilityAddTraits(.isHeader) } footer: {
                Text("Summaries, smart replies, descriptions and @AI run only on this iPhone. Nothing is sent to a server.")
            }

            if chat.isGroup, isAdmin {
                Section {
                    Picker("Slow mode", selection: Binding(get: { s.group?.slow_mode_seconds ?? 0 }, set: { v in
                        var g = s.group ?? .init(); g.slow_mode_seconds = v; s.group = g; patch(["slow_mode_seconds": v, "group": ["slow_mode_seconds": v]]) })) {
                        ForEach([0, 10, 30, 60, 300, 900, 3600], id: \.self) { v in Text(v == 0 ? "Off" : v < 60 ? "\(v) seconds" : v < 3600 ? "\(v / 60) minutes" : "1 hour").tag(v) }
                    }
                    Toggle("Only admins can post", isOn: Binding(get: { s.group?.admins_only_post ?? false }, set: { v in
                        var g = s.group ?? .init(); g.admins_only_post = v; s.group = g; patch(["admins_only_post": v, "group": ["admins_only_post": v]]) }))
                    Toggle("Approve new members from invite links", isOn: Binding(get: { s.group?.require_approval ?? false }, set: { v in
                        var g = s.group ?? .init(); g.require_approval = v; s.group = g; patch(["require_approval": v, "group": ["require_approval": v]]) }))
                    if case .group(let gid) = chat {
                        NavigationLink { InviteLinksView(groupID: gid) } label: { Label("Invite links and join requests", systemImage: "link") }
                    }
                } header: { Text("Group admin").accessibilityAddTraits(.isHeader) }
            }

            // 1. Clear from server, 13. export / delete mine, 14. report/block, security log
            Section {
                Button("Clear this chat from the server", role: .destructive) { confirmClear = true }
                    .disabled(!ServerFeatures.shared.isAvailable(.clearServer))
                Button("Export my data from this chat") { Task { await export() } }
                    .disabled(!ServerFeatures.shared.isAvailable(.export))
                if let exportURL { ShareLink(item: exportURL) { Label("Share export file", systemImage: "square.and.arrow.up") } }
                Button("Delete all my messages in this chat", role: .destructive) { confirmDeleteMine = true }
                    .disabled(!ServerFeatures.shared.isAvailable(.deleteMine))
                NavigationLink { SecurityLogView(chat: chat) } label: { Label("Security log", systemImage: "list.bullet.rectangle") }
                if let h = handle {
                    Button("Block @\(h)", role: .destructive) { Task { _ = await communications.block(handle: h) } }
                }
            } header: { Text("Data").accessibilityAddTraits(.isHeader) } footer: {
                Text("Unsend is one tap on any of your messages and removes it for everyone, with no time limit.")
            }
            if !status.isEmpty { Section { Text(status).accessibilityAddTraits(.updatesFrequently) } }
        }
        .navigationTitle("Security & Privacy")
        .task { await load() }
        .confirmationDialog("Delete every message, photo and reaction in this chat from the server, for everyone? Copies already on devices stay until those people delete them.", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear from server", role: .destructive) { Task { await run("Chat cleared from the server.") { try await SecurityAPI.clearServer(chat, scope: chat.isGroup ? (isAdmin ? "all" : "mine") : nil) } } }
        }
        .confirmationDialog("Delete every message you sent in this chat, for everyone?", isPresented: $confirmDeleteMine, titleVisibility: .visible) {
            Button("Delete my messages", role: .destructive) { Task { await run("Your messages were deleted.") { try await SecurityAPI.deleteMine(chat) } } }
        }
    }

    private func sec(_ kp: WritableKeyPath<ChatSecuritySettings.Security, Bool>, _ key: String) -> Binding<Bool> {
        Binding(get: { s.security[keyPath: kp] }, set: { v in s.security[keyPath: kp] = v; patch([key: v, "security": [key: v]]) })
    }
    private func my(_ kp: WritableKeyPath<ChatSecuritySettings.Mine, Bool>, _ key: String) -> Binding<Bool> {
        Binding(get: { s.my[keyPath: kp] }, set: { v in s.my[keyPath: kp] = v; patch(["my": [key: v]]) })
    }

    private func load() async {
        aiAllowed = AISettings.chatAllowed(chat.key)
        mentionAllowed = AIAssistant.allowed(chatKey: chat.key)
        localLock = ChatLock.isLocked(chat.key)
        if let cached = ChatSettingsCache.get(chat.key) { s = cached }
        do {
            s = try await SecurityAPI.settings(chat)
            serverMissing = false
        } catch is NeedsServerUpdate { serverMissing = true } catch {}
        e2ee.setE2EE(s.e2ee, chatKey: chat.key)
        ChatSettingsCache.set(s, chat.key)
        applyServerAI()
        loaded = true
    }

    /// allow_ai = false from the server wins over the local AI switches.
    private func applyServerAI() {
        guard !s.allow_ai else { return }
        aiAllowed = false; AISettings.setChat(chat.key, false)
        mentionAllowed = false; AIAssistant.setAllowed(false, chatKey: chat.key)
    }

    private func patch(_ body: [String: Any]) {
        AppHaptics.selection()
        ChatSettingsCache.set(s, chat.key)
        guard loaded else { return }
        Task {
            do { try await SecurityAPI.patchSettings(chat, body); status = "" }
            catch is NeedsServerUpdate { serverMissing = true }
            catch { status = error.localizedDescription; UIAccessibility.post(notification: .announcement, argument: status) }
        }
    }

    private func run(_ done: String, _ work: () async throws -> Void) async {
        do { try await work(); status = done; AppHaptics.success() } catch { status = error.localizedDescription; AppHaptics.error() }
        UIAccessibility.post(notification: .announcement, argument: status)
    }

    private func export() async {
        do {
            let data = try await SecurityAPI.export(chat)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("blindbandit-export-\(Int(Date().timeIntervalSince1970)).json")
            try data.write(to: url)
            exportURL = url
            status = "Export ready. Use Share export file."
        } catch { status = error.localizedDescription }
        UIAccessibility.post(notification: .announcement, argument: status)
    }

    private func sendAIPolicy(_ on: Bool) async {
        guard case .group(let gid) = chat else { return }
        _ = try? await E2EEService.shared.sendGroup(id: gid, payload: E2EEPayload(t: "ai_policy", body: on ? "on" : "off", target_msg_id: chat.key))
    }
}

/// Per-chat Face ID lock (on device).
enum ChatLock {
    static func isLocked(_ key: String) -> Bool { (UserDefaults.standard.stringArray(forKey: "chatLock") ?? []).contains(key) }
    static func set(_ key: String, _ on: Bool) {
        var s = Set(UserDefaults.standard.stringArray(forKey: "chatLock") ?? [])
        if on { s.insert(key) } else { s.remove(key) }
        UserDefaults.standard.set(Array(s), forKey: "chatLock")
    }
    static func authenticate(reason: String) async -> Bool {
        let ctx = LAContext()
        return (try? await ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) ?? false
    }
}

struct ChatLockGate<Content: View>: View {
    let chatKey: String
    @ViewBuilder let content: () -> Content
    @State private var unlocked = false
    var body: some View {
        if !ChatLock.isLocked(chatKey) || unlocked { content() } else {
            VStack(spacing: 16) {
                Image(systemName: "lock.fill").font(.largeTitle).accessibilityHidden(true)
                Text("This chat is locked").font(.headline)
                Button("Unlock with Face ID") { Task { unlocked = await ChatLock.authenticate(reason: "Unlock this chat") } }
                    .buttonStyle(.borderedProminent)
            }
            .task { unlocked = await ChatLock.authenticate(reason: "Unlock this chat") }
        }
    }
}

/// Screenshot / screen-recording alerts (§22.6).
@MainActor
final class ScreenCaptureMonitor: ObservableObject {
    private var tokens: [NSObjectProtocol] = []
    func start(chat: ChatRef) {
        stop()
        let nc = NotificationCenter.default
        tokens.append(nc.addObserver(forName: UIApplication.userDidTakeScreenshotNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in await SecurityAPI.postSecurityEvent(chat, type: "screenshot") }
        })
        tokens.append(nc.addObserver(forName: UIScreen.capturedDidChangeNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in
                let captured = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.screen.isCaptured }.contains(true)
                await SecurityAPI.postSecurityEvent(chat, type: captured ? "screen_recording_started" : "screen_recording_stopped")
            }
        })
    }
    func stop() { tokens.forEach(NotificationCenter.default.removeObserver); tokens = [] }
}

struct SafetyNumberView: View {
    let handle: String
    var displayName: String? = nil
    @ObservedObject private var e2ee = E2EEService.shared
    @State private var number: SafetyNumber?
    @State private var loaded = false
    @State private var scanning = false
    @State private var result = ""

    private var name: String { displayName.flatMap { $0.isEmpty ? nil : $0 } ?? "@\(handle)" }

    var body: some View {
        List {
            if let n = number {
                Section {
                    Text(n.display).font(.system(.title3, design: .monospaced))
                        .accessibilityLabel(SafetyNumberSpeech.paused(n))
                        .accessibilityHint("Reads all 12 groups of five digits with a pause between groups.")
                    ForEach(Array(n.groups.enumerated()), id: \.offset) { i, _ in
                        Text(n.spokenGroup(i)).accessibilityLabel(n.spokenGroup(i))
                    }
                    if let img = qr(n.qrPayload) {
                        Image(uiImage: img).interpolation(.none).resizable().scaledToFit().frame(maxWidth: 220)
                            .accessibilityLabel("QR code of your security number with \(name). Ask them to scan it.")
                    }
                } header: { Text("Security number with \(name)").accessibilityAddTraits(.isHeader) } footer: {
                    Text("Compare these 60 digits with \(name) in person or on a call. VoiceOver reads them in groups of five.")
                }
                Section {
                    Toggle(isOn: Binding(get: { e2ee.isVerified(handle) }, set: { on in
                        e2ee.setVerified(handle, on)
                        UIAccessibility.post(notification: .announcement, argument: on ? "\(name) marked as verified." : "Verification removed.")
                        AppHaptics.success()
                    })) { Label("Mark as verified", systemImage: "checkmark.shield") }
                    Button { scanning = true } label: { Label("Scan their QR code", systemImage: "qrcode.viewfinder") }
                    Button {
                        UIPasteboard.general.string = n.display
                        UIAccessibility.post(notification: .announcement, argument: "Security number copied.")
                    } label: { Label("Copy", systemImage: "doc.on.doc") }
                    ShareLink(item: "Our Mr. BlindBandit security number: \(n.display)") { Label("Share", systemImage: "square.and.arrow.up") }
                    if !result.isEmpty { Text(result) }
                }
            } else if loaded {
                Section {
                    if !e2ee.ready {
                        Text("Your encryption keys are still being set up. The app retries automatically.")
                        Text(KeySetupLog.last).font(.footnote).foregroundStyle(.secondary)
                    } else {
                        Text("\(name) needs to open the latest app to set up encryption.")
                    }
                    Button("Check again") { Task { await load(force: true) } }
                }
            } else {
                ProgressView("Loading security number…")
            }
        }
        .navigationTitle("Security number")
        .task { await load(force: false) }
        .sheet(isPresented: $scanning) {
            QRScannerView { code in
                scanning = false
                if let n = number, n.matches(scanned: code) {
                    e2ee.setVerified(handle, true)
                    result = "Match. \(name) is verified."
                    AppHaptics.success()
                } else {
                    result = "Doesn't match. Don't trust this chat until you've checked with \(name)."
                    AppHaptics.error()
                }
                UIAccessibility.post(notification: .announcement, argument: result)
            }
        }
    }

    private func load(force: Bool) async {
        if force { _ = try? await e2ee.devices(for: handle, force: true) }
        number = await e2ee.safetyNumber(with: handle)
        loaded = true
    }

    private func qr(_ s: String) -> UIImage? {
        let f = CIFilter.qrCodeGenerator()
        f.message = Data(s.utf8)
        guard let out = f.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)),
              let cg = CIContext().createCGImage(out, from: out.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

struct SecurityLogView: View {
    let chat: ChatRef
    @State private var events: [SecurityEvent] = []
    @State private var note = ""
    var body: some View {
        List {
            if !note.isEmpty { Text(note) }
            ForEach(events) { e in
                VStack(alignment: .leading) {
                    Text(e.readable)
                    Text(Date(timeIntervalSince1970: e.created_at > 100_000_000_000 ? e.created_at / 1000 : e.created_at).formatted()).font(.caption).foregroundStyle(.secondary)
                }.accessibilityElement(children: .combine)
            }
        }
        .navigationTitle("Security log")
        .task {
            do { events = try await SecurityAPI.securityEvents(chat); note = events.isEmpty ? "No security events yet." : "" }
            catch is NeedsServerUpdate { note = ServerFeatures.needsUpdateText }
            catch { note = error.localizedDescription }
        }
    }
}

struct InviteLinksView: View {
    let groupID: String
    @State private var link: String?
    @State private var requests: [JoinRequest] = []
    @State private var note = ""
    var body: some View {
        List {
            Section {
                Button("Create invite link") { Task {
                    do { link = try await SecurityAPI.createInviteLink(groupID: groupID) } catch { note = error.localizedDescription }
                } }
                if let link { ShareLink(item: link) { Label(link, systemImage: "link") } }
            }
            Section("Join requests") {
                if requests.isEmpty { Text("No pending requests.") }
                ForEach(requests) { r in
                    HStack {
                        Text(r.display_name ?? "@\(r.handle)")
                        Spacer()
                        Button("Approve") { answer(r, true) }.buttonStyle(.borderless)
                        Button("Decline", role: .destructive) { answer(r, false) }.buttonStyle(.borderless)
                    }.accessibilityElement(children: .contain)
                }
            }
            if !note.isEmpty { Text(note) }
        }
        .navigationTitle("Invite links")
        .task { await reload() }
    }
    private func reload() async {
        do { requests = try await SecurityAPI.joinRequests(groupID: groupID) } catch is NeedsServerUpdate { note = ServerFeatures.needsUpdateText } catch {}
    }
    private func answer(_ r: JoinRequest, _ ok: Bool) {
        Task {
            try? await SecurityAPI.answerJoinRequest(groupID: groupID, requestID: r.id, approve: ok)
            UIAccessibility.post(notification: .announcement, argument: ok ? "Approved" : "Declined")
            await reload()
        }
    }
}


enum SafetyNumberSpeech {
    /// "12345, 67890, …" — the commas and periods make VoiceOver pause between groups.
    static func paused(_ n: SafetyNumber) -> String {
        n.groups.map { $0.map(String.init).joined(separator: " ") }.joined(separator: ". ")
    }
}

/// Per-member security numbers for a group chat.
struct GroupSafetyNumbersView: View {
    let members: [(handle: String, name: String)]
    @ObservedObject private var e2ee = E2EEService.shared
    var body: some View {
        List(members, id: \.handle) { m in
            NavigationLink { SafetyNumberView(handle: m.handle, displayName: m.name) } label: {
                HStack {
                    Text(m.name)
                    if e2ee.isVerified(m.handle) { Image(systemName: "checkmark.shield.fill").foregroundStyle(.green).accessibilityHidden(true) }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(m.name + (e2ee.isVerified(m.handle) ? ", verified" : ", not verified"))
            }
        }
        .navigationTitle("Security numbers")
    }
}
