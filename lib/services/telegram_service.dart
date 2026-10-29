import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
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
  TelegramService._internal();

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

  /// Validates whether the current bot token is working.
  Future<Map<String, dynamic>> validateToken([String? tokenToTest]) async {
    final token = tokenToTest ?? _botToken;
    if (token.trim().isEmpty) {
      return {'ok': false, 'error': 'Token boş olamaz'};
    }

    try {
      final response = await http
          .get(Uri.parse('$_baseUrl${token.trim()}/getMe'))
          .timeout(const Duration(seconds: 10));
      final data = jsonDecode(response.body);
      if (data['ok'] == true) {
        return {
          'ok': true,
          'botName': data['result']?['first_name'] ?? 'Unknown',
          'username': data['result']?['username'] ?? '',
        };
      } else {
        return {
          'ok': false,
          'error': data['description'] ?? 'Geçersiz token',
        };
      }
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

    final response = await http
        .get(Uri.parse('$_apiBase/getStickerSet?name=$setName'))
        .timeout(const Duration(seconds: 15));

    final data = jsonDecode(response.body);
    if (data['ok'] != true) {
      final desc = data['description']?.toString() ?? '';
      if (response.statusCode == 401 ||
          desc.toLowerCase().contains('unauthorized')) {
        throw Exception(
          'Girdiğiniz Bot Token geçersiz veya yetkisiz (Unauthorized).\n'
          'Lütfen Ayarlar sekmesinden geçerli bir Bot Token girin.',
        );
      }
      throw Exception(
        desc.isNotEmpty ? desc : 'Sticker paketi bulunamadı.',
      );
    }
    return TelegramStickerSet.fromJson(data['result']);
  }

  /// Retrieves the download URL for a given file_id.
  Future<String> getFileUrl(String fileId) async {
    if (!hasToken) {
      throw Exception('Bot Token tanımlanmamış.');
    }

    final response = await http
        .get(Uri.parse('$_apiBase/getFile?file_id=$fileId'))
        .timeout(const Duration(seconds: 10));

    final data = jsonDecode(response.body);
    if (data['ok'] != true) {
      throw Exception('Dosya yolu alınamadı: ${data['description'] ?? 'Hata'}');
    }
    final filePath = data['result']['file_path'];
    return 'https://api.telegram.org/file/bot$_botToken/$filePath';
  }

  /// Downloads a sticker file to local storage and returns its path.
  Future<String> downloadSticker(
    TelegramSticker sticker,
    String packName,
  ) async {
    final dir = await getApplicationDocumentsDirectory();
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
    final response = await http
        .get(Uri.parse(url))
        .timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      throw Exception('Sticker indirilemedi (HTTP ${response.statusCode})');
    }

    await file.writeAsBytes(response.bodyBytes);
    return filePath;
  }

  /// Downloads a thumbnail for a sticker (used for previews).
  Future<Uint8List?> downloadThumbnail(String fileId) async {
    try {
      final url = await getFileUrl(fileId);
      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        return response.bodyBytes;
      }
    } catch (_) {}
    return null;
  }
}
