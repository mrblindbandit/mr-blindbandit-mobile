package net.mrblindbandit.app.connect

import android.content.Context
import io.agora.rtc2.ChannelMediaOptions
import io.agora.rtc2.Constants
import io.agora.rtc2.IRtcEngineEventHandler
import io.agora.rtc2.RtcEngine
import io.agora.rtc2.RtcEngineConfig

/**
 * Agora RTC session. Production tokens are user-account tokens (`buildTokenWithUserAccount`);
 * those must join with [RtcEngine.joinChannelWithUserAccount]. Numeric uid grants still use
 * [RtcEngine.joinChannel].
 */
class AgoraCallSession(
    private val appContext: Context,
    private val onJoined: () -> Unit = {},
    private val onUserJoined: (Int) -> Unit = {},
    private val onUserOffline: (Int) -> Unit = {},
    private val onError: (Int) -> Unit = {},
) {
    private var engine: RtcEngine? = null
    val remoteUids = linkedSetOf<Int>()
    @Volatile var joined: Boolean = false
        private set

    private val handler = object : IRtcEngineEventHandler() {
        override fun onJoinChannelSuccess(channel: String?, uid: Int, elapsed: Int) {
            joined = true
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
            CallLog.i("agora remote offline uid=$uid reason=$reason")
            onUserOffline(uid)
        }

        override fun onError(err: Int) {
            CallLog.e("agora onError code=$err")
            onError(err)
        }
    }

    fun join(
        appId: String,
        channel: String,
        token: String,
        uid: Int,
        userAccount: String?,
        video: Boolean,
        echoCancellation: Boolean,
        noiseSuppression: Boolean,
    ) {
        leave()
        val config = RtcEngineConfig().apply {
            mContext = appContext.applicationContext
            mAppId = appId
            mEventHandler = handler
        }
        val eng = RtcEngine.create(config)
        eng.setChannelProfile(Constants.CHANNEL_PROFILE_COMMUNICATION)
        eng.setClientRole(Constants.CLIENT_ROLE_BROADCASTER)
        eng.setParameters("{\"che.audio.aec.enable\":$echoCancellation}")
        eng.setParameters("{\"che.audio.ans.enable\":$noiseSuppression}")
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
        val account = userAccount?.trim().orEmpty()
        val code = if (account.isNotEmpty()) {
            val registered = eng.registerLocalUserAccount(appId, account)
            CallLog.i("agora registerLocalUserAccount code=$registered accountLen=${account.length}")
            eng.joinChannelWithUserAccount(token.ifBlank { null }, channel, account, options)
        } else {
            eng.joinChannel(token.ifBlank { null }, channel, uid, options)
        }
        CallLog.i("agora join returned code=$code userAccount=${account.isNotEmpty()} video=$video")
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

    companion object {
        /** Errors that mean this grant will not connect. Transient network blips are excluded. */
        val FATAL_ERRORS = setOf(1, 2, 5, 7, 17, 101, 102, 109, 110)
    }
}
