package com.example.stickerswap

import android.content.Intent
import android.graphics.Bitmap
import android.graphics.ImageFormat
import android.graphics.Rect
import android.graphics.YuvImage
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.os.Build
import android.os.Bundle
import android.util.Log
import com.example.stickerswap.whatsapp.WhatsAppMethodHandler
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.stickerswap/share"
    private val VIDEO_CHANNEL = "com.example.stickerswap/video"
    private var sharedData: String? = null
    private var channel: MethodChannel? = null
    private var whatsAppHandler: WhatsAppMethodHandler? = null

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

        // WhatsApp stickers method channel
        whatsAppHandler = WhatsAppMethodHandler(this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, WhatsAppMethodHandler.CHANNEL_NAME)
            .setMethodCallHandler(whatsAppHandler)

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
                val maxFrames = call.argument<Int>("maxFrames") ?: 18
                if (videoPath == null) {
                    result.error("INVALID_ARG", "videoPath is null", null)
                    return@setMethodCallHandler
                }

                Thread {
                    val frames = mutableListOf<ByteArray>()
                    var extractor: MediaExtractor? = null
                    var decoder: MediaCodec? = null

                    try {
                        extractor = MediaExtractor()
                        extractor.setDataSource(videoPath)
                        var videoTrackIndex = -1
                        var mediaFormat: MediaFormat? = null
                        for (t in 0 until extractor.trackCount) {
                            val f = extractor.getTrackFormat(t)
                            val m = f.getString(MediaFormat.KEY_MIME) ?: ""
                            if (m.startsWith("video/")) {
                                videoTrackIndex = t
                                mediaFormat = f
                                break
                            }
                        }

                        if (videoTrackIndex >= 0 && mediaFormat != null) {
                            extractor.selectTrack(videoTrackIndex)
                            val width = mediaFormat.getInteger(MediaFormat.KEY_WIDTH)
                            val height = mediaFormat.getInteger(MediaFormat.KEY_HEIGHT)
                            val mime = mediaFormat.getString(MediaFormat.KEY_MIME) ?: "video/x-vnd.on2.vp9"
                            val durationUs = if (mediaFormat.containsKey(MediaFormat.KEY_DURATION)) {
                                mediaFormat.getLong(MediaFormat.KEY_DURATION)
                            } else {
                                2000000L
                            }

                            val safeDurationMs = (durationUs / 1000L).coerceAtMost(3000L)
                            val targetFrameCount = ((safeDurationMs / 1000.0) * targetFps).toInt().coerceIn(6, maxFrames)
                            val targetIntervalUs = if (targetFrameCount > 1) durationUs / targetFrameCount else durationUs

                            decoder = MediaCodec.createDecoderByType(mime)
                            decoder.configure(mediaFormat, null, null, 0)
                            decoder.start()

                            val bufferInfo = MediaCodec.BufferInfo()
                            var isEOS = false
                            val timeoutUs = 10000L
                            var stride = width
                            var sliceHeight = height
                            var colorFormat = 19
                            var nextTargetTimeUs = 0L

                            while (!isEOS && frames.size < targetFrameCount) {
                                val inIdx = decoder.dequeueInputBuffer(timeoutUs)
                                if (inIdx >= 0) {
                                    val inBuf = decoder.getInputBuffer(inIdx)
                                    if (inBuf != null) {
                                        val sampleSize = extractor.readSampleData(inBuf, 0)
                                        if (sampleSize < 0) {
                                            decoder.queueInputBuffer(inIdx, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                                        } else {
                                            decoder.queueInputBuffer(inIdx, 0, sampleSize, extractor.sampleTime, 0)
                                            extractor.advance()
                                        }
                                    }
                                }

                                val outIdx = decoder.dequeueOutputBuffer(bufferInfo, timeoutUs)
                                if (outIdx >= 0) {
                                    if ((bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) {
                                        isEOS = true
                                    }
                                    if (bufferInfo.size > 0 && bufferInfo.presentationTimeUs >= nextTargetTimeUs) {
                                        val outBuf = decoder.getOutputBuffer(outIdx)
                                        if (outBuf != null) {
                                            val rawYuv = ByteArray(bufferInfo.size)
                                            outBuf.position(bufferInfo.offset)
                                            outBuf.get(rawYuv, 0, bufferInfo.size)

                                            val ySize = stride * sliceHeight
                                            val uvSize = (stride / 2) * (sliceHeight / 2)
                                            val nv21 = ByteArray(stride * sliceHeight * 3 / 2)
                                            val actualYSize = minOf(ySize, rawYuv.size)
                                            System.arraycopy(rawYuv, 0, nv21, 0, actualYSize)

                                            if (colorFormat == 21) {
                                                // NV12: swap U and V to make NV21
                                                val uvStart = ySize
                                                for (j in 0 until uvSize) {
                                                    val idx = uvStart + j * 2
                                                    if (idx + 1 < rawYuv.size && ySize + j * 2 + 1 < nv21.size) {
                                                        nv21[ySize + j * 2] = rawYuv[idx + 1]
                                                        nv21[ySize + j * 2 + 1] = rawYuv[idx]
                                                    }
                                                }
                                            } else {
                                                // I420 (Planar): interleave V and U
                                                val uOffset = ySize
                                                val vOffset = ySize + uvSize
                                                var nv21Pos = ySize
                                                for (j in 0 until uvSize) {
                                                    if (vOffset + j < rawYuv.size && uOffset + j < rawYuv.size && nv21Pos + 1 < nv21.size) {
                                                        nv21[nv21Pos++] = rawYuv[vOffset + j]
                                                        nv21[nv21Pos++] = rawYuv[uOffset + j]
                                                    }
                                                }
                                            }

                                            try {
                                                val yuvImage = YuvImage(nv21, ImageFormat.NV21, width, height, intArrayOf(stride, stride))
                                                val stream = ByteArrayOutputStream()
                                                yuvImage.compressToJpeg(Rect(0, 0, width, height), 85, stream)
                                                frames.add(stream.toByteArray())
                                                nextTargetTimeUs += targetIntervalUs
                                            } catch (_: Exception) {}
                                        }
                                    }
                                    decoder.releaseOutputBuffer(outIdx, false)
                                } else if (outIdx == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                                    val outFormat = decoder.outputFormat
                                    if (outFormat.containsKey("stride")) stride = outFormat.getInteger("stride")
                                    if (outFormat.containsKey("slice-height")) sliceHeight = outFormat.getInteger("slice-height")
                                    if (outFormat.containsKey("color-format")) colorFormat = outFormat.getInteger("color-format")
                                }
                            }
                        }
                    } catch (e: Exception) {
                        Log.e("MainActivity", "MediaCodec extraction error, attempting fallback", e)
                    } finally {
                        try { decoder?.stop() } catch (_: Exception) {}
                        try { decoder?.release() } catch (_: Exception) {}
                        try { extractor?.release() } catch (_: Exception) {}
                    }

                    // Fallback to MediaMetadataRetriever if MediaCodec produced nothing
                    if (frames.isEmpty()) {
                        val retriever = MediaMetadataRetriever()
                        try {
                            retriever.setDataSource(videoPath)
                            val bitmap = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
                                retriever.getScaledFrameAtTime(0, MediaMetadataRetriever.OPTION_CLOSEST, 512, 512)
                            } else {
                                retriever.getFrameAtTime(0, MediaMetadataRetriever.OPTION_CLOSEST)
                            }
                            if (bitmap != null) {
                                val stream = ByteArrayOutputStream()
                                bitmap.compress(Bitmap.CompressFormat.PNG, 85, stream)
                                frames.add(stream.toByteArray())
                                bitmap.recycle()
                            }
                        } catch (e: Exception) {
                            Log.e("MainActivity", "Fallback retriever failed", e)
                        } finally {
                            try { retriever.release() } catch (_: Exception) {}
                        }
                    }

                    runOnUiThread {
                        result.success(frames)
                    }
                }.start()
            } else {
                result.notImplemented()
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        val handled = whatsAppHandler?.onActivityResult(requestCode, resultCode, data) ?: false
        if (!handled) {
            super.onActivityResult(requestCode, resultCode, data)
        }
    }
}
