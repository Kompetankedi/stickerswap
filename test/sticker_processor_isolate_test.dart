import 'dart:io';
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
}

