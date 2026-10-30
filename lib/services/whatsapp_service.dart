import 'package:flutter/services.dart';

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

  /// Sanitizes text to strictly match Android WhatsApp Stickers Validator:
  /// Pattern: [\\w-.,'\\s]+ (ASCII word chars, dash, dot, comma, apostrophe, space)
  /// Length: 1 - 128 characters, and must NOT contain double dots '..'
  static String sanitizeForWhatsApp(String input, {String fallback = 'Stickers'}) {
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
    result = result.replaceAll(RegExp(r'\s+'), ' ').trim();

    if (result.isEmpty) result = fallback;
    if (result.length > 120) result = result.substring(0, 120).trim();
    return result;
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
    // Minimum 3 stickers required by WhatsApp
    if (stickerData.length < 3) {
      throw Exception(
        'WhatsApp en az 3 çıkartma gerektirir. '
        'Pakette sadece ${stickerData.length} adet var.',
      );
    }

    // Maximum 30 stickers per WhatsApp pack
    if (stickerData.length > 30) {
      throw Exception(
        'WhatsApp tek pakette en fazla 30 çıkartmaya izin verir. '
        'Paket parçalara ayrılmalıdır.',
      );
    }

    // Sanitize strings to avoid Android StickerPackValidator rejection
    final safeIdentifier = sanitizeIdentifier(identifier);
    final safeName = sanitizeForWhatsApp(name, fallback: 'Sticker Pack');
    final safePublisher = sanitizeForWhatsApp(publisher, fallback: 'StickerSwap');

    final payload = {
      'identifier': safeIdentifier,
      'name': safeName,
      'publisher': safePublisher,
      'trayImage': trayPath,
      'stickers': stickerData,
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
        final errorMsg = res?['error'] as String? ?? 'Bilinmeyen aktarım hatası';
        return WhatsAppExportResult(
          status: WhatsAppExportStatus.error,
          errorMessage: errorMsg,
        );
      }
    } on PlatformException catch (e) {
      return WhatsAppExportResult(
        status: WhatsAppExportStatus.error,
        errorMessage: e.message ?? e.code,
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
