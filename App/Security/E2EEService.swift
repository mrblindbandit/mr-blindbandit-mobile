import Foundation
import UIKit
#if canImport(CryptoKit)
import CryptoKit
#endif

/// Coordinates keys, encryption and the plaintext cache. Every server call is gated: when the key routes are
/// missing, messages keep going out the old plaintext way and old plaintext chats keep working.
@MainActor
final class E2EEService: ObservableObject {
    static let shared = E2EEService()

    @Published private(set) var ready = false
    @Published private(set) var keyChanges: Set<String> = []
    @Published private(set) var plaintextPeers: Set<String> = []
    @Published var lastStatus = ""

    var myUserID = ""
    private(set) var myHandle = ""
    private(set) var identity: E2EELocalIdentity?
    private let storage = KeychainSessionStorage.shared
    private let store = LocalMessageStore.shared
    private var bundleCache: [String: (at: Date, devices: [E2EEDeviceBundle])] = [:]
    private var groupMembers: [String: (at: Date, handles: [String])] = [:]
    private let knownKeysKey = "e2ee.knownSignKeys"
    private let verifiedKey = "e2ee.verified"
    private let disabledKey = "e2ee.disabledChats"

    var mySignPub: String? { identity.map { E2EECrypto.b64u($0.signPub) } }

    // MARK: Bootstrap

    func bootstrap(handle: String) async {
        myHandle = handle.lowercased()
        SharedKeychainMigration.run()
        UserDefaults(suiteName: "group.net.mrblindbandit.app")?.set(myHandle, forKey: "myHandle")
        guard let id = IdentityStore.shared.identity(handle: handle) else { return }
        identity = id
        guard ServerFeatures.shared.isAvailable(.keys) else { return }
        do {
            try await registerIfNeeded(id)
            try await replenishPrekeys(id)
            ready = true
            if IdentityStore.shared.restoredFromICloud {
                lastStatus = "Your encryption keys were restored from iCloud Keychain."
                UIAccessibility.post(notification: .announcement, argument: lastStatus)
            }
        } catch {
            ready = false
        }
    }

    private func spkPayload(_ s: IdentityStore.PrekeyState, _ id: E2EELocalIdentity) throws -> [String: Any] {
        let priv = try P256.KeyAgreement.PrivateKey(rawRepresentation: try E2EECrypto.unb64u(s.spk))
        let pub = priv.publicKey.x963Representation
        let sig = try E2EECrypto.sign(pub, with: id.sign)
        return ["id": s.spkID, "pub": E2EECrypto.b64u(pub), "sig": E2EECrypto.b64u(sig)]
    }

    private func opkPayload(_ items: [(Int, String)]) -> [[String: Any]] {
        items.compactMap { idx, raw in
            guard let d = try? E2EECrypto.unb64u(raw), let k = try? P256.KeyAgreement.PrivateKey(rawRepresentation: d) else { return nil }
            return ["id": idx, "pub": E2EECrypto.b64u(k.publicKey.x963Representation)]
        }
    }

    private func registerIfNeeded(_ id: E2EELocalIdentity) async throws {
        guard var s = IdentityStore.shared.prekeys() else { return }
        if s.uploaded {
            if let rotated = IdentityStore.shared.rotateSignedPrekeyIfNeeded() {
                let body = try spkPayload(rotated, id)
                try await SecurityAPI.gated(.keys) {
                    try await BlindbanditAPI.request("v1/social/keys/devices/\(ChatRef.escape(id.deviceID))/signed-prekey", method: "PUT", body: body)
                }
            }
            return
        }
        let body: [String: Any] = [
            "device_id": id.deviceID, "platform": "ios", "name": UIDevice.current.name, "suite": E2EECrypto.suite,
            "identity_sign_pub": E2EECrypto.b64u(id.signPub), "identity_dh_pub": E2EECrypto.b64u(id.dhPub),
            "signed_prekey": try spkPayload(s, id),
            "prekeys": opkPayload(s.opks.sorted { $0.key < $1.key }.map { ($0.key, $0.value) })
        ]
        try await SecurityAPI.gated(.keys) { try await BlindbanditAPI.request("v1/social/keys/devices", method: "POST", body: body) }
        s.uploaded = true
        IdentityStore.shared.savePrekeys(s)
    }

