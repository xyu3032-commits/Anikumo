package com.anikumo.app

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.Locale

/**
 * Batch 158: system text-to-speech for the novel reader's
 * optional read-aloud feature. The Dart side owns the
 * chunk queue and feeds one utterance at a time; this
 * handler speaks it and reports completion back so the
 * queue can advance. Utterance callbacks arrive off the
 * main thread, so results are posted before touching the
 * channel.
 */
class TtsHandler(context: Context, private val channel: MethodChannel) :
    MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "com.anikumo.app/novel_tts"
    }

    private val mainHandler = Handler(Looper.getMainLooper())

    @Volatile
    private var ready = false

    private var tts: TextToSpeech? = null

    // Batch 270: speech settings are kept natively so values
    // set before the engine finishes initializing are
    // applied the moment it is ready.
    private var speechRate = 1.0f
    private var speechPitch = 1.0f
    private var voiceName = ""
    private var defaultVoice: android.speech.tts.Voice? = null

    private fun applySpeechSettings() {
        val engine = tts ?: return
        engine.setSpeechRate(speechRate)
        engine.setPitch(speechPitch)
        if (voiceName.isEmpty()) {
            defaultVoice?.let { engine.voice = it }
        } else {
            engine.voices?.firstOrNull { it.name == voiceName }?.let {
                engine.voice = it
            }
        }
    }

    // Batch 280 (#14): voice/pitch for ONE utterance.
    // Narration (altVoice=false) re-applies the global
    // settings, undoing any dialogue override the previous
    // utterance left on the engine. Dialogue asks for a
    // voice different from the narration voice; engines
    // with a single voice keep the narration voice and
    // take the caller's shifted pitch instead.
    private fun applyUtteranceVoice(
        engine: TextToSpeech,
        altVoice: Boolean,
        altPitch: Double?,
    ) {
        engine.setSpeechRate(speechRate)
        val narrationVoice: android.speech.tts.Voice? =
            if (voiceName.isEmpty()) {
                defaultVoice
            } else {
                engine.voices?.firstOrNull { it.name == voiceName }
                    ?: defaultVoice
            }
        if (!altVoice) {
            narrationVoice?.let { engine.voice = it }
            engine.setPitch(speechPitch)
            return
        }
        val alternate =
            engine.voices?.firstOrNull { it.name != narrationVoice?.name }
        if (alternate != null) {
            engine.voice = alternate
            engine.setPitch(speechPitch)
        } else {
            narrationVoice?.let { engine.voice = it }
            engine.setPitch((altPitch ?: speechPitch.toDouble()).toFloat())
        }
    }

    init {
        tts = TextToSpeech(context) { status ->
            if (status == TextToSpeech.SUCCESS) {
                val engine = tts
                if (engine != null) {
                    val langResult = engine.setLanguage(Locale.SIMPLIFIED_CHINESE)
                    if (langResult == TextToSpeech.LANG_MISSING_DATA ||
                        langResult == TextToSpeech.LANG_NOT_SUPPORTED
                    ) {
                        engine.setLanguage(Locale.getDefault())
                    }
                    defaultVoice = engine.voice
                    applySpeechSettings()
                    engine.setOnUtteranceProgressListener(
                        object : UtteranceProgressListener() {
                            override fun onStart(utteranceId: String?) {}

                            override fun onDone(utteranceId: String?) {
                                mainHandler.post {
                                    channel.invokeMethod(
                                        "onUtteranceDone", utteranceId ?: ""
                                    )
                                }
                            }

                            @Deprecated("Deprecated in Java")
                            override fun onError(utteranceId: String?) {
                                mainHandler.post {
                                    channel.invokeMethod(
                                        "onUtteranceError", utteranceId ?: ""
                                    )
                                }
                            }

                            override fun onError(utteranceId: String?, errorCode: Int) {
                                mainHandler.post {
                                    channel.invokeMethod(
                                        "onUtteranceError", utteranceId ?: ""
                                    )
                                }
                            }
                        }
                    )
                }
                ready = true
            }
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isAvailable" -> result.success(ready)
            "speak" -> {
                val text = call.argument<String>("text") ?: ""
                val id = call.argument<String>("id") ?: "u"
                val engine = tts
                if (!ready || engine == null) {
                    result.error("not_ready", "Speech engine is not ready", null)
                    return
                }
                // Batch 280 (#14): dialogue utterances carry
                // altVoice (and a fallback pitch); narration
                // carries neither and re-applies the globals.
                val altVoice = call.argument<Boolean>("altVoice") ?: false
                val altPitch = call.argument<Double>("pitch")
                applyUtteranceVoice(engine, altVoice, altPitch)
                engine.speak(text, TextToSpeech.QUEUE_FLUSH, null, id)
                result.success(null)
            }
            "stop" -> {
                tts?.stop()
                result.success(null)
            }
            "setRate" -> {
                speechRate = (call.argument<Double>("rate") ?: 1.0).toFloat()
                applySpeechSettings()
                result.success(null)
            }
            "setPitch" -> {
                speechPitch = (call.argument<Double>("pitch") ?: 1.0).toFloat()
                applySpeechSettings()
                result.success(null)
            }
            "getVoices" -> {
                val voices = tts?.voices
                    ?.map {
                        mapOf(
                            "name" to it.name,
                            "locale" to it.locale.toString(),
                        )
                    }
                    ?.sortedBy { it["name"] }
                    ?: emptyList()
                result.success(voices)
            }
            "setVoice" -> {
                voiceName = call.argument<String>("name") ?: ""
                applySpeechSettings()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }
}
