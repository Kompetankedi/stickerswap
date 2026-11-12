import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stickerswap/screens/settings_screen.dart';
import 'package:stickerswap/services/whatsapp_service.dart';
import 'package:stickerswap/widgets/ios_unsupported_dialog.dart';

void main() {
  test('WhatsAppService returns unsupportedPlatform safely on iOS', () async {
    final iosService = WhatsAppService(isIosOverride: () => true);

    expect(iosService.isExportUnsupportedPlatform, isTrue);

    final result = await iosService.addStickerPack(
      identifier: 'sample_pack',
      name: 'Sample Pack',
      publisher: 'StickerSwap',
      trayPath: '/nonexistent/tray.png',
      stickerData: const [
        {'path': '/nonexistent/1.webp', 'emojis': ['⭐']},
        {'path': '/nonexistent/2.webp', 'emojis': ['⭐']},
        {'path': '/nonexistent/3.webp', 'emojis': ['⭐']},
      ],
    );

    expect(result.isUnsupportedPlatform, isTrue);
    expect(result.status, WhatsAppExportStatus.unsupportedPlatform);
    expect(result.errorMessage, WhatsAppService.iosUnsupportedMessage);
  });

  testWidgets('guardUnsupportedIosExport displays informational dialog on iOS',
      (tester) async {
    final iosService = WhatsAppService(isIosOverride: () => true);
    bool? blocked;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () async {
                blocked = await guardUnsupportedIosExport(context, iosService);
              },
              child: const Text('Aktar'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Aktar'));
    await tester.pumpAndSettle();

    expect(find.text('Yalnızca Android Desteklenir'), findsOneWidget);
    expect(find.text(WhatsAppService.iosUnsupportedMessage), findsOneWidget);

    await tester.tap(find.text('Anladım'));
    await tester.pumpAndSettle();

    expect(blocked, isTrue);
  });

  testWidgets('SettingsScreen renders legal disclaimer and copyright notice',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SettingsScreen(),
      ),
    );

    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));

    await tester.ensureVisible(find.text('Yasal Uyarı & Sorumluluk Reddi'));
    await tester.pump();

    expect(find.text('Yasal Uyarı & Sorumluluk Reddi'), findsOneWidget);
    expect(find.text('Bağımsız Araç Bildirimi'), findsOneWidget);
    expect(find.text('Telif Hakları & Kullanım Sorumluluğu'), findsOneWidget);
  });
}
