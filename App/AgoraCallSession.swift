import Foundation
import simd
import AgoraRtcKit

/// Agora RTC session used when the server returns `provider=agora`.
/// App ID, token, channel, and account come from the server grant — never a client certificate.
@MainActor
final class AgoraCallSession: NSObject {
    private(set) var engine: AgoraRtcEngineKit?
    private(set) var remoteUids: Set<UInt> = []
    private(set) var joined = false
    private var spatial: AgoraLocalSpatialAudioKit?
    private(set) var currentRoute: CallAudioRoute?

    var onJoined: (() -> Void)?
    var onUserJoined: ((UInt) -> Void)?
    var onUserOffline: ((UInt) -> Void)?
    var onError: ((String) -> Void)?
    var onActiveSpeaker: ((UInt) -> Void)?
    var onAudioRoute: ((CallAudioRoute) -> Void)?

    func join(appId: String, channel: String, token: String, uid: UInt, userAccount: String? = nil, video: Bool, defaultToSpeaker: Bool) throws {
        leave()
        // Ask for media volume without activating the session. CallKit owns activation.
        CallMediaSession.configureAgoraMediaVolume()
        let mediaVolume = CallMediaSession.mediaVolumeIsActive()
        let config = AgoraRtcEngineConfig()
        config.appId = appId
        config.audioScenario = .gameStreaming
        let eng = AgoraRtcEngineKit.sharedEngine(with: config, delegate: self)
        // The SDK must not call setActive. That fights CallKit and surfaces as recording not allowed.
        eng.setAudioSessionOperationRestriction(.all)
        eng.setChannelProfile(.communication)
        eng.setClientRole(.broadcaster)
        eng.setAudioScenario(.gameStreaming)
        let advanced = AgoraAdvancedAudioOptions()
        if mediaVolume {
            eng.setAudioProfile(.musicHighQualityStereo)
            if let stereo = AgoraAudioProcessChannels(rawValue: CallAudioPolicy.stereoProcessingChannels) {
                advanced.audioProcessingChannels = stereo
            }
        } else {
            // Voice-chat unit is mono. Publishing stereo on it is what the far end hears as scrambled.
            eng.setAudioProfile(.musicHighQuality)
            if let mono = AgoraAudioProcessChannels(rawValue: 1) {
                advanced.audioProcessingChannels = mono
            }
        }
        eng.setAdvancedAudioOptions(advanced)
        eng.setAINSMode(CallAudioPolicy.aiNoiseSuppression, mode: AUDIO_AINS_MODE.AINS_MODE_BALANCED)
        eng.setParameters("{\"che.audio.aec.enable\":\(CallAudioPolicy.echoCancellation)}")
        eng.setParameters("{\"che.audio.ans.enable\":\(CallAudioPolicy.noiseSuppression)}")
        eng.setParameters("{\"che.audio.agc.enable\":\(CallAudioPolicy.automaticGainControl)}")
        eng.adjustRecordingSignalVolume(CallAudioPolicy.unityVolume)
        eng.adjustPlaybackSignalVolume(CallAudioPolicy.unityVolume)
        eng.setDefaultAudioRouteToSpeakerphone(defaultToSpeaker)
        eng.enableAudioVolumeIndication(400, smooth: 3, reportVad: true)
        eng.enableAudio()
        eng.setEnableSpeakerphone(defaultToSpeaker)
        startSpatialAudio(eng)
        if video {
            eng.enableVideo()
            eng.enableLocalVideo(true)
        } else {
            eng.disableVideo()
        }
        let options = AgoraRtcChannelMediaOptions()
        options.clientRoleType = .broadcaster
        options.channelProfile = .communication
        options.publishMicrophoneTrack = true
        options.publishCameraTrack = video
        options.autoSubscribeAudio = true
        options.autoSubscribeVideo = true
        let code: Int32
        if let userAccount, !userAccount.isEmpty {
            code = eng.joinChannel(byToken: token.isEmpty ? nil : token,
                channelId: channel, userAccount: userAccount, mediaOptions: options)
        } else {
            code = eng.joinChannel(byToken: token.isEmpty ? nil : token,
                channelId: channel, uid: uid, mediaOptions: options)
        }
        engine = eng
        guard code == 0 else {
            leave()
            throw CommunicationsError.server("Agora join failed (code \(code)).")
        }
    }

    func setMic(enabled: Bool) {
        engine?.muteLocalAudioStream(!enabled)
        engine?.enableLocalAudio(enabled)
        spatial?.muteLocalAudioStream(!enabled)
    }

    /// Mutes one remote person on this phone only. Does not remove their spatial seat.
    func muteRemote(uid: UInt, muted: Bool) {
        engine?.muteRemoteAudioStream(uid, mute: muted)
    }

    func setSpeakerphone(_ enabled: Bool) {
        engine?.setEnableSpeakerphone(enabled)
    }