    private func replenishPrekeys(_ id: E2EELocalIdentity) async throws {
        let d = try await SecurityAPI.gated(.keys) {
            try await BlindbanditAPI.request("v1/social/keys/devices/\(ChatRef.escape(id.deviceID))/prekeys/count")
        }
        let count = SecurityAPI.data(d)["count"] as? Int ?? 100
        guard count < 20, var s = IdentityStore.shared.prekeys() else { return }
        var fresh: [(Int, String)] = []
        for _ in 0..<100 {
            let raw = E2EECrypto.b64u(P256.KeyAgreement.PrivateKey().rawRepresentation)
            s.opks[s.nextOPK] = raw; fresh.append((s.nextOPK, raw)); s.nextOPK += 1
        }
        IdentityStore.shared.savePrekeys(s)
        let body: [String: Any] = ["prekeys": opkPayload(fresh)]
        try await SecurityAPI.gated(.keys) {
            try await BlindbanditAPI.request("v1/social/keys/devices/\(ChatRef.escape(id.deviceID))/prekeys", method: "POST", body: body)
        }
    }

    // MARK: Directory + TOFU

    func devices(for handle: String, force: Bool = false) async throws -> [E2EEDeviceBundle] {
        let h = handle.lowercased()
        if !force, let c = bundleCache[h], Date().timeIntervalSince(c.at) < 600 { return c.devices }
        let d = try await SecurityAPI.gated(.keys) { try await BlindbanditAPI.request("v1/social/keys/bundles/\(ChatRef.escape(h))") }
        let list = (SecurityAPI.data(d)["devices"] as? [[String: Any]] ?? []).compactMap { obj -> E2EEDeviceBundle? in
            guard let j = try? JSONSerialization.data(withJSONObject: obj), var b = try? JSONDecoder().decode(E2EEDeviceBundle.self, from: j) else { return nil }
            b.handle = h
            return (try? X3DH.verifyBundle(b)) != nil ? b : nil
        }
        bundleCache[h] = (Date(), list)
        if h != "me" { checkKeyChange(handle: h, signPubs: Set(list.map(\.identity_sign_pub))) }
        return list
    }

    func knownSignPubs(_ handle: String) -> [String] {
        (UserDefaults.standard.dictionary(forKey: knownKeysKey)?[handle.lowercased()] as? [String]) ?? []
    }

    private func checkKeyChange(handle: String, signPubs: Set<String>) {
        guard !signPubs.isEmpty else { return }
        var all = UserDefaults.standard.dictionary(forKey: knownKeysKey) ?? [:]
        let known = Set((all[handle] as? [String]) ?? [])
        if !known.isEmpty && !signPubs.isSubset(of: known) {
            keyChanges.insert(handle)
            setVerified(handle, false)
            let msg = "@\(handle)'s safety number changed. Verify before sending."
            lastStatus = msg
            UIAccessibility.post(notification: .announcement, argument: msg)
            AppHaptics.warning()
        }
        all[handle] = Array(signPubs.union(known)).sorted()
        UserDefaults.standard.set(all, forKey: knownKeysKey)
    }

    func acknowledgeKeyChange(_ handle: String) { keyChanges.remove(handle.lowercased()) }

    func isVerified(_ handle: String) -> Bool {
        (UserDefaults.standard.dictionary(forKey: verifiedKey)?[handle.lowercased()] as? Bool) ?? false
    }

    func setVerified(_ handle: String, _ value: Bool) {
        var all = UserDefaults.standard.dictionary(forKey: verifiedKey) ?? [:]
        all[handle.lowercased()] = value
        UserDefaults.standard.set(all, forKey: verifiedKey)
        if value { keyChanges.remove(handle.lowercased()) }
        objectWillChange.send()
    }

    func safetyNumber(with handle: String) async -> SafetyNumber? {
        guard let mine = mySignPub else { return nil }
        _ = try? await devices(for: handle)
        let theirs = knownSignPubs(handle)
        guard !theirs.isEmpty else { return nil }
        guard let mineData = try? E2EECrypto.unb64u(mine) else { return nil }
        return SafetyNumber(myHandle: myHandle, mySignPubs: [mineData], theirHandle: handle,
                            theirSignPubs: theirs.compactMap { try? E2EECrypto.unb64u($0) })
    }

