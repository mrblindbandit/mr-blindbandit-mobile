import UserNotifications
import Intents
import Foundation
import CryptoKit

/// Decrypts E2EE message pushes on device and turns them into communication notifications
/// (sender name and avatar via INSendMessageIntent). Calls and @mentions are time-sensitive.
/// Decryption is read-only ("peek"): the app still owns the ratchet state, so nothing is written here.
final class NotificationService: UNNotificationServiceExtension {
    private var handler: ((UNNotificationContent) -> Void)?
    private var best: UNMutableNotificationContent?

    override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        handler = contentHandler
        guard let content = request.content.mutableCopy() as? UNMutableNotificationContent else { contentHandler(request.content); return }
        best = content
        let info = content.userInfo
        let category = (info["category"] as? String) ?? (info["type"] as? String) ?? ""

        if let text = PushDecryptor.decrypt(info) {
            content.body = text
            if (info["is_group"] as? Bool) != true, content.title.isEmpty { content.title = PushDecryptor.senderName(info) ?? content.title }
        }
        let myHandle = UserDefaults(suiteName: PushDecryptor.appGroup)?.string(forKey: "myHandle")?.lowercased()
        let mentioned = category.contains("mention") || (myHandle.map { content.body.lowercased().contains("@" + $0) } ?? false)
        if category.contains("call") || mentioned { content.interruptionLevel = .timeSensitive }

        Task {
            let final = await Self.communication(content, info: info)
            contentHandler(final)
        }
    }

    override func serviceExtensionTimeWillExpire() {
        if let handler, let best { handler(best) }
    }

    /// Wraps the content in an INSendMessageIntent so iOS shows the sender's photo and treats it as a message.
    static func communication(_ content: UNMutableNotificationContent, info: [AnyHashable: Any]) async -> UNNotificationContent {
        let handle = (info["sender_handle"] as? String) ?? (info["from"] as? String) ?? ""
        guard !handle.isEmpty else { return content }
        let name = PushDecryptor.senderName(info) ?? handle
        var image: INImage?
        if let s = info["avatar_url"] as? String, let url = URL(string: s), url.scheme == "https",
           let (data, _) = try? await URLSession.shared.data(from: url), data.count < 2_000_000 {
            image = INImage(imageData: data)
        }
        let sender = INPerson(personHandle: INPersonHandle(value: handle, type: .unknown), nameComponents: nil,
                              displayName: name, image: image, contactIdentifier: nil, customIdentifier: handle)
        let groupName = info["group_name"] as? String
        let intent = INSendMessageIntent(recipients: nil, outgoingMessageType: .outgoingMessageText, content: content.body,
                                         speakableGroupName: groupName.map { INSpeakableString(spokenPhrase: $0) },
                                         conversationIdentifier: (info["chat_id"] as? String) ?? handle,
                                         serviceName: "Mr. BlindBandit", sender: sender, attachments: nil)
        let interaction = INInteraction(intent: intent, response: nil)
        interaction.direction = .incoming
        try? await interaction.donate()
        return (try? content.updating(from: intent)) ?? content
    }
}

enum PushDecryptor {
    static let appGroup = "group.net.mrblindbandit.app"

    static func senderName(_ info: [AnyHashable: Any]) -> String? {
        (info["sender_name"] as? String) ?? (info["display_name"] as? String)
    }

    /// Accepts an envelope as a dict or a JSON string under "e2ee", "envelope" or "ciphertext_envelope".
    static func decrypt(_ info: [AnyHashable: Any]) -> String? {
        let raw = info["e2ee"] ?? info["envelope"] ?? info["ciphertext_envelope"]
        let data: Data?
        if let s = raw as? String { data = Data(s.utf8) }
        else if let d = raw as? [String: Any] { data = try? JSONSerialization.data(withJSONObject: d) }
        else { data = nil }
        guard let data, let env = try? JSONDecoder().decode(E2EEEnvelope.self, from: data) else { return nil }
        let handle = UserDefaults(suiteName: appGroup)?.string(forKey: "myHandle") ?? ""
        guard let me = IdentityStore.shared.identity(handle: handle, createIfMissing: false),
              let out = try? MessageCrypto.decrypt(env, local: me, storage: PeekSessionStorage()) else { return nil }
        switch out.payload.t {
        case "voice": return "Voice message"
        case "poll": return "Poll: " + (out.payload.body ?? "")
        case "image", "photo": return "Photo"
        default: return out.payload.body
        }
    }
}

/// Reads the app's sessions and prekeys but never writes, so the app's own decrypt later still works.
final class PeekSessionStorage: E2EESessionStorage {
    private let real = KeychainSessionStorage.shared
    func outbound(peer deviceID: String) -> E2EEOutboundSession? { nil }
    func setOutbound(_ session: E2EEOutboundSession?, peer deviceID: String) {}
    func inbound(sender deviceID: String, ek: String) -> E2EEInboundSession? { real.inbound(sender: deviceID, ek: ek) }
    func setInbound(_ session: E2EEInboundSession, sender deviceID: String, ek: String) {}
    func signedPrekeyPrivate(id: Int) -> P256.KeyAgreement.PrivateKey? { real.signedPrekeyPrivate(id: id) }
    func oneTimePrekeyPrivate(id: Int) -> P256.KeyAgreement.PrivateKey? { real.oneTimePrekeyPrivate(id: id) }
    func consumeOneTimePrekey(id: Int) {}
}
