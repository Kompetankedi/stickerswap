import 'dart:io';
import 'package:characters/characters.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

enum WhatsAppExportStatus {
  added,
  cancelled,
  error,
}

class WhatsAppExportResult {
  final WhatsAppExportStatus status;
  final String? errorMessage;

  const WhatsAppExportResult({
    required this.status,
    this.errorMessage,
  });

  bool get isAdded => status == WhatsAppExportStatus.added;
  bool get isCancelled => status == WhatsAppExportStatus.cancelled;
  bool get isError => status == WhatsAppExportStatus.error;
}

/// Handles adding sticker packs to WhatsApp through the official
/// WhatsApp Stickers third-party API / Content Provider mechanism.
class WhatsAppService {
  static const MethodChannel _channel = MethodChannel('com.example.stickerswap/whatsapp');

  static String _sanitizeCore(String input) {
    const trMap = {
      'ç': 'c', 'Ç': 'C',
      'ğ': 'g', 'Ğ': 'G',
      'ı': 'i', 'I': 'I', 'İ': 'I',
      'ö': 'o', 'Ö': 'O',
      'ş': 's', 'Ş': 'S',
      'ü': 'u', 'Ü': 'U',
    };
    var result = input;
    trMap.forEach((k, v) => result = result.replaceAll(k, v));

    // Convert '::' or '@' into dash or spaces
    result = result.replaceAll('::', ' - ');
    result = result.replaceAll('@', ' ');

    // Keep strictly ASCII letters, digits, underscore, hyphen, dot, comma, apostrophe, and space
    result = result.replaceAll(RegExp(r"[^a-zA-Z0-9_\-.,'\s]"), ' ');

    // Remove multiple dots '..' which triggers !string.contains("..") in validator
    while (result.contains('..')) {
      result = result.replaceAll('..', '.');
    }

    // Collapse whitespace
    return result.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Sanitizes text to strictly match Android WhatsApp Stickers Validator:
  /// Pattern: [\\w-.,'\\s]+ (ASCII word chars, dash, dot, comma, apostrophe, space)
  /// Length: 1 - 128 characters, and must NOT contain double dots '..'
  static String sanitizeForWhatsApp(String input, {String fallback = 'Stickers'}) {
    var result = _sanitizeCore(input);

    if (result.isEmpty) result = fallback;
    if (result.length > 120) result = result.substring(0, 120).trim();
    return result;
  }

  /// Builds a WhatsApp-compliant sticker pack name from an optional [customName]
  /// and [defaultTitle], preserving `Part X` suffixes within the 120-character cap.
  static String buildPackName({
    String? customName,
    required String defaultTitle,
    int partIndex = 0,
    int totalParts = 1,
  }) {
    final safeTotalParts = totalParts < 1 ? 1 : totalParts;
    final safePartIndex = partIndex < 0 ? 0 : partIndex;
    final partSuffix =
        safeTotalParts > 1 ? ' Part ${safePartIndex + 1}' : '';
    final fallbackName = safeTotalParts > 1
        ? 'Sticker Pack ${safePartIndex + 1}'
        : 'Sticker Pack';

    var sanitizedBase = customName != null ? _sanitizeCore(customName) : '';
    if (sanitizedBase.isEmpty) {
      sanitizedBase = _sanitizeCore(defaultTitle);
    }
    if (sanitizedBase.isEmpty) {
      return sanitizeForWhatsApp(fallbackName, fallback: 'Sticker Pack');
    }

    if (partSuffix.isEmpty) {
      return sanitizeForWhatsApp(sanitizedBase, fallback: fallbackName);
    }

    final maxBaseLength = (120 - partSuffix.length).clamp(1, 120);
    final trimmedBase = sanitizedBase.length > maxBaseLength
        ? sanitizedBase.substring(0, maxBaseLength).trimRight()
        : sanitizedBase;
    if (trimmedBase.isEmpty) {
      return sanitizeForWhatsApp(fallbackName, fallback: 'Sticker Pack');
    }

    return sanitizeForWhatsApp('$trimmedBase$partSuffix', fallback: fallbackName);
  }

  /// Sanitizes pack identifier to safe ASCII word/hyphen characters only.
  static String sanitizeIdentifier(String input) {
    var result = input.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
    result = result.replaceAll(RegExp(r'_{2,}'), '_').trim();
    if (result.isEmpty || !RegExp(r'^[a-zA-Z0-9_\-]+$').hasMatch(result)) {
      result = 'pack_${DateTime.now().millisecondsSinceEpoch}';
    }
    if (result.length > 64) result = result.substring(0, 64);
    return result;
  }

  /// Builds a cache-busting WhatsApp pack identifier with a trailing unix timestamp.
  static String buildVersionedIdentifier(
    String baseIdentifier, {
    int? epochSeconds,
  }) {
    final sanitized = sanitizeIdentifier(baseIdentifier)
        .replaceAll(RegExp(r'_[0-9]{10,}$'), '');
    final ts = epochSeconds ?? (DateTime.now().millisecondsSinceEpoch ~/ 1000);
    final suffix = '_$ts';
    final maxBaseLen = (64 - suffix.length).clamp(1, 64);
    final trimmedBase = sanitized.length > maxBaseLen
        ? sanitized.substring(0, maxBaseLen)
        : sanitized;
    return sanitizeIdentifier('$trimmedBase$suffix');
  }

  /// Sanitizes raw emoji text into a list of 1 to 3 valid Unicode emojis.
  /// Standard WhatsApp Stickers Validator rule:
  /// - Each sticker must have at least 1 and at most 3 emojis.
  /// - Empty or invalid emojis cause WhatsApp to reject the sticker pack.
  /// - If no valid emojis found, safely falls back to ['⭐'].
  static List<String> sanitizeEmojis(String? rawEmoji) {
    if (rawEmoji == null || rawEmoji.trim().isEmpty) {
      return const ['⭐'];
    }

    final emojis = <String>[];
    for (final char in rawEmoji.characters) {
      final isEmoji = char.runes.any((rune) {
        return (rune >= 0x1F300 && rune <= 0x1FAFF) ||
            (rune >= 0x2600 && rune <= 0x27BF) ||
            (rune >= 0x2300 && rune <= 0x23FF) ||
            (rune >= 0x2B50 && rune <= 0x2B55) ||
            (rune >= 0x1F1E6 && rune <= 0x1F1FF) ||
            rune == 0x203C ||
            rune == 0x2049 ||
            rune == 0x00A9 ||
            rune == 0x00AE;
      });

      if (isEmoji && char.trim().isNotEmpty) {
        emojis.add(char);
      }
      if (emojis.length == 3) break;
    }

    if (emojis.isEmpty) {
      return const ['⭐'];
    }
    return emojis;
  }

  /// Sends a processed sticker pack to WhatsApp.
  ///
  /// [identifier] – unique pack identifier (e.g., "pack_name_part1")
  /// [name]       – display name of the pack
  /// [publisher]  – publisher / author name
  /// [trayPath]   – absolute path to 96x96 PNG tray icon
  /// [stickerData]– list of maps with 'path' and 'emojis' keys
  Future<WhatsAppExportResult> addStickerPack({
    required String identifier,
    required String name,
    required String publisher,
    required String trayPath,
    required List<Map<String, dynamic>> stickerData,
    bool animatedStickerPack = false,
  }) async {
    // 1. Pack size limits (WhatsApp requires 3 to 30 stickers)
    if (stickerData.length < 3) {
      throw Exception(
        'WhatsApp en az 3 çıkartma gerektirir. '
        'Pakette sadece ${stickerData.length} adet var.',
      );
    }
    if (stickerData.length > 30) {
      throw Exception(
        'WhatsApp tek pakette en fazla 30 çıkartmaya izin verir. '
        'Paket parçalara ayrılmalıdır.',
      );
    }

    // 2. Tray icon validation (must exist and be <= 48 KB, strictly under WhatsApp 50 KB ceiling)
    final trayFile = File(trayPath);
    if (!await trayFile.exists()) {
      throw Exception('Tepsi simgesi (tray icon) bulunamadı: $trayPath');
    }
    final traySize = await trayFile.length();
    if (traySize > 48 * 1024) {
      throw Exception(
        'Tepsi simgesi boyutu WhatsApp 50 KB sınırını aşıyor: '
        '${(traySize / 1024).toStringAsFixed(1)} KB.',
      );
    }

    // 3. Sticker files and emojis pre-validation (Strict WhatsApp compliance: <= 470 KB animated, <= 96 KB static)
    final maxAllowedBytes = animatedStickerPack ? 470 * 1024 : 96 * 1024;
    final sanitizedStickers = <Map<String, dynamic>>[];

    for (int i = 0; i < stickerData.length; i++) {
      final item = stickerData[i];
      final path = item['path'] as String?;
      if (path == null || path.isEmpty) {
        throw Exception('${i + 1}. çıkartma dosya yolu belirtilmemiş.');
      }
      final file = File(path);
      if (!await file.exists()) {
        throw Exception('${i + 1}. çıkartma dosyası bulunamadı: $path');
      }
      final size = await file.length();
      if (size == 0) {
        throw Exception('${i + 1}. çıkartma dosyası boş (0 bayt): $path');
      }
      if (size > maxAllowedBytes) {
        final limitKb = animatedStickerPack ? 470 : 96;
        final actualKb = (size / 1024).toStringAsFixed(1);
        throw Exception(
          '${i + 1}. çıkartma boyutu ($actualKb KB) '
          'WhatsApp $limitKb KB sınırını aşıyor: ${p.basename(path)}',
        );
      }

      // Sanitize emojis to ensure exactly 1 to 3 valid Unicode emojis
      final rawEmojis = item['emojis'];
      final emojisList = <String>[];
      if (rawEmojis is List) {
        for (final e in rawEmojis) {
          if (e != null) {
            emojisList.addAll(sanitizeEmojis(e.toString()));
          }
        }
      } else if (rawEmojis is String) {
        emojisList.addAll(sanitizeEmojis(rawEmojis));
      }
      final safeEmojis = emojisList.isEmpty
          ? const ['⭐']
          : (emojisList.length > 3 ? emojisList.take(3).toList() : emojisList);

      sanitizedStickers.add({
        'path': path,
        'emojis': safeEmojis,
      });
    }

    // 4. Sanitize pack identifier and metadata strings
    final safeIdentifier = sanitizeIdentifier(identifier);
    final safeName = sanitizeForWhatsApp(name, fallback: 'Sticker Pack');
    final safePublisher = sanitizeForWhatsApp(publisher, fallback: 'StickerSwap');

    final payload = {
      'identifier': safeIdentifier,
      'name': safeName,
      'publisher': safePublisher,
      'trayImage': trayPath,
      'stickers': sanitizedStickers,
      'animatedStickerPack': animatedStickerPack,
    };

    try {
      final res = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'addStickerPack',
        payload,
      );

      final statusStr = res?['status'] as String? ?? 'unknown';
      if (statusStr == 'added') {
        return const WhatsAppExportResult(status: WhatsAppExportStatus.added);
      } else if (statusStr == 'cancelled') {
        return const WhatsAppExportResult(status: WhatsAppExportStatus.cancelled);
      } else {
        var errorMsg = res?['error'] as String? ?? 'Bilinmeyen aktarım hatası';
        if (errorMsg.contains('handleStickerPackPreviewResult') ||
            errorMsg.contains('validation_error')) {
          errorMsg =
              'WhatsApp çıkartma paketini doğrulayamadı (handleStickerPackPreviewResult). '
              'Lütfen WhatsApp sürümünün güncel olduğundan emin olun.';
        }
        return WhatsAppExportResult(
          status: WhatsAppExportStatus.error,
          errorMessage: errorMsg,
        );
      }
    } on PlatformException catch (e) {
      var msg = e.message ?? e.code;
      if (msg.contains('handleStickerPackPreviewResult')) {
        msg = 'WhatsApp doğrulama hatası (handleStickerPackPreviewResult).';
      }
      return WhatsAppExportResult(
        status: WhatsAppExportStatus.error,
        errorMessage: msg,
      );
    } catch (e) {
      return WhatsAppExportResult(
        status: WhatsAppExportStatus.error,
        errorMessage: e.toString().replaceAll('Exception: ', '').trim(),
      );
    }
  }

  /// Deletes a sticker pack from native StickerContentProvider storage.
  Future<bool> deleteStickerPack(String identifier) async {
    try {
      final result = await _channel.invokeMethod<bool>(
        'deleteStickerPack',
        {'identifier': sanitizeIdentifier(identifier)},
      );
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Checks whether WhatsApp is installed on the device.
  Future<bool> isWhatsAppInstalled() async {
    try {
      final result = await _channel.invokeMethod<bool>('isWhatsAppInstalled');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Checks whether a specific pack is already installed.
  Future<bool> isPackInstalled(String identifier) async {
    try {
      final result = await _channel.invokeMethod<bool>(
        'isPackInstalled',
        {'identifier': sanitizeIdentifier(identifier)},
      );
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Splits a large pack into WhatsApp-compliant sub-packs (max 30 stickers each).
  List<List<T>> splitIntoPacks<T>(List<T> items, {int maxPerPack = 30}) {
    final packs = <List<T>>[];
    for (var i = 0; i < items.length; i += maxPerPack) {
      final end = (i + maxPerPack > items.length) ? items.length : i + maxPerPack;
      packs.add(items.sublist(i, end));
    }
    return packs;
  }
}
