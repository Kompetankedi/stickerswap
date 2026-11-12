import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../models/telegram_sticker.dart';
import '../models/telegram_sticker_set.dart';

/// Singleton service that communicates with the Telegram Bot API
/// to fetch and download sticker packs.
class TelegramService {
  static final TelegramService _instance = TelegramService._internal();
  factory TelegramService() => _instance;

  TelegramService._internal({
    http.Client? httpClient,
    Duration retryBaseDelay = const Duration(milliseconds: 500),
    Duration requestTimeout = const Duration(seconds: 15),
    Future<Directory> Function()? documentsDirProvider,
  })  : _httpClient = httpClient ?? http.Client(),
        _retryBaseDelay = retryBaseDelay,
        _requestTimeout = requestTimeout,
        _documentsDirProvider =
            documentsDirProvider ?? getApplicationDocumentsDirectory;

  /// Creates an isolated instance for unit tests using `MockClient`.
  @visibleForTesting
  factory TelegramService.withClient(
    http.Client client, {
    Duration retryBaseDelay = const Duration(milliseconds: 5),
    Duration requestTimeout = const Duration(seconds: 5),
    Future<Directory> Function()? documentsDirProvider,
  }) {
    return TelegramService._internal(
      httpClient: client,
      retryBaseDelay: retryBaseDelay,
      requestTimeout: requestTimeout,
      documentsDirProvider: documentsDirProvider,
    );
  }

  final http.Client _httpClient;
  final Duration _retryBaseDelay;
  final Duration _requestTimeout;
  final Future<Directory> Function() _documentsDirProvider;

  String _botToken = '';
  static const String _baseUrl = 'https://api.telegram.org/bot';

  String get botToken => _botToken;
  bool get hasToken => _botToken.trim().isNotEmpty;

  void setBotToken(String token) {
    _botToken = token.trim();
  }

  void clearToken() {
    _botToken = '';
  }

  String get _apiBase => '$_baseUrl$_botToken';

