package net.mrblindbandit.app.connect

import android.content.Context
import io.agora.rtc2.ChannelMediaOptions
import io.agora.rtc2.Constants
import io.agora.rtc2.IRtcEngineEventHandler
import io.agora.rtc2.RtcEngine
import io.agora.rtc2.RtcEngineConfig
import io.agora.rtc2.SpatialAudioParams
import io.agora.rtc2.audio.AdvancedAudioOptions
import io.agora.spatialaudio.ILocalSpatialAudioEngine
import io.agora.spatialaudio.LocalSpatialAudioConfig
import io.agora.spatialaudio.RemoteVoicePositionInfo

/**
 * Agora RTC session. Production tokens are user-account tokens (`buildTokenWithUserAccount`);
 * those must join with [RtcEngine.joinChannelWithUserAccount]. Numeric uid grants still use
 * [RtcEngine.joinChannel].
 *
 * Audio is music high-quality stereo on the game-streaming scenario (media volume),
 * with noise suppression off and echo cancellation on.
 */
class AgoraCallSession(
    private val appContext: Context,
    private val onJoined: () -> Unit = {},
    private val onUserJoined: (Int) -> Unit = {},
    private val onUserOffline: (Int) -> Unit = {},
    private val onError: (Int) -> Unit = {},
    private val onActiveSpeaker: (Int) -> Unit = {},
    private val onAudioRoute: (CallAudioRoute) -> Unit = {},
) {
    private var engine: RtcEngine? = null
    private var spatial: ILocalSpatialAudioEngine? = null
    val remoteUids = linkedSetOf<Int>()
    @Volatile var joined: Boolean = false
        private set
    var currentRoute: CallAudioRoute? = null
        private set

    private val handler = object : IRtcEngineEventHandler() {
        override fun onJoinChannelSuccess(channel: String?, uid: Int, elapsed: Int) {
            joined = true
            updateSelfPosition()
            CallLog.i("agora local join channel=${channel.orEmpty().take(24)} elapsed=$elapsed")
            onJoined()
        }

        override fun onUserJoined(uid: Int, elapsed: Int) {
            remoteUids.add(uid)
            CallLog.i("agora remote joined uid=$uid")
            onUserJoined(uid)
        }

        override fun onUserOffline(uid: Int, reason: Int) {
            remoteUids.remove(uid)
            // Agora: skipping removeRemotePosition can silence everyone else.
            runCatching { spatial?.removeRemotePosition(uid) }
            CallLog.i("agora remote offline uid=$uid reason=$reason")
            onUserOffline(uid)
        }

        override fun onError(err: Int) {
            CallLog.e("agora onError code=$err")
            onError(err)
        }

        override fun onAudioRouteChanged(routing: Int) {
            val route = CallAudioRoute.from(routing)
            currentRoute = route
            applyHeadphoneEQ(route)
            CallLog.i("agora route ${route.label} raw=$routing")
            onAudioRoute(route)
        }

        override fun onAudioVolumeIndication(speakers: Array<AudioVolumeInfo>?, totalVolume: Int) {
            val loudest = speakers
                ?.filter { it.uid != 0 && it.volume > 40 }
                ?.maxByOrNull { it.volume }
                ?: return
            onActiveSpeaker(loudest.uid)
        }
    }

    fun join(
        appId: String,
        channel: String,
        token: String,
        uid: Int,
        userAccount: String?,
        video: Boolean,
        defaultToSpeaker: Boolean,
    ) {
        leave()
        val config = RtcEngineConfig().apply {
            mContext = appContext.applicationContext
            mAppId = appId
            mEventHandler = handler
            mAudioScenario = Constants.AUDIO_SCENARIO_GAME_STREAMING
        }
        val eng = RtcEngine.create(config)
        eng.setChannelProfile(Constants.CHANNEL_PROFILE_COMMUNICATION)
        eng.setClientRole(Constants.CLIENT_ROLE_BROADCASTER)
        eng.setAudioScenario(Constants.AUDIO_SCENARIO_GAME_STREAMING)
        eng.setAudioProfile(Constants.AUDIO_PROFILE_MUSIC_HIGH_QUALITY_STEREO)
        val advanced = AdvancedAudioOptions()
        advanced.audioProcessingChannels = AdvancedAudioOptions.AudioProcessingChannelsEnum.AGORA_AUDIO_STEREO_PROCESSING
        eng.setAdvancedAudioOptions(advanced)
        eng.setAINSMode(CallAudioPolicy.aiNoiseSuppression, CallAudioPolicy.ainsModeBalanced)
        eng.setParameters("{\"che.audio.aec.enable\":${CallAudioPolicy.echoCancellation}}")
        eng.setParameters("{\"che.audio.ans.enable\":${CallAudioPolicy.noiseSuppression}}")
        eng.setParameters("{\"che.audio.agc.enable\":${CallAudioPolicy.automaticGainControl}}")
        eng.setParameters("{\"che.audio.sf.nsEnable\":0}")
        eng.setParameters("{\"che.audio.sf.ainsToLoadFlag\":0}")
        eng.adjustRecordingSignalVolume(CallAudioPolicy.unityVolume)
        eng.adjustPlaybackSignalVolume(CallAudioPolicy.unityVolume)
        eng.setDefaultAudioRoutetoSpeakerphone(defaultToSpeaker)
        eng.enableAudioVolumeIndication(400, 3, true)
        eng.enableAudio()
        eng.setEnableSpeakerphone(defaultToSpeaker)
        startSpatialAudio(eng)
        if (video) {
            eng.enableVideo()
            eng.enableLocalVideo(true)
        } else {
            eng.disableVideo()
        }
        val options = ChannelMediaOptions().apply {
            clientRoleType = Constants.CLIENT_ROLE_BROADCASTER
            channelProfile = Constants.CHANNEL_PROFILE_COMMUNICATION
            publishMicrophoneTrack = true
            publishCameraTrack = video
            autoSubscribeAudio = true
            autoSubscribeVideo = true
        }
        val account = userAccount?.trim().orEmpty()
        val code = if (account.isNotEmpty()) {
            val registered = eng.registerLocalUserAccount(appId, account)
            CallLog.i("agora registerLocalUserAccount code=$registered accountLen=${account.length}")
            eng.joinChannelWithUserAccount(token.ifBlank { null }, channel, account, options)
        } else {
            eng.joinChannel(token.ifBlank { null }, channel, uid, options)
        }
        engine = eng
        CallLog.i("agora join returned code=$code userAccount=${account.isNotEmpty()} video=$video stereo=2 scenario=gameStreaming")
        if (code != 0) {
            leave()
            error("Agora join failed (code $code)")
        }
    }

    fun setMic(enabled: Boolean) {
        engine?.muteLocalAudioStream(!enabled)
        engine?.enableLocalAudio(enabled)
        runCatching { spatial?.muteLocalAudioStream(!enabled) }
    }

    fun muteRemote(uid: Int, muted: Boolean) {
        engine?.muteRemoteAudioStream(uid, muted)
    }

    fun setSpeakerphone(enabled: Boolean) {
        engine?.setEnableSpeakerphone(enabled)
    }

    /**
     * Cycles speaker, then earpiece. A connected headset wins when speakerphone is off,
     * which keeps wired and Bluetooth routes working under the media-volume scenario.
     */
    fun cycleOutputRoute(): String {
        // Speaker, then earpiece. A connected headset still takes the route when speakerphone is off.
        val enableSpeaker = currentRoute?.isSpeaker != true
        engine?.setEnableSpeakerphone(enableSpeaker)
        if (enableSpeaker) return "speaker"
        val external = currentRoute?.takeIf { it.isExternal }?.label
        return external ?: "earpiece"
    }

    fun applySpatialSeats(seats: List<Pair<Int, CallSpatialSeat>>) {
        val spatialEngine = spatial ?: return
        val eng = engine ?: return
        updateSelfPosition()
        for ((uid, seat) in seats) {
            val info = RemoteVoicePositionInfo()
            info.position = floatArrayOf(seat.front, seat.right, seat.top)
            info.forward = floatArrayOf(seat.forwardFront, seat.forwardRight, seat.forwardTop)
            spatialEngine.updateRemotePosition(uid, info)
            val params = SpatialAudioParams()
            params.enable_air_absorb = true
            params.enable_doppler = false
            params.enable_blur = false
            params.speaker_attenuation = CallSpatialLayout.AIR_ATTENUATION
            eng.setRemoteUserSpatialAudioParams(uid, params)
        }
    }

    fun setCamera(enabled: Boolean) {
        val eng = engine ?: return
        if (enabled) {
            eng.enableVideo()
            eng.enableLocalVideo(true)
            eng.muteLocalVideoStream(false)
        } else {
            eng.muteLocalVideoStream(true)
            eng.enableLocalVideo(false)
        }
    }

    fun switchCamera() {
        engine?.switchCamera()
    }

    fun leave() {
        val spatialEngine = spatial
        spatial = null
        remoteUids.toList().forEach { uid ->
            runCatching { spatialEngine?.removeRemotePosition(uid) }
        }
        if (spatialEngine != null) {
            runCatching { ILocalSpatialAudioEngine.destroy() }
        }
        try {
            engine?.leaveChannel()
        } catch (_: Exception) {
        }
        try {
            RtcEngine.destroy()
        } catch (_: Exception) {
        }
        engine = null
        remoteUids.clear()
        joined = false
        currentRoute = null
    }

    private fun startSpatialAudio(eng: RtcEngine) {
        try {
            eng.enableSpatialAudio(true)
            val spatialEngine = ILocalSpatialAudioEngine.create()
            val config = LocalSpatialAudioConfig()
            config.mRtcEngine = eng
            val code = spatialEngine.initialize(config)
            if (code != 0) {
                CallLog.e("agora spatial initialize failed code=$code")
                runCatching { ILocalSpatialAudioEngine.destroy() }
                return
            }
            spatialEngine.setMaxAudioRecvCount(CallSpatialLayout.MAX_HEARD)
            spatialEngine.setAudioRecvRange(CallSpatialLayout.RECEIVE_RANGE)
            spatialEngine.setDistanceUnit(1f)
            spatial = spatialEngine
            updateSelfPosition()
            CallLog.i("agora spatial ready")
        } catch (t: Throwable) {
            CallLog.e("agora spatial init failed ${t.javaClass.simpleName}")
            spatial = null
        }
    }

    private fun updateSelfPosition() {
        spatial?.updateSelfPosition(
            floatArrayOf(0f, 0f, 0f),
            floatArrayOf(1f, 0f, 0f),
            floatArrayOf(0f, 1f, 0f),
            floatArrayOf(0f, 0f, 1f),
        )
    }

    private fun applyHeadphoneEQ(route: CallAudioRoute) {
        val preset = when (route.headphoneEQ) {
            CallAudioRoute.HeadphoneEQ.OFF -> Constants.HEADPHONE_EQUALIZER_OFF
            CallAudioRoute.HeadphoneEQ.OVER_EAR -> Constants.HEADPHONE_EQUALIZER_OVEREAR
            CallAudioRoute.HeadphoneEQ.IN_EAR -> Constants.HEADPHONE_EQUALIZER_INEAR
        }
        engine?.setHeadphoneEQPreset(preset)
    }

    companion object {
        /** Errors that mean this grant will not connect. Transient network blips are excluded. */
        val FATAL_ERRORS = setOf(1, 2, 5, 7, 17, 101, 102, 109, 110)
    }
}
