package net.mrblindbandit.app.ai

import android.Manifest
import android.content.Intent
import android.os.Build
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics

/** Android 12+ on-device recognizer only; never silently uses a network recognizer. */
@Composable
fun LocalCaptionsPanel() {
    val context = LocalContext.current
    val available = remember { Build.VERSION.SDK_INT >= 31 && SpeechRecognizer.isOnDeviceRecognitionAvailable(context) }
    var recognizer by remember { mutableStateOf<SpeechRecognizer?>(null) }
    var status by remember { mutableStateOf("") }
    var listening by remember { mutableStateOf(false) }
    fun start() {
        if (!available || Build.VERSION.SDK_INT < 31) return
        recognizer?.destroy()
        val service = SpeechRecognizer.createOnDeviceSpeechRecognizer(context)
        recognizer = service
        service.setRecognitionListener(object : RecognitionListener {
            override fun onReadyForSpeech(params: android.os.Bundle?) { listening = true; status = "Listening on this device" }
            override fun onBeginningOfSpeech() {}
            override fun onRmsChanged(rmsdB: Float) {}
            override fun onBufferReceived(buffer: ByteArray?) {}
            override fun onEndOfSpeech() { listening = false }
            override fun onError(error: Int) { listening = false; status = "Speech recognition stopped (error $error). Tap Start to retry." }
            override fun onResults(results: android.os.Bundle?) { listening = false; status = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull() ?: "No speech recognized" }
            override fun onPartialResults(partialResults: android.os.Bundle?) { partialResults?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull()?.let { status = it } }
            override fun onEvent(eventType: Int, params: android.os.Bundle?) {}
        })
        listening = true
        service.startListening(Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM).putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true))
    }
    val permission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        if (granted) start() else { status = "Microphone permission is needed for captions." }
    }
    DisposableEffect(Unit) { onDispose { recognizer?.cancel(); recognizer?.destroy() } }
    Text("Captions transcribe nearby microphone speech on supported devices. They do not capture the other person's call audio.")
    if (!available) Text("On-device speech recognition is unavailable on this device.")
    Button(enabled = available, onClick = {
        if (listening) { recognizer?.cancel(); listening = false; status = "Captions stopped" }
        else permission.launch(Manifest.permission.RECORD_AUDIO)
    }) { Text(if (listening) "Stop captions" else "Start on-device captions") }
    Text(status, modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite })
}
