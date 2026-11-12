import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stickerswap/screens/home_screen.dart';
import 'package:stickerswap/services/telegram_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    TelegramService().clearToken();
  });

  testWidgets('HomeScreen shows friendly token onboarding instead of red error when searching without token', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: const HomeScreen(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('İlk Kurulum / Token Ekle'), findsOneWidget);
    expect(find.byIcon(Icons.error_outline_rounded), findsNothing);

    await tester.enterText(
      find.byType(TextField),
      'https://t.me/addstickers/pepethefrog',
    );
    await tester.pump();

    await tester.tap(find.text('Paketi Getir'));
    await tester.pumpAndSettle();

    // Friendly onboarding sheet opens instead of a red error message.
    expect(find.text('Bot Token Alma Rehberi'), findsOneWidget);
    expect(find.byIcon(Icons.error_outline_rounded), findsNothing);

    // Dismiss sheet without saving token -> friendly non-red inline hint appears.
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();

    expect(
      find.text('İlk kurulum için ücretsiz Bot Token eklemeniz gerekir.'),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.error_outline_rounded), findsNothing);
  });
}