    // MARK: Per-chat E2EE switch (cached from settings)

    func setE2EE(_ on: Bool, chatKey: String) {
        var s = Set(UserDefaults.standard.stringArray(forKey: disabledKey) ?? [])
        if on { s.remove(chatKey) } else { s.insert(chatKey) }
        UserDefaults.standard.set(Array(s), forKey: disabledKey)
    }
    func isE2EEDisabled(_ chatKey: String) -> Bool { (UserDefaults.standard.stringArray(forKey: disabledKey) ?? []).contains(chatKey) }

    // MARK: Sending

    private func recipients(handles: [String]) async throws -> [E2EEDeviceBundle] {
        var all: [E2EEDeviceBundle] = []
        for h in Set(handles.map { $0.lowercased() }) where h != myHandle {
            let list = try await devices(for: h)
            if list.isEmpty { plaintextPeers.insert(h); return [] }
            plaintextPeers.remove(h)
            all += list
        }
        if let mine = try? await devices(for: "me") { all += mine.filter { $0.device_id != identity?.deviceID } }
        return Array(all.prefix(64))
    }

    private func stamp(_ p: E2EEPayload, chatKey: String) -> E2EEPayload {
        var p = p
        p.sent_at = Int(Date().timeIntervalSince1970 * 1000)
        if p.expires_in == nil, let s = ChatSettingsCache.get(chatKey)?.disappearing_seconds, s > 0 { p.expires_in = s }
        return p
    }

    /// Sends an encrypted DM. Returns nil when E2EE can't be used (server not updated, peer has no keys, E2EE off) so the
    /// caller sends the classic plaintext message instead.
    func sendDM(handle: String, payload: E2EEPayload, viewOnce: Bool = false, chatKey: String? = nil) async throws -> BlindbanditMessageResponse? {
        guard ready, let id = identity, ServerFeatures.shared.isAvailable(.keys) else { return nil }
        let key = chatKey ?? "dmh:\(handle.lowercased())"
        if isE2EEDisabled(key) { return nil }
        let devs: [E2EEDeviceBundle]
        do { devs = try await recipients(handles: [handle]) } catch is NeedsServerUpdate { return nil }
        guard !devs.isEmpty else { return nil }
        let p = stamp(payload, chatKey: key)
        let env = try MessageCrypto.encrypt(p, local: id, recipients: devs, storage: storage)
        store.store(p, msgID: env.msg_id, sender: myHandle, expiresIn: p.expires_in)
        var body: [String: Any] = ["handle": handle, "e2ee": true, "envelope": env.jsonObject, "client_msg_id": env.msg_id]
        if viewOnce { body["view_once"] = true }
        if p.silent == true { body["silent"] = true }
        let d = try await BlindbanditAPI.request("v1/social/messages", method: "POST", body: body)
        return try BlindbanditAPI.decode(BlindbanditMessageResponse.self, from: d)
    }

    func members(groupID: String) async -> [String] {
        if let c = groupMembers[groupID], Date().timeIntervalSince(c.at) < 600 { return c.handles }
        guard let detail = try? await BlindbanditAPI.groupDetail(id: groupID) else { return [] }
        let handles = detail.members.map(\.handle).filter { !$0.isEmpty }
        groupMembers[groupID] = (Date(), handles)
        return handles
    }

    /// Pairwise fan-out for groups (≤ 64 devices). Returns false when the caller should fall back to plaintext.
    func sendGroup(id groupID: String, payload: E2EEPayload, viewOnce: Bool = false) async throws -> Bool {
        guard ready, let id = identity, ServerFeatures.shared.isAvailable(.keys), !isE2EEDisabled("group:\(groupID)") else { return false }
        let handles = await members(groupID: groupID)
        guard !handles.isEmpty else { return false }
        let devs: [E2EEDeviceBundle]
        do { devs = try await recipients(handles: handles) } catch is NeedsServerUpdate { return false }
        guard !devs.isEmpty else { return false }
        let p = stamp(payload, chatKey: "group:\(groupID)")
        let env = try MessageCrypto.encrypt(p, local: id, recipients: devs, storage: storage)
        store.store(p, msgID: env.msg_id, sender: myHandle, expiresIn: p.expires_in)
        var body: [String: Any] = ["e2ee": true, "envelope": env.jsonObject, "client_msg_id": env.msg_id]
        if viewOnce { body["view_once"] = true }
        if p.silent == true { body["silent"] = true }
        try await BlindbanditAPI.request("v1/social/groups/\(ChatRef.escape(groupID))/messages", method: "POST", body: body)
        return true
    }

