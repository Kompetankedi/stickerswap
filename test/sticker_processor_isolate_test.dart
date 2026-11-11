import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:stickerswap/services/sticker_processor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late StickerProcessor processor;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('sticker_proc_test_');
    processor = StickerProcessor();
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('processImageBytes runs in background isolate and generates valid WebP', () async {
    // Create dummy 512x512 image
    final sampleImg = img.Image(width: 400, height: 400);
    img.fill(sampleImg, color: img.ColorUint8.rgba(0, 150, 255, 255));
    final pngBytes = img.encodePng(sampleImg);

    final outputPath = await processor.processImageBytes(
      pngBytes,
      tempDir.path,
      'test_sample_wa.webp',
      asAnimated: false,
    );

    final file = File(outputPath);
    expect(await file.exists(), isTrue);
    final fileBytes = await file.readAsBytes();
    expect(fileBytes.length, greaterThan(0));
    expect(fileBytes.length, lessThanOrEqualTo(100 * 1024)); // <= 100 KB for WhatsApp

    final decoded = img.decodeWebP(fileBytes);
    expect(decoded, isNotNull);
    expect(decoded!.width, 512);
    expect(decoded.height, 512);
  });

  test('generateTrayIcon runs in background isolate and generates 96x96 PNG < 50KB', () async {
    final sampleImg = img.Image(width: 512, height: 512);
    img.fill(sampleImg, color: img.ColorUint8.rgba(255, 100, 50, 255));
    final pngBytes = img.encodePng(sampleImg);
    final samplePath = '${tempDir.path}/input.png';
    await File(samplePath).writeAsBytes(pngBytes);

    final trayPath = await processor.generateTrayIcon(
      samplePath,
      tempDir.path,
      fileName: 'tray_part_1.png',
    );

    final trayFile = File(trayPath);
    expect(await trayFile.exists(), isTrue);
    final trayBytes = await trayFile.readAsBytes();
    expect(trayBytes.length, greaterThan(0));
    expect(trayBytes.length, lessThanOrEqualTo(50 * 1024)); // <= 50 KB

    final decoded = img.decodePng(trayBytes);
    expect(decoded, isNotNull);
    expect(decoded!.width, 96);
    expect(decoded.height, 96);
  });

  test('processImageBytes asAnimated produces compliant animated WebP <= 480KB with at least 2 frames', () async {
    final sampleImg = img.Image(width: 400, height: 400);
    img.fill(sampleImg, color: img.ColorUint8.rgba(200, 50, 100, 255));
    final pngBytes = img.encodePng(sampleImg);

    final outputPath = await processor.processImageBytes(
      pngBytes,
      tempDir.path,
      'test_anim_wa.webp',
      asAnimated: true,
    );

    final file = File(outputPath);
    expect(await file.exists(), isTrue);
    final fileBytes = await file.readAsBytes();
    expect(fileBytes.length, greaterThan(0));
    expect(fileBytes.length, lessThanOrEqualTo(480 * 1024)); // <= 480 KB strict ceiling

    final decoded = img.decodeWebP(fileBytes);
    expect(decoded, isNotNull);
    expect(decoded!.width, 512);
    expect(decoded.height, 512);
    expect(decoded.numFrames, greaterThanOrEqualTo(2));
  });

  test('createAnimatedWebpFromPngFramesSyncForTest supports 22 frames with full ~3.0s duration <= 460KB', () async {
    final frames = <Uint8List>[];
    for (int i = 0; i < 22; i++) {
      final frame = img.Image(width: 256, height: 256);
      img.fill(frame, color: img.ColorUint8.rgba((i * 11) % 255, 120, 200, 255));
      frames.add(img.encodePng(frame));
    }

    final outPath = '${tempDir.path}/test_22frames_wa_v2.webp';
    final resultPath = StickerProcessor.createAnimatedWebpFromPngFramesSyncForTest(
      pngFrames: frames,
      outputPath: outPath,
      frameDelayMs: 136, // 22 frames * 136ms = 2992ms (~3.0s)
      totalDurationMs: 3000,
    );

    final file = File(resultPath);
    expect(await file.exists(), isTrue);
    final bytes = await file.readAsBytes();
    expect(bytes.length, greaterThan(0));
    expect(bytes.length, lessThanOrEqualTo(460 * 1024)); // WhatsApp 460 KB strict ceiling

    final decoded = img.decodeWebP(bytes);
    expect(decoded, isNotNull);
    expect(decoded!.width, 512);
    expect(decoded.height, 512);
    expect(decoded.numFrames, greaterThanOrEqualTo(10));
    expect(decoded.frameDuration, greaterThanOrEqualTo(8));
    expect(decoded.loopCount, 0);
    final totalDuration =
        decoded.frames.fold<int>(0, (sum, f) => sum + f.frameDuration);
    expect(totalDuration, inInclusiveRange(2800, 3000));
  });

  test('createAnimatedWebpFromPngFramesSyncForTest preserves duration and enforces <= 460KB on heavy frames', () async {
    // Generate complex frames to trigger multi-quality / downsampling fallback
    final frames = <Uint8List>[];
    for (int i = 0; i < 24; i++) {
      final frame = img.Image(width: 512, height: 512);
      // High frequency patterns
      for (int y = 0; y < 512; y += 8) {
        for (int x = 0; x < 512; x += 8) {
          img.fillRect(
            frame,
            x1: x,
            y1: y,
            x2: x + 4,
            y2: y + 4,
            color: img.ColorUint8.rgba((x + i * 10) % 255, (y * 3) % 255, (x ^ y) % 255, 255),
          );
        }
      }
      frames.add(img.encodePng(frame));
    }

    final outPath = '${tempDir.path}/test_heavy_frames_wa_v3.webp';
    final resultPath = StickerProcessor.createAnimatedWebpFromPngFramesSyncForTest(
      pngFrames: frames,
      outputPath: outPath,
      frameDelayMs: 125, // 24 frames * 125ms = 3000ms
      totalDurationMs: 3000,
    );

    final file = File(resultPath);
    expect(await file.exists(), isTrue);
    final bytes = await file.readAsBytes();
    expect(bytes.length, lessThanOrEqualTo(460 * 1024));

    final decoded = img.decodeWebP(bytes);
    expect(decoded, isNotNull);
    expect(decoded!.width, 512);
    expect(decoded.height, 512);
    expect(decoded.numFrames, greaterThanOrEqualTo(6));
    expect(decoded.frameDuration, greaterThanOrEqualTo(8));
    expect(decoded.loopCount, 0);
    final totalDuration =
        decoded.frames.fold<int>(0, (sum, f) => sum + f.frameDuration);
    expect(totalDuration, inInclusiveRange(2500, 3000));
  });

  test('extreme size ceiling fallback still preserves full animation duration instead of collapsing to 1s', () async {
    final frames = <Uint8List>[];
    for (int i = 0; i < 22; i++) {
      final frame = img.Image(width: 320, height: 320, numChannels: 4);
      img.fillRect(
        frame,
        x1: 20,
        y1: 20,
        x2: 300,
        y2: 300,
        color: img.ColorUint8.rgba((i * 23) % 255, (i * 47) % 255, 190, 255),
      );
      img.fillCircle(
        frame,
        x: 60 + (i * 9),
        y: 160,
        radius: 36,
        color: img.ColorUint8.rgba(255, 240, 40, 255),
      );
      frames.add(img.encodePng(frame));
    }

    final outPath = '${tempDir.path}/test_tight_budget_wa_v3.webp';
    final resultPath = StickerProcessor.createAnimatedWebpFromPngFramesSyncForTest(
      pngFrames: frames,
      outputPath: outPath,
      frameDelayMs: 127,
      maxKb: 35,
      totalDurationMs: 2800,
    );

    final bytes = await File(resultPath).readAsBytes();
    expect(bytes.length, lessThanOrEqualTo(35 * 1024));

    final decoded = img.decodeWebP(bytes);
    expect(decoded, isNotNull);
    expect(decoded!.numFrames, greaterThanOrEqualTo(2));
    expect(decoded.loopCount, 0);
    final totalDuration =
        decoded.frames.fold<int>(0, (sum, f) => sum + f.frameDuration);
    expect(totalDuration, inInclusiveRange(2600, 3000));
  });

  test('single-frame input duplicates to 2 frames while preserving requested duration', () async {
    final frame = img.Image(width: 256, height: 256, numChannels: 4);
    img.fill(frame, color: img.ColorUint8.rgba(90, 200, 140, 255));
    final png = img.encodePng(frame);

    final outPath = '${tempDir.path}/test_single_frame_wa_v3.webp';
    final resultPath = StickerProcessor.createAnimatedWebpFromPngFramesSyncForTest(
      pngFrames: [png],
      outputPath: outPath,
      frameDelayMs: 125,
      totalDurationMs: 2500,
    );

    final bytes = await File(resultPath).readAsBytes();
    final decoded = img.decodeWebP(bytes);
    expect(decoded, isNotNull);
    expect(decoded!.numFrames, 2);
    expect(decoded.loopCount, 0);
    final totalDuration =
        decoded.frames.fold<int>(0, (sum, f) => sum + f.frameDuration);
    expect(totalDuration, 2500);
  });

  test('processVideoSticker migrates legacy caches to _wa_v4.webp and preserves sparse >250ms delays', () async {
    const channel = MethodChannel('com.example.stickerswap/video');
    final inputVideo = File('${tempDir.path}/sample.webm')..writeAsBytesSync([0, 1, 2]);
    final legacyV1 = File('${tempDir.path}/sample_wa.webp')..writeAsBytesSync([1, 2, 3]);
    final legacyV2 = File('${tempDir.path}/sample_wa_v2.webp')..writeAsBytesSync([4, 5, 6]);
    final legacyV3 = File('${tempDir.path}/sample_wa_v3.webp')..writeAsBytesSync([7, 8, 9]);

    final sparseFrames = <Uint8List>[];
    for (int i = 0; i < 4; i++) {
      final f = img.Image(width: 200, height: 200, numChannels: 4);
      img.fill(f, color: img.ColorUint8.rgba(i * 60, 120, 220, 255));
      sparseFrames.add(Uint8List.fromList(img.encodePng(f)));
    }

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'extractFrames') {
        return {
          'frames': sparseFrames,
          'durationMs': 2800,
          'frameDelayMs': 700,
        };
      }
      return null;
    });

    try {
      final outPath = await processor.processVideoSticker(
        inputVideo.path,
        tempDir.path,
      );
      expect(outPath.endsWith('sample_wa_v4.webp'), isTrue);
      expect(await File(outPath).exists(), isTrue);
      expect(await legacyV1.exists(), isFalse);
      expect(await legacyV2.exists(), isFalse);
      expect(await legacyV3.exists(), isFalse);

      final decoded = img.decodeWebP(await File(outPath).readAsBytes());
      expect(decoded, isNotNull);
      expect(decoded!.numFrames, 4);
      expect(decoded.frameDuration, 700);
      final totalDuration =
          decoded.frames.fold<int>(0, (sum, f) => sum + f.frameDuration);
      expect(totalDuration, 2800);
    } finally {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    }
  });
}

