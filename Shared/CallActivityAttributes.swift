import Foundation
import ActivityKit

struct CallActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var phase: String // ringing | connected | ending
        var elapsedSeconds: Int
        var muted: Bool
        var onSpeaker: Bool
    }

    var callID: String
    var handle: String
    var displayName: String
}

struct BitePostActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var stage: String // composing | uploading | posted | failed
        var progress: Double
        var detail: String
    }

    var draftPreview: String
}
