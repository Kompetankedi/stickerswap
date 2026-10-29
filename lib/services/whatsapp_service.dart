import 'package:whatsapp_stickers_handler/whatsapp_stickers_handler.dart';
import 'package:whatsapp_stickers_handler/model/sticker_pack.dart';

/// Handles adding sticker packs to WhatsApp through the official
/// WhatsApp Stickers third-party API / Content Provider mechanism.
class WhatsAppService {
  final WhatsappStickersHandler _handler = WhatsappStickersHandler();

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
  Future<bool> addStickerPack({
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

    final stickers = stickerData.map((d) => d['path'] as String).toList();

    // Sanitize strings to avoid Android StickerPackValidator rejection
    final safeIdentifier = sanitizeIdentifier(identifier);
    final safeName = sanitizeForWhatsApp(name, fallback: 'Sticker Pack');
    final safePublisher = sanitizeForWhatsApp(publisher, fallback: 'StickerSwap');

    final pack = StickerPack(
      identifier: safeIdentifier,
      name: safeName,
      publisher: safePublisher,
      trayImage: trayPath,
      stickers: stickers,
      animatedStickerPack: animatedStickerPack,
    );

    try {
      await _handler.addStickerPack(pack);
      return true;
    } catch (e) {
      final msg = e.toString().replaceAll('Exception: ', '').trim();
      throw Exception('WhatsApp aktarım hatası: $msg');
    }
  }

  /// Checks whether WhatsApp is installed on the device.
  Future<bool> isWhatsAppInstalled() async {
    try {
      return await _handler.isWhatsAppInstalled;
    } catch (_) {
      return false;
    }
  }

  /// Checks whether a specific pack is already installed.
  Future<bool> isPackInstalled(String identifier) async {
    try {
      return await _handler.isStickerPackInstalled(sanitizeIdentifier(identifier));
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