  Map<String, dynamic> _decodeJsonObject(String body) {
    if (body.trim().isEmpty) {
      throw const FormatException('Telegram API boş yanıt döndürdü.');
    }
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Telegram API beklenmeyen JSON formatı döndürdü.');
    }
    return decoded;
  }

  Duration _computeRateLimitDelay(http.Response response, int attempt) {
    final retryAfterRaw = response.headers['retry-after'];
    final retrySeconds =
        retryAfterRaw != null ? int.tryParse(retryAfterRaw.trim()) : null;
    if (retrySeconds != null && retrySeconds > 0) {
      // Bound server-requested delay so fast unit tests remain responsive when backoff is tiny.
      final cappedMs = (_retryBaseDelay.inMilliseconds * retrySeconds * 2)
          .clamp(_retryBaseDelay.inMilliseconds, retrySeconds * 1000);
      return Duration(milliseconds: cappedMs);
    }
    return Duration(milliseconds: _retryBaseDelay.inMilliseconds * attempt);
  }

  Future<http.Response> _getWithRetry(
    Uri uri, {
    int maxAttempts = 3,
    Duration? timeout,
  }) async {
    final effectiveTimeout = timeout ?? _requestTimeout;
    int attempts = 0;

    while (true) {
      attempts++;
      try {
        final response =
            await _httpClient.get(uri).timeout(effectiveTimeout);

        if (response.statusCode == 429) {
          if (attempts >= maxAttempts) {
            throw Exception(
              'Telegram API hız sınırına ulaşıldı (429 Too Many Requests). '
              'Lütfen biraz sonra tekrar deneyin.',
            );
          }
          await Future<void>.delayed(_computeRateLimitDelay(response, attempts));
          continue;
        }

        if (response.statusCode >= 500 && attempts < maxAttempts) {
          await Future<void>.delayed(
            Duration(milliseconds: _retryBaseDelay.inMilliseconds * attempts),
          );
          continue;
        }

        return response;
      } catch (e) {
        if (attempts >= maxAttempts) {
          rethrow;
        }
        await Future<void>.delayed(
          Duration(milliseconds: _retryBaseDelay.inMilliseconds * attempts),
        );
      }
    }
  }

  /// Validates whether the current bot token is working.
  Future<Map<String, dynamic>> validateToken([String? tokenToTest]) async {
    final token = tokenToTest ?? _botToken;
    if (token.trim().isEmpty) {
      return {'ok': false, 'error': 'Token boş olamaz'};
    }

    try {
      final response = await _getWithRetry(
        Uri.parse('$_baseUrl${token.trim()}/getMe'),
        maxAttempts: 2,
        timeout: const Duration(seconds: 10),
      );
      if (response.statusCode == 401) {
        return {
          'ok': false,
          'error': 'Unauthorized: Bot Token geçersiz (401)',
        };
      }
      final data = _decodeJsonObject(response.body);
      if (data['ok'] == true) {
        final result = data['result'];
        return {
          'ok': true,
          'botName': result is Map ? (result['first_name'] ?? 'Unknown') : 'Unknown',
          'username': result is Map ? (result['username'] ?? '') : '',
        };
      } else {
        return {
          'ok': false,
          'error': data['description'] ?? 'Geçersiz token',
        };
      }
    } on FormatException catch (e) {
      return {'ok': false, 'error': e.message};
    } catch (e) {
      return {'ok': false, 'error': e.toString()};
    }
  }

  /// Extracts the sticker set name from various Telegram link formats.
  static String? extractSetName(String input) {
    input = input.trim();

    // Direct set name (no URL)
    if (!input.contains('/') && !input.contains(':') && input.isNotEmpty) {
      return input;
    }

    // https://t.me/addstickers/SetName
    final regexHttps = RegExp(
      r'(?:https?://)?(?:t\.me|telegram\.me)/addstickers/([a-zA-Z0-9_]+)',
      caseSensitive: false,
    );
    final matchHttps = regexHttps.firstMatch(input);
    if (matchHttps != null) return matchHttps.group(1);

    // tg://addstickers?set=SetName
    final regexTg = RegExp(
      r'tg://addstickers\?set=([a-zA-Z0-9_]+)',
      caseSensitive: false,
    );
    final matchTg = regexTg.firstMatch(input);
    if (matchTg != null) return matchTg.group(1);

    return null;
  }

  /// Fetches a sticker set by its name from the Telegram Bot API.
  Future<TelegramStickerSet> getStickerSet(String setName) async {
    if (!hasToken) {
      throw Exception(
        'Telegram Bot Token tanımlanmamış.\n'
        'Lütfen Ayarlar sekmesinden geçerli bir Bot Token girin.',
      );
    }

    final response = await _getWithRetry(
      Uri.parse('$_apiBase/getStickerSet?name=$setName'),
    );

    if (response.statusCode == 401) {
      throw Exception(
        'Girdiğiniz Bot Token geçersiz veya yetkisiz (Unauthorized).\n'
        'Lütfen Ayarlar sekmesinden geçerli bir Bot Token girin.',
      );
    }

    final data = _decodeJsonObject(response.body);
    if (data['ok'] != true) {
      final desc = data['description']?.toString() ?? '';
      if (desc.toLowerCase().contains('unauthorized')) {
        throw Exception(
          'Girdiğiniz Bot Token geçersiz veya yetkisiz (Unauthorized).\n'
          'Lütfen Ayarlar sekmesinden geçerli bir Bot Token girin.',
        );
      }
      throw Exception(
        desc.isNotEmpty ? desc : 'Sticker paketi bulunamadı.',
      );
    }
    final result = data['result'];
    if (result is! Map<String, dynamic>) {
      throw const FormatException('Telegram API geçersiz paket verisi döndürdü.');
    }
    return TelegramStickerSet.fromJson(result);
  }

  /// Retrieves the download URL for a given file_id with retry.
  Future<String> getFileUrl(String fileId) async {
    if (!hasToken) {
      throw Exception('Bot Token tanımlanmamış.');
    }

    final response = await _getWithRetry(
      Uri.parse('$_apiBase/getFile?file_id=$fileId'),
    );

    if (response.statusCode == 401) {
      throw Exception('Bot Token yetkisiz (Unauthorized).');
    }

    final data = _decodeJsonObject(response.body);
    if (data['ok'] != true) {
      throw Exception(
        'Dosya yolu alınamadı: ${data['description'] ?? 'Hata'}',
      );
    }
    final result = data['result'];
    final filePath = result is Map ? result['file_path'] as String? : null;
    if (filePath == null || filePath.isEmpty) {
      throw const FormatException('Telegram API dosya yolunu döndürmedi.');
    }
    return 'https://api.telegram.org/file/bot$_botToken/$filePath';
  }

  /// Downloads a sticker file to local storage and returns its path.
  /// Implements automated 3-pass retry with backoff and atomic temporary writes
  /// to ensure socket drops (ClientRead failed) do not abort bulk preparation.
  Future<String> downloadSticker(
    TelegramSticker sticker,
    String packName,
  ) async {
    final dir = await _documentsDirProvider();
    final packDir = Directory(p.join(dir.path, 'stickers', packName));
    if (!await packDir.exists()) {
      await packDir.create(recursive: true);
    }

    final ext = sticker.isVideo
        ? '.webm'
        : sticker.isAnimated
            ? '.tgs'
            : '.webp';
    final fileName = '${sticker.fileUniqueId}$ext';
    final filePath = p.join(packDir.path, fileName);
    final file = File(filePath);

    if (await file.exists() && await file.length() > 0) {
      return filePath;
    }

    final url = await getFileUrl(sticker.fileId);
    final response = await _getWithRetry(
      Uri.parse(url),
      timeout: const Duration(seconds: 30),
    );

    if (response.statusCode != 200) {
      throw Exception('Sticker indirilemedi (HTTP ${response.statusCode})');
    }

    final tmpPath = '$filePath.tmp';
    final tmpFile = File(tmpPath);
    await tmpFile.writeAsBytes(response.bodyBytes);
    await tmpFile.rename(filePath);
    return filePath;
  }

  /// Downloads a thumbnail for a sticker (used for previews) with retry.
  Future<Uint8List?> downloadThumbnail(String fileId) async {
    try {
      final url = await getFileUrl(fileId);
      final response = await _getWithRetry(Uri.parse(url));
      if (response.statusCode == 200) {
        return response.bodyBytes;
      }
    } catch (_) {}
    return null;
  }
}
