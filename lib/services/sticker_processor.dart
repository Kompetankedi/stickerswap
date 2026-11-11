import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Alignment, BoxFit, Canvas, Rect;
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:lottie/lottie.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Processes Telegram sticker images and videos into WhatsApp-compatible format:
/// - 512x512 px WebP with transparency
/// - < 100 KB for static stickers
/// - < 500 KB for animated WebP stickers (duration <= 3 sec, infinite loop)
/// - 96x96 px tray icon < 50 KB PNG
///
/// All heavy CPU encoding and resizing operations run in background Dart Isolates
/// (or Android hardware-accelerated native compression) to guarantee 60/120 FPS
/// responsiveness on the main UI thread during bulk export.
class StickerProcessor {
  static const int _whatsappSize = 512;
  static const int _traySize = 96;
  static const int _maxStaticKb = 96;
  static const int _maxAnimatedKb = 460; // Strictly under WhatsApp 500KB decimal (500,000 bytes) limit
  static const int _maxTrayKb = 48; // Strictly under WhatsApp 50KB limit
  static const int _padding = 16;

  static const MethodChannel _videoChannel =
      MethodChannel('com.example.stickerswap/video');

  /// Deletes older animated cache variants so updated encoders regenerate clean WebPs.
  Future<void> _cleanupLegacyAnimatedCache(
    String outputDir,
    String baseName,
  ) async {
    for (final suffix in const ['_wa.webp', '_wa_v2.webp', '_wa_v3.webp']) {
      final oldFile = File(p.join(outputDir, '$baseName$suffix'));
      if (await oldFile.exists()) {
        try {
          await oldFile.delete();
        } catch (_) {}
      }
    }
  }

  /// Converts a video sticker (e.g. .webm) into a WhatsApp-compliant Animated WebP.
  /// Dynamically computes frame delay across the full video duration (up to 3.0s)
  /// to prevent premature looping and fast-forward truncation.
  /// Heavy frame decoding and multi-frame WebP encoding run inside an isolate worker.
  Future<String> processVideoSticker(
    String videoPath,
    String outputDir, {
    Uint8List? fallbackThumbnailBytes,
    bool forceRefresh = false,
  }) async {
    final baseName = p.basenameWithoutExtension(videoPath);
    final outputName = '${baseName}_wa_v4.webp';
    final outputPath = p.join(outputDir, outputName);

    // Fast return if already processed, not forcing refresh, and within valid limits
    final outputFile = File(outputPath);
    if (!forceRefresh && await outputFile.exists()) {
      final len = await outputFile.length();
      if (len > 0 && len <= _maxAnimatedKb * 1024) {
        return outputPath;
      }
    }

    await _cleanupLegacyAnimatedCache(outputDir, baseName);

    try {
      // Extract frames via Android native MediaCodec sequential extractor
      final dynamic rawResult = await _videoChannel.invokeMethod('extractFrames', {
        'videoPath': videoPath,
        'fps': 8,
        'maxFrames': 22,
      });

      List<Uint8List> frames = [];
      int totalDurationMs = 3000;
      int frameDelayMs = 125;

      if (rawResult is Map) {
        final rawFrames = rawResult['frames'];
        if (rawFrames is List && rawFrames.isNotEmpty) {
          frames = rawFrames.whereType<Uint8List>().toList();
        }
        final reportedDuration = (rawResult['durationMs'] as num?)?.toInt();
        if (reportedDuration != null && reportedDuration > 0) {
          totalDurationMs = reportedDuration.clamp(200, 3000);
        }
        final reportedDelay = (rawResult['frameDelayMs'] as num?)?.toInt();
        if (reportedDelay != null && reportedDelay > 0) {
          frameDelayMs = reportedDelay.clamp(8, 3000);
        } else if (frames.isNotEmpty) {
          frameDelayMs = (totalDurationMs / frames.length).round().clamp(8, 3000);
        }
      } else if (rawResult is List && rawResult.isNotEmpty) {
        frames = rawResult.whereType<Uint8List>().toList();
        frameDelayMs = (totalDurationMs / frames.length).round().clamp(8, 3000);
      }

      if (frames.isNotEmpty) {
        debugPrint(
          'processVideoSticker($baseName): extracted=${frames.length} frames, '
          'duration=${totalDurationMs}ms, delay=${frameDelayMs}ms',
        );
        // Offload heavy image decoding and WebP compression to background Isolate
        return await Isolate.run(() {
          return _createAnimatedWebpFromPngFramesSync(
            pngFrames: frames,
            outputPath: outputPath,
            frameDelayMs: frameDelayMs,
            maxKb: _maxAnimatedKb,
            totalDurationMs: totalDurationMs,
          );
        });
      }
    } catch (e) {
      debugPrint('Video sticker extraction error: $e');
    }

    if (fallbackThumbnailBytes != null && fallbackThumbnailBytes.isNotEmpty) {
      return await processImageBytes(
        fallbackThumbnailBytes,
        outputDir,
        outputName,
        asAnimated: true,
        forceRefresh: forceRefresh,
      );
    }

    throw Exception('Video ve önizleme çözülemedi: $videoPath');
  }

