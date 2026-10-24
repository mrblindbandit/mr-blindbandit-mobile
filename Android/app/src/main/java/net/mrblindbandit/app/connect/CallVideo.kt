package net.mrblindbandit.app.connect

import androidx.compose.foundation.layout.*
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import io.livekit.android.room.Room
import io.livekit.android.room.track.VideoTrack
import kotlinx.coroutines.delay
import livekit.org.webrtc.SurfaceViewRenderer

@Composable
fun CallVideoGrid(room: Room) {
    var tracks by remember(room) { mutableStateOf<List<Pair<String, VideoTrack>>>(emptyList()) }
    LaunchedEffect(room) {
        while (true) {
            tracks = (listOf(room.localParticipant) + room.remoteParticipants.values).flatMap { participant ->
                participant.videoTrackPublications.mapNotNull { (_, track) -> (track as? VideoTrack)?.let { (participant.name ?: "Participant") to it } }
            }
            delay(500)
        }
    }
    Column {
        tracks.take(8).forEach { (name, track) ->
            key(track) {
                Text("Video: $name")
                AndroidView(
                    factory = { context -> SurfaceViewRenderer(context).also { room.initVideoRenderer(it); track.addRenderer(it); it.contentDescription = "Live video from $name" } },
                    modifier = Modifier.fillMaxWidth().height(180.dp),
                    onReset = null,
                    onRelease = { renderer -> track.removeRenderer(renderer); renderer.release() },
                    update = {},
                )
            }
        }
    }
}
