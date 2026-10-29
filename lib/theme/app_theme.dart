import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // ─── Dark Theme Palette (Siyah / Mavi tonları) ─────────────
  static const Color backgroundDark = Color(0xFF090D16);
  static const Color surfaceDark = Color(0xFF111827);
  static const Color surfaceDarkElevated = Color(0xFF1E293B);
  static const Color cardDark = Color(0xFF151E32);

  static const Color textPrimaryDark = Color(0xFFF8FAFC);
  static const Color textSecondaryDark = Color(0xFF94A3B8);
  static const Color textMutedDark = Color(0xFF64748B);

  // ─── Light Theme Palette (Beyaz / Mavi tonları) ────────────
  static const Color backgroundLight = Color(0xFFF8FAFC);
  static const Color surfaceLightMode = Color(0xFFFFFFFF);
  static const Color surfaceLightMuted = Color(0xFFF1F5F9);
  static const Color cardLight = Color(0xFFFFFFFF);

  static const Color textPrimaryLight = Color(0xFF0F172A);
  static const Color textSecondaryLight = Color(0xFF475569);
  static const Color textMutedLight = Color(0xFF94A3B8);

  // ─── Accent Colors (Mavi Tonları) ──────────────────────────
  static const Color primaryBlue = Color(0xFF2563EB); // Royal Blue
  static const Color lightBlue = Color(0xFF38BDF8);   // Sky Blue
  static const Color darkBlue = Color(0xFF1D4ED8);    // Deep Blue
  static const Color cyanBlue = Color(0xFF0EA5E9);    // Vivid Cyan Blue

  // Backwards compatibility aliases
  static const Color accentPrimary = primaryBlue;
  static const Color accentSecondary = lightBlue;
  static const Color accentTertiary = cyanBlue;
  static const Color surfaceLight = surfaceDarkElevated;
  static const Color textPrimary = textPrimaryDark;
  static const Color textSecondary = textSecondaryDark;
  static const Color textMuted = textMutedDark;

  // ─── Brand & Semantic ──────────────────────────────────────
  static const Color telegramBlue = Color(0xFF0088CC);
  static const Color whatsappGreen = Color(0xFF25D366);
  static const Color success = Color(0xFF10B981);
  static const Color warning = Color(0xFFF59E0B);
  static const Color error = Color(0xFFEF4444);
  static const Color info = Color(0xFF3B82F6);

  // ─── Gradients ─────────────────────────────────────────────
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [primaryBlue, cyanBlue],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient telegramGradient = LinearGradient(
    colors: [Color(0xFF0088CC), Color(0xFF00D4FF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient whatsappGradient = LinearGradient(
    colors: [Color(0xFF25D366), Color(0xFF128C7E)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient cardGradient = LinearGradient(
    colors: [Color(0xFF151E32), Color(0xFF0F172A)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static const LinearGradient lightCardGradient = LinearGradient(
    colors: [Color(0xFFFFFFFF), Color(0xFFF8FAFC)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  // ─── Border & Radius ───────────────────────────────────────
  static Border glassBorder = Border.all(
    color: Colors.white.withAlpha(20),
    width: 1,
  );

  static Border lightBorder = Border.all(
    color: const Color(0xFFE2E8F0),
    width: 1,
  );

  static BorderRadius cardRadius = BorderRadius.circular(20);
  static BorderRadius chipRadius = BorderRadius.circular(12);
  static BorderRadius buttonRadius = BorderRadius.circular(16);

  // ─── Shadows ───────────────────────────────────────────────
  static List<BoxShadow> glowShadow(Color color, {double blur = 20}) => [
        BoxShadow(
          color: color.withAlpha(50),
          blurRadius: blur,
          spreadRadius: 0,
        ),
      ];

  static List<BoxShadow> lightCardShadow = [
    BoxShadow(
      color: const Color(0xFF0F172A).withAlpha(15),
      blurRadius: 16,
      offset: const Offset(0, 4),
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

  static Color getText(BuildContext context) =>
      isDark(context) ? textPrimaryDark : textPrimaryLight;

  static Color getTextSec(BuildContext context) =>
      isDark(context) ? textSecondaryDark : textSecondaryLight;

  static Color getTextMut(BuildContext context) =>
      isDark(context) ? textMutedDark : textMutedLight;

  static Border getBorder(BuildContext context) =>
      isDark(context) ? glassBorder : lightBorder;

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