    /// One-tap unsend for everyone: server delete + signed E2EE delete control so other devices drop their copy.
    func unsend(chat: ChatRef, serverID: String, envelopeMsgID: String?) async throws {
        try await SecurityAPI.unsend(chat, messageID: serverID)
        store.forget(serverID)
        if let mid = envelopeMsgID {
            store.forget(mid)
            if let id = identity, let control = try? MessageCrypto.deletePayload(target: mid, local: id) {
                switch chat {
                case .dm(_, let handle): _ = try? await sendDM(handle: handle, payload: control)
                case .group(let gid): _ = try? await sendGroup(id: gid, payload: control)
                }
            }
        }
    }

    /// Edit = PATCH the row with a fresh envelope (new msg_id).
    func edit(chat: ChatRef, serverID: String, newText: String, oldMsgID: String?) async throws {
        guard let id = identity else { throw NeedsServerUpdate(feature: .edit) }
        var handles: [String]
        switch chat { case .dm(_, let h): handles = [h]; case .group(let g): handles = await members(groupID: g) }
        let devs = try await recipients(handles: handles)
        var p = stamp(E2EEPayload(t: "text", body: newText), chatKey: chat.key)
        if let old = oldMsgID, let prior = store.payload(old) { p.reply_to = prior.reply_to }
        let env = try MessageCrypto.encrypt(p, local: id, recipients: devs, storage: storage)
        store.store(p, msgID: env.msg_id, sender: myHandle, expiresIn: p.expires_in)
        try await SecurityAPI.edit(chat, messageID: serverID, envelope: env)
    }

    // MARK: Receiving

    /// Decrypts (or reads from the cache) every E2EE row, applies control messages and hides expired/unsent rows.
    func decryptPayload(_ env: E2EEEnvelope) -> (E2EEPayload, String?)? {
        if let cached = store.payload(env.msg_id) { return (cached, store.snapshot.senders[env.msg_id]) }
        guard let id = identity, let out = try? MessageCrypto.decrypt(env, local: id, storage: storage) else { return nil }
        let signer = out.senderSignPub
        let handle: String? = nil
        apply(out.payload, signerPub: signer, senderHandle: handle)
        store.store(out.payload, msgID: env.msg_id, sender: handle, expiresIn: out.payload.expires_in)
        return (out.payload, handle)
    }

    private func apply(_ p: E2EEPayload, signerPub: String?, senderHandle: String?) {
        switch p.t {
        case "delete":
            guard let target = p.target_msg_id, let pub = signerPub, MessageCrypto.verifyDelete(p, senderSignPubs: [pub]) else { return }
            // Only the original sender may delete: the signer must have sent the target (or we never saw it).
            store.forget(target)
        case "ai_policy":
            if let chat = p.target_msg_id { AIAssistant.setAllowed(p.body != "off", chatKey: chat) }
        case "vote":
            guard let target = p.target_msg_id else { return }
            let voter = senderHandle ?? signerPub ?? "?"
            store.mutate { $0.votes[target, default: [:]][voter] = p.vote ?? [] }
        default: break
        }
    }

    static func isControl(_ p: E2EEPayload) -> Bool { ["delete", "vote", "reaction", "receipt", "ai_policy"].contains(p.t) }

