import Foundation
import SwiftUI

// MARK: - DM protocol + local persistence (UserDefaults)

enum MessageReceipt: String, Codable, Equatable {
    case sending, sent, delivered, read
}

enum DMPayloadType: String, Codable {
    case text
    case typing
    case receipt
    case attachment
    case attachmentChunk
    case voiceNote
    case voiceNoteChunk
}

/// JSON envelope over LiveKit reliable data channel (topic: `mb.dm`).
struct DMEnvelope: Codable, Equatable {
    var v: Int = 1
    var type: DMPayloadType
    var threadId: String
    var messageId: String
    var senderId: String
    var senderName: String
    var body: String?
    var receiptStatus: MessageReceipt?
    var isTyping: Bool?
    var attachmentName: String?
    var attachmentMime: String?
    var attachmentSize: Int?
    var chunkIndex: Int?
    var chunkTotal: Int?
    var payloadB64: String?
    var sentAt: Double

    static let topic = "mb.dm"
    static let maxChunkBytes = 10_000
}

struct DMMessage: Identifiable, Codable, Equatable {
    var id: String
    var threadId: String
    var senderId: String
    var senderName: String
    var body: String
    var sentAt: Date
    var isLocal: Bool
    var kind: Kind
    var receipt: MessageReceipt
    var localFilePath: String?
    var attachmentMime: String?
    var attachmentName: String?

    enum Kind: String, Codable { case text, attachment, voiceNote, system }

    var isVoiceNote: Bool { kind == .voiceNote }
    var voiceNoteURL: URL? {
        guard let localFilePath else { return nil }
        return URL(fileURLWithPath: localFilePath)
    }
}

struct DMThread: Identifiable, Codable, Equatable {
    var id: String
    var peerId: String
    var peerName: String
    var updatedAt: Date
    var messages: [DMMessage]

    var preview: String {
        guard let last = messages.last(where: { $0.kind != .system }) else { return "No messages yet" }
        switch last.kind {
        case .voiceNote: return "🎙 Voice note"
        case .attachment: return "📎 \(last.attachmentName ?? "Attachment")"
        default: return last.body
        }
    }
}

@MainActor
final class DMThreadStore: ObservableObject {
    static let shared = DMThreadStore()
    private let key = "connect.dm.threads.v1"
    @Published private(set) var threads: [DMThread] = []

    init() {
        load()
        if threads.isEmpty {
            seedDemo()
        }
    }

    func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([DMThread].self, from: data) else {
            threads = []
            return
        }
        threads = decoded.sorted { $0.updatedAt > $1.updatedAt }
    }

    func persist() {
        threads.sort { $0.updatedAt > $1.updatedAt }
        if let data = try? JSONEncoder().encode(threads) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    func upsert(_ thread: DMThread) {
        if let idx = threads.firstIndex(where: { $0.id == thread.id }) {
            threads[idx] = thread
        } else {
            threads.insert(thread, at: 0)
        }
        persist()
    }

    func thread(id: String) -> DMThread? {
        threads.first { $0.id == id }
    }

    func ensureThread(peerId: String, peerName: String) -> DMThread {
        if let existing = threads.first(where: { $0.peerId == peerId || $0.id == Self.threadId(with: peerId) }) {
            return existing
        }
        let t = DMThread(
            id: Self.threadId(with: peerId),
            peerId: peerId,
            peerName: peerName,
            updatedAt: Date(),
            messages: []
        )
        upsert(t)
        return t
    }

    func appendMessage(_ message: DMMessage, peerId: String, peerName: String) {
        var t = ensureThread(peerId: peerId, peerName: peerName)
        if t.messages.contains(where: { $0.id == message.id }) { return }
        t.messages.append(message)
        t.updatedAt = message.sentAt
        if peerName != t.peerName, !message.isLocal {
            t.peerName = peerName
        }
        upsert(t)
    }

    func updateReceipt(threadId: String, messageId: String, receipt: MessageReceipt) {
        guard var t = thread(id: threadId) else { return }
        guard let idx = t.messages.firstIndex(where: { $0.id == messageId }) else { return }
        let current = t.messages[idx].receipt
        let order: [MessageReceipt] = [.sending, .sent, .delivered, .read]
        if let a = order.firstIndex(of: current), let b = order.firstIndex(of: receipt), b < a {
            return
        }
        t.messages[idx].receipt = receipt
        upsert(t)
    }

    func seedDemo() {
        let studio = DMThread(
            id: Self.threadId(with: "studio"),
            peerId: "studio",
            peerName: "Studio",
            updatedAt: Date(),
            messages: [
                DMMessage(
                    id: UUID().uuidString,
                    threadId: Self.threadId(with: "studio"),
                    senderId: "studio",
                    senderName: "Studio",
                    body: "TEST SCAFFOLD — DMs use LiveKit data packets. Tokens are temporary.",
                    sentAt: Date().addingTimeInterval(-120),
                    isLocal: false,
                    kind: .text,
                    receipt: .read
                )
            ]
        )
        threads = [studio]
        persist()
    }

    static func threadId(with peerId: String) -> String {
        let a = "local"
        let b = peerId
        let pair = [a, b].sorted().joined(separator: ":")
        return "dm-\(pair)"
    }

    static func attachmentsDirectory() -> URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("dm-attachments", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
