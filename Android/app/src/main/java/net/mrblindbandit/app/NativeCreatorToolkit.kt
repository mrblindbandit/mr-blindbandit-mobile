package net.mrblindbandit.app

import android.content.Context
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Slider
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import java.security.MessageDigest
import java.text.Normalizer
import java.time.LocalDate
import java.time.temporal.ChronoUnit
import java.util.Locale
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.roundToInt

enum class NativeCreatorTool(val title: String, val subtitle: String) {
    BPM("BPM Tapper", "Tap tempo without uploading audio"),
    ROYALTY("Royalty Split", "Calculate equal collaborator percentages"),
    STORAGE("Storage Estimator", "Estimate PCM audio storage"),
    BITRATE("Video Bitrate", "Estimate bitrate from size and duration"),
    ASPECT("Aspect Ratio", "Scale dimensions proportionally"),
    COUNTDOWN("Release Countdown", "Count days until release"),
    ISRC("ISRC Validator", "Check basic ISRC formatting"),
    UPC("UPC Validator", "Validate UPC-A check digits"),
    SLUG("Slug Generator", "Create clean URL slugs"),
    FILENAME("Filename Cleaner", "Create safe media filenames"),
    CASE("Text Case Converter", "Uppercase, lowercase, title case"),
    CAPTION("Caption Counter", "Count social caption characters"),
    HASHTAG("Hashtag Builder", "Turn keywords into hashtags"),
    CHECKSUM("SHA-256 Checksum", "Verify a local file"),
    CONTRAST("Contrast Checker", "Check WCAG text contrast"),
    QR_TEXT("QR Payload Prep", "Clean and verify QR payload text"),
    METADATA("Metadata Notes", "Build release metadata notes"),
    TIMECODE("Timecode Converter", "Convert frames to timecode"),
    SAMPLES("Sample Calculator", "Convert seconds to samples"),
    DURATION("Audio Duration", "Convert sample counts to duration")
}

@Composable
fun NativeCreatorToolkitScreen() {
    var selected by remember { mutableStateOf<NativeCreatorTool?>(null) }
    val haptic = LocalHapticFeedback.current

    if (selected == null) {
        LazyColumn(
            modifier = Modifier.fillMaxSize().padding(20.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            item {
                Text("Creator Toolkit", fontWeight = FontWeight.Bold, modifier = Modifier.semantics { heading() })
                Text("20 offline Android utilities. No WebView and no upload required.")
                HorizontalDivider(Modifier.padding(vertical = 8.dp))
            }
            items(NativeCreatorTool.entries) { tool ->
                Card(Modifier.fillMaxWidth()) {
                    Button(
                        onClick = { haptic.performHapticFeedback(HapticFeedbackType.LongPress); selected = tool },
                        modifier = Modifier.fillMaxWidth().padding(10.dp)
                    ) {
                        Column(Modifier.fillMaxWidth()) {
                            Text(tool.title, fontWeight = FontWeight.SemiBold)
                            Text(tool.subtitle)
                        }
                    }
                }
            }
        }
    } else {
        Column(Modifier.fillMaxSize()) {
            Row(Modifier.fillMaxWidth().padding(12.dp), horizontalArrangement = Arrangement.SpaceBetween) {
                Button(onClick = { haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove); selected = null }) { Text("Back") }
                Text(selected!!.title, fontWeight = FontWeight.Bold, modifier = Modifier.padding(12.dp))
            }
            when (selected!!) {
                NativeCreatorTool.BPM -> BPMTool()
                NativeCreatorTool.ROYALTY -> RoyaltyTool()
                NativeCreatorTool.STORAGE -> StorageTool()
                NativeCreatorTool.BITRATE -> BitrateTool()
                NativeCreatorTool.ASPECT -> AspectTool()
                NativeCreatorTool.COUNTDOWN -> CountdownTool()
                NativeCreatorTool.ISRC -> IsrcTool()
                NativeCreatorTool.UPC -> UpcTool()
                NativeCreatorTool.SLUG -> SlugTool(false)
                NativeCreatorTool.FILENAME -> SlugTool(true)
                NativeCreatorTool.CASE -> CaseTool()
                NativeCreatorTool.CAPTION -> CaptionTool()
                NativeCreatorTool.HASHTAG -> HashtagTool()
                NativeCreatorTool.CHECKSUM -> ChecksumTool()
                NativeCreatorTool.CONTRAST -> ContrastTool()
                NativeCreatorTool.QR_TEXT -> QrPayloadTool()
                NativeCreatorTool.METADATA -> MetadataTool()
                NativeCreatorTool.TIMECODE -> TimecodeTool()
                NativeCreatorTool.SAMPLES -> SamplesTool()
                NativeCreatorTool.DURATION -> DurationTool()
            }
        }
    }
}

