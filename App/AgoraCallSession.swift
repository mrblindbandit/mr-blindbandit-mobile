import Foundation
import AgoraRtcKit

/// Thin Agora RTC wrapper used when the server returns `provider=agora`.
/// App ID + token + channel + uid come from the server grant — never from a client certificate.
@MainActor
final class AgoraCallSession: NSObject {
    private(set) var engine: AgoraRtcEngineKit?
    private(set) var remoteUids: Set<UInt> = []
    private(set) var joined = false

    var onJoined: (() -> Void)?
    var onUserJoined: ((UInt) -> Void)?
    var onUserOffline: ((UInt) -> Void)?
    var onError: ((String) -> Void)?

    func join(appId: String, channel: String, token: String, uid: UInt, video: Bool) throws {
        leave()
        let config = AgoraRtcEngineConfig()
        config.appId = appId
        guard let eng = AgoraRtcEngineKit.sharedEngine(with: config, delegate: self) else {
            throw CommunicationsError.server("Could not start Agora RTC engine.")
        }
        eng.setChannelProfile(.communication)
        eng.setClientRole(.broadcaster)
        eng.enableAudio()
        if video {
            eng.enableVideo()
            eng.enableLocalVideo(true)
        } else {
            eng.disableVideo()
        }
        // Prefer server-provided grant; do not set encryption unless we later map call_key.
        let options = AgoraRtcChannelMediaOptions()
        options.clientRoleType = .broadcaster
        options.channelProfile = .communication
        options.publishMicrophoneTrack = true
        options.publishCameraTrack = video
        options.autoSubscribeAudio = true
        options.autoSubscribeVideo = true
        let code = eng.joinChannel(
            byToken: token.isEmpty ? nil : token,
            channelId: channel,
            uid: uid,
            mediaOptions: options
        )
        guard code == 0 else {
            AgoraRtcEngineKit.destroy()
            throw CommunicationsError.server("Agora join failed (code \(code)).")
        }
        engine = eng
    }

    func setMic(enabled: Bool) {
        engine?.muteLocalAudioStream(!enabled)
        engine?.enableLocalAudio(enabled)
    }

    func setCamera(enabled: Bool) {
        guard let engine else { return }
        if enabled {
            engine.enableVideo()
            engine.enableLocalVideo(true)
            engine.muteLocalVideoStream(false)
        } else {
            engine.muteLocalVideoStream(true)
            engine.enableLocalVideo(false)
        }
    }

    func switchCamera() {
        engine?.switchCamera()
    }

    func leave() {
        engine?.leaveChannel(nil)
        if engine != nil {
            AgoraRtcEngineKit.destroy()
        }
        engine = nil
        remoteUids = []
        joined = false
    }
}

extension AgoraCallSession: AgoraRtcEngineDelegate {
    nonisolated func rtcEngine(_ engine: AgoraRtcEngineKit, didJoinChannel channel: String, withUid uid: UInt, elapsed: Int) {
        Task { @MainActor in
            self.joined = true
            self.onJoined?()
        }
    }

    nonisolated func rtcEngine(_ engine: AgoraRtcEngineKit, didJoinedOfUid uid: UInt, elapsed: Int) {
        Task { @MainActor in
            self.remoteUids.insert(uid)
            self.onUserJoined?(uid)
        }
    }

    nonisolated func rtcEngine(_ engine: AgoraRtcEngineKit, didOfflineOfUid uid: UInt, reason: AgoraUserOfflineReason) {
        Task { @MainActor in
            self.remoteUids.remove(uid)
            self.onUserOffline?(uid)
        }
    }

    nonisolated func rtcEngine(_ engine: AgoraRtcEngineKit, didOccurError errorCode: AgoraErrorCode) {
        Task { @MainActor in
            self.onError?("Agora error \(errorCode.rawValue)")
        }
    }
}
