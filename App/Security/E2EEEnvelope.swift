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
        /// Optional alternate key material (base64/base64url) when peers wrap the attachment key.
        var wrapped_key: String? = nil
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

        init(url: String?, attachment_id: String?, key: String, wrapped_key: String? = nil, nonce: String?, sha256: String,
             mime: String, size: Int?, filename: String?, caption: String?, view_once: Bool?, duration: Double?,
             transcript: String?, alt: String?) {
            self.url = url; self.attachment_id = attachment_id; self.key = key; self.wrapped_key = wrapped_key
            self.nonce = nonce; self.sha256 = sha256; self.mime = mime; self.size = size; self.filename = filename
            self.caption = caption; self.view_once = view_once; self.duration = duration; self.transcript = transcript; self.alt = alt
        }

        private enum CodingKeys: String, CodingKey {
            case url, attachment_id, key, wrapped_key, nonce, sha256, mime, size, filename, caption, view_once, listen_once, duration, transcript, alt
            case attachment_key, encryption_key, base_nonce, iv
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            url = try c.decodeIfPresent(String.self, forKey: .url)
            attachment_id = try c.decodeIfPresent(String.self, forKey: .attachment_id)
            key = (try c.decodeIfPresent(String.self, forKey: .key))
                ?? (try c.decodeIfPresent(String.self, forKey: .attachment_key))
                ?? (try c.decodeIfPresent(String.self, forKey: .encryption_key)) ?? ""
            wrapped_key = try c.decodeIfPresent(String.self, forKey: .wrapped_key)
            nonce = (try c.decodeIfPresent(String.self, forKey: .nonce))
                ?? (try c.decodeIfPresent(String.self, forKey: .base_nonce))
                ?? (try c.decodeIfPresent(String.self, forKey: .iv))
            sha256 = (try c.decodeIfPresent(String.self, forKey: .sha256)) ?? ""
            mime = (try c.decodeIfPresent(String.self, forKey: .mime)) ?? ""
            size = try c.decodeIfPresent(Int.self, forKey: .size)
            filename = try c.decodeIfPresent(String.self, forKey: .filename)
            caption = try c.decodeIfPresent(String.self, forKey: .caption)
            view_once = (try c.decodeIfPresent(Bool.self, forKey: .view_once))
                ?? (try c.decodeIfPresent(Bool.self, forKey: .listen_once))
            duration = try c.decodeIfPresent(Double.self, forKey: .duration)
            transcript = try c.decodeIfPresent(String.self, forKey: .transcript)
            alt = try c.decodeIfPresent(String.self, forKey: .alt)
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encodeIfPresent(url, forKey: .url); try c.encodeIfPresent(attachment_id, forKey: .attachment_id)
            try c.encode(key, forKey: .key); try c.encodeIfPresent(wrapped_key, forKey: .wrapped_key)
            try c.encodeIfPresent(nonce, forKey: .nonce); try c.encode(sha256, forKey: .sha256); try c.encode(mime, forKey: .mime)
            try c.encodeIfPresent(size, forKey: .size); try c.encodeIfPresent(filename, forKey: .filename)
            try c.encodeIfPresent(caption, forKey: .caption); try c.encodeIfPresent(view_once, forKey: .view_once)
            try c.encodeIfPresent(duration, forKey: .duration); try c.encodeIfPresent(transcript, forKey: .transcript)
            try c.encodeIfPresent(alt, forKey: .alt)
        }
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
