import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:stickerswap/services/sticker_processor.dart';
import 'package:stickerswap/services/webp_inspector.dart';
import 'package:stickerswap/services/whatsapp_service.dart';

String _buildAnimatedLottieJson({
  required double fps,
  required double outPoint,
}) {
  return jsonEncode({
    'v': '5.7.4',
    'fr': fps,
    'ip': 0,
    'op': outPoint,
    'w': 512,
    'h': 512,
    'nm': 'MovingSquare',
    'ddd': 0,
    'assets': [],
    'layers': [
      {
        'ddd': 0,
        'ind': 1,
        'ty': 4,
        'nm': 'RectLayer',
        'sr': 1,
        'ks': {
          'o': {'a': 0, 'k': 100},
          'r': {'a': 0, 'k': 0},
          'p': {
            'a': 1,
            'k': [
              {
                't': 0,
                's': [80.0, 256.0, 0.0],
                'e': [432.0, 256.0, 0.0],
                'i': {'x': [0.5], 'y': [0.5]},
                'o': {'x': [0.5], 'y': [0.5]},
              },
              {
                't': outPoint,
                's': [432.0, 256.0, 0.0],
              }
            ]
          },
          'a': {'a': 0, 'k': [0, 0, 0]},
          's': {'a': 0, 'k': [100, 100, 100]},
        },
        'ao': 0,
        'shapes': [
          {
            'ty': 'gr',
            'it': [
              {
                'ty': 'rc',
                'd': 1,
                's': {'a': 0, 'k': [100, 100]},
                'p': {'a': 0, 'k': [0, 0]},
                'r': {'a': 0, 'k': 10},
                'nm': 'Rect',
              },
              {
                'ty': 'fl',
                'c': {'a': 0, 'k': [1, 0.2, 0.2, 1]},
                'o': {'a': 0, 'k': 100},
                'r': 1,
                'nm': 'Fill',
              },
              {
                'ty': 'tr',
                'p': {'a': 0, 'k': [0, 0]},
                'a': {'a': 0, 'k': [0, 0]},
                's': {'a': 0, 'k': [100, 100]},
                'r': {'a': 0, 'k': 0},
                'o': {'a': 0, 'k': 100},
              }
            ],
            'nm': 'Group',
          }
        ],
        'ip': 0,
        'op': outPoint,
        'st': 0,
        'bm': 0,
      }
    ],
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('WebpInspector parses animated and static WebP container headers', () {
    final anim = img.Image(width: 512, height: 512, numChannels: 4);
    for (int i = 0; i < 22; i++) {
      final frame = img.Image(width: 512, height: 512, numChannels: 4);
      img.fillRect(
        frame,
        x1: 20 + i * 10,
        y1: 200,
        x2: 120 + i * 10,
        y2: 300,
        color: img.ColorRgba8(255, 60, 60, 255),
      );
      frame.frameDuration = 136;
      if (i == 0) {
        anim.frames[0] = frame;
      } else {
        anim.addFrame(frame);
      }
    }

    final animBytes = img.encodeWebP(anim);
    final animMeta = WebpInspector.inspectBytes(animBytes);
    expect(animMeta, isNotNull);
    expect(animMeta!.isAnimated, isTrue);
    expect(animMeta.width, 512);
    expect(animMeta.height, 512);
    expect(animMeta.frameCount, 22);
    expect(animMeta.totalDurationMs, 22 * 136);
    expect(animMeta.loopCount, 0);

    final staticImg = img.Image(width: 512, height: 512, numChannels: 4);
    img.fill(staticImg, color: img.ColorRgba8(20, 120, 240, 255));
    final staticBytes = img.encodeWebP(staticImg);
    final staticMeta = WebpInspector.inspectBytes(staticBytes);
    expect(staticMeta, isNotNull);
    expect(staticMeta!.isAnimated, isFalse);
    expect(staticMeta.width, 512);
    expect(staticMeta.height, 512);
    expect(staticMeta.frameCount, 1);
  });

  test('StickerProcessor.processLottieSticker preserves full 3s motion', () async {
    final tmpDir = await Directory.systemTemp.createTemp('tgs_lottie_test_');
    try {
      final processor = StickerProcessor();
      final tgsPath = p.join(tmpDir.path, 'anim_3s.tgs');
      final gzBytes = gzip.encode(
        utf8.encode(_buildAnimatedLottieJson(fps: 30.0, outPoint: 90.0)),
      );
      await File(tgsPath).writeAsBytes(gzBytes, flush: true);

      final outPath = await processor.processLottieSticker(
        tgsPath,
        tmpDir.path,
        forceRefresh: true,
      );
      expect(outPath.endsWith('_wa_v4.webp'), isTrue);

      final meta = await WebpInspector.inspectFile(outPath);
      expect(meta, isNotNull);
      expect(meta!.isAnimated, isTrue);
      expect(meta.frameCount, greaterThanOrEqualTo(18));
      expect(meta.totalDurationMs, inInclusiveRange(2700, 3100));
      expect(meta.fileSizeBytes, lessThanOrEqualTo(460 * 1024));

      final decoded = img.decodeWebP(await File(outPath).readAsBytes())!;
      double centroidX(img.Image frame) {
        double sumX = 0;
        int count = 0;
        for (int y = 0; y < frame.height; y++) {
          for (int x = 0; x < frame.width; x++) {
            if (frame.getPixel(x, y).a > 20) {
              sumX += x;
              count++;
            }
          }
        }
        return count > 0 ? sumX / count : -1.0;
      }

      final firstX = centroidX(decoded.frames.first);
      final midX = centroidX(decoded.frames[decoded.numFrames ~/ 2]);
      final lastX = centroidX(decoded.frames.last);
      expect(midX - firstX, greaterThan(50.0));
      expect(lastX - midX, greaterThan(50.0));
    } finally {
      await tmpDir.delete(recursive: true);
    }
  });

  test('WhatsAppService.buildVersionedIdentifier stays <= 64 chars cleanly', () {
    final longBase = 'very_long_telegram_sticker_pack_identifier_name_over_fifty_chars_part2';
    final v1 = WhatsAppService.buildVersionedIdentifier(
      longBase,
      epochSeconds: 1762870000,
    );
    expect(v1.length, lessThanOrEqualTo(64));
    expect(v1.endsWith('_1762870000'), isTrue);

    final v2 = WhatsAppService.buildVersionedIdentifier(
      v1,
      epochSeconds: 1762871111,
    );
    expect(v2.length, lessThanOrEqualTo(64));
    expect(v2.endsWith('_1762871111'), isTrue);
    expect(v2.contains('1762870000'), isFalse);
  });
}

