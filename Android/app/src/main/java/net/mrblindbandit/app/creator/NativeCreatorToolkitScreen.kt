package net.mrblindbandit.app.creator

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Slider
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlin.math.roundToInt

private data class Tool(val title: String, val subtitle: String, val content: @Composable () -> Unit)

@Composable
fun NativeCreatorToolkitScreen() {
    var selected by remember { mutableStateOf<String?>(null) }
    val tools = listOf(
        Tool("Metronome BPM", "Set a practice tempo") { MetronomeTool() },
        Tool("Key / BPM notes", "Session key and tempo notes") { KeyBpmTool() },
        Tool("Setlist notes", "Gig setlist on device") { SetlistTool() },
        Tool("Release checklist", "Pre-release QA") { ChecklistTool() },
        Tool("Lyric scratchpad", "Draft verses offline") { LyricTool() },
        Tool("Loudness tips", "LUFS / true-peak guidance") { LoudnessTool() },
        Tool("Cover size checker", "Validate square covers") { CoverSizeTool() },
        Tool("Hashtag / blurb helper", "Promo copy") { HashtagTool() },
        Tool("BPM tapper", "Tap tempo") { BpmTapTool() },
        Tool("Royalty split", "Collaborator percentages") { RoyaltyTool() }
    )

    if (selected == null) {
        LazyColumn(Modifier.fillMaxSize().padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            item {
                Text("Create", fontSize = 28.sp, fontWeight = FontWeight.Bold, modifier = Modifier.semantics { heading() })
                Text("Native musician and creator utilities. No upload required.", color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            items(tools) { tool ->
                Card(Modifier.fillMaxWidth()) {
                    Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        Text(tool.title, fontWeight = FontWeight.SemiBold)
                        Text(tool.subtitle, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        Button(onClick = { selected = tool.title }) { Text("Open") }
                    }
                }
            }
        }
    } else {
        val tool = tools.first { it.title == selected }
        Column(Modifier.fillMaxSize().padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Button(onClick = { selected = null }) { Text("Back to tools") }
            Text(tool.title, fontSize = 22.sp, fontWeight = FontWeight.Bold, modifier = Modifier.semantics { heading() })
            tool.content()
        }
    }
}

@Composable private fun MetronomeTool() {
    var bpm by remember { mutableFloatStateOf(120f) }
    Text("${bpm.roundToInt()} BPM", fontSize = 32.sp, fontWeight = FontWeight.Bold)
    Slider(value = bpm, onValueChange = { bpm = it }, valueRange = 40f..240f)
}

@Composable private fun KeyBpmTool() {
    var notes by remember { mutableStateOf("") }
    OutlinedTextField(notes, { notes = it }, modifier = Modifier.fillMaxWidth(), label = { Text("Key / tempo notes") })
}

@Composable private fun SetlistTool() {
    var draft by remember { mutableStateOf("") }
    var items by remember { mutableStateOf(listOf<String>()) }
    OutlinedTextField(draft, { draft = it }, modifier = Modifier.fillMaxWidth(), label = { Text("Song / key / BPM") })
    Button(onClick = {
        val t = draft.trim(); if (t.isNotEmpty()) { items = items + t; draft = "" }
    }) { Text("Add") }
    items.forEachIndexed { i, s -> Text("${i + 1}. $s") }
}

@Composable private fun ChecklistTool() {
    val labels = listOf("WAV 24-bit master", "−14 LUFS streaming", "True peak ≤ −1 dBTP", "3000×3000 cover", "ISRC assigned", "Credits proofed")
    var done by remember { mutableStateOf(List(labels.size) { false }) }
    labels.forEachIndexed { i, label ->
        Button(onClick = { done = done.toMutableList().also { it[i] = !it[i] } }, modifier = Modifier.fillMaxWidth()) {
            Text("${if (done[i]) "✓" else "○"} $label")
        }
    }
}

@Composable private fun LyricTool() {
    var text by remember { mutableStateOf("") }
    OutlinedTextField(text, { text = it }, modifier = Modifier.fillMaxWidth(), label = { Text("Lyrics") }, minLines = 8)
    Text("${text.split(Regex("\\s+")).filter { it.isNotBlank() }.size} words")
}

@Composable private fun LoudnessTool() {
    Text("Spotify / Apple Music ≈ −14 LUFS")
    Text("True peak ≤ −1.0 dBTP")
    Text("Leave headroom before limiting. A/B at matched loudness.")
}

@Composable private fun CoverSizeTool() {
    var w by remember { mutableStateOf("3000") }
    var h by remember { mutableStateOf("3000") }
    OutlinedTextField(w, { w = it }, label = { Text("Width px") })
    OutlinedTextField(h, { h = it }, label = { Text("Height px") })
    val wi = w.toIntOrNull() ?: 0
    val hi = h.toIntOrNull() ?: 0
    Text(when {
        wi == hi && wi >= 3000 -> "Store-ready square."
        wi == hi && wi >= 1400 -> "Acceptable; 3000 preferred."
        wi != hi -> "Not square — stores need 1:1."
        else -> "Too small."
    }, fontWeight = FontWeight.SemiBold)
}

@Composable private fun HashtagTool() {
    var title by remember { mutableStateOf("") }
    var vibe by remember { mutableStateOf("") }
    var out by remember { mutableStateOf("") }
    OutlinedTextField(title, { title = it }, label = { Text("Title") }, modifier = Modifier.fillMaxWidth())
    OutlinedTextField(vibe, { vibe = it }, label = { Text("Keywords") }, modifier = Modifier.fillMaxWidth())
    Button(onClick = {
        val tags = vibe.split(",").map { "#${it.trim().replace(" ", "")}" }.filter { it.length > 1 }
        out = "“${title.ifBlank { "New release" }}” is out now on Blindbandit Records.\n\n${(tags + listOf("#BlindbanditRecords", "#MrBlindBandit")).joinToString(" ")}"
    }) { Text("Build blurb") }
    if (out.isNotBlank()) Text(out)
}

@Composable private fun BpmTapTool() {
    var taps by remember { mutableStateOf(listOf<Long>()) }
    var bpm by remember { mutableStateOf("—") }
    Button(onClick = {
        val now = System.currentTimeMillis()
        taps = (taps + now).takeLast(8)
        if (taps.size >= 2) {
            val intervals = taps.zipWithNext { a, b -> b - a }
            val avg = intervals.average()
            if (avg > 0) bpm = (60000.0 / avg).roundToInt().toString()
        }
    }, modifier = Modifier.fillMaxWidth()) { Text("Tap") }
    Text("$bpm BPM", fontSize = 28.sp, fontWeight = FontWeight.Bold)
}

@Composable private fun RoyaltyTool() {
    var a by remember { mutableFloatStateOf(50f) }
    Text("Artist A: ${a.roundToInt()}%")
    Slider(value = a, onValueChange = { a = it }, valueRange = 0f..100f)
    Text("Artist B: ${(100 - a).roundToInt()}%")
}