@Composable
private fun ToolColumn(content: @Composable () -> Unit) {
    LazyColumn(Modifier.fillMaxSize().padding(20.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) { item { content() } }
}

@Composable
private fun BPMTool() {
    var taps by remember { mutableStateOf(listOf<Long>()) }
    val bpm = if (taps.size < 2) 0 else {
        val intervals = taps.zipWithNext { a, b -> b - a }
        val avg = intervals.average().coerceAtLeast(1.0)
        (60000.0 / avg).roundToInt()
    }
    val haptic = LocalHapticFeedback.current
    ToolColumn {
        Text("BPM: ${if (bpm == 0) "—" else bpm}")
        Button(onClick = { haptic.performHapticFeedback(HapticFeedbackType.LongPress); taps = (taps + System.currentTimeMillis()).takeLast(8) }) { Text("Tap Beat") }
        Button(onClick = { taps = emptyList() }) { Text("Reset") }
    }
}

@Composable
private fun RoyaltyTool() {
    var people by remember { mutableStateOf("2") }
    val n = people.toIntOrNull()?.coerceIn(1, 100) ?: 1
    ToolColumn {
        OutlinedTextField(value = people, onValueChange = { people = it.filter(Char::isDigit) }, label = { Text("People") })
        Text("Each person: ${"%.2f".format(Locale.US, 100.0 / n)}%")
    }
}

@Composable
private fun StorageTool() {
    var minutes by remember { mutableStateOf("3") }
    var sampleRate by remember { mutableStateOf("48000") }
    var bits by remember { mutableStateOf("24") }
    var channels by remember { mutableStateOf("2") }
    val mb = (minutes.toDoubleOrNull() ?: 0.0) * 60 * (sampleRate.toDoubleOrNull() ?: 0.0) * (bits.toDoubleOrNull() ?: 0.0) * (channels.toDoubleOrNull() ?: 0.0) / 8 / 1_000_000
    ToolColumn {
        NumberField("Minutes", minutes) { minutes = it }
        NumberField("Sample rate", sampleRate) { sampleRate = it }
        NumberField("Bit depth", bits) { bits = it }
        NumberField("Channels", channels) { channels = it }
        Text("Estimated size: ${"%.1f".format(Locale.US, mb)} MB")
    }
}

@Composable
private fun BitrateTool() {
    var size by remember { mutableStateOf("100") }
    var minutes by remember { mutableStateOf("3") }
    val mbps = (size.toDoubleOrNull() ?: 0.0) * 8 / max((minutes.toDoubleOrNull() ?: 0.0) * 60, 1.0)
    ToolColumn {
        NumberField("Target size MB", size) { size = it }
        NumberField("Duration minutes", minutes) { minutes = it }
        Text("Approx bitrate: ${"%.2f".format(Locale.US, mbps)} Mbps")
    }
}

@Composable
private fun AspectTool() {
    var width by remember { mutableStateOf("1920") }
    var height by remember { mutableStateOf("1080") }
    var targetWidth by remember { mutableStateOf("1080") }
    val h = if ((width.toDoubleOrNull() ?: 0.0) == 0.0) 0 else ((targetWidth.toDoubleOrNull() ?: 0.0) * (height.toDoubleOrNull() ?: 0.0) / (width.toDoubleOrNull() ?: 1.0)).roundToInt()
    ToolColumn {
        NumberField("Original width", width) { width = it }
        NumberField("Original height", height) { height = it }
        NumberField("Target width", targetWidth) { targetWidth = it }
        Text("Target height: $h px")
    }
}

@Composable
private fun CountdownTool() {
    var dateText by remember { mutableStateOf(LocalDate.now().plusDays(14).toString()) }
    val days = runCatching { max(0, ChronoUnit.DAYS.between(LocalDate.now(), LocalDate.parse(dateText)).toInt()) }.getOrNull()
    ToolColumn {
        OutlinedTextField(value = dateText, onValueChange = { dateText = it }, label = { Text("Release date YYYY-MM-DD") })
        Text(days?.let { "Days remaining: $it" } ?: "Enter a valid ISO date")
    }
}

@Composable
private fun IsrcTool() {
    var code by remember { mutableStateOf("") }
    val clean = code.uppercase().replace("-", "")
    val valid = Regex("^[A-Z]{2}[A-Z0-9]{3}[0-9]{7}$").matches(clean)
    ToolColumn { OutlinedTextField(value = code, onValueChange = { code = it }, label = { Text("ISRC") }); Text(if (code.isBlank()) "Enter an ISRC" else if (valid) "Valid format" else "Invalid format") }
}

@Composable
private fun UpcTool() {
    var code by remember { mutableStateOf("") }
    val valid = upcValid(code)
    ToolColumn { OutlinedTextField(value = code, onValueChange = { code = it.filter(Char::isDigit).take(12) }, label = { Text("UPC-A") }); Text(if (code.isBlank()) "Enter 12 digits" else if (valid) "Valid UPC-A" else "Invalid UPC-A") }
}

private fun upcValid(code: String): Boolean {
    if (code.length != 12 || !code.all(Char::isDigit)) return false
    val d = code.map { it.digitToInt() }
    val sum = d.take(11).mapIndexed { i, n -> n * if (i % 2 == 0) 3 else 1 }.sum()
    return (10 - sum % 10) % 10 == d[11]
}

private fun slugify(value: String): String = Normalizer.normalize(value, Normalizer.Form.NFD)
    .replace(Regex("\\p{Mn}+"), "")
    .lowercase()
    .replace(Regex("[^a-z0-9]+"), "-")
    .trim('-')

@Composable
private fun SlugTool(filename: Boolean) {
    var text by remember { mutableStateOf("") }
    val result = if (filename) slugify(text).replace('-', '_') else slugify(text)
    ToolColumn { OutlinedTextField(value = text, onValueChange = { text = it }, label = { Text(if (filename) "Filename" else "Title") }); Text(result) }
}

@Composable
private fun CaseTool() {
    var text by remember { mutableStateOf("") }
    ToolColumn {
        OutlinedTextField(value = text, onValueChange = { text = it }, label = { Text("Text") }, minLines = 4)
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Button(onClick = { text = text.uppercase() }) { Text("UPPER") }
            Button(onClick = { text = text.lowercase() }) { Text("lower") }
            Button(onClick = { text = text.split(" ").joinToString(" ") { it.replaceFirstChar { c -> c.titlecase() } } }) { Text("Title") }
        }
    }
}