    static func display(_ p: E2EEPayload) -> String {
        switch p.t {
        case "poll": return "📊 Poll: \(p.poll?.question ?? "")" + (p.poll.map { "\n" + $0.options.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n") } ?? "")
        case "image", "media", "file", "voice", "video":
            let kind = p.media?.mime.hasPrefix("audio") == true ? "🎤 Voice message" : p.media?.mime.hasPrefix("image") == true ? "📷 Photo" : "📎 Attachment"
            return [kind, p.media?.caption, p.media?.alt.map { "Description: \($0)" }, p.media?.transcript.map { "Transcript: \($0)" }]
                .compactMap { $0 }.joined(separator: "\n")
        case "ai": return "🤖 AI (via @\(p.ai_via ?? "someone")): " + (p.body ?? "")
        default: return p.body ?? ""
        }
    }

    static let undecryptable = "🔒 Couldn't decrypt this message on this device."

    func resolve(_ items: [BlindbanditServerMessage], conversationID: String) async -> [BlindbanditServerMessage] {
        store.purgeExpired()
        let now = Date().timeIntervalSince1970
        var out: [BlindbanditServerMessage] = []
        for var m in items {
            if store.isDeleted(m.id) { continue }
            if let e = m.expires_at, (e > 100_000_000_000 ? e / 1000 : e) <= now { continue }
            if m.e2ee, let env = m.envelope {
                if store.isDeleted(env.msg_id) { continue }
                if let (p, _) = decryptPayload(env) {
                    if Self.isControl(p) { continue }
                    m.decrypted = p
                    m.body = Self.display(p)
                } else {
                    m.decryptFailed = true
                    m.body = Self.undecryptable
                }
            } else if m.e2ee && m.view_once {
                m.body = m.opened_at == nil ? "👁 View-once message. Double-tap to open." : "👁 Opened"
            }
            out.append(m)
        }
        // Relay-only messages live on this device only.
        for r in store.snapshot.relay["dm:\(conversationID)"] ?? [] where !store.isDeleted(r.msgID) {
            guard let p = store.payload(r.msgID) else { continue }
            var m = BlindbanditServerMessage(id: r.id, sender_id: r.senderID, body: Self.display(p), created_at: r.createdAt)
            m.e2ee = true; m.decrypted = p
            out.append(m)
        }
        return out.sorted { $0.created_at < $1.created_at }
    }

    func resolveGroup(_ items: [BlindbanditGroupMessage], groupID: String) -> [BlindbanditGroupMessage] {
        store.purgeExpired()
        var out: [BlindbanditGroupMessage] = []
        for var m in items {
            if store.isDeleted(m.id) { continue }
            if m.e2ee, let env = m.envelope {
                if store.isDeleted(env.msg_id) { continue }
                if let (p, _) = decryptPayload(env) {
                    if Self.isControl(p) { continue }
                    m.decrypted = p; m.body = Self.display(p)
                } else { m.body = Self.undecryptable }
            }
            out.append(m)
        }
        return out
    }

    /// Relay-only mode: fetch, decrypt, keep on device, ack (deletes from the server).
    func pollRelay() async {
        guard ready, let id = identity, ServerFeatures.shared.isAvailable(.relay) else { return }
        guard let items = try? await SecurityAPI.relayPending(), !items.isEmpty else { return }
        var acked: [String] = []
        for item in items {
            acked.append(item.id)
            guard let env = item.envelope, decryptPayload(env) != nil, let p = store.payload(env.msg_id), !Self.isControl(p) else { continue }
            let key = item.chatType == "group" ? "group:\(item.chatID)" : "dm:\(item.chatID)"
            let r = LocalMessageStore.RelayMessage(id: item.messageID.isEmpty ? env.msg_id : item.messageID, chatKey: key,
                                                   senderID: "relay:\(item.sender)", senderHandle: item.sender, createdAt: item.createdAt, msgID: env.msg_id)
            store.mutate { $0.relay[key, default: []].append(r) }
        }
        await SecurityAPI.relayAck(deviceID: id.deviceID, ids: acked)
    }

    /// Delete my data: wipes local keys, sessions and the plaintext cache.
    func wipeLocal() {
        IdentityStore.shared.resetDevice()
        store.wipeAll()
        ready = false
    }
}

/// Last known settings per chat so sending never waits on the network.
enum ChatSettingsCache {
    static func get(_ key: String) -> ChatSecuritySettings? {
        UserDefaults.standard.data(forKey: "chatSettings.\(key)").flatMap { try? JSONDecoder().decode(ChatSecuritySettings.self, from: $0) }
    }
    static func set(_ s: ChatSecuritySettings, _ key: String) {
        if let d = try? JSONEncoder().encode(s) { UserDefaults.standard.set(d, forKey: "chatSettings.\(key)") }
    }
}
