import Foundation

/// Wire formats (SPEC.md §1.6). All binary fields are base64url without padding.
struct E2EEPrekeyHeader: Codable, Equatable {
    /// Sender's ephemeral key for this session.
    var ek: String
    var spk_id: Int
    var opk_id: Int?
    /// Sender identity agreement key (IKdh).
    var ik: String
    /// Sender identity signing key (used in AD and to pin TOFU identity).
    var isk: String?
}

struct E2EEKeyEntry: Codable, Equatable {
    var device_id: String
    var handle: String?
    var prekey: E2EEPrekeyHeader?
    var n: Int
    var pn: Int
    var wrapped: String
    var nonce: String
}

struct E2EEEnvelope: Codable, Equatable {
    var v: Int = 1
    var suite: String = E2EECrypto.suite
    var type: String = "msg"
    var sender_device_id: String
    var msg_id: String
    var nonce: String
    var ciphertext: String
    var keys: [E2EEKeyEntry]
    var sig: String?

    var jsonObject: [String: Any] {
        guard let data = try? JSONEncoder().encode(self),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return obj
    }

    /// Lenient decode from a server field that may be an object or a JSON string.
    static func from(any value: Any?) -> E2EEEnvelope? {
        if let s = value as? String, let d = s.data(using: .utf8) { return try? JSONDecoder().decode(E2EEEnvelope.self, from: d) }
        if let o = value as? [String: Any], let d = try? JSONSerialization.data(withJSONObject: o) { return try? JSONDecoder().decode(E2EEEnvelope.self, from: d) }
        return nil
    }
}

/// Decrypted plaintext payload (SPEC.md §1.6 plus §22/§25 additions).
struct E2EEPayload: Codable, Equatable {
    struct Media: Codable, Equatable {
        var url: String?
        var attachment_id: String?
        var key: String
        var nonce: String?
        var sha256: String
        var mime: String
        var size: Int?
        var filename: String?
        var caption: String?
        var view_once: Bool?
        var duration: Double?
        var transcript: String?
        var alt: String?
    }
    struct Poll: Codable, Equatable {
        var question: String
        var options: [String]
        var multiple: Bool?
    }

    var t: String
    var body: String?
    var media: Media?
    var reply_to: String?
    var sent_at: Int?
    var expires_in: Int?
    var orig_lang: String?
    var orig: String?
    var silent: Bool?
    var poll: Poll?
    var vote: [Int]?
    var target_msg_id: String?
    var sig: String?
    var pinned: Bool?
    /// Set on answers produced by @AI on the sender's device: the asker's handle.
    var ai_via: String?

    init(t: String, body: String? = nil, media: Media? = nil, reply_to: String? = nil, sent_at: Int? = nil,
         expires_in: Int? = nil, orig_lang: String? = nil, orig: String? = nil, silent: Bool? = nil, poll: Poll? = nil,
         vote: [Int]? = nil, target_msg_id: String? = nil, sig: String? = nil, pinned: Bool? = nil, ai_via: String? = nil) {
        self.t = t; self.body = body; self.media = media; self.reply_to = reply_to; self.sent_at = sent_at
        self.expires_in = expires_in; self.orig_lang = orig_lang; self.orig = orig; self.silent = silent; self.poll = poll
        self.vote = vote; self.target_msg_id = target_msg_id; self.sig = sig; self.pinned = pinned; self.ai_via = ai_via
    }

    /// Canonical JSON: sorted keys, no whitespace, nil fields omitted (matches the reference generator).
    func canonicalJSON() throws -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try enc.encode(self)
    }

    static func deleteSigningMessage(_ target: String) -> Data { Data("bb-delete:\(target)".utf8) }
}
