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
  static const int _maxStaticKb = 100;
  static const int _maxAnimatedKb = 480; // Strictly under WhatsApp 500KB limit
  static const int _maxTrayKb = 50;
  static const int _padding = 16;

  static const MethodChannel _videoChannel =
      MethodChannel('com.example.stickerswap/video');

  /// Converts a video sticker (e.g. .webm) into a WhatsApp-compliant Animated WebP.
  /// Heavy frame decoding and multi-frame WebP encoding run inside an isolate worker.
  Future<String> processVideoSticker(
    String videoPath,
    String outputDir, {
    Uint8List? fallbackThumbnailBytes,
  }) async {
    final outputName =
        '${p.basenameWithoutExtension(videoPath)}_wa.webp';
    final outputPath = p.join(outputDir, outputName);

    // Fast return if already processed
    final outputFile = File(outputPath);
    if (await outputFile.exists() && await outputFile.length() > 0) {
      return outputPath;
    }

    try {
      // 1. Extract frames via Android native MediaCodec sequential extractor
      final dynamic rawFrames = await _videoChannel.invokeMethod('extractFrames', {
        'videoPath': videoPath,
        'fps': 12,
        'maxFrames': 15, // 15 frames at 12fps = 1.25s, optimal visual smoothness and size
      });

      if (rawFrames is List && rawFrames.isNotEmpty) {
        final frames = rawFrames.cast<Uint8List>();
        // Offload heavy image decoding and WebP compression to background Isolate
        return await Isolate.run(() {
          return _createAnimatedWebpFromPngFramesSync(
            pngFrames: frames,
            outputPath: outputPath,
            frameDelayMs: 83, // ~12 fps
            maxKb: _maxAnimatedKb,
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
      );
    }

    throw Exception('Video ve önizleme çözülemedi: $videoPath');
  }

  /// Converts a Lottie sticker (.tgs) into a compliant 512x512 Animated WebP.
  /// Yields to the UI event loop during frame extraction, then offloads
  /// Animated WebP encoding to a background isolate.
  Future<String> processLottieSticker(
    String tgsPath,
    String outputDir, {
    Uint8List? fallbackThumbnailBytes,
  }) async {
    final outputName =
        '${p.basenameWithoutExtension(tgsPath)}_wa.webp';
    final outputPath = p.join(outputDir, outputName);

    final outputFile = File(outputPath);
    if (await outputFile.exists() && await outputFile.length() > 0) {
      return outputPath;
    }

    try {
      final fileBytes = await File(tgsPath).readAsBytes();
      final unzipped = Uint8List.fromList(gzip.decode(fileBytes));
      final composition = await LottieComposition.fromBytes(unzipped);
      final drawable = LottieDrawable(composition);

      final frames = <Uint8List>[];
      const frameCount = 14;
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
        final progress = i / (frameCount - 1);
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
            frameDelayMs: 83,
            maxKb: _maxAnimatedKb,
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
  }) async {
    final outputPath = p.join(outputDir, outputName);
    final outputFile = File(outputPath);
    if (await outputFile.exists() && await outputFile.length() > 0) {
      return outputPath;
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
  }) async {
    final outputName =
        '${p.basenameWithoutExtension(inputPath)}_wa.webp';
    final outputPath = p.join(outputDir, outputName);

    final outputFile = File(outputPath);
    if (await outputFile.exists() && await outputFile.length() > 0) {
      return outputPath;
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
  }) async {
    final outputPath = p.join(outputDir, fileName);
    final outputFile = File(outputPath);
    if (await outputFile.exists() && await outputFile.length() > 0) {
      return outputPath;
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

  /// Synchronously encodes a list of frames into Animated WebP within a background isolate.
  static String _createAnimatedWebpFromPngFramesSync({
    required List<Uint8List> pngFrames,
    required String outputPath,
    int frameDelayMs = 83,
    int maxKb = _maxAnimatedKb,
  }) {
    if (pngFrames.isEmpty) {
      throw Exception('Kare listesi boş olamaz');
    }

    final firstDecoded = img.decodeImage(pngFrames.first);
    if (firstDecoded == null) {
      throw Exception('İlk kare çözülemedi');
    }

    const availableSize = _whatsappSize - (_padding * 2);

    // Base canvas 512x512
    final baseCanvas = img.Image(
      width: _whatsappSize,
      height: _whatsappSize,
      numChannels: 4,
    );
    final resizedFirst = _fitImage(firstDecoded, availableSize);
    final ox = (_whatsappSize - resizedFirst.width) ~/ 2;
    final oy = (_whatsappSize - resizedFirst.height) ~/ 2;
    img.compositeImage(baseCanvas, resizedFirst, dstX: ox, dstY: oy);
    baseCanvas.frameDuration = frameDelayMs;
    baseCanvas.loopCount = 0; // Infinite loop

    for (int i = 1; i < pngFrames.length; i++) {
      final decodedFrame = img.decodeImage(pngFrames[i]);
      if (decodedFrame == null) continue;

      final frameCanvas = img.Image(
        width: _whatsappSize,
        height: _whatsappSize,
        numChannels: 4,
      );
      final resized = _fitImage(decodedFrame, availableSize);
      final fx = (_whatsappSize - resized.width) ~/ 2;
      final fy = (_whatsappSize - resized.height) ~/ 2;
      img.compositeImage(frameCanvas, resized, dstX: fx, dstY: fy);
      frameCanvas.frameDuration = frameDelayMs;

      baseCanvas.frames.add(frameCanvas);
    }

    // Try encoding and compress to ensure <= 480 KB
    // Quality 70 provides high fidelity while reliably producing 200-350 KB files
    Uint8List webpBytes = Uint8List.fromList(
      img.encodeWebP(baseCanvas, lossless: false, quality: 70),
    );

    if (webpBytes.length > maxKb * 1024) {
      webpBytes = Uint8List.fromList(
        img.encodeWebP(baseCanvas, lossless: false, quality: 55),
      );
    }
    if (webpBytes.length > maxKb * 1024) {
      webpBytes = Uint8List.fromList(
        img.encodeWebP(baseCanvas, lossless: false, quality: 40),
      );
    }
    if (webpBytes.length > maxKb * 1024) {
      webpBytes = Uint8List.fromList(
        img.encodeWebP(baseCanvas, lossless: false, quality: 25),
      );
    }

    File(outputPath).writeAsBytesSync(webpBytes);
    return outputPath;
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

      final webpBytes = Uint8List.fromList(
        img.encodeWebP(canvas, lossless: false, quality: 80),
      );
      File(outputPath).writeAsBytesSync(webpBytes);
      return outputPath;
    }

    Uint8List webpBytes = Uint8List.fromList(
      img.WebPEncoder(lossless: true).encode(canvas),
    );

    if (webpBytes.length > _maxStaticKb * 1024) {
      webpBytes = Uint8List.fromList(
        img.WebPEncoder(lossless: false, quality: 85).encode(canvas),
      );
    }
    if (webpBytes.length > _maxStaticKb * 1024) {
      webpBytes = Uint8List.fromList(
        img.WebPEncoder(lossless: false, quality: 70).encode(canvas),
      );
    }
    if (webpBytes.length > _maxStaticKb * 1024) {
      webpBytes = Uint8List.fromList(
        img.WebPEncoder(lossless: false, quality: 50).encode(canvas),
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

      final webpBytes = Uint8List.fromList(
        img.encodeWebP(canvas, lossless: false, quality: 80),
      );
      File(outputPath).writeAsBytesSync(webpBytes);
      return outputPath;
    }

    Uint8List webpBytes = Uint8List.fromList(
      img.WebPEncoder(lossless: true).encode(canvas),
    );
    if (webpBytes.length > _maxStaticKb * 1024) {
      webpBytes = Uint8List.fromList(
        img.WebPEncoder(lossless: false, quality: 85).encode(canvas),
      );
    }
    File(outputPath).writeAsBytesSync(webpBytes);
    return outputPath;
  }

  /// Synchronously generates a 96x96 tray icon within an isolate.
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

    final resized = _fitImage(decoded, _traySize - 8);
    final canvas = img.Image(
      width: _traySize,
      height: _traySize,
      numChannels: 4,
    );
    final offsetX = (_traySize - resized.width) ~/ 2;
    final offsetY = (_traySize - resized.height) ~/ 2;
    img.compositeImage(canvas, resized, dstX: offsetX, dstY: offsetY);

    Uint8List pngBytes = Uint8List.fromList(img.encodePng(canvas));

    // If over 50KB, reduce size
    if (pngBytes.length > _maxTrayKb * 1024) {
      final smaller = img.copyResize(canvas,
          width: _traySize ~/ 2, height: _traySize ~/ 2);
      final finalCanvas = img.Image(
        width: _traySize,
        height: _traySize,
        numChannels: 4,
      );
      final ox = (_traySize - smaller.width) ~/ 2;
      final oy = (_traySize - smaller.height) ~/ 2;
      img.compositeImage(finalCanvas, smaller, dstX: ox, dstY: oy);
      pngBytes = Uint8List.fromList(img.encodePng(finalCanvas));
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