  /// Converts a Lottie sticker (.tgs) into a compliant 512x512 Animated WebP.
  /// Samples frames evenly across full composition duration (up to 3.0s)
  /// so animations play at natural 1.0x speed without premature truncation.
  /// Yields to the UI event loop during frame extraction, then offloads
  /// Animated WebP encoding to a background isolate.
  Future<String> processLottieSticker(
    String tgsPath,
    String outputDir, {
    Uint8List? fallbackThumbnailBytes,
    bool forceRefresh = false,
  }) async {
    final baseName = p.basenameWithoutExtension(tgsPath);
    final outputName = '${baseName}_wa_v4.webp';
    final outputPath = p.join(outputDir, outputName);

    final outputFile = File(outputPath);
    if (!forceRefresh && await outputFile.exists()) {
      final len = await outputFile.length();
      if (len > 0 && len <= _maxAnimatedKb * 1024) {
        return outputPath;
      }
    }

    await _cleanupLegacyAnimatedCache(outputDir, baseName);

    try {
      final fileBytes = await File(tgsPath).readAsBytes();
      final unzipped = Uint8List.fromList(gzip.decode(fileBytes));
      final composition = await LottieComposition.fromBytes(unzipped);
      final drawable = LottieDrawable(composition);

      // WhatsApp target animation duration ceiling (Telegram .tgs max is 3000 ms)
      final compositionDurationMs = composition.duration.inMilliseconds;
      final totalDurationMs =
          (compositionDurationMs > 0 ? compositionDurationMs : 3000)
              .clamp(200, 3000);

      // Target ~8 fps across full duration, allowing up to totalDurationMs/frameCount delay
      final frameCount = ((totalDurationMs / 1000.0) * 8).round().clamp(4, 22);
      final frameDelayMs =
          (totalDurationMs / frameCount).round().clamp(8, 3000);

      final frames = <Uint8List>[];
      final targetRect = Rect.fromLTWH(
        _padding.toDouble(),
        _padding.toDouble(),
        (_whatsappSize - (_padding * 2)).toDouble(),
        (_whatsappSize - (_padding * 2)).toDouble(),
      );

      for (int i = 0; i < frameCount; i++) {
        // Clamp below 1.0 so compositions with exclusive out-point don't render a blank final frame
        final progress =
            frameCount > 1 ? (i / (frameCount - 1)).clamp(0.0, 0.999) : 0.0;
        drawable.setProgress(progress);

        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        drawable.draw(
          canvas,
          targetRect,
          fit: BoxFit.contain,
          alignment: Alignment.center,
        );

        final picture = recorder.endRecording();
        ui.Image? uiImg;
        try {
          uiImg = await picture.toImage(_whatsappSize, _whatsappSize);
          final byteData =
              await uiImg.toByteData(format: ui.ImageByteFormat.png);
          if (byteData != null) {
            frames.add(byteData.buffer.asUint8List());
          }
        } finally {
          uiImg?.dispose();
          picture.dispose();
        }

        // Yield to event loop between frames to keep UI responsive
        await Future<void>.delayed(Duration.zero);
      }

      if (frames.isNotEmpty) {
        debugPrint(
          'processLottieSticker($baseName): rendered=${frames.length} frames, '
          'duration=${totalDurationMs}ms, delay=${frameDelayMs}ms',
        );
        return await Isolate.run(() {
          return _createAnimatedWebpFromPngFramesSync(
            pngFrames: frames,
            outputPath: outputPath,
            frameDelayMs: frameDelayMs,
            maxKb: _maxAnimatedKb,
            totalDurationMs: totalDurationMs,
          );
        });
      }
    } catch (e) {
      debugPrint('Lottie sticker conversion error: $e');
    }

    if (fallbackThumbnailBytes != null && fallbackThumbnailBytes.isNotEmpty) {
      return await processImageBytes(
        fallbackThumbnailBytes,
        outputDir,
        outputName,
        asAnimated: true,
        forceRefresh: forceRefresh,
      );
    }

    throw Exception('Lottie çıkartma çözülemedi: $tgsPath');
  }

