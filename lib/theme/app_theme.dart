import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // ─── Dark Theme Palette (Kurumsal Koyu Slate) ─────────────
  static const Color backgroundDark = Color(0xFF0F172A); // Slate 900
  static const Color surfaceDark = Color(0xFF1E293B); // Slate 800
  static const Color surfaceDarkElevated = Color(0xFF334155); // Slate 700
  static const Color cardDark = Color(0xFF1E293B); // Slate 800

  static const Color textPrimaryDark = Color(0xFFF8FAFC); // Slate 50
  static const Color textSecondaryDark = Color(0xFFCBD5E1); // Slate 300
  static const Color textMutedDark = Color(0xFF94A3B8); // Slate 400

  // ─── Light Theme Palette (Kurumsal Açık Slate) ────────────
  static const Color backgroundLight = Color(0xFFF8FAFC); // Slate 50
  static const Color surfaceLightMode = Color(0xFFFFFFFF); // White
  static const Color surfaceLightMuted = Color(0xFFF1F5F9); // Slate 100
  static const Color cardLight = Color(0xFFFFFFFF); // White

  static const Color textPrimaryLight = Color(0xFF0F172A); // Slate 900
  static const Color textSecondaryLight = Color(0xFF334155); // Slate 700
  static const Color textMutedLight = Color(0xFF64748B); // Slate 500

  // ─── Accent Colors (Dengeli Kurumsal Mavi Tonları) ────────
  static const Color primaryBlue = Color(0xFF2563EB); // Royal Blue
  static const Color lightBlue = Color(0xFF0284C7); // Slate Sky Blue
  static const Color darkBlue = Color(0xFF1D4ED8); // Deep Corporate Blue
  static const Color cyanBlue = Color(0xFF0369A1); // Deep Cyan / Steel Blue

  // Backwards compatibility aliases
  static const Color accentPrimary = primaryBlue;
  static const Color accentSecondary = lightBlue;
  static const Color accentTertiary = cyanBlue;
  static const Color surfaceLight = surfaceDarkElevated;
  static const Color textPrimary = textPrimaryDark;
  static const Color textSecondary = textSecondaryDark;
  static const Color textMuted = textMutedDark;

  // ─── Brand & Semantic (Kurumsal ve Sade) ───────────────────
  static const Color telegramBlue = Color(0xFF0088CC);
  static const Color whatsappGreen = Color(0xFF16A34A); // Corporate Green
  static const Color success = Color(0xFF16A34A);
  static const Color warning = Color(0xFFD97706);
  static const Color error = Color(0xFFDC2626);
  static const Color info = Color(0xFF2563EB);

  // ─── Gradients (Dengeli, Kurumsal Tonlar - Neon Efekti Yok)
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF2563EB), Color(0xFF1D4ED8)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static const LinearGradient telegramGradient = LinearGradient(
    colors: [Color(0xFF0088CC), Color(0xFF0077B5)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static const LinearGradient whatsappGradient = LinearGradient(
    colors: [Color(0xFF16A34A), Color(0xFF15803D)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  // Düz, sade kurumsal kart zeminleri
  static const LinearGradient cardGradient = LinearGradient(
    colors: [cardDark, cardDark],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static const LinearGradient lightCardGradient = LinearGradient(
    colors: [cardLight, cardLight],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  // ─── Border & Radius (Net ve Minimalist) ────────────────────
  static Border darkBorder = Border.all(
    color: const Color(0xFF334155),
    width: 1,
  );

  static Border lightBorder = Border.all(
    color: const Color(0xFFE2E8F0),
    width: 1,
  );

  // Backwards compatibility for glassBorder
  static Border glassBorder = darkBorder;

  static BorderRadius cardRadius = BorderRadius.circular(14);
  static BorderRadius chipRadius = BorderRadius.circular(8);
  static BorderRadius buttonRadius = BorderRadius.circular(10);

  // ─── Shadows (Kurumsal, Minimal Gölgeler - Parlama/Glow Yok)
  static List<BoxShadow> glowShadow(Color color, {double blur = 20}) =>
      const [];

  static List<BoxShadow> lightCardShadow = [
    BoxShadow(
      color: const Color(0xFF0F172A).withAlpha(8),
      blurRadius: 4,
      offset: const Offset(0, 1),
    ),
  ];

  // ─── Context Helpers ───────────────────────────────────────
  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  static Color getBackground(BuildContext context) =>
      isDark(context) ? backgroundDark : backgroundLight;

  static Color getSurface(BuildContext context) =>
      isDark(context) ? surfaceDark : surfaceLightMode;

  static Color getSurfaceMuted(BuildContext context) =>
      isDark(context) ? surfaceDarkElevated : surfaceLightMuted;

  static Color getCardColor(BuildContext context) =>
      isDark(context) ? cardDark : cardLight;

  static Color getText(BuildContext context) =>
      isDark(context) ? textPrimaryDark : textPrimaryLight;

  static Color getTextSec(BuildContext context) =>
      isDark(context) ? textSecondaryDark : textSecondaryLight;

  static Color getTextMut(BuildContext context) =>
      isDark(context) ? textMutedDark : textMutedLight;

  static Border getBorder(BuildContext context) =>
      isDark(context) ? darkBorder : lightBorder;

  static LinearGradient getCardGrad(BuildContext context) =>
      isDark(context) ? cardGradient : lightCardGradient;

  // ─── Dark Theme ThemeData ──────────────────────────────────
  static ThemeData get darkTheme => ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: backgroundDark,
    primaryColor: primaryBlue,
    colorScheme: const ColorScheme.dark(
      primary: primaryBlue,
      secondary: lightBlue,
      surface: surfaceDark,
      error: error,
    ),
    textTheme: GoogleFonts.interTextTheme(
      const TextTheme(
        displayLarge: TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.w800,
          color: textPrimaryDark,
          letterSpacing: -0.5,
        ),
        headlineMedium: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          color: textPrimaryDark,
        ),
        titleLarge: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: textPrimaryDark,
        ),
        titleMedium: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: textPrimaryDark,
        ),
        bodyLarge: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w400,
          color: textSecondaryDark,
        ),
        bodyMedium: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: textSecondaryDark,
        ),
        bodySmall: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w400,
          color: textMutedDark,
        ),
        labelLarge: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: textPrimaryDark,
          letterSpacing: 0.5,
        ),
      ),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
      iconTheme: IconThemeData(color: textPrimaryDark),
      titleTextStyle: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: textPrimaryDark,
      ),
    ),
    cardTheme: CardThemeData(
      color: surfaceDark,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: cardRadius),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: surfaceDark,
      selectedItemColor: lightBlue,
      unselectedItemColor: textMutedDark,
      type: BottomNavigationBarType.fixed,
      elevation: 0,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: surfaceDarkElevated,
      contentTextStyle: const TextStyle(color: textPrimaryDark),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      behavior: SnackBarBehavior.floating,
    ),
  );

  // ─── Light Theme ThemeData ─────────────────────────────────
  static ThemeData get lightTheme => ThemeData(
    brightness: Brightness.light,
    scaffoldBackgroundColor: backgroundLight,
    primaryColor: primaryBlue,
    colorScheme: const ColorScheme.light(
      primary: primaryBlue,
      secondary: cyanBlue,
      surface: surfaceLightMode,
      error: error,
    ),
    textTheme: GoogleFonts.interTextTheme(
      const TextTheme(
        displayLarge: TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.w800,
          color: textPrimaryLight,
          letterSpacing: -0.5,
        ),
        headlineMedium: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          color: textPrimaryLight,
        ),
        titleLarge: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: textPrimaryLight,
        ),
        titleMedium: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: textPrimaryLight,
        ),
        bodyLarge: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w400,
          color: textSecondaryLight,
        ),
        bodyMedium: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: textSecondaryLight,
        ),
        bodySmall: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w400,
          color: textMutedLight,
        ),
        labelLarge: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: textPrimaryLight,
          letterSpacing: 0.5,
        ),
      ),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
      iconTheme: IconThemeData(color: textPrimaryLight),
      titleTextStyle: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: textPrimaryLight,
      ),
    ),
    cardTheme: CardThemeData(
      color: surfaceLightMode,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: cardRadius),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: surfaceLightMode,
      selectedItemColor: primaryBlue,
      unselectedItemColor: textMutedLight,
      type: BottomNavigationBarType.fixed,
      elevation: 2,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: surfaceLightMode,
      contentTextStyle: const TextStyle(color: textPrimaryLight),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      behavior: SnackBarBehavior.floating,
    ),
  );
}
