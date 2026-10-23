import LiveKit

/// Broadcast Upload extension: LiveKit's handler streams the whole iPhone screen to the app over the
/// App Group socket (RTCAppGroupIdentifier), and the app publishes it into the call.
final class SampleHandler: LKSampleHandler {
    override var enableLogging: Bool { false }
}