  /// Processes raw image bytes into a 512x512 WebP sticker in a background isolate.
  Future<String> processImageBytes(
    Uint8List bytes,
    String outputDir,
    String outputName, {
    bool asAnimated = false,
    bool forceRefresh = false,
  }) async {
    final outputPath = p.join(outputDir, outputName);
    final outputFile = File(outputPath);
    if (!forceRefresh && await outputFile.exists()) {
      final len = await outputFile.length();
      final maxBytes = (asAnimated ? _maxAnimatedKb : _maxStaticKb) * 1024;
      if (len > 0 && len <= maxBytes) {
        return outputPath;
      }
    }

    return await Isolate.run(() {
      return _processImageBytesSync(
        bytes: bytes,
        outputPath: outputPath,
        asAnimated: asAnimated,
      );
    });
  }

  /// Converts a downloaded Telegram sticker to WhatsApp format.
  /// Uses Android native hardware-accelerated WebP compression for static stickers when available;
  /// otherwise runs image decoding, resizing, and WebP encoding inside a background Isolate.
  Future<String> processSticker(
    String inputPath,
    String outputDir, {
    bool asAnimated = false,
    bool forceRefresh = false,
  }) async {
    final outputName =
        '${p.basenameWithoutExtension(inputPath)}_wa.webp';
    final outputPath = p.join(outputDir, outputName);

    final outputFile = File(outputPath);
    if (!forceRefresh && await outputFile.exists()) {
      final len = await outputFile.length();
      final maxBytes = (asAnimated ? _maxAnimatedKb : _maxStaticKb) * 1024;
      if (len > 0 && len <= maxBytes) {
        return outputPath;
      }
    }

    // Try hardware-accelerated native compression on Android for static stickers
    if (!asAnimated && Platform.isAndroid) {
      try {
        final nativeResult = await _videoChannel.invokeMethod<String>(
          'compressStaticWebP',
          {
            'inputPath': inputPath,
            'outputPath': outputPath,
          },
        );
        if (nativeResult != null && await File(nativeResult).exists()) {
          return nativeResult;
        }
      } catch (_) {
        // Native fallback to Dart isolate worker below
      }
    }

    return await Isolate.run(() {
      return _processStickerSync(
        inputPath: inputPath,
        outputPath: outputPath,
        asAnimated: asAnimated,
      );
    });
  }

  /// Generates a 96x96 tray icon in PNG format (< 50 KB) in a background isolate.
  Future<String> generateTrayIcon(
    String inputPath,
    String outputDir, {
    String fileName = 'tray_icon.png',
    bool forceRefresh = false,
  }) async {
    final outputPath = p.join(outputDir, fileName);
    final outputFile = File(outputPath);
    if (!forceRefresh && await outputFile.exists()) {
      final len = await outputFile.length();
      if (len > 0 && len <= _maxTrayKb * 1024) {
        return outputPath;
      }
    }

    return await Isolate.run(() {
      return _generateTrayIconSync(
        inputPath: inputPath,
        outputPath: outputPath,
      );
    });
  }