    func applySpatialSeats(_ seats: [(uid: UInt, seat: CallSpatialSeat)]) {
        guard let spatial else { return }
        updateSelfPosition()
        for item in seats {
            let info = AgoraRemoteVoicePositionInfo()
            info.position = simd_float3(item.seat.front, item.seat.right, item.seat.top)
            info.forward = simd_float3(item.seat.forwardFront, item.seat.forwardRight, item.seat.forwardTop)
            spatial.updateRemotePosition(item.uid, positionInfo: info)
            // Position comes from the spatial engine only. SpatialAudioParams defaults
            // azimuth and distance to 0, which fights the seat and muffles the voice.
            spatial.setRemoteAudioAttenuation(CallSpatialLayout.airAttenuation, uid: item.uid, forceSet: false)
        }
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
        let uids = remoteUids
        for uid in uids {
            spatial?.removeRemotePosition(uid)
        }
        if spatial != nil {
            spatial = nil
            AgoraLocalSpatialAudioKit.destroy()
        }
        engine?.leaveChannel(nil)
        if engine != nil {
            AgoraRtcEngineKit.destroy()
        }
        engine = nil
        remoteUids = []
        joined = false
        currentRoute = nil
    }

    private func startSpatialAudio(_ eng: AgoraRtcEngineKit) {
        eng.enableSpatialAudio(true)
        let config = AgoraLocalSpatialAudioConfig()
        config.rtcEngine = eng
        let kit = AgoraLocalSpatialAudioKit.sharedLocalSpatialAudio(with: config)
        kit.setMaxAudioRecvCount(UInt(CallSpatialLayout.maxHeard))
        kit.setAudioRecvRange(CallSpatialLayout.receiveRange)
        kit.setDistanceUnit(1)
        spatial = kit
        updateSelfPosition()
    }

    private func updateSelfPosition() {
        // Local listener at the origin, facing forward. Axes are front, right, top.
        spatial?.updateSelfPosition(
            simd_float3(0, 0, 0),
            axisForward: simd_float3(1, 0, 0),
            axisRight: simd_float3(0, 1, 0),
            axisUp: simd_float3(0, 0, 1)
        )
    }

    private func applyHeadphoneEQ(_ route: CallAudioRoute) {
        guard let engine else { return }
        // AgoraHeadphoneEQPreset raw values from AgoraEnumerates.h. The ObjC case
        // names do not import as .off / .overEar, so the raw values are the stable API.
        let raw: Int
        switch route.headphoneEQ {
        case .off: raw = 0x00000000
        case .overEar: raw = 0x04000001
        case .inEar: raw = 0x04000002
        }
        if let preset = AgoraHeadphoneEQPreset(rawValue: raw) {
            engine.setHeadphoneEQPreset(preset)
        }
    }
}

extension AgoraCallSession: AgoraRtcEngineDelegate {
    nonisolated func rtcEngine(_ engine: AgoraRtcEngineKit, didJoinChannel channel: String, withUid uid: UInt, elapsed: Int) {
        Task { @MainActor in
            guard self.engine === engine else { return }
            self.joined = true
            self.updateSelfPosition()
            self.onJoined?()
        }
    }

    nonisolated func rtcEngine(_ engine: AgoraRtcEngineKit, didJoinedOfUid uid: UInt, elapsed: Int) {
        Task { @MainActor in
            guard self.engine === engine else { return }
            self.remoteUids.insert(uid)
            self.onUserJoined?(uid)
        }
    }

    nonisolated func rtcEngine(_ engine: AgoraRtcEngineKit, didOfflineOfUid uid: UInt, reason: AgoraUserOfflineReason) {
        Task { @MainActor in
            guard self.engine === engine else { return }
            self.remoteUids.remove(uid)
            // Agora: skipping removeRemotePosition can silence everyone else.
            self.spatial?.removeRemotePosition(uid)
            self.onUserOffline?(uid)
        }
    }

    nonisolated func rtcEngine(_ engine: AgoraRtcEngineKit, didOccurError errorCode: AgoraErrorCode) {
        Task { @MainActor in
            guard self.engine === engine else { return }
            self.onError?("Agora error \(errorCode.rawValue)")
        }
    }

    nonisolated func rtcEngine(_ engine: AgoraRtcEngineKit, didAudioRouteChanged routing: AgoraAudioOutputRouting) {
        Task { @MainActor in
            guard self.engine === engine else { return }
            let route = CallAudioRoute.from(agoraRoute: routing.rawValue)
            self.currentRoute = route
            self.applyHeadphoneEQ(route)
            self.onAudioRoute?(route)
        }
    }

    nonisolated func rtcEngine(_ engine: AgoraRtcEngineKit, reportAudioVolumeIndicationOfSpeakers speakers: [AgoraRtcAudioVolumeInfo], totalVolume: Int) {
        let loudest = speakers.filter { $0.uid != 0 && $0.volume > 40 }.max { $0.volume < $1.volume }
        guard let uid = loudest?.uid else { return }
        Task { @MainActor in
            guard self.engine === engine else { return }
            self.onActiveSpeaker?(uid)
        }
    }
}
