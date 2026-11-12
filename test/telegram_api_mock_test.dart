import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:stickerswap/models/telegram_sticker.dart';
import 'package:stickerswap/services/telegram_service.dart';

void main() {
  group('TelegramService Mock HTTP Tests', () {
    test('handles 401 Unauthorized cleanly in validateToken and getStickerSet',
        () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({'ok': false, 'description': 'Unauthorized'}),
          401,
        );
      });

      final service = TelegramService.withClient(client)
        ..setBotToken('123456:BAD_TOKEN');

      final tokenRes = await service.validateToken();
      expect(tokenRes['ok'], isFalse);
      expect(tokenRes['error'].toString().toLowerCase(), contains('unauthorized'));

      await expectLater(
        () => service.getStickerSet('CatsPack'),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString().toLowerCase(),
            'message',
            contains('unauthorized'),
          ),
        ),
      );
    });

    test('retries on 429 Too Many Requests and succeeds when rate limit clears',
        () async {
      int calls = 0;
      final client = MockClient((request) async {
        calls++;
        if (calls < 3) {
          return http.Response(
            jsonEncode({
              'ok': false,
              'error_code': 429,
              'description': 'Too Many Requests: retry after 1',
            }),
            429,
            headers: {'retry-after': '1'},
          );
        }
        return http.Response(
          jsonEncode({
            'ok': true,
            'result': {
              'name': 'RetryPack',
              'title': 'Retry Pack',
              'sticker_type': 'regular',
              'is_animated': false,
              'is_video': false,
              'stickers': [],
            },
          }),
          200,
        );
      });

      final service = TelegramService.withClient(
        client,
        retryBaseDelay: const Duration(milliseconds: 5),
      )..setBotToken('123:VALID');

      final set = await service.getStickerSet('RetryPack');
      expect(calls, 3);
      expect(set.name, 'RetryPack');
      expect(set.title, 'Retry Pack');
    });

    test('throws descriptive error when 429 Too Many Requests persists',
        () async {
      int calls = 0;
      final client = MockClient((request) async {
        calls++;
        return http.Response('{"ok":false,"description":"Too Many Requests"}', 429);
      });

      final service = TelegramService.withClient(
        client,
        retryBaseDelay: const Duration(milliseconds: 2),
      )..setBotToken('123:VALID');

      await expectLater(
        () => service.getStickerSet('AnyPack'),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('429'),
          ),
        ),
      );
      expect(calls, 3);
    });

    test('recovers from transient network drop / TimeoutException via backoff retry',
        () async {
      int attempts = 0;
      final client = MockClient((request) async {
        attempts++;
        if (attempts == 1) {
          throw const SocketException('Connection reset by peer');
        }
        if (attempts == 2) {
          throw TimeoutException('Timed out');
        }
        return http.Response(
          jsonEncode({
            'ok': true,
            'result': {'file_path': 'stickers/file_99.webp'},
          }),
          200,
        );
      });

      final service = TelegramService.withClient(
        client,
        retryBaseDelay: const Duration(milliseconds: 2),
      )..setBotToken('123:VALID');

      final url = await service.getFileUrl('file_99');
      expect(attempts, 3);
      expect(url, 'https://api.telegram.org/file/bot123:VALID/stickers/file_99.webp');
    });

    test('rejects empty or non-JSON API responses gracefully', () async {
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/getMe')) {
          return http.Response('', 200);
        }
        return http.Response('<html>502 Bad Gateway</html>', 200);
      });

      final service = TelegramService.withClient(
        client,
        retryBaseDelay: const Duration(milliseconds: 2),
      )..setBotToken('123:VALID');

      final meResult = await service.validateToken();
      expect(meResult['ok'], isFalse);

      await expectLater(
        () => service.getStickerSet('BrokenHtmlPack'),
        throwsA(isA<FormatException>()),
      );
    });

    test('downloadSticker writes file atomically after download retry', () async {
      final tempDir = Directory.systemTemp.createTempSync('tg_dl_mock_');
      addTearDown(() {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      });

      int fileGets = 0;
      final client = MockClient((request) async {
        if (request.url.path.contains('/getFile')) {
          return http.Response(
            jsonEncode({
              'ok': true,
              'result': {'file_path': 'stickers/s1.webp'},
            }),
            200,
          );
        }
        fileGets++;
        if (fileGets == 1) {
          throw const SocketException('Transient socket drop');
        }
        return http.Response.bytes([1, 2, 3, 4], 200);
      });

      final service = TelegramService.withClient(
        client,
        retryBaseDelay: const Duration(milliseconds: 2),
        documentsDirProvider: () async => tempDir,
      )..setBotToken('123:VALID');

      final sticker = TelegramSticker(
        fileId: 'f1',
        fileUniqueId: 'u1',
        width: 512,
        height: 512,
        isAnimated: false,
        isVideo: false,
      );

      final path = await service.downloadSticker(sticker, 'TestPack');
      expect(fileGets, 2);
      expect(File(path).existsSync(), isTrue);
      expect(File('$path.tmp').existsSync(), isFalse);
      expect(File(path).readAsBytesSync(), [1, 2, 3, 4]);
    });
  });
}
