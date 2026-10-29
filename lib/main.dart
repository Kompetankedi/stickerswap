import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'theme/app_theme.dart';
import 'theme/theme_controller.dart';
import 'screens/main_navigation_screen.dart';

import 'services/storage_service.dart';
import 'services/telegram_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final storage = StorageService();
  await storage.init();

  // Initialize theme mode
  ThemeController.instance.init(storage);

  // Load saved bot token into TelegramService singleton
  final savedToken = storage.getBotToken();
  if (savedToken != null && savedToken.trim().isNotEmpty) {
    TelegramService().setBotToken(savedToken);
  }

  runApp(const StickerSwapApp());
}

class StickerSwapApp extends StatelessWidget {
  const StickerSwapApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeController.instance,
      builder: (context, _) {
        final isDark = ThemeController.instance.isDarkMode;
        SystemChrome.setSystemUIOverlayStyle(
          SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
            systemNavigationBarColor:
                isDark ? AppTheme.backgroundDark : AppTheme.backgroundLight,
            systemNavigationBarIconBrightness:
                isDark ? Brightness.light : Brightness.dark,
          ),
        );

        return MaterialApp(
          title: 'StickerSwap',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: ThemeController.instance.themeMode,
          home: const MainNavigationScreen(),
        );
      },
    );
  }
}
