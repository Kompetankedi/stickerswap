import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/saved_pack.dart';

/// Manages local persistent storage using SharedPreferences and file system.
/// Stores bot token, publisher name, saved sticker packs, recent packs, and cache.
class StorageService {
  static const String _keyBotToken = 'bot_token';
  static const String _keyPublisher = 'publisher_name';
  static const String _keySavedPacks = 'saved_packs';
  static const String _keyRecentPacks = 'recent_packs';
  static const String _keyTargetApp = 'target_whatsapp_app';
  static const String _keyThemeMode = 'app_theme_mode';

  late SharedPreferences _prefs;

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
  String? getBotToken() => _prefs.getString(_keyBotToken);

  Future<void> setBotToken(String token) async {
    await _prefs.setString(_keyBotToken, token);
  }

  Future<void> clearBotToken() async {
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

    // Also remove file directory if exists
    try {
      final dir = await getApplicationDocumentsDirectory();
      final packDir = Directory(p.join(dir.path, 'whatsapp_packs', identifier));
      if (await packDir.exists()) {
        await packDir.delete(recursive: true);
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