@Composable
private fun CaptionTool() {
    var text by remember { mutableStateOf("") }
    ToolColumn {
        OutlinedTextField(value = text, onValueChange = { text = it }, label = { Text("Caption") }, minLines = 6)
        Text("Characters: ${text.length}")
        Text("Words: ${text.trim().split(Regex("\\s+")).filter { it.isNotBlank() }.size}")
    }
}

@Composable
private fun HashtagTool() {
    var text by remember { mutableStateOf("") }
    val tags = text.split(Regex("[,\\s]+"))
        .map { it.filter(Char::isLetterOrDigit) }
        .filter { it.isNotBlank() }
        .joinToString(" ") { "#$it" }
    ToolColumn { OutlinedTextField(value = text, onValueChange = { text = it }, label = { Text("Keywords") }); Text(tags) }
}

@Composable
private fun ChecksumTool() {
    val context = LocalContext.current
    var hash by remember { mutableStateOf("") }
    val launcher = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri: Uri? ->
        if (uri != null) hash = sha256(context, uri) ?: "Could not read file"
    }
    ToolColumn {
        Button(onClick = { launcher.launch(arrayOf("*/*")) }) { Text("Choose File") }
        if (hash.isNotBlank()) Text(hash)
    }
}

private fun sha256(context: Context, uri: Uri): String? = runCatching {
    val digest = MessageDigest.getInstance("SHA-256")
    context.contentResolver.openInputStream(uri)?.use { input ->
        val buffer = ByteArray(8192)
        while (true) {
            val read = input.read(buffer)
            if (read <= 0) break
            digest.update(buffer, 0, read)
        }
    } ?: return@runCatching null
    digest.digest().joinToString("") { "%02x".format(it) }
}.getOrNull()