  /// Gets or creates a dedicated output directory for a sticker pack.
  Future<String> getPackOutputDir(String packName) async {
    final dir = await getApplicationDocumentsDirectory();
    final packDir = Directory(p.join(dir.path, 'whatsapp_packs', packName));
    if (!await packDir.exists()) {
      await packDir.create(recursive: true);
    }
    return packDir.path;
  }

  // =========================================================================
  // Synchronous Worker Routines (Executed inside background Dart Isolates)
  // =========================================================================

  /// Progressive quality/resolution tiers that shrink canvas artwork and frame count
  /// gradually while preserving full animation duration.
  static const List<({
    int targetFrames,
    int drawSize,
    int alphaQuality,
    int method,
    List<int> qualities,
  })> _animatedEncodeTiers = [
    (
      targetFrames: 0, // Use all available frames
      drawSize: _whatsappSize - (_padding * 2),
      alphaQuality: 75,
      method: 3,
      qualities: [70, 52, 35, 20],
    ),
    (
      targetFrames: 12,
      drawSize: 420,
      alphaQuality: 65,
      method: 2,
      qualities: [60, 40, 22],
    ),
    (
      targetFrames: 8,
      drawSize: 360,
      alphaQuality: 55,
      method: 2,
      qualities: [50, 30, 15],
    ),
    (
      targetFrames: 6,
      drawSize: 300,
      alphaQuality: 45,
      method: 2,
      qualities: [40, 22, 10],
    ),
    (
      targetFrames: 4,
      drawSize: 240,
      alphaQuality: 35,
      method: 2,
      qualities: [30, 15, 8],
    ),
    (
      targetFrames: 2,
      drawSize: 192,
      alphaQuality: 25,
      method: 2,
      qualities: [20, 10, 5],
    ),
    (
      targetFrames: 2,
      drawSize: 128,
      alphaQuality: 20,
      method: 2,
      qualities: [10, 5],
    ),
  ];

  /// Renders a single [frame] centered inside a 512x512 RGBA sticker canvas.
  static img.Image _renderStickerFrameCanvas(
    img.Image frame,
    int delayMs,
    int drawSize,
  ) {
    final frameCanvas = img.Image(
      width: _whatsappSize,
      height: _whatsappSize,
      numChannels: 4,
    );
    final resized = _fitImage(frame, drawSize);
    final ox = (_whatsappSize - resized.width) ~/ 2;
    final oy = (_whatsappSize - resized.height) ~/ 2;
    img.compositeImage(frameCanvas, resized, dstX: ox, dstY: oy);
    frameCanvas.frameDuration = delayMs;
    return frameCanvas;
  }

  /// Composes a sequence of [frames] into an animated [img.Image] canvas of 512x512.
  static img.Image _composeAnimatedCanvas(
    List<img.Image> frames,
    int delayMs, {
    int drawSize = _whatsappSize - (_padding * 2),
  }) {
    final baseCanvas =
        _renderStickerFrameCanvas(frames.first, delayMs, drawSize);
    baseCanvas.loopCount = 0; // Infinite loop required by WhatsApp
    for (int i = 1; i < frames.length; i++) {
      baseCanvas.frames.add(
        _renderStickerFrameCanvas(frames[i], delayMs, drawSize),
      );
    }
    return baseCanvas;
  }

  /// Samples [targetCount] frames evenly across [source], always retaining first and last.
  static List<img.Image> _sampleFramesEvenly(
    List<img.Image> source,
    int targetCount,
  ) {
    if (source.length <= targetCount) {
      return List<img.Image>.from(source);
    }
    if (targetCount <= 2) {
      return [source.first, source.last];
    }
    final sampled = <img.Image>[];
    final lastIndex = source.length - 1;
    for (int i = 0; i < targetCount; i++) {
      final idx =
          ((i * lastIndex) / (targetCount - 1)).round().clamp(0, lastIndex);
      sampled.add(source[idx]);
    }
    return sampled;
  }

