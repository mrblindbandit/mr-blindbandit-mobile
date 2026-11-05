package net.mrblindbandit.app.connect

import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * Call-audio contract for Agora. Numbers match Agora RTC 4.x:
 * music high-quality stereo = 5 (48 kHz, stereo, up to 128 kbps),
 * game streaming = 3 (media volume), stereo processing = 2.
 */
object CallAudioPolicy {
    const val musicHighQualityStereo = 5
    const val gameStreamingScenario = 3
    const val stereoProcessingChannels = 2
    const val echoCancellation = true
    const val noiseSuppression = false
    const val aiNoiseSuppression = false
    const val automaticGainControl = true
    /** Unity gain. Agora treats 100 as the original signal, not a boost. */
    const val unityVolume = 100
    const val ainsModeBalanced = 0
}

/** One remote seat. Agora positions are ordered front, right, top. */
data class CallSpatialSeat(
    val index: Int,
    val front: Float,
    val right: Float,
    val top: Float,
    val forwardFront: Float,
    val forwardRight: Float,
    val forwardTop: Float,
    val spokenDirection: String,
)

data class CallAudioRoute(
    val raw: Int,
    val label: String,
    val kind: Kind,
    val headphoneEQ: HeadphoneEQ,
) {
    enum class Kind { SPEAKER, EARPIECE, WIRED, BLUETOOTH, OTHER }
    enum class HeadphoneEQ { OFF, OVER_EAR, IN_EAR }

    val isSpeaker: Boolean get() = kind == Kind.SPEAKER
    val isExternal: Boolean get() = kind == Kind.WIRED || kind == Kind.BLUETOOTH

    companion object {
        /** Agora route raw values. 0–5 and 10 match iOS. Raw 8 is a USB headset here and DisplayPort on iOS. */
        fun from(agoraRoute: Int): CallAudioRoute = when (agoraRoute) {
            3, 4 -> CallAudioRoute(agoraRoute, "speaker", Kind.SPEAKER, HeadphoneEQ.OFF)
            1 -> CallAudioRoute(agoraRoute, "earpiece", Kind.EARPIECE, HeadphoneEQ.OFF)
            0, 2, 6, 8 -> CallAudioRoute(
                agoraRoute,
                if (agoraRoute == 6 || agoraRoute == 8) "USB headset" else "wired headset",
                Kind.WIRED,
                HeadphoneEQ.OVER_EAR,
            )
            5, 10 -> CallAudioRoute(agoraRoute, "Bluetooth", Kind.BLUETOOTH, HeadphoneEQ.IN_EAR)
            9 -> CallAudioRoute(agoraRoute, "AirPlay", Kind.OTHER, HeadphoneEQ.OFF)
            else -> CallAudioRoute(agoraRoute, "audio device", Kind.OTHER, HeadphoneEQ.OFF)
        }
    }
}

/** Seats remote people on a virtual circle around the local listener. */
object CallSpatialLayout {
    const val RADIUS = 1.6f
    const val RECEIVE_RANGE = 30f
    const val MAX_HEARD = 16
    /** Plain-scene air absorption is about 0.1. Slightly under that keeps speech clear. */
    const val AIR_ATTENUATION = 0.08
    const val GROUP_ALONE_MS = 120_000L

    fun shouldEndImmediately(isGroup: Boolean, remotesRemaining: Int, hadRemote: Boolean): Boolean =
        hadRemote && remotesRemaining == 0 && !isGroup

    fun seats(count: Int): List<CallSpatialSeat> {
        if (count <= 0) return emptyList()
        val angles: List<Double> = when {
            count == 1 -> listOf(0.0)
            count <= 6 -> {
                val start = -PI / 2
                val step = PI / (count - 1)
                List(count) { start + step * it }
            }
            else -> List(count) { (2 * PI * it) / count }
        }
        return angles.mapIndexed { index, angle -> seat(index, angle) }
    }

    fun joinedAnnouncement(name: String, direction: String): String =
        "${spokenName(name)} joined, $direction."

    fun movedAnnouncement(name: String, direction: String): String =
        "${spokenName(name)} moved. Now $direction."

    fun speakingAnnouncement(name: String, direction: String?): String =
        if (!direction.isNullOrBlank()) "${spokenName(name)} is speaking, $direction."
        else "${spokenName(name)} is speaking."

    private fun spokenName(name: String): String = name.trim().ifBlank { "Someone" }

    private fun seat(index: Int, angle: Double): CallSpatialSeat {
        val front = (cos(angle) * RADIUS).toFloat()
        val right = (sin(angle) * RADIUS).toFloat()
        val top = 0f
        val length = sqrt(front * front + right * right + top * top)
        val forwardFront: Float
        val forwardRight: Float
        val forwardTop: Float
        if (length < 0.001f) {
            forwardFront = 1f
            forwardRight = 0f
            forwardTop = 0f
        } else {
            forwardFront = -front / length
            forwardRight = -right / length
            forwardTop = -top / length
        }
        return CallSpatialSeat(
            index = index,
            front = front,
            right = right,
            top = top,
            forwardFront = forwardFront,
            forwardRight = forwardRight,
            forwardTop = forwardTop,
            spokenDirection = direction(angle),
        )
    }

    /** Angle 0 is in front. Positive angles are to the listener's right. */
    fun direction(angle: Double): String {
        var degrees = angle * 180 / PI
        while (degrees > 180) degrees -= 360
        while (degrees < -180) degrees += 360
        return when {
            degrees in -22.5..22.5 -> "in front of you"
            degrees >= 22.5 && degrees < 67.5 -> "in front and to your right"
            degrees >= 67.5 && degrees < 112.5 -> "on your right"
            degrees >= 112.5 && degrees < 157.5 -> "behind you on the right"
            degrees >= 157.5 || degrees < -157.5 -> "behind you"
            degrees >= -67.5 && degrees < -22.5 -> "in front and to your left"
            degrees >= -112.5 && degrees < -67.5 -> "on your left"
            else -> "behind you on the left"
        }
    }
}
