import Foundation
import LiveKit

/// One person in the call grid (including me), rebuilt from LiveKit once a second and on room events.
struct CallParticipantInfo: Identifiable {
    let id: String
    let name: String
    let isLocal: Bool
    let isSpeaking: Bool
    let micOn: Bool
    let cameraOn: Bool
    let sharingScreen: Bool
    let quality: ConnectionQuality
    let handRaised: Bool
    let videoTrack: VideoTrack?
    let screenTrack: VideoTrack?

    var qualityLabel: String { CallParticipantInfo.label(for: quality) }

    static func label(for quality: ConnectionQuality) -> String {
        switch quality {
        case .excellent: return "Excellent connection"
        case .good: return "Good connection"
        case .poor: return "Poor connection"
        case .lost: return "Connection lost"
        default: return "Connection unknown"
        }
    }

    var accessibilitySummary: String {
        var parts = [isLocal ? "You" : name]
        if isSpeaking { parts.append("speaking") }
        parts.append(micOn ? "microphone on" : "muted")
        parts.append(cameraOn ? "camera on" : "camera off")
        if sharingScreen { parts.append("sharing screen") }
        if handRaised { parts.append("hand raised") }
        if quality == .poor || quality == .lost { parts.append(qualityLabel.lowercased()) }
        return parts.joined(separator: ", ")
    }
}

struct InCallChatMessage: Identifiable, Equatable {
    let id: String
    let sender: String
    let text: String
    let mine: Bool
    let date: Date
}

/// Wire format of the in-call data channel (topic "bb.call").
struct CallDataMessage: Codable {
    var type: String
    var raised: Bool?
    var id: String?
    var text: String?
}

/// Bridges LiveKit's room delegate (any thread) onto the main-actor service.
final class CallRoomObserver: NSObject, RoomDelegate, @unchecked Sendable {
    weak var service: ProductionCommunicationsService?

    init(service: ProductionCommunicationsService) { self.service = service }

    func room(_ room: Room, participant: RemoteParticipant?, didReceiveData data: Data, forTopic topic: String, encryptionType: EncryptionType) {
        guard topic == "bb.call" else { return }
        let sender = participant?.name.flatMap { $0.isEmpty ? nil : $0 } ?? participant?.identity?.stringValue ?? "Someone"
        let identity = participant?.identity?.stringValue ?? ""
        Task { @MainActor [weak self] in self?.service?.handleCallData(data, identity: identity, sender: sender) }
    }

    func room(_ room: Room, participantDidConnect participant: RemoteParticipant) {
        Task { @MainActor [weak self] in self?.service?.roomChanged() }
    }

    func room(_ room: Room, participantDidDisconnect participant: RemoteParticipant) {
        Task { @MainActor [weak self] in self?.service?.roomChanged() }
    }

    func room(_ room: Room, didUpdateSpeakingParticipants participants: [Participant]) {
        Task { @MainActor [weak self] in self?.service?.roomChanged() }
    }

    func room(_ room: Room, didDisconnectWithError error: LiveKitError?) {
        Task { @MainActor [weak self] in self?.service?.roomDisconnected(room) }
    }
}