  /// Computes per-frame delay preserving [targetDurationMs] without exceeding 3000 ms.
  static int _computeDurationPreservingDelay(
    int frameCount,
    int targetDurationMs,
  ) {
    final safeTotalMs = targetDurationMs.clamp(frameCount * 8, 3000);
    var delay = (safeTotalMs / frameCount).round().clamp(8, 3000);
    if (frameCount * delay > 3000) {
      delay = (3000 ~/ frameCount).clamp(8, 3000);
    }
    return delay;
  }

  /// Encodes [canvas] through [qualities], skipping middle passes when far over [maxBytes].
  static ({Uint8List? matched, Uint8List? smallest}) _tryEncodeAnimatedTier({
    required img.Image canvas,
    required List<int> qualities,
    required int alphaQuality,
    required int method,
    required int maxBytes,
  }) {
    Uint8List? smallest;
    for (int i = 0; i < qualities.length; i++) {
      final bytes = Uint8List.fromList(
        img.encodeWebP(
          canvas,
          lossless: false,
          exact: false,
          quality: qualities[i],
          method: method,
          alphaQuality: alphaQuality,
        ),
      );
      if (smallest == null || bytes.length < smallest.length) {
        smallest = bytes;
      }
      if (bytes.length <= maxBytes) {
        return (matched: bytes, smallest: smallest);
      }
      if (i == 0 && bytes.length > maxBytes * 2 && qualities.length > 2) {
        // Way over ceiling at tier's top quality; jump directly to its lowest quality
        i = qualities.length - 2;
      }
    }
    return (matched: null, smallest: smallest);
  }

  /// Synchronously encodes a list of frames into Animated WebP within a background isolate.
  /// Strictly guarantees:
  /// - Exact 512x512 pixels
  /// - Animated WebP with at least 2 frames and infinite loop (`loopCount = 0`)
  /// - File size strictly <= 460 KB (under WhatsApp's 500 KB limit)
  /// - Total animation duration <= 3000 ms, each frame duration >= 8 ms
  static String _createAnimatedWebpFromPngFramesSync({
    required List<Uint8List> pngFrames,
    required String outputPath,
    int frameDelayMs = 125,
    int maxKb = _maxAnimatedKb,
    int totalDurationMs = 3000,
  }) {
    if (pngFrames.isEmpty) {
      throw Exception('Kare listesi boş olamaz');
    }

    final decodedList = <img.Image>[];
    for (final frameBytes in pngFrames) {
      final decoded = img.decodeImage(frameBytes);
      if (decoded != null) {
        decodedList.add(decoded);
      }
    }
    if (decodedList.isEmpty) {
      throw Exception('Hiçbir kare çözülemedi');
    }

    // Determine desired playback duration before duplicating a single-frame input
    final derivedMs = decodedList.length * frameDelayMs;
    final targetDurationMs =
        (totalDurationMs > 0 ? totalDurationMs : derivedMs).clamp(16, 3000);

    // WhatsApp animated stickers strictly require at least 2 frames
    if (decodedList.length == 1) {
      decodedList.add(decodedList.first);
    }

    final maxBytes = maxKb * 1024;
    Uint8List? smallestBytes;

    for (final tier in _animatedEncodeTiers) {
      final desiredCount = tier.targetFrames <= 0
          ? decodedList.length
          : min(decodedList.length, tier.targetFrames)
              .clamp(2, decodedList.length);
      final tierFrames = _sampleFramesEvenly(decodedList, desiredCount);
      final tierDelayMs =
          _computeDurationPreservingDelay(tierFrames.length, targetDurationMs);
      final canvas = _composeAnimatedCanvas(
        tierFrames,
        tierDelayMs,
        drawSize: tier.drawSize,
      );

      final result = _tryEncodeAnimatedTier(
        canvas: canvas,
        qualities: tier.qualities,
        alphaQuality: tier.alphaQuality,
        method: tier.method,
        maxBytes: maxBytes,
      );
      if (result.matched != null) {
        File(outputPath).writeAsBytesSync(result.matched!);
        return outputPath;
      }
      final candidate = result.smallest;
      if (candidate != null &&
          (smallestBytes == null || candidate.length < smallestBytes.length)) {
        smallestBytes = candidate;
      }
    }

    if (smallestBytes == null) {
      throw Exception('Animasyonlu WebP oluşturulamadı: $outputPath');
    }

    File(outputPath).writeAsBytesSync(smallestBytes);
    return outputPath;
  }

