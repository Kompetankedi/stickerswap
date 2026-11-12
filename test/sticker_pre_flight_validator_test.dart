import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:stickerswap/services/sticker_pre_flight_validator.dart';
import 'package:stickerswap/services/sticker_processor.dart';
import 'package:stickerswap/widgets/pre_flight_dialog.dart';

Future<String> _writeTrayPng(
  Directory dir,
  String name, {
  int width = 96,
  int height = 96,
}) async {
  final image = img.Image(width: width, height: height, numChannels: 4);
  img.fill(image, color: img.ColorRgba8(0, 122, 255, 255));
  final path = '${dir.path}/$name';
  await File(path).writeAsBytes(img.encodePng(image));
  return path;
}

Future<String> _writeStaticWebp(
  Directory dir,
  String name, {
  int width = 512,
  int height = 512,
  int padTrailingBytes = 0,
}) async {
  final image = img.Image(width: width, height: height, numChannels: 4);
  img.fill(image, color: img.ColorRgba8(240, 80, 40, 255));
  final encoded = img.WebPEncoder(lossless: false, quality: 75).encode(image);
  final path = '${dir.path}/$name';
  final bytes = padTrailingBytes > 0
      ? (BytesBuilder()
            ..add(encoded)
            ..add(Uint8List(padTrailingBytes)))
          .toBytes()
      : encoded;
  await File(path).writeAsBytes(bytes);
  return path;
}

