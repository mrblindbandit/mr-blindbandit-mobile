import LiveKit

/// Broadcast Upload extension: LiveKit's handler streams the whole iPhone screen to the app over the
/// App Group socket (RTCAppGroupIdentifier), and the app publishes it into the call.
/// LKSampleHandler forwards .video and, once the app's BroadcastScreenCapturer asks for it
/// (ScreenShareCaptureOptions(appAudio: true)), .audioApp buffers too. .audioMic is intentionally
/// ignored here: the main app already publishes the mic, so forwarding it would double/echo the voice.
final class SampleHandler: LKSampleHandler {
    override var enableLogging: Bool { false }
}
