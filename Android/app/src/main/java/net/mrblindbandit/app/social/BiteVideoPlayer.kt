package net.mrblindbandit.app.social

import android.net.Uri
import android.widget.MediaController
import android.widget.VideoView
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView

/**
 * Native in-app video for BanditBites (VideoView — no WebView, no external Intent).
 * TalkBack: Play/Pause button + status.
 */
@Composable
fun BiteVideoPlayer(
    videoUrl: String,
    modifier: Modifier = Modifier,
    autoPlay: Boolean = false,
    onPlaying: () -> Unit = {},
) {
    if (videoUrl.isBlank()) return
    var playing by remember(videoUrl) { mutableStateOf(autoPlay) }
    var error by remember(videoUrl) { mutableStateOf<String?>(null) }
    var videoViewRef by remember { mutableStateOf<VideoView?>(null) }

    Box(
        modifier
            .fillMaxWidth()
            .heightIn(min = 200.dp, max = 420.dp)
            .background(MaterialTheme.colorScheme.surfaceVariant)
            .semantics { contentDescription = if (playing) "BanditBite video, playing" else "BanditBite video, paused" },
    ) {
        AndroidView(
            factory = { ctx ->
                VideoView(ctx).apply {
                    val controller = MediaController(ctx)
                    controller.setAnchorView(this)
                    setMediaController(controller)
                    setOnPreparedListener { mp ->
                        mp.isLooping = true
                        error = null
                        if (autoPlay || playing) {
                            start()
                            playing = true
                            onPlaying()
                        }
                    }
                    setOnErrorListener { _, what, extra ->
                        error = "Video could not play ($what/$extra)."
                        playing = false
                        true
                    }
                    setOnCompletionListener { playing = false }
                    setVideoURI(Uri.parse(videoUrl))
                    videoViewRef = this
                    contentDescription = "BanditBite video player"
                }
            },
            update = { view ->
                if (playing && !view.isPlaying) {
                    view.start()
                    onPlaying()
                } else if (!playing && view.isPlaying) {
                    view.pause()
                }
            },
            modifier = Modifier.fillMaxWidth().heightIn(min = 200.dp, max = 420.dp),
        )
        TextButton(
            onClick = {
                val v = videoViewRef
                if (v == null) return@TextButton
                if (playing) {
                    v.pause()
                    playing = false
                } else {
                    v.start()
                    playing = true
                    onPlaying()
                }
            },
            modifier = Modifier.align(Alignment.BottomStart).padding(8.dp),
        ) {
            Text(if (playing) "Pause" else "Play")
        }
        if (error != null) {
            Text(
                error!!,
                color = MaterialTheme.colorScheme.error,
                modifier = Modifier.align(Alignment.Center).padding(16.dp),
            )
        }
    }

    DisposableEffect(videoUrl) {
        onDispose {
            videoViewRef?.stopPlayback()
            videoViewRef = null
        }
    }
}
