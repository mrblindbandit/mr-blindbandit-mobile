package net.mrblindbandit.app.connect

import android.content.Context
import io.agora.rtc2.ChannelMediaOptions
import io.agora.rtc2.Constants
import io.agora.rtc2.IRtcEngineEventHandler
import io.agora.rtc2.RtcEngine
import io.agora.rtc2.RtcEngineConfig

/**
 * Thin Agora RTC wrapper for dual-provider calls (`provider=agora`).
 * App ID / token / channel / uid come from the server grant — never embed AGORA_APP_CERTIFICATE.
 */
class AgoraCallSession(
    private val appContext: Context,
    private val onJoined: () -> Unit = {},
    private val onUserJoined: (Int) -> Unit = {},
    private val onUserOffline: (Int) -> Unit = {},
    private val onError: (String) -> Unit = {},
) {
    private var engine: RtcEngine? = null
    val remoteUids = linkedSetOf<Int>()
    @Volatile var joined: Boolean = false
        private set

    private val handler = object : IRtcEngineEventHandler() {
        override fun onJoinChannelSuccess(channel: String?, uid: Int, elapsed: Int) {
            joined = true
            onJoined()
        }

        override fun onUserJoined(uid: Int, elapsed: Int) {
            remoteUids.add(uid)
            onUserJoined(uid)
        }

        override fun onUserOffline(uid: Int, reason: Int) {
            remoteUids.remove(uid)
            onUserOffline(uid)
        }

        override fun onError(err: Int) {
            onError("Agora error $err")
        }
    }

    fun join(appId: String, channel: String, token: String, uid: Int, video: Boolean) {
        leave()
        val config = RtcEngineConfig().apply {
            mContext = appContext.applicationContext
            mAppId = appId
            mEventHandler = handler
        }
        val eng = RtcEngine.create(config)
        eng.setChannelProfile(Constants.CHANNEL_PROFILE_COMMUNICATION)
        eng.setClientRole(Constants.CLIENT_ROLE_BROADCASTER)
        eng.enableAudio()
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
        val code = eng.joinChannel(token.ifBlank { null }, channel, uid, options)
        require(code == 0) { "Agora join failed (code $code)" }
        engine = eng
    }

    fun setMic(enabled: Boolean) {
        engine?.muteLocalAudioStream(!enabled)
        engine?.enableLocalAudio(enabled)
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
    }
}