private fun luminance(hex: String): Double? {
    val s = hex.trim().removePrefix("#")
    if (s.length != 6) return null
    val n = s.toIntOrNull(16) ?: return null
    val rgb = listOf((n shr 16) and 255, (n shr 8) and 255, n and 255).map { v ->
        val x = v / 255.0
        if (x <= 0.03928) x / 12.92 else ((x + 0.055) / 1.055).pow(2.4)
    }
    return 0.2126 * rgb[0] + 0.7152 * rgb[1] + 0.0722 * rgb[2]
}

@Composable
private fun ContrastTool() {
    var fg by remember { mutableStateOf("FFFFFF") }
    var bg by remember { mutableStateOf("000000") }
    val ratio = remember(fg, bg) {
        val a = luminance(fg); val b = luminance(bg)
        if (a == null || b == null) null else (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
    ToolColumn {
        OutlinedTextField(value = fg, onValueChange = { fg = it }, label = { Text("Foreground hex") })
        OutlinedTextField(value = bg, onValueChange = { bg = it }, label = { Text("Background hex") })
        Text(ratio?.let { "Contrast: ${"%.2f".format(Locale.US, it)}:1" } ?: "Invalid color")
        if (ratio != null) Text(if (ratio >= 4.5) "Passes normal-text WCAG AA" else "Does not pass normal-text WCAG AA")
    }
}

@Composable
private fun QrPayloadTool() {
    var text by remember { mutableStateOf("https://mrblindbandit.net") }
    val clean = text.trim()
    ToolColumn {
        OutlinedTextField(value = text, onValueChange = { text = it }, label = { Text("QR text or URL") }, minLines = 3)
        Text("Payload bytes: ${clean.toByteArray().size}")
        Text(if (clean.startsWith("https://")) "Secure HTTPS URL" else "Plain text / non-HTTPS payload")
    }
}

@Composable
private fun MetadataTool() {
    var title by remember { mutableStateOf("") }
    var artist by remember { mutableStateOf("") }
    var label by remember { mutableStateOf("Blindbandit Records") }
    var year by remember { mutableStateOf(LocalDate.now().year.toString()) }
    val notes = "Title: $title\nArtist: $artist\nLabel: $label\nYear: $year\nCopyright: © $year $label\nPhonographic: ℗ $year $label"
    ToolColumn {
        OutlinedTextField(value = title, onValueChange = { title = it }, label = { Text("Title") })
        OutlinedTextField(value = artist, onValueChange = { artist = it }, label = { Text("Artist") })
        OutlinedTextField(value = label, onValueChange = { label = it }, label = { Text("Label") })
        OutlinedTextField(value = year, onValueChange = { year = it.filter(Char::isDigit).take(4) }, label = { Text("Year") })
        Text(notes)
    }
}

@Composable
private fun TimecodeTool() {
    var frames by remember { mutableStateOf("0") }
    var fps by remember { mutableStateOf("30") }
    val f = frames.toLongOrNull() ?: 0L
    val rate = (fps.toIntOrNull() ?: 30).coerceAtLeast(1)
    val seconds = f / rate
    val frame = f % rate
    val tc = "%02d:%02d:%02d:%02d".format(seconds / 3600, (seconds % 3600) / 60, seconds % 60, frame)
    ToolColumn { NumberField("Frames", frames) { frames = it }; NumberField("FPS", fps) { fps = it }; Text("Timecode: $tc") }
}

@Composable
private fun SamplesTool() {
    var seconds by remember { mutableStateOf("60") }
    var rate by remember { mutableStateOf("48000") }
    val samples = ((seconds.toDoubleOrNull() ?: 0.0) * (rate.toDoubleOrNull() ?: 0.0)).toLong()
    ToolColumn { NumberField("Seconds", seconds) { seconds = it }; NumberField("Sample rate", rate) { rate = it }; Text("Samples: $samples") }
}

@Composable
private fun DurationTool() {
    var samples by remember { mutableStateOf("2880000") }
    var rate by remember { mutableStateOf("48000") }
    val seconds = (samples.toDoubleOrNull() ?: 0.0) / max(rate.toDoubleOrNull() ?: 1.0, 1.0)
    ToolColumn { NumberField("Samples", samples) { samples = it }; NumberField("Sample rate", rate) { rate = it }; Text("Duration: ${"%.2f".format(Locale.US, seconds)} seconds") }
}

@Composable
private fun NumberField(label: String, value: String, onValueChange: (String) -> Unit) {
    OutlinedTextField(value = value, onValueChange = { onValueChange(it.filter { c -> c.isDigit() || c == '.' }) }, label = { Text(label) })
}
