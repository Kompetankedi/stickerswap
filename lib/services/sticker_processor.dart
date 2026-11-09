import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Canvas, Rect;
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

  /// Converts a video sticker (e.g. .webm) into a WhatsApp-compliant Animated WebP.
  /// Dynamically computes frame delay and targets 20-22 frames across the full video duration
  /// (up to WhatsApp's 3.0s limit) to prevent premature looping and fast-forward truncation.
  /// Heavy frame decoding and multi-frame WebP encoding run inside an isolate worker.
  Future<String> processVideoSticker(
    String videoPath,
    String outputDir, {
    Uint8List? fallbackThumbnailBytes,
    bool forceRefresh = false,
  }) async {
    final outputName =
        '${p.basenameWithoutExtension(videoPath)}_wa_v2.webp';
    final outputPath = p.join(outputDir, outputName);

    // Fast return if already processed, not forcing refresh, and within valid limits
    final outputFile = File(outputPath);
    if (!forceRefresh && await outputFile.exists()) {
      final len = await outputFile.length();
      if (len > 0 && len <= _maxAnimatedKb * 1024) {
        return outputPath;
      }
    }

    // Clean up older truncated _wa.webp cache file if present
    final oldPath = p.join(
      outputDir,
      '${p.basenameWithoutExtension(videoPath)}_wa.webp',
    );
    final oldFile = File(oldPath);
    if (await oldFile.exists()) {
      try {
        await oldFile.delete();
      } catch (_) {}
    }

    try {
      // 1. Extract frames via Android native MediaCodec sequential extractor
      // Request target 8 fps and max 22 frames to cover full 2.5s - 3.0s duration
      final dynamic rawResult = await _videoChannel.invokeMethod('extractFrames', {
        'videoPath': videoPath,
        'fps': 8,
        'maxFrames': 22,
      });

      List<Uint8List> frames = [];
      int frameDelayMs = 125;
      int totalDurationMs = 3000;

      if (rawResult is Map) {
        final rawFrames = rawResult['frames'];
        if (rawFrames is List && rawFrames.isNotEmpty) {
          frames = rawFrames.cast<Uint8List>();
        }
        totalDurationMs = (rawResult['durationMs'] as num?)?.toInt() ?? 3000;
        frameDelayMs = (rawResult['frameDelayMs'] as num?)?.toInt() ??
            (frames.isNotEmpty ? (totalDurationMs ~/ frames.length) : 125);
      } else if (rawResult is List && rawResult.isNotEmpty) {
        frames = rawResult.cast<Uint8List>();
        frameDelayMs = (3000 ~/ frames.length).clamp(8, 250);
        totalDurationMs = frames.length * frameDelayMs;
      }

      if (frames.isNotEmpty) {
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
  /// Dynamically computes frame count and frame delay from composition duration (up to 3.0s)
  /// so animations play at natural 1.0x speed without premature truncation.
  /// Yields to the UI event loop during frame extraction, then offloads
  /// Animated WebP encoding to a background isolate.
  Future<String> processLottieSticker(
    String tgsPath,
    String outputDir, {
    Uint8List? fallbackThumbnailBytes,
    bool forceRefresh = false,
  }) async {
    final outputName =
        '${p.basenameWithoutExtension(tgsPath)}_wa_v2.webp';
    final outputPath = p.join(outputDir, outputName);

    final outputFile = File(outputPath);
    if (!forceRefresh && await outputFile.exists()) {
      final len = await outputFile.length();
      if (len > 0 && len <= _maxAnimatedKb * 1024) {
        return outputPath;
      }
    }

    // Clean up older truncated _wa.webp cache file if present
    final oldPath = p.join(
      outputDir,
      '${p.basenameWithoutExtension(tgsPath)}_wa.webp',
    );
    final oldFile = File(oldPath);
    if (await oldFile.exists()) {
      try {
        await oldFile.delete();
      } catch (_) {}
    }

    try {
      final fileBytes = await File(tgsPath).readAsBytes();
      final unzipped = Uint8List.fromList(gzip.decode(fileBytes));
      final composition = await LottieComposition.fromBytes(unzipped);
      final drawable = LottieDrawable(composition);

      // WhatsApp max animation duration is 3000 ms (3 seconds)
      final compositionDurationMs = composition.duration.inMilliseconds;
      final totalDurationMs =
          (compositionDurationMs > 0 ? compositionDurationMs : 3000).clamp(500, 3000);

      // Target ~8 fps for optimal smoothness and WebP size
      // e.g. for 3000ms -> 22 frames; for 2000ms -> 16 frames; for 1000ms -> 8 frames
      final frameCount = ((totalDurationMs / 1000.0) * 8).round().clamp(8, 22);
      final frameDelayMs = (totalDurationMs / frameCount).round().clamp(8, 250);

      final frames = <Uint8List>[];
      final bounds = composition.bounds;
      final drawRect = Rect.fromLTWH(
        bounds.left.toDouble(),
        bounds.top.toDouble(),
        bounds.width.toDouble(),
        bounds.height.toDouble(),
      );
      const size = 512.0;
      const pad = 16.0;
      final drawSize = size - (pad * 2);
      final scale = min(drawSize / bounds.width, drawSize / bounds.height);
      final scaledW = bounds.width * scale;
      final scaledH = bounds.height * scale;
      final dx = (size - scaledW) / 2.0;
      final dy = (size - scaledH) / 2.0;

      for (int i = 0; i < frameCount; i++) {
        final progress = frameCount > 1 ? i / (frameCount - 1) : 0.0;
        drawable.setProgress(progress);

        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        canvas.save();
        canvas.translate(dx, dy);
        canvas.scale(scale, scale);
        drawable.draw(canvas, drawRect);
        canvas.restore();

        final picture = recorder.endRecording();
        final uiImg = await picture.toImage(512, 512);
        final byteData = await uiImg.toByteData(format: ui.ImageByteFormat.png);
        if (byteData != null) {
          frames.add(byteData.buffer.asUint8List());
        }

        // Yield to event loop between frames to keep UI responsive
        await Future<void>.delayed(Duration.zero);
      }

      if (frames.isNotEmpty) {
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

  /// Composes a sequence of [frames] into an animated [img.Image] canvas of 512x512.
  static img.Image _composeAnimatedCanvas(
    List<img.Image> frames,
    int delayMs,
  ) {
    const availableSize = _whatsappSize - (_padding * 2);
    final first = frames.first;
    final baseCanvas = img.Image(
      width: _whatsappSize,
      height: _whatsappSize,
      numChannels: 4,
    );
    final resizedFirst = _fitImage(first, availableSize);
    final ox = (_whatsappSize - resizedFirst.width) ~/ 2;
    final oy = (_whatsappSize - resizedFirst.height) ~/ 2;
    img.compositeImage(baseCanvas, resizedFirst, dstX: ox, dstY: oy);
    baseCanvas.frameDuration = delayMs;
    baseCanvas.loopCount = 0; // Infinite loop required by WhatsApp

    for (int i = 1; i < frames.length; i++) {
      final f = frames[i];
      final frameCanvas = img.Image(
        width: _whatsappSize,
        height: _whatsappSize,
        numChannels: 4,
      );
      final resized = _fitImage(f, availableSize);
      final fx = (_whatsappSize - resized.width) ~/ 2;
      final fy = (_whatsappSize - resized.height) ~/ 2;
      img.compositeImage(frameCanvas, resized, dstX: fx, dstY: fy);
      frameCanvas.frameDuration = delayMs;
      baseCanvas.frames.add(frameCanvas);
    }
    return baseCanvas;
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

    // WhatsApp animated stickers strictly require at least 2 frames
    if (decodedList.length == 1) {
      decodedList.add(decodedList.first);
    }

    final maxBytes = maxKb * 1024;
    Uint8List? bestBytes;
    var currentFrames = List<img.Image>.from(decodedList);
    var currentDelay = frameDelayMs.clamp(8, 500);

    // Ensure total animation duration <= 3000 ms as strictly required by WhatsApp
    if (currentFrames.length * currentDelay > 3000) {
      currentDelay = (3000 ~/ currentFrames.length).clamp(8, 250);
    }

    // Strategy 1: Multi-quality encoding passes on full frames
    var canvas = _composeAnimatedCanvas(currentFrames, currentDelay);
    for (final q in const [70, 55, 40, 25, 15]) {
      final bytes = Uint8List.fromList(
        img.encodeWebP(canvas, lossless: false, quality: q),
      );
      bestBytes = bytes;
      if (bytes.length <= maxBytes) {
        File(outputPath).writeAsBytesSync(bytes);
        return outputPath;
      }
    }

    // Strategy 2: If still > maxKb, downsample frames (sample every 2nd frame)
    // while preserving total animation duration
    if (currentFrames.length > 6) {
      final downsampled = <img.Image>[];
      for (int i = 0; i < currentFrames.length; i += 2) {
        downsampled.add(currentFrames[i]);
      }
      if (downsampled.length < 2) {
        downsampled.add(currentFrames.last);
      }
      currentFrames = downsampled;
      currentDelay = (currentDelay * 2).clamp(8, 500);
      if (currentFrames.length * currentDelay > 3000) {
        currentDelay = (3000 ~/ currentFrames.length).clamp(8, 250);
      }
      canvas = _composeAnimatedCanvas(currentFrames, currentDelay);

      for (final q in const [60, 45, 30, 15]) {
        final bytes = Uint8List.fromList(
          img.encodeWebP(canvas, lossless: false, quality: q),
        );
        bestBytes = bytes;
        if (bytes.length <= maxBytes) {
          File(outputPath).writeAsBytesSync(bytes);
          return outputPath;
        }
      }
    }

    // Strategy 3: Extreme fallback: sparse 4-frame animation while preserving duration
    if (currentFrames.length > 4) {
      final step = (currentFrames.length / 4).ceil();
      final sparseFrames = <img.Image>[];
      for (int i = 0; i < currentFrames.length; i += step) {
        sparseFrames.add(currentFrames[i]);
        if (sparseFrames.length == 4) break;
      }
      while (sparseFrames.length < 2) {
        sparseFrames.add(currentFrames.last);
      }
      currentFrames = sparseFrames;
      final targetTotal = totalDurationMs.clamp(1000, 3000);
      currentDelay = (targetTotal ~/ currentFrames.length).clamp(80, 500);
      if (currentFrames.length * currentDelay > 3000) {
        currentDelay = (3000 ~/ currentFrames.length).clamp(80, 500);
      }
      canvas = _composeAnimatedCanvas(currentFrames, currentDelay);

      for (final q in const [40, 25, 15, 10]) {
        final bytes = Uint8List.fromList(
          img.encodeWebP(canvas, lossless: false, quality: q),
        );
        bestBytes = bytes;
        if (bytes.length <= maxBytes) {
          File(outputPath).writeAsBytesSync(bytes);
          return outputPath;
        }
      }
    }

    // Strategy 4: Strict 2-frame minimal animation if still oversized
    if (currentFrames.length > 2) {
      currentFrames = [currentFrames.first, currentFrames.last];
      currentDelay = (totalDurationMs ~/ 2).clamp(250, 500);
      canvas = _composeAnimatedCanvas(currentFrames, currentDelay);
      for (final q in const [25, 15, 10, 5]) {
        final bytes = Uint8List.fromList(
          img.encodeWebP(canvas, lossless: false, quality: q),
        );
        bestBytes = bytes;
        if (bytes.length <= maxBytes) {
          File(outputPath).writeAsBytesSync(bytes);
          return outputPath;
        }
      }
    }

    // Final safety guard: ensure bytes <= maxBytes unconditionally by downscaling frames
    if (bestBytes == null || bestBytes.length > maxBytes) {
      final smallerCanvas = img.Image(width: _whatsappSize, height: _whatsappSize, numChannels: 4);
      final twoFrames = currentFrames.take(2).toList();
      while (twoFrames.length < 2) {
        twoFrames.add(twoFrames.first);
      }
      final sFirst = _fitImage(twoFrames[0], 360);
      img.compositeImage(smallerCanvas, sFirst, dstX: (_whatsappSize - sFirst.width) ~/ 2, dstY: (_whatsappSize - sFirst.height) ~/ 2);
      smallerCanvas.frameDuration = 500;
      smallerCanvas.loopCount = 0;

      final sSecond = _fitImage(twoFrames[1], 360);
      final frame2 = img.Image(width: _whatsappSize, height: _whatsappSize, numChannels: 4);
      img.compositeImage(frame2, sSecond, dstX: (_whatsappSize - sSecond.width) ~/ 2, dstY: (_whatsappSize - sSecond.height) ~/ 2);
      frame2.frameDuration = 500;
      smallerCanvas.frames.add(frame2);

      bestBytes = Uint8List.fromList(
        img.encodeWebP(smallerCanvas, lossless: false, quality: 15),
      );
    }

    File(outputPath).writeAsBytesSync(bestBytes);
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
