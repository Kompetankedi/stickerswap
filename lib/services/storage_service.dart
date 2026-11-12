import 'dart:io';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/saved_pack.dart';
import 'whatsapp_service.dart';

/// Manages local persistent storage using SharedPreferences, secure storage, and file system.
/// Stores bot token securely, publisher name, saved sticker packs, recent packs, and cache.
class StorageService {
  static const String _keyBotToken = 'bot_token';
  static const String _keyPublisher = 'publisher_name';
  static const String _keySavedPacks = 'saved_packs';
  static const String _keyRecentPacks = 'recent_packs';
  static const String _keyTargetApp = 'target_whatsapp_app';
  static const String _keyThemeMode = 'app_theme_mode';

  final FlutterSecureStorage _secureStorage;
  late SharedPreferences _prefs;

  StorageService({FlutterSecureStorage? secureStorage})
      : _secureStorage = secureStorage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  // ─── Theme Mode ───────────────────────────────────────────
  // 'dark' (default) or 'light'
  String getThemeMode() => _prefs.getString(_keyThemeMode) ?? 'dark';

  Future<void> setThemeMode(String mode) async {
    await _prefs.setString(_keyThemeMode, mode);
  }

  // ─── Bot Token ────────────────────────────────────────────
  Future<String?> getBotToken() async {
    final token = await _secureStorage.read(key: _keyBotToken);
    if (token != null && token.trim().isNotEmpty) {
      if (_prefs.containsKey(_keyBotToken)) {
        await _prefs.remove(_keyBotToken);
      }
      return token;
    }

    final legacyToken = _prefs.getString(_keyBotToken);
    if (legacyToken != null && legacyToken.trim().isNotEmpty) {
      final trimmed = legacyToken.trim();
      await _secureStorage.write(key: _keyBotToken, value: trimmed);
      await _prefs.remove(_keyBotToken);
      return trimmed;
    }

    return null;
  }

  Future<void> setBotToken(String token) async {
    await _secureStorage.write(key: _keyBotToken, value: token.trim());
    await _prefs.remove(_keyBotToken);
  }

  Future<void> clearBotToken() async {
    await _secureStorage.delete(key: _keyBotToken);
    await _prefs.remove(_keyBotToken);
  }

  // ─── Publisher Name ───────────────────────────────────────
  String getPublisherName() =>
      _prefs.getString(_keyPublisher) ?? 'StickerSwap';

  Future<void> setPublisherName(String name) async {
    await _prefs.setString(_keyPublisher, name);
  }

  // ─── Target WhatsApp App ─────────────────────────────────
  // 'whatsapp' (default) or 'whatsapp_smb' (Business)
  String getTargetWhatsApp() =>
      _prefs.getString(_keyTargetApp) ?? 'whatsapp';

  Future<void> setTargetWhatsApp(String appType) async {
    await _prefs.setString(_keyTargetApp, appType);
  }

  // ─── Recent Packs ────────────────────────────────────────
  List<String> getRecentPacks() {
    return _prefs.getStringList(_keyRecentPacks) ?? [];
  }

  Future<void> addRecentPack(String packName) async {
    final list = getRecentPacks().toList();
    list.removeWhere((item) => item.toLowerCase() == packName.toLowerCase());
    list.insert(0, packName);
    if (list.length > 10) {
      list.removeRange(10, list.length);
    }
    await _prefs.setStringList(_keyRecentPacks, list);
  }

  Future<void> clearRecentPacks() async {
    await _prefs.remove(_keyRecentPacks);
  }

  // ─── Saved Packs ─────────────────────────────────────────
  List<SavedPack> getSavedPacks() {
    final list = _prefs.getStringList(_keySavedPacks) ?? [];
    return list.map((s) => SavedPack.fromJsonString(s)).toList();
  }

  Future<void> savePack(SavedPack pack) async {
    final packs = getSavedPacks();
    // Remove existing pack with same identifier
    packs.removeWhere((p) => p.identifier == pack.identifier);
    packs.insert(0, pack);
    await _prefs.setStringList(
      _keySavedPacks,
      packs.map((p) => p.toJsonString()).toList(),
    );
  }

  Future<void> removePack(String identifier) async {
    final packs = getSavedPacks();
    packs.removeWhere((p) => p.identifier == identifier);
    await _prefs.setStringList(
      _keySavedPacks,
      packs.map((p) => p.toJsonString()).toList(),
    );

    // Safely remove file directory only if no remaining pack uses it
    try {
      final remainingPacks = getSavedPacks();
      final baseName = identifier.replaceAll(RegExp(r'_part\d+.*$'), '');
      final isUsedByOthers = remainingPacks.any((p) {
        final pBase = p.identifier.replaceAll(RegExp(r'_part\d+.*$'), '');
        return p.identifier == identifier || pBase == baseName;
      });

      if (!isUsedByOthers) {
        final dir = await getApplicationDocumentsDirectory();
        final packDir = Directory(p.join(dir.path, 'whatsapp_packs', identifier));
        if (await packDir.exists()) {
          await packDir.delete(recursive: true);
        }
        if (baseName != identifier) {
          final baseDir = Directory(p.join(dir.path, 'whatsapp_packs', baseName));
          if (await baseDir.exists()) {
            await baseDir.delete(recursive: true);
          }
        }
      }
    } catch (_) {}
  }

  Future<void> updatePackStatus(String identifier, bool addedToWhatsApp) async {
    final packs = getSavedPacks();
    for (final pack in packs) {
      if (pack.identifier == identifier) {
        pack.addedToWhatsApp = addedToWhatsApp;
        break;
      }
    }
    await _prefs.setStringList(
      _keySavedPacks,
      packs.map((p) => p.toJsonString()).toList(),
    );
  }

  /// Updates the display name of a saved pack after applying WhatsApp sanitization.
  /// Returns the updated [SavedPack], or `null` if [identifier] is not found.
  Future<SavedPack?> updatePackName(String identifier, String newName) async {
    final packs = getSavedPacks();
    final index = packs.indexWhere((p) => p.identifier == identifier);
    if (index == -1) return null;

    final existing = packs[index];
    final safeName = WhatsAppService.buildPackName(
      customName: newName,
      defaultTitle: existing.name,
    );
    final updated = existing.copyWith(name: safeName);
    packs[index] = updated;

    await _prefs.setStringList(
      _keySavedPacks,
      packs.map((p) => p.toJsonString()).toList(),
    );
    return updated;
  }

  // ─── Cache Management ────────────────────────────────────
  /// Calculates total bytes used by downloaded and processed stickers.
  Future<int> getCacheSizeBytes() async {
    int total = 0;
    try {
      final docDir = await getApplicationDocumentsDirectory();
      final stickersDir = Directory(p.join(docDir.path, 'stickers'));
      final waDir = Directory(p.join(docDir.path, 'whatsapp_packs'));

      if (await stickersDir.exists()) {
        await for (final file in stickersDir.list(recursive: true, followLinks: false)) {
          if (file is File) total += await file.length();
        }
      }
      if (await waDir.exists()) {
        await for (final file in waDir.list(recursive: true, followLinks: false)) {
          if (file is File) total += await file.length();
        }
      }
    } catch (_) {}
    return total;
  }

  /// Formats byte count to human-readable string (e.g. "3.5 MB").
  static String formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  /// Clears downloaded source stickers and temp files.
  Future<void> clearCache() async {
    try {
      final docDir = await getApplicationDocumentsDirectory();
      final stickersDir = Directory(p.join(docDir.path, 'stickers'));
      if (await stickersDir.exists()) {
        await stickersDir.delete(recursive: true);
      }
    } catch (_) {}
  }
}
