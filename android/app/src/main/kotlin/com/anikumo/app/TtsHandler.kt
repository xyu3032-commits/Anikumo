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
                engine.speak(text, TextToSpeech.QUEUE_FLUSH, null, id)
                result.success(null)
            }
            "stop" -> {
                tts?.stop()
                result.success(null)
            }
            "setRate" -> {
                val rate = (call.argument<Double>("rate") ?: 1.0).toFloat()
                tts?.setSpeechRate(rate)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }
}