  /// Helper exposed for unit testing animated WebP generation and duration verification.
  @visibleForTesting
  static String createAnimatedWebpFromPngFramesSyncForTest({
    required List<Uint8List> pngFrames,
    required String outputPath,
    int frameDelayMs = 125,
    int maxKb = _maxAnimatedKb,
    int totalDurationMs = 3000,
  }) {
    return _createAnimatedWebpFromPngFramesSync(
      pngFrames: pngFrames,
      outputPath: outputPath,
      frameDelayMs: frameDelayMs,
      maxKb: maxKb,
      totalDurationMs: totalDurationMs,
    );
  }

  /// Synchronously processes a static or 2-frame animated sticker within an isolate.
  static String _processStickerSync({
    required String inputPath,
    required String outputPath,
    required bool asAnimated,
  }) {
    final inputFile = File(inputPath);
    final bytes = inputFile.readAsBytesSync();

    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw Exception('Görsel çözülemedi: $inputPath');
    }

    const availableSize = _whatsappSize - (_padding * 2);
    final resized = _fitImage(decoded, availableSize);

    final canvas = img.Image(
      width: _whatsappSize,
      height: _whatsappSize,
      numChannels: 4,
    );
    final offsetX = (_whatsappSize - resized.width) ~/ 2;
    final offsetY = (_whatsappSize - resized.height) ~/ 2;
    img.compositeImage(canvas, resized, dstX: offsetX, dstY: offsetY);

    if (asAnimated) {
      canvas.frameDuration = 500;
      canvas.loopCount = 0;
      final secondFrame = img.Image(
        width: _whatsappSize,
        height: _whatsappSize,
        numChannels: 4,
      );
      img.compositeImage(secondFrame, resized, dstX: offsetX, dstY: offsetY);
      secondFrame.frameDuration = 500;
      canvas.frames.add(secondFrame);

      Uint8List webpBytes = Uint8List.fromList(
        img.encodeWebP(canvas, lossless: false, quality: 80),
      );
      for (final q in const [65, 50, 35, 20]) {
        if (webpBytes.length <= _maxAnimatedKb * 1024) break;
        webpBytes = Uint8List.fromList(
          img.encodeWebP(canvas, lossless: false, quality: q),
        );
      }
      File(outputPath).writeAsBytesSync(webpBytes);
      return outputPath;
    }

    Uint8List webpBytes = Uint8List.fromList(
      img.WebPEncoder(lossless: true).encode(canvas),
    );
    for (final q in const [85, 70, 50, 35, 20]) {
      if (webpBytes.length <= _maxStaticKb * 1024) break;
      webpBytes = Uint8List.fromList(
        img.WebPEncoder(lossless: false, quality: q).encode(canvas),
      );
    }

