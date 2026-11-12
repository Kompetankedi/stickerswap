package com.example.stickerswap

import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.ImageFormat
import android.graphics.Rect
import android.graphics.YuvImage
import android.media.Image
import android.media.MediaCodec
import android.media.MediaCodecList
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
import java.io.File
import java.io.FileOutputStream
import kotlin.math.roundToInt

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
                val targetFps = call.argument<Int>("fps") ?: 8
                val maxFrames = call.argument<Int>("maxFrames") ?: 22
                if (videoPath == null) {
                    result.error("INVALID_ARG", "videoPath is null", null)
                    return@setMethodCallHandler
                }

                Thread {
                    val response = extractVideoFrames(videoPath, targetFps, maxFrames)
                    runOnUiThread {
                        result.success(response)
                    }
                }.start()
            } else if (call.method == "compressStaticWebP") {
                val inputPath = call.argument<String>("inputPath")
                val outputPath = call.argument<String>("outputPath")
                if (inputPath == null || outputPath == null) {
                    result.error("INVALID_ARG", "inputPath and outputPath cannot be null", null)
                    return@setMethodCallHandler
                }

                Thread {
                    try {
                        val srcBitmap = BitmapFactory.decodeFile(inputPath)
                        if (srcBitmap == null) {
                            runOnUiThread { result.error("DECODE_FAIL", "Cannot decode static sticker: $inputPath", null) }
                            return@Thread
                        }

                        val targetSize = 512
                        val padding = 16
                        val maxDraw = targetSize - (padding * 2)

                        val srcW = srcBitmap.width
                        val srcH = srcBitmap.height
                        val scale = minOf(maxDraw.toFloat() / srcW, maxDraw.toFloat() / srcH)
                        val dstW = (srcW * scale).toInt().coerceAtLeast(1)
                        val dstH = (srcH * scale).toInt().coerceAtLeast(1)

                        val scaledBitmap = Bitmap.createScaledBitmap(srcBitmap, dstW, dstH, true)
                        if (scaledBitmap != srcBitmap) {
                            srcBitmap.recycle()
                        }

                        val finalBitmap = Bitmap.createBitmap(targetSize, targetSize, Bitmap.Config.ARGB_8888)
                        val canvas = Canvas(finalBitmap)
                        val left = ((targetSize - dstW) / 2).toFloat()
                        val top = ((targetSize - dstH) / 2).toFloat()
                        canvas.drawBitmap(scaledBitmap, left, top, null)
                        scaledBitmap.recycle()

                        val format = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                            Bitmap.CompressFormat.WEBP_LOSSY
                        } else {
                            @Suppress("DEPRECATION")
                            Bitmap.CompressFormat.WEBP
                        }

                        val outFile = File(outputPath)
                        outFile.parentFile?.mkdirs()

                        var quality = 85
                        var stream = ByteArrayOutputStream()
                        finalBitmap.compress(format, quality, stream)

                        val qualities = intArrayOf(70, 55, 40, 25, 15)
                        var qIdx = 0
                        while (stream.size() > 96 * 1024 && qIdx < qualities.size) {
                            quality = qualities[qIdx++]
                            stream = ByteArrayOutputStream()
                            finalBitmap.compress(format, quality, stream)
                        }

                        FileOutputStream(outFile).use { fos ->
                            fos.write(stream.toByteArray())
                        }
                        finalBitmap.recycle()

                        runOnUiThread {
                            result.success(outputPath)
                        }
                    } catch (e: Exception) {
                        runOnUiThread {
                            result.error("NATIVE_COMPRESS_ERROR", e.message, null)
                        }
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

    private data class VideoExtractOutcome(
        val frames: List<ByteArray>,
        val durationMs: Long,
        val frameDelayMs: Int,
        val targetFrameCount: Int,
        val pathUsed: String
    )

    private fun isSufficientOutcome(
        outcome: VideoExtractOutcome?,
        retrieverDurationUs: Long
    ): Boolean {
        if (outcome == null || outcome.frames.size < 2) return false
        val minExpectedFrames = maxOf(
            2,
            minOf(outcome.targetFrameCount, maxOf(4, (outcome.targetFrameCount * 2) / 3))
        )
        if (outcome.frames.size < minExpectedFrames) return false
        val knownDurationMs = retrieverDurationUs / 1000L
        if (knownDurationMs >= 1500L && outcome.durationMs < 1200L) return false
        return true
    }

    private fun pickBestOutcome(
        candidates: List<VideoExtractOutcome?>,
        fallbackOutcome: VideoExtractOutcome
    ): VideoExtractOutcome {
        val valid = candidates.filterNotNull().filter { it.frames.isNotEmpty() }
        if (valid.isEmpty()) return fallbackOutcome
        return valid.maxWithOrNull(
            compareBy<VideoExtractOutcome> { it.durationMs / 250L }
                .thenBy { it.frames.size }
        ) ?: fallbackOutcome
    }

    private fun extractVideoFrames(videoPath: String, targetFps: Int, maxFrames: Int): Map<String, Any> {
        val retrieverDurationUs = probeVideoDurationUs(videoPath)
        val streamDurationUs = probeVideoStreamDurationUs(videoPath)
        val knownDurationUs = maxOf(retrieverDurationUs, streamDurationUs)

        val primaryOutcome = extractWithMediaCodec(
            videoPath = videoPath,
            targetFps = targetFps,
            maxFrames = maxFrames,
            preferSoftware = false,
            retrieverDurationUs = knownDurationUs
        )
        var softwareOutcome: VideoExtractOutcome? = null
        var retrieverOutcome: VideoExtractOutcome? = null

        val outcome = when {
            isSufficientOutcome(primaryOutcome, knownDurationUs) -> primaryOutcome!!
            else -> {
                softwareOutcome = extractWithMediaCodec(
                    videoPath = videoPath,
                    targetFps = targetFps,
                    maxFrames = maxFrames,
                    preferSoftware = true,
                    retrieverDurationUs = knownDurationUs
                )
                if (isSufficientOutcome(softwareOutcome, knownDurationUs)) {
                    softwareOutcome!!
                } else {
                    retrieverOutcome = extractWithRetriever(
                        videoPath = videoPath,
                        targetFps = targetFps,
                        maxFrames = maxFrames,
                        detectedDurationUs = knownDurationUs
                    )
                    pickBestOutcome(
                        listOf(primaryOutcome, softwareOutcome, retrieverOutcome),
                        retrieverOutcome
                    )
                }
            }
        }

        if (BuildConfig.DEBUG) {
            Log.i(
                "MainActivity",
                "extractFrames[${outcome.pathUsed}] file=${File(videoPath).name} " +
                    "frames=${outcome.frames.size}/${outcome.targetFrameCount} durationMs=${outcome.durationMs} " +
                    "frameDelayMs=${outcome.frameDelayMs} retrieverDurUs=$retrieverDurationUs " +
                    "streamDurUs=$streamDurationUs hw=${primaryOutcome?.frames?.size ?: -1} sw=${softwareOutcome?.frames?.size ?: -1}"
            )
        }

        return mapOf(
            "frames" to outcome.frames,
            "durationMs" to outcome.durationMs.toInt(),
            "frameDelayMs" to outcome.frameDelayMs
        )
    }

    /**
     * Scans packet timestamps via MediaExtractor without decoding so containers with
     * inaccurate header durations (e.g., 33 ms single-frame WebM metadata) still report
     * their actual stream duration up to the 3.5s probe cap.
     */
    private fun probeVideoStreamDurationUs(videoPath: String): Long {
        var extractor: MediaExtractor? = null
        return try {
            extractor = MediaExtractor()
            extractor.setDataSource(videoPath)
            var trackIdx = -1
            for (t in 0 until extractor.trackCount) {
                val m = extractor.getTrackFormat(t).getString(MediaFormat.KEY_MIME) ?: ""
                if (m.startsWith("video/")) {
                    trackIdx = t
                    break
                }
            }
            if (trackIdx < 0) return 0L
            extractor.selectTrack(trackIdx)

            var firstPtsUs = Long.MAX_VALUE
            var maxPtsUs = Long.MIN_VALUE
            var prevPtsUs = -1L
            var lastPositiveDeltaUs = 33333L
            var sampleCount = 0

            while (sampleCount < 1000) {
                val pts = extractor.sampleTime
                if (pts < 0L) break
                if (pts < firstPtsUs) firstPtsUs = pts
                if (pts > maxPtsUs) {
                    if (prevPtsUs >= 0L && pts > prevPtsUs) {
                        lastPositiveDeltaUs = pts - prevPtsUs
                    }
                    maxPtsUs = pts
                }
                prevPtsUs = pts
                sampleCount++
                if (firstPtsUs != Long.MAX_VALUE && (maxPtsUs - firstPtsUs) >= 3500000L) {
                    break
                }
                if (!extractor.advance()) break
            }

            if (sampleCount <= 0 || firstPtsUs == Long.MAX_VALUE || maxPtsUs <= firstPtsUs) {
                0L
            } else {
                (maxPtsUs - firstPtsUs) + lastPositiveDeltaUs.coerceIn(16000L, 125000L)
            }
        } catch (e: Exception) {
            Log.w("MainActivity", "probeVideoStreamDurationUs error: ${e.message}")
            0L
        } finally {
            try { extractor?.release() } catch (_: Exception) {}
        }
    }

    private fun probeVideoDurationUs(videoPath: String): Long {
        var retriever: MediaMetadataRetriever? = null
        return try {
            retriever = MediaMetadataRetriever()
            retriever.setDataSource(videoPath)
            val durStr = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
            val durMs = durStr?.toLongOrNull() ?: 0L
            if (durMs > 0L) durMs * 1000L else 0L
        } catch (e: Exception) {
            Log.w("MainActivity", "MediaMetadataRetriever duration probe error: ${e.message}")
            0L
        } finally {
            try { retriever?.release() } catch (_: Exception) {}
        }
    }

    private fun findSoftwareDecoderName(mime: String): String? {
        return try {
            val codecList = MediaCodecList(MediaCodecList.REGULAR_CODECS)
            for (info in codecList.codecInfos) {
                if (info.isEncoder) continue
                val supportsMime = info.supportedTypes.any { it.equals(mime, ignoreCase = true) }
                if (!supportsMime) continue
                val isSoftware = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    info.isSoftwareOnly
                } else {
                    info.name.startsWith("OMX.google.", ignoreCase = true) ||
                        info.name.startsWith("c2.android.", ignoreCase = true)
                }
                if (isSoftware) {
                    return info.name
                }
            }
            null
        } catch (e: Exception) {
            Log.w("MainActivity", "findSoftwareDecoderName failed: ${e.message}")
            null
        }
    }

    private fun extractWithMediaCodec(
        videoPath: String,
        targetFps: Int,
        maxFrames: Int,
        preferSoftware: Boolean,
        retrieverDurationUs: Long
    ): VideoExtractOutcome? {
        val frames = mutableListOf<ByteArray>()
        var extractor: MediaExtractor? = null
        var decoder: MediaCodec? = null
        val modeLabel = if (preferSoftware) "sw-mediacodec" else "hw-mediacodec"

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
            if (videoTrackIndex < 0 || mediaFormat == null) {
                return null
            }

            extractor.selectTrack(videoTrackIndex)
            val width = mediaFormat.getInteger(MediaFormat.KEY_WIDTH)
            val height = mediaFormat.getInteger(MediaFormat.KEY_HEIGHT)
            val mime = mediaFormat.getString(MediaFormat.KEY_MIME) ?: "video/x-vnd.on2.vp9"

            var formatDurationUs = 0L
            if (mediaFormat.containsKey(MediaFormat.KEY_DURATION)) {
                try {
                    formatDurationUs = mediaFormat.getLong(MediaFormat.KEY_DURATION)
                } catch (_: Exception) {}
            }

            val detectedDurationUs = maxOf(retrieverDurationUs, formatDurationUs)
            val durationWasEstimated = detectedDurationUs <= 0L
            val durationUs = if (detectedDurationUs > 0L) detectedDurationUs else 3000000L

            // WhatsApp duration ceiling is strictly 3000 ms (3 seconds)
            val safeDurationMs = (durationUs / 1000L).coerceIn(500L, 3000L)
            val targetFrameCount = ((safeDurationMs / 1000.0) * targetFps).roundToInt().coerceIn(6, maxFrames)
            val targetIntervalUs = if (targetFrameCount > 1) durationUs / targetFrameCount else durationUs

            decoder = if (preferSoftware) {
                val swName = findSoftwareDecoderName(mime) ?: return null
                MediaCodec.createByCodecName(swName)
            } else {
                MediaCodec.createDecoderByType(mime)
            }
            decoder.configure(mediaFormat, null, null, 0)
            decoder.start()

            val bufferInfo = MediaCodec.BufferInfo()
            val timeoutUs = 10000L
            var inputDone = false
            var outputDone = false
            var noProgressCount = 0
            var totalIdleIterations = 0
            var stride = width
            var sliceHeight = height
            var colorFormat = 19
            var firstPtsUs = -1L
            var nextTargetTimeUs = -1L
            var maxPtsUs = 0L

            while (!outputDone && frames.size < targetFrameCount) {
                var hadProgress = false
                if (!inputDone) {
                    val inIdx = decoder.dequeueInputBuffer(timeoutUs)
                    if (inIdx >= 0) {
                        hadProgress = true
                        val inBuf = decoder.getInputBuffer(inIdx)
                        if (inBuf != null) {
                            val sampleSize = extractor.readSampleData(inBuf, 0)
                            if (sampleSize < 0) {
                                decoder.queueInputBuffer(
                                    inIdx,
                                    0,
                                    0,
                                    0,
                                    MediaCodec.BUFFER_FLAG_END_OF_STREAM
                                )
                                inputDone = true
                            } else {
                                decoder.queueInputBuffer(
                                    inIdx,
                                    0,
                                    sampleSize,
                                    extractor.sampleTime,
                                    0
                                )
                                extractor.advance()
                            }
                        }
                    }
                }

                val outIdx = decoder.dequeueOutputBuffer(bufferInfo, timeoutUs)
                when {
                    outIdx >= 0 -> {
                        hadProgress = true
                        noProgressCount = 0
                        if ((bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) {
                            outputDone = true
                        }
                        val isCodecConfig = (bufferInfo.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG) != 0
                        if (!isCodecConfig && bufferInfo.size > 0 && bufferInfo.presentationTimeUs >= 0) {
                            val pts = bufferInfo.presentationTimeUs
                            if (firstPtsUs < 0L) {
                                firstPtsUs = pts
                                nextTargetTimeUs = pts
                            }
                            if (pts > maxPtsUs) {
                                maxPtsUs = pts
                            }
                            if (pts >= nextTargetTimeUs) {
                                val jpegBytes = encodeOutputFrameToJpeg(
                                    decoder = decoder,
                                    outIdx = outIdx,
                                    bufferInfo = bufferInfo,
                                    width = width,
                                    height = height,
                                    stride = stride,
                                    sliceHeight = sliceHeight,
                                    colorFormat = colorFormat
                                )
                                if (jpegBytes != null) {
                                    frames.add(jpegBytes)
                                    while (nextTargetTimeUs <= pts) {
                                        nextTargetTimeUs += targetIntervalUs
                                    }
                                }
                            }
                        }
                        decoder.releaseOutputBuffer(outIdx, false)
                    }
                    outIdx == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                        hadProgress = true
                        noProgressCount = 0
                        val outFormat = decoder.outputFormat
                        if (outFormat.containsKey("stride")) stride = outFormat.getInteger("stride")
                        if (outFormat.containsKey("slice-height")) sliceHeight = outFormat.getInteger("slice-height")
                        if (outFormat.containsKey("color-format")) colorFormat = outFormat.getInteger("color-format")
                    }
                    outIdx == MediaCodec.INFO_TRY_AGAIN_LATER -> {
                        if (inputDone) {
                            noProgressCount++
                            if (noProgressCount > 250) {
                                Log.w("MainActivity", "$modeLabel stalled after input EOS, frames=${frames.size}")
                                break
                            }
                        }
                    }
                }
                if (hadProgress) {
                    totalIdleIterations = 0
                } else {
                    totalIdleIterations++
                    if (totalIdleIterations > 1000) {
                        Log.w("MainActivity", "$modeLabel stalled without codec progress, frames=${frames.size}")
                        break
                    }
                }
            }

            if (frames.isEmpty()) {
                return null
            }

            val spannedUs = if (firstPtsUs >= 0L && maxPtsUs > firstPtsUs) maxPtsUs - firstPtsUs else maxPtsUs
            val spannedMs = (spannedUs / 1000L).coerceIn(500L, 3000L)
            val actualDurationMs = when {
                durationWasEstimated && spannedUs > 500000L -> spannedMs
                spannedMs > safeDurationMs -> spannedMs
                else -> safeDurationMs
            }

            if (frames.size == 1) {
                frames.add(frames.first())
            }

            val frameDelayMs = (actualDurationMs.toDouble() / frames.size)
                .roundToInt()
                .coerceIn(8, 3000)

            return VideoExtractOutcome(
                frames = frames,
                durationMs = actualDurationMs,
                frameDelayMs = frameDelayMs,
                targetFrameCount = targetFrameCount,
                pathUsed = modeLabel
            )
        } catch (e: Exception) {
            Log.w("MainActivity", "$modeLabel extraction failed (frames=${frames.size}): ${e.message}")
            return null
        } finally {
            try { decoder?.stop() } catch (_: Exception) {}
            try { decoder?.release() } catch (_: Exception) {}
            try { extractor?.release() } catch (_: Exception) {}
        }
    }

    private fun encodeOutputFrameToJpeg(
        decoder: MediaCodec,
        outIdx: Int,
        bufferInfo: MediaCodec.BufferInfo,
        width: Int,
        height: Int,
        stride: Int,
        sliceHeight: Int,
        colorFormat: Int
    ): ByteArray? {
        // Prefer Android Image API (handles COLOR_FormatYUV420Flexible, padding, and cropRect accurately)
        var image: Image? = null
        try {
            image = decoder.getOutputImage(outIdx)
            if (image != null && image.format == ImageFormat.YUV_420_888) {
                val crop = image.cropRect
                val outW = crop.width() and -2
                val outH = crop.height() and -2
                val nv21 = imageToNv21(image, outW, outH)
                if (nv21 != null) {
                    return compressNv21ToJpeg(nv21, outW, outH, null)
                }
            }
        } catch (e: Exception) {
            Log.w("MainActivity", "getOutputImage conversion failed, trying raw ByteBuffer: ${e.message}")
        } finally {
            try { image?.close() } catch (_: Exception) {}
        }

        // Fallback to raw ByteBuffer layout if getOutputImage is unavailable
        return try {
            val outBuf = decoder.getOutputBuffer(outIdx) ?: return null
            val rawYuv = ByteArray(bufferInfo.size)
            outBuf.position(bufferInfo.offset)
            outBuf.get(rawYuv, 0, bufferInfo.size)

            val outW = width and -2
            val outH = height and -2
            val nv21 = rawYuvToNv21(rawYuv, outW, outH, stride, sliceHeight, colorFormat) ?: return null
            compressNv21ToJpeg(nv21, outW, outH, null)
        } catch (e: Exception) {
            Log.w("MainActivity", "Raw ByteBuffer frame compression failed: ${e.message}")
            null
        }
    }

    private fun imageToNv21(image: Image, outW: Int, outH: Int): ByteArray? {
        if (outW <= 0 || outH <= 0 || image.planes.size < 3) return null
        val crop = image.cropRect
        val yPlane = image.planes[0]
        val uPlane = image.planes[1]
        val vPlane = image.planes[2]

        val yBuf = yPlane.buffer
        val uBuf = uPlane.buffer
        val vBuf = vPlane.buffer

        val yLimit = yBuf.limit()
        val uLimit = uBuf.limit()
        val vLimit = vBuf.limit()

        val yRowStride = yPlane.rowStride
        val yPixelStride = yPlane.pixelStride
        val uRowStride = uPlane.rowStride
        val uPixelStride = uPlane.pixelStride
        val vRowStride = vPlane.rowStride
        val vPixelStride = vPlane.pixelStride

        val nv21 = ByteArray(outW * outH * 3 / 2)
        var pos = 0

        if (yPixelStride == 1 && yRowStride == outW && crop.left == 0 && crop.top == 0 && yLimit >= outW * outH) {
            yBuf.position(0)
            yBuf.get(nv21, 0, outW * outH)
            pos = outW * outH
        } else {
            val rowBuf = ByteArray(yRowStride)
            for (row in 0 until outH) {
                val rowStart = (row + crop.top) * yRowStride + crop.left * yPixelStride
                if (rowStart < 0 || rowStart >= yLimit) {
                    pos += outW
                    continue
                }
                if (yPixelStride == 1) {
                    val len = minOf(outW, yLimit - rowStart)
                    yBuf.position(rowStart)
                    yBuf.get(nv21, pos, len)
                    pos += outW
                } else {
                    val len = minOf(rowBuf.size, yLimit - rowStart)
                    yBuf.position(rowStart)
                    yBuf.get(rowBuf, 0, len)
                    for (col in 0 until outW) {
                        val idx = col * yPixelStride
                        nv21[pos++] = if (idx < len) rowBuf[idx] else 0
                    }
                }
            }
        }

        val chromaH = outH / 2
        val chromaW = outW / 2
        val cropChromaTop = crop.top / 2
        val cropChromaLeft = crop.left / 2
        pos = outW * outH

        for (row in 0 until chromaH) {
            val vRowStart = (row + cropChromaTop) * vRowStride + cropChromaLeft * vPixelStride
            val uRowStart = (row + cropChromaTop) * uRowStride + cropChromaLeft * uPixelStride
            for (col in 0 until chromaW) {
                val vIdx = vRowStart + col * vPixelStride
                val uIdx = uRowStart + col * uPixelStride
                nv21[pos++] = if (vIdx in 0 until vLimit) vBuf.get(vIdx) else 128.toByte()
                nv21[pos++] = if (uIdx in 0 until uLimit) uBuf.get(uIdx) else 128.toByte()
            }
        }

        return nv21
    }

    private fun rawYuvToNv21(
        rawYuv: ByteArray,
        width: Int,
        height: Int,
        stride: Int,
        sliceHeight: Int,
        colorFormat: Int
    ): ByteArray? {
        if (width <= 0 || height <= 0 || stride < width || sliceHeight < height) return null
        val nv21 = ByteArray(width * height * 3 / 2)
        for (row in 0 until height) {
            val srcOffset = row * stride
            val dstOffset = row * width
            if (srcOffset + width <= rawYuv.size) {
                System.arraycopy(rawYuv, srcOffset, nv21, dstOffset, width)
            }
        }

        val yPlaneBytes = stride * sliceHeight
        val uvPlaneBytes = (stride / 2) * (sliceHeight / 2)
        val chromaH = height / 2
        val chromaW = width / 2
        var dstPos = width * height

        if (colorFormat == 21) {
            // NV12: interleaved U, V
            for (row in 0 until chromaH) {
                val rowOffset = yPlaneBytes + row * stride
                for (col in 0 until chromaW) {
                    val idx = rowOffset + col * 2
                    if (idx + 1 < rawYuv.size && dstPos + 1 < nv21.size) {
                        nv21[dstPos++] = rawYuv[idx + 1]
                        nv21[dstPos++] = rawYuv[idx]
                    }
                }
            }
        } else {
            // I420 planar: U plane followed by V plane
            val uBase = yPlaneBytes
            val vBase = yPlaneBytes + uvPlaneBytes
            val uvStride = stride / 2
            for (row in 0 until chromaH) {
                val rowOff = row * uvStride
                for (col in 0 until chromaW) {
                    val uIdx = uBase + rowOff + col
                    val vIdx = vBase + rowOff + col
                    if (vIdx < rawYuv.size && uIdx < rawYuv.size && dstPos + 1 < nv21.size) {
                        nv21[dstPos++] = rawYuv[vIdx]
                        nv21[dstPos++] = rawYuv[uIdx]
                    }
                }
            }
        }

        return nv21
    }

    private fun compressNv21ToJpeg(
        nv21: ByteArray,
        width: Int,
        height: Int,
        strides: IntArray?
    ): ByteArray? {
        return try {
            val yuvImage = YuvImage(nv21, ImageFormat.NV21, width, height, strides)
            val stream = ByteArrayOutputStream()
            yuvImage.compressToJpeg(Rect(0, 0, width, height), 85, stream)
            stream.toByteArray()
        } catch (e: Exception) {
            Log.w("MainActivity", "compressNv21ToJpeg failed: ${e.message}")
            null
        }
    }

    private fun extractWithRetriever(
        videoPath: String,
        targetFps: Int,
        maxFrames: Int,
        detectedDurationUs: Long
    ): VideoExtractOutcome {
        val frames = mutableListOf<ByteArray>()
        val retriever = MediaMetadataRetriever()
        val durationUs = if (detectedDurationUs > 0L) detectedDurationUs else 3000000L
        val safeDurationMs = (durationUs / 1000L).coerceIn(500L, 3000L)
        val targetFrameCount = ((safeDurationMs / 1000.0) * targetFps).roundToInt().coerceIn(8, maxFrames)

        try {
            retriever.setDataSource(videoPath)
            val maxSampleUs = maxOf(0L, durationUs - 50000L)

            for (i in 0 until targetFrameCount) {
                val timeUs = if (targetFrameCount > 1) {
                    (i.toLong() * maxSampleUs) / (targetFrameCount - 1)
                } else {
                    0L
                }
                var rawBmp = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
                    retriever.getScaledFrameAtTime(
                        timeUs,
                        MediaMetadataRetriever.OPTION_CLOSEST,
                        512,
                        512
                    )
                } else {
                    retriever.getFrameAtTime(timeUs, MediaMetadataRetriever.OPTION_CLOSEST)
                }
                if (rawBmp == null) {
                    rawBmp = retriever.getFrameAtTime(
                        timeUs,
                        MediaMetadataRetriever.OPTION_CLOSEST_SYNC
                    )
                }
                if (rawBmp != null) {
                    val stream = ByteArrayOutputStream()
                    val format = if (rawBmp.hasAlpha()) {
                        Bitmap.CompressFormat.PNG
                    } else {
                        Bitmap.CompressFormat.JPEG
                    }
                    rawBmp.compress(format, 88, stream)
                    frames.add(stream.toByteArray())
                    rawBmp.recycle()
                }
            }
        } catch (e: Exception) {
            Log.e("MainActivity", "Multi-frame retriever fallback failed", e)
        } finally {
            try { retriever.release() } catch (_: Exception) {}
        }

        if (frames.size == 1) {
            frames.add(frames.first())
        }

        val frameDelayMs = if (frames.isNotEmpty()) {
            (safeDurationMs.toDouble() / frames.size).roundToInt().coerceIn(8, 3000)
        } else {
            125
        }

        return VideoExtractOutcome(
            frames = frames,
            durationMs = safeDurationMs,
            frameDelayMs = frameDelayMs,
            targetFrameCount = targetFrameCount,
            pathUsed = "retriever-fallback"
        )
    }
}
