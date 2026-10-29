package com.example.stickerswap

import android.content.Intent
import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.stickerswap/share"
    private val VIDEO_CHANNEL = "com.example.stickerswap/video"
    private var sharedData: String? = null
    private var channel: MethodChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleIntent(intent)
        sharedData?.let { data ->
            channel?.invokeMethod("onSharedText", data)
            sharedData = null
        }
    }

    private fun handleIntent(intent: Intent?) {
        if (intent == null) return
        val action = intent.action
        val type = intent.type

        if (Intent.ACTION_SEND == action && type == "text/plain") {
            sharedData = intent.getStringExtra(Intent.EXTRA_TEXT)
        } else if (Intent.ACTION_VIEW == action) {
            sharedData = intent.dataString
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        channel?.setMethodCallHandler { call, result ->
            if (call.method == "getInitialSharedText") {
                result.success(sharedData)
                sharedData = null
            } else {
                result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, VIDEO_CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "extractFrames") {
                val videoPath = call.argument<String>("videoPath")
                val targetFps = call.argument<Int>("fps") ?: 12
                val maxFrames = call.argument<Int>("maxFrames") ?: 24
                if (videoPath == null) {
                    result.error("INVALID_ARG", "videoPath is null", null)
                    return@setMethodCallHandler
                }

                Thread {
                    val retriever = MediaMetadataRetriever()
                    try {
                        retriever.setDataSource(videoPath)
                        val durationStr = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                        val durationMs = durationStr?.toLongOrNull() ?: 2000L
                        val safeDurationMs = durationMs.coerceAtMost(3000L) // WhatsApp max 3s
                        
                        val frameCount = ((safeDurationMs / 1000.0) * targetFps).toInt().coerceIn(4, maxFrames)
                        val intervalUs = (safeDurationMs * 1000L) / frameCount

                        val frames = mutableListOf<ByteArray>()
                        for (i in 0 until frameCount) {
                            val timeUs = i * intervalUs
                            val bitmap = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
                                retriever.getScaledFrameAtTime(timeUs, MediaMetadataRetriever.OPTION_CLOSEST, 512, 512)
                            } else {
                                retriever.getFrameAtTime(timeUs, MediaMetadataRetriever.OPTION_CLOSEST)
                            }

                            if (bitmap != null) {
                                val stream = ByteArrayOutputStream()
                                bitmap.compress(Bitmap.CompressFormat.PNG, 85, stream)
                                frames.add(stream.toByteArray())
                                bitmap.recycle()
                            }
                        }
                        runOnUiThread {
                            result.success(frames)
                        }
                    } catch (e: Exception) {
                        runOnUiThread {
                            result.error("EXTRACTION_ERROR", e.localizedMessage, null)
                        }
                    } finally {
                        try {
                            retriever.release()
                        } catch (_: Exception) {}
                    }
                }.start()
            } else {
                result.notImplemented()
            }
        }
    }
}
