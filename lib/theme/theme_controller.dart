import 'package:flutter/material.dart';
import '../services/storage_service.dart';

class ThemeController extends ChangeNotifier {
  static final ThemeController instance = ThemeController._();
  ThemeController._();

  ThemeMode _themeMode = ThemeMode.dark;
  ThemeMode get themeMode => _themeMode;
  bool get isDarkMode => _themeMode == ThemeMode.dark;

  void init(StorageService storage) {
    final saved = storage.getThemeMode();
    if (saved == 'light') {
      _themeMode = ThemeMode.light;
    } else {
      _themeMode = ThemeMode.dark;
    }
    notifyListeners();
  }

  Future<void> toggleTheme(StorageService storage) async {
    if (_themeMode == ThemeMode.dark) {
      _themeMode = ThemeMode.light;
      await storage.setThemeMode('light');
    } else {
      _themeMode = ThemeMode.dark;
      await storage.setThemeMode('dark');
    }
    notifyListeners();
  }

  Future<void> setTheme(ThemeMode mode, StorageService storage) async {
    _themeMode = mode;
    await storage.setThemeMode(mode == ThemeMode.light ? 'light' : 'dark');
    notifyListeners();
  }
}
