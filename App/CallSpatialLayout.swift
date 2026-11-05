import AVFoundation
import Foundation

/// Call-audio contract for Agora. Numbers match Agora RTC 4.x:
/// music high-quality stereo = 5 (48 kHz, stereo, up to 128 kbps),
/// game streaming = 3 (media volume), stereo processing = 2.
enum CallAudioPolicy {
    static let musicHighQualityStereo = 5
    static let gameStreamingScenario = 3
    static let stereoProcessingChannels = 2
    static let echoCancellation = true
    static let noiseSuppression = false
    static let aiNoiseSuppression = false
    static let automaticGainControl = true
    /// Unity gain. Agora treats 100 as the original signal, not a boost.
    static let unityVolume = 100
    static let ainsModeBalanced = 0
}

/// One remote seat in the listener's space.
/// Agora's position array is ordered front, right, top — not a typical x, y, z.
struct CallSpatialSeat: Equatable {
    let index: Int
    let front: Float
    let right: Float
    let top: Float
    /// Unit vector from this seat toward the listener, same axis order.
    let forwardFront: Float
    let forwardRight: Float
    let forwardTop: Float
    /// Spoken direction for VoiceOver / TalkBack, such as "on your left".
    let spokenDirection: String
}

struct CallAudioRoute: Equatable {
    enum Kind: Equatable {
        case speaker
        case earpiece
        case wired
        case bluetooth
        case other
    }

    enum HeadphoneEQ: Equatable {
        case off
        case overEar
        case inEar
    }

    let raw: Int
    let label: String
    let kind: Kind
    let headphoneEQ: HeadphoneEQ

    var isSpeaker: Bool { kind == .speaker }
    var isExternal: Bool { kind == .wired || kind == .bluetooth }

    /// Agora route raw values. 0–5 and 10 match on iOS and Android.
    /// Raw 8 is a USB headset on Android and DisplayPort on iOS; both get over-ear EQ.
    static func from(agoraRoute raw: Int) -> CallAudioRoute {
        switch raw {
        case 3, 4:
            return CallAudioRoute(raw: raw, label: "speaker", kind: .speaker, headphoneEQ: .off)
        case 1:
            return CallAudioRoute(raw: raw, label: "earpiece", kind: .earpiece, headphoneEQ: .off)
        case 0, 2, 6, 8:
            let label = (raw == 6 || raw == 8) ? "USB headset" : "wired headset"
            return CallAudioRoute(raw: raw, label: label, kind: .wired, headphoneEQ: .overEar)
        case 5, 10:
            return CallAudioRoute(raw: raw, label: "Bluetooth", kind: .bluetooth, headphoneEQ: .inEar)
        case 9:
            return CallAudioRoute(raw: raw, label: "AirPlay", kind: .other, headphoneEQ: .off)
        default:
            return CallAudioRoute(raw: raw, label: "audio device", kind: .other, headphoneEQ: .off)
        }
    }
}

/// Seats remote people on a virtual circle around the local listener.
enum CallSpatialLayout {
    /// Close enough that light air absorption does not muffle speech.
    static let radius: Float = 1.6
    static let receiveRange: Float = 30
    static let maxHeard = 16
    /// Agora's plain-scene example is 0.1 (slow decay). Slightly under that keeps voices clear.
    static let airAttenuation: Double = 0.08
    /// A 1:1 call ends when the other person leaves. A group stays open this long.
    static let groupAloneSeconds: TimeInterval = 120

    static func shouldEndImmediately(isGroup: Bool, remotesRemaining: Int, hadRemote: Bool) -> Bool {
        hadRemote && remotesRemaining == 0 && !isGroup
    }

    static func seats(count: Int) -> [CallSpatialSeat] {
        guard count > 0 else { return [] }
        let angles: [Double]
        if count == 1 {
            angles = [0]
        } else if count <= 6 {
            // Front semicircle: leftmost to rightmost, so a small group stays in front.
            let start = -Double.pi / 2
            let step = Double.pi / Double(count - 1)
            angles = (0..<count).map { start + step * Double($0) }
        } else {
            // Full circle. The first person stays in front; the rest go clockwise.
            angles = (0..<count).map { (2 * Double.pi * Double($0)) / Double(count) }
        }
        return angles.enumerated().map { seat(index: $0.offset, angle: $0.element) }
    }

    static func joinedAnnouncement(name: String, direction: String) -> String {
        "\(spokenName(name)) joined, \(direction)."
    }

    static func movedAnnouncement(name: String, direction: String) -> String {
        "\(spokenName(name)) moved. Now \(direction)."
    }

    static func speakingAnnouncement(name: String, direction: String?) -> String {
        if let direction, !direction.isEmpty {
            return "\(spokenName(name)) is speaking, \(direction)."
        }
        return "\(spokenName(name)) is speaking."
    }

    private static func spokenName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Someone" : trimmed
    }

    private static func seat(index: Int, angle: Double) -> CallSpatialSeat {
        let front = Float(cos(angle) * Double(radius))
        let right = Float(sin(angle) * Double(radius))
        let top: Float = 0
        let length = sqrt(front * front + right * right + top * top)
        let forwardFront: Float
        let forwardRight: Float
        let forwardTop: Float
        if length < 0.001 {
            forwardFront = 1
            forwardRight = 0
            forwardTop = 0
        } else {
            // Face the listener at the origin.
            forwardFront = -front / length
            forwardRight = -right / length
            forwardTop = -top / length
        }
        return CallSpatialSeat(
            index: index,
            front: front,
            right: right,
            top: top,
            forwardFront: forwardFront,
            forwardRight: forwardRight,
            forwardTop: forwardTop,
            spokenDirection: direction(angle)
        )
    }

    /// Angle 0 is in front. Positive angles are to the listener's right.
    static func direction(_ angle: Double) -> String {
        var degrees = angle * 180 / .pi
        while degrees > 180 { degrees -= 360 }
        while degrees < -180 { degrees += 360 }
        switch degrees {
        case -22.5...22.5: return "in front of you"
        case 22.5..<67.5: return "in front and to your right"
        case 67.5..<112.5: return "on your right"
        case 112.5..<157.5: return "behind you on the right"
        case 157.5...180, -180..<(-157.5): return "behind you"
        case -67.5..<(-22.5): return "in front and to your left"
        case -112.5..<(-67.5): return "on your left"
        default: return "behind you on the left"
        }
    }
}

/// Media-volume session for Agora game-streaming. Voice-chat mode uses the call
/// volume and Apple's noise suppression, which this call path must not turn on.
enum CallMediaSession {
    nonisolated static func activateAgoraMediaVolume(_ session: AVAudioSession = .sharedInstance()) {
        let options: AVAudioSession.CategoryOptions = [.allowBluetooth, .allowBluetoothA2DP, .mixWithOthers]
        try? session.setCategory(.playAndRecord, mode: .default, options: options)
        try? session.setActive(true)
    }
}