    File(outputPath).writeAsBytesSync(webpBytes);
    return outputPath;
  }

  /// Synchronously processes raw image bytes into WebP within an isolate.
  static String _processImageBytesSync({
    required Uint8List bytes,
    required String outputPath,
    required bool asAnimated,
  }) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw Exception('Görsel çözülemedi');
    }
    const availableSize = _whatsappSize - (_padding * 2);
    final resized = _fitImage(decoded, availableSize);

    final canvas = img.Image(
      width: _whatsappSize,
      height: _whatsappSize,
      numChannels: 4,
    );
    final offsetX = (_whatsappSize - resized.width) ~/ 2;
    final offsetY = (_whatsappSize - resized.height) ~/ 2;
    img.compositeImage(canvas, resized, dstX: offsetX, dstY: offsetY);

    if (asAnimated) {
      canvas.frameDuration = 500;
      canvas.loopCount = 0;
      final secondFrame = img.Image(
        width: _whatsappSize,
        height: _whatsappSize,
        numChannels: 4,
      );
      img.compositeImage(secondFrame, resized, dstX: offsetX, dstY: offsetY);
      secondFrame.frameDuration = 500;
      canvas.frames.add(secondFrame);

      Uint8List webpBytes = Uint8List.fromList(
        img.encodeWebP(canvas, lossless: false, quality: 80),
      );
      for (final q in const [65, 50, 35, 20]) {
        if (webpBytes.length <= _maxAnimatedKb * 1024) break;
        webpBytes = Uint8List.fromList(
          img.encodeWebP(canvas, lossless: false, quality: q),
        );
      }
      File(outputPath).writeAsBytesSync(webpBytes);
      return outputPath;
    }

    Uint8List webpBytes = Uint8List.fromList(
      img.WebPEncoder(lossless: true).encode(canvas),
    );
    for (final q in const [85, 70, 50, 35, 20]) {
      if (webpBytes.length <= _maxStaticKb * 1024) break;
      webpBytes = Uint8List.fromList(
        img.WebPEncoder(lossless: false, quality: q).encode(canvas),
      );
    }
    File(outputPath).writeAsBytesSync(webpBytes);
    return outputPath;
  }

  /// Synchronously generates a 96x96 tray icon within an isolate.
  /// Strictly guarantees:
  /// - Exact 96x96 pixels PNG format
  /// - File size strictly <= 48 KB (WhatsApp limit is 50 KB)
  /// - Discards multi-frame animation layers so only the first frame is used
  static String _generateTrayIconSync({
    required String inputPath,
    required String outputPath,
  }) {
    final inputFile = File(inputPath);
    final bytes = inputFile.readAsBytesSync();

    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw Exception('Tray ikonu oluşturulamadı: $inputPath');
    }

    // If multi-frame (e.g. animated webp input), take only the first frame
    final firstFrame = decoded.frames.isNotEmpty ? decoded.frames.first : decoded;

    final canvas = img.Image(
      width: _traySize,
      height: _traySize,
      numChannels: 4,
    );
    final resized = _fitImage(firstFrame, _traySize - 8);
    final offsetX = (_traySize - resized.width) ~/ 2;
    final offsetY = (_traySize - resized.height) ~/ 2;
    img.compositeImage(canvas, resized, dstX: offsetX, dstY: offsetY);

    Uint8List pngBytes = Uint8List.fromList(img.encodePng(canvas, level: 9));

    // If over 48 KB (WhatsApp strictly requires < 50 KB PNG), scale down inside 96x96 canvas
    if (pngBytes.length > (_maxTrayKb - 2) * 1024) {
      final smallerCanvas = img.Image(
        width: _traySize,
        height: _traySize,
        numChannels: 4,
      );
      final smaller = _fitImage(firstFrame, 64);
      final ox = (_traySize - smaller.width) ~/ 2;
      final oy = (_traySize - smaller.height) ~/ 2;
      img.compositeImage(smallerCanvas, smaller, dstX: ox, dstY: oy);
      pngBytes = Uint8List.fromList(img.encodePng(smallerCanvas, level: 9));
    }

    if (pngBytes.length > (_maxTrayKb - 2) * 1024) {
      final quantized = img.quantize(canvas, numberOfColors: 128);
      pngBytes = Uint8List.fromList(img.encodePng(quantized, level: 9));
    }

    File(outputPath).writeAsBytesSync(pngBytes);
    return outputPath;
  }

  /// Resize image to fit within [maxSize] preserving aspect ratio.
  static img.Image _fitImage(img.Image source, int maxSize) {
    if (source.width <= maxSize && source.height <= maxSize) {
      return source;
    }
    if (source.width >= source.height) {
      return img.copyResize(source, width: maxSize);
    } else {
      return img.copyResize(source, height: maxSize);
    }
  }
}
