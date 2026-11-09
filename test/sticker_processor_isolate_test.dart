import 'dart:io';
import 'dart:typed_data';
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
    // Total animation duration should not exceed WhatsApp 3000 ms limit
    expect(decoded.numFrames * decoded.frameDuration, lessThanOrEqualTo(3000));
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

    final outPath = '${tempDir.path}/test_heavy_frames_wa_v2.webp';
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
    expect(decoded.numFrames, greaterThanOrEqualTo(2));
    expect(decoded.frameDuration, greaterThanOrEqualTo(8));
    expect(decoded.numFrames * decoded.frameDuration, lessThanOrEqualTo(3000));
  });
}