Future<String> _writeAnimatedWebp(
  Directory dir,
  String name, {
  int frameCount = 3,
  int frameDelayMs = 200,
  int width = 512,
  int height = 512,
}) async {
  final base = img.Image(width: width, height: height, numChannels: 4);
  img.fill(base, color: img.ColorRgba8(30, 180, 90, 255));
  base.frameDuration = frameDelayMs;
  base.loopCount = 0;

  for (int i = 1; i < frameCount; i++) {
    final frame = img.Image(width: width, height: height, numChannels: 4);
    img.fill(frame, color: img.ColorRgba8(30 + i * 20, 100, 200, 255));
    frame.frameDuration = frameDelayMs;
    base.frames.add(frame);
  }

  final encoded = img.encodeWebP(base, lossless: false, quality: 65);
  final path = '${dir.path}/$name';
  await File(path).writeAsBytes(encoded);
  return path;
}

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('preflight_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('validates compliant static pack cleanly', () async {
    final trayPath = await _writeTrayPng(tempDir, 'tray.png');
    final s1 = await _writeStaticWebp(tempDir, 's1.webp');
    final s2 = await _writeStaticWebp(tempDir, 's2.webp');
    final s3 = await _writeStaticWebp(tempDir, 's3.webp');

    const validator = StickerPreFlightValidator();
    final report = await validator.validatePack(
      trayPath: trayPath,
      stickerData: [
        {'path': s1, 'emojis': ['🔥']},
        {'path': s2, 'emojis': ['⭐']},
        {'path': s3, 'emojis': ['😂', '👍']},
      ],
      isAnimatedPack: false,
    );

    expect(report.isValid, isTrue);
    expect(report.packErrors, isEmpty);
    expect(report.stickerIssues, isEmpty);
    expect(report.validCount, 3);
  });

  test('detects oversized file, bad dimensions, bad duration, and invalid emojis',
      () async {
    final trayPath = await _writeTrayPng(tempDir, 'tray.png');
    final ok1 = await _writeAnimatedWebp(tempDir, 'ok1.webp');
    final ok2 = await _writeAnimatedWebp(tempDir, 'ok2.webp');
    final ok3 = await _writeAnimatedWebp(tempDir, 'ok3.webp');
    // Bad sticker: wrong dimensions (256x256), duration 3600ms (>3000), invalid emoji
    final badDurationAndSize = await _writeAnimatedWebp(
      tempDir,
      'bad.webp',
      frameCount: 4,
      frameDelayMs: 900,
      width: 256,
      height: 256,
    );

    const validator = StickerPreFlightValidator();
    final report = await validator.validatePack(
      trayPath: trayPath,
      stickerData: [
        {'path': ok1, 'emojis': ['🎉']},
        {'path': ok2, 'emojis': ['🔥']},
        {'path': ok3, 'emojis': ['🚀']},
        {'path': badDurationAndSize, 'emojis': ['not_an_emoji']},
      ],
      isAnimatedPack: true,
    );

    expect(report.isValid, isFalse);
    expect(report.stickerIssues, hasLength(1));
    final issue = report.stickerIssues.first;
    expect(issue.stickerIndex, 3);
    expect(issue.issues, contains(PreFlightIssueType.invalidDimensions));
    expect(issue.issues, contains(PreFlightIssueType.exceedsMaxDuration));
    expect(issue.issues, contains(PreFlightIssueType.invalidEmojis));
    expect(issue.canFixByRecompress, isTrue);
    expect(report.canContinueByExcluding, isTrue);
    expect(report.validCount, 3);
  });

  test('detects oversized static sticker and fixes it via recompressWebpSticker',
      () async {
    final trayPath = await _writeTrayPng(tempDir, 'tray.png');
    final s1 = await _writeStaticWebp(tempDir, 's1.webp');
    final s2 = await _writeStaticWebp(tempDir, 's2.webp');
    final oversized = await _writeStaticWebp(
      tempDir,
      'oversized.webp',
      padTrailingBytes: 110 * 1024,
    );

    const validator = StickerPreFlightValidator();
    final initialReport = await validator.validatePack(
      trayPath: trayPath,
      stickerData: [
        {'path': s1, 'emojis': ['😎']},
        {'path': s2, 'emojis': ['🥳']},
        {'path': oversized, 'emojis': ['💎']},
      ],
      isAnimatedPack: false,
    );

    expect(initialReport.isValid, isFalse);
    expect(
      initialReport.stickerIssues.single.issues,
      contains(PreFlightIssueType.oversizedFile),
    );
    expect(initialReport.canContinueByExcluding, isFalse);

    await StickerProcessor().recompressWebpSticker(oversized, asAnimated: false);

    final rechecked = await validator.validatePack(
      trayPath: trayPath,
      stickerData: [
        {'path': s1, 'emojis': ['😎']},
        {'path': s2, 'emojis': ['🥳']},
        {'path': oversized, 'emojis': ['💎']},
      ],
      isAnimatedPack: false,
    );
    expect(rechecked.isValid, isTrue);
  });

  testWidgets('runPreFlightValidationGate allows excluding faulty sticker',
      (tester) async {
    late String trayPath;
    late String s1;
    late String s2;
    late String s3;
    late String badDims;

    await tester.runAsync(() async {
      trayPath = await _writeTrayPng(tempDir, 'tray.png');
      s1 = await _writeStaticWebp(tempDir, 's1.webp');
      s2 = await _writeStaticWebp(tempDir, 's2.webp');
      s3 = await _writeStaticWebp(tempDir, 's3.webp');
      badDims = await _writeStaticWebp(
        tempDir,
        'bad_dim.webp',
        width: 256,
        height: 256,
      );
    });

    List<Map<String, dynamic>>? gateResult;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () async {
                gateResult = await runPreFlightValidationGate(
                  context: context,
                  trayPath: trayPath,
                  stickerData: [
                    {'path': s1, 'emojis': ['😀']},
                    {'path': s2, 'emojis': ['😃']},
                    {'path': s3, 'emojis': ['😄']},
                    {'path': badDims, 'emojis': ['😅']},
                  ],
                  isAnimatedPack: false,
                );
              },
              child: const Text('Kontrol Et'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Kontrol Et'));
    for (int i = 0;
        i < 25 && find.text('Aktarım Öncesi Kontrol').evaluate().isEmpty;
        i++) {
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 15)),
      );
    }
    await tester.pumpAndSettle();

    expect(find.text('Aktarım Öncesi Kontrol'), findsOneWidget);
    expect(find.text('Hariç Tutarak Ekle (3)'), findsOneWidget);

    await tester.tap(find.text('Hariç Tutarak Ekle (3)'));
    await tester.pumpAndSettle();

    expect(gateResult, hasLength(3));
  });
}

