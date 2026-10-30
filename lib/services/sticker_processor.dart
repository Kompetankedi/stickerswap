import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;
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
  Future<String> processVideoSticker(
    String videoPath,
    String outputDir, {
    Uint8List? fallbackThumbnailBytes,
  }) async {
    final outputName =
        '${p.basenameWithoutExtension(videoPath)}_wa.webp';
    final outputPath = p.join(outputDir, outputName);

    try {
      // 1. Extract frames via Android native MediaCodec sequential extractor
      final dynamic rawFrames = await _videoChannel.invokeMethod('extractFrames', {
        'videoPath': videoPath,
        'fps': 12,
        'maxFrames': 18, // 18 frames at 12fps = ~1.5 sec, fits WhatsApp 500KB easily
      });

      if (rawFrames is List && rawFrames.isNotEmpty) {
        final frames = rawFrames.cast<Uint8List>();
        return await _createAnimatedWebpFromPngFrames(frames, outputPath);
      }
    } catch (_) {
      // Extraction failed
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
  Future<String> processLottieSticker(
    String tgsPath,
    String outputDir, {
    Uint8List? fallbackThumbnailBytes,
  }) async {
    final outputName =
        '${p.basenameWithoutExtension(tgsPath)}_wa.webp';
    final outputPath = p.join(outputDir, outputName);

    try {
      final fileBytes = await File(tgsPath).readAsBytes();
      final unzipped = Uint8List.fromList(gzip.decode(fileBytes));
      final composition = await LottieComposition.fromBytes(unzipped);
      final drawable = LottieDrawable(composition);

      final frames = <Uint8List>[];
      const frameCount = 16;
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
      }

      if (frames.isNotEmpty) {
        return await _createAnimatedWebpFromPngFrames(frames, outputPath);
      }
    } catch (_) {
      // Fallback
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

  /// Processes raw image bytes into a 512x512 WebP sticker.
  Future<String> processImageBytes(
    Uint8List bytes,
    String outputDir,
    String outputName, {
    bool asAnimated = false,
  }) async {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw Exception('Görsel çözülemedi');
    }
    final availableSize = _whatsappSize - (_padding * 2);
    final resized = _fitImage(decoded, availableSize);

    final canvas = img.Image(
      width: _whatsappSize,
      height: _whatsappSize,
      numChannels: 4,
    );
    final offsetX = (_whatsappSize - resized.width) ~/ 2;
    final offsetY = (_whatsappSize - resized.height) ~/ 2;
    img.compositeImage(canvas, resized, dstX: offsetX, dstY: offsetY);

    final outputPath = p.join(outputDir, outputName);

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
      await File(outputPath).writeAsBytes(webpBytes);
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
    await File(outputPath).writeAsBytes(webpBytes);
    return outputPath;
  }

  /// Converts a list of image frames (PNG or JPEG) into a compliant 512x512 Animated WebP.
  Future<String> _createAnimatedWebpFromPngFrames(
    List<Uint8List> pngFrames,
    String outputPath, {
    int frameDelayMs = 83, // ~12 fps
  }) async {
    final firstDecoded = img.decodeImage(pngFrames.first);
    if (firstDecoded == null) {
      throw Exception('İlk kare çözülemedi');
    }

    final availableSize = _whatsappSize - (_padding * 2);

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
    Uint8List webpBytes = Uint8List.fromList(
      img.encodeWebP(baseCanvas, lossless: false, quality: 75),
    );

    if (webpBytes.length > _maxAnimatedKb * 1024) {
      webpBytes = Uint8List.fromList(
        img.encodeWebP(baseCanvas, lossless: false, quality: 60),
      );
    }
    if (webpBytes.length > _maxAnimatedKb * 1024) {
      webpBytes = Uint8List.fromList(
        img.encodeWebP(baseCanvas, lossless: false, quality: 45),
      );
    }
    if (webpBytes.length > _maxAnimatedKb * 1024) {
      webpBytes = Uint8List.fromList(
        img.encodeWebP(baseCanvas, lossless: false, quality: 30),
      );
    }

    await File(outputPath).writeAsBytes(webpBytes);
    return outputPath;
  }

  /// Converts a downloaded Telegram sticker to WhatsApp format.
  /// If [asAnimated] is true, generates an Animated WebP with 2 frames
  /// so that mixed packs pass WhatsApp's animated pack requirement.
  Future<String> processSticker(
    String inputPath,
    String outputDir, {
    bool asAnimated = false,
  }) async {
    final inputFile = File(inputPath);
    final bytes = await inputFile.readAsBytes();

    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw Exception('Görsel çözülemedi: $inputPath');
    }

    // Calculate fit dimensions with padding
    final availableSize = _whatsappSize - (_padding * 2);
    final resized = _fitImage(decoded, availableSize);

    // Create 512x512 canvas with transparency
    final canvas = img.Image(
      width: _whatsappSize,
      height: _whatsappSize,
      numChannels: 4,
    );

    // Center the sticker on the canvas
    final offsetX = (_whatsappSize - resized.width) ~/ 2;
    final offsetY = (_whatsappSize - resized.height) ~/ 2;
    img.compositeImage(canvas, resized, dstX: offsetX, dstY: offsetY);

    final outputName =
        '${p.basenameWithoutExtension(inputPath)}_wa.webp';
    final outputPath = p.join(outputDir, outputName);

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
      await File(outputPath).writeAsBytes(webpBytes);
      return outputPath;
    }

    // Try lossless first, then progressively reduce quality for static
    Uint8List webpBytes = Uint8List.fromList(
      img.WebPEncoder(lossless: true).encode(canvas),
    );

    if (webpBytes.length > _maxStaticKb * 1024) {
      webpBytes = Uint8List.fromList(
        img.WebPEncoder(lossless: false, quality: 90).encode(canvas),
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

    await File(outputPath).writeAsBytes(webpBytes);
    return outputPath;
  }

  /// Generates a 96x96 tray icon from the first sticker.
  Future<String> generateTrayIcon(String inputPath, String outputDir) async {
    final inputFile = File(inputPath);
    final bytes = await inputFile.readAsBytes();

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

    final outputPath = p.join(outputDir, 'tray_icon.png');
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

    await File(outputPath).writeAsBytes(pngBytes);
    return outputPath;
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

  /// Resize image to fit within [maxSize] preserving aspect ratio.
  img.Image _fitImage(img.Image source, int maxSize) {
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
