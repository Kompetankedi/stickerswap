import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stickerswap/models/saved_pack.dart';
import 'package:stickerswap/models/telegram_sticker.dart';
import 'package:stickerswap/models/telegram_sticker_set.dart';
import 'package:stickerswap/screens/my_packs_screen.dart';
import 'package:stickerswap/screens/pack_preview_screen.dart';
import 'package:stickerswap/services/storage_service.dart';
import 'package:stickerswap/services/whatsapp_service.dart';
import 'package:stickerswap/widgets/installed_pack_cache_dialog.dart';
import 'package:stickerswap/widgets/pack_metadata_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  group('SavedPack & StorageService.updatePackName Tests', () {
    test('SavedPack.copyWith updates name and preserves other fields', () {
      final original = SavedPack(
        identifier: 'karimm_pack',
        name: 'Karimm',
        publisher: 'StickerSwap',
        trayImagePath: '/tmp/tray.png',
        stickerPaths: ['/tmp/1.webp', '/tmp/2.webp', '/tmp/3.webp'],
        emojis: ['🐱', '😂', '⭐'],
        stickerCount: 3,
        savedAt: DateTime(2026, 11, 11),
        isAnimated: true,
        addedToWhatsApp: true,
      );

      final updated = original.copyWith(name: 'Yeni Karimm');
      expect(updated.identifier, 'karimm_pack');
      expect(updated.name, 'Yeni Karimm');
      expect(updated.publisher, 'StickerSwap');
      expect(updated.stickerPaths, ['/tmp/1.webp', '/tmp/2.webp', '/tmp/3.webp']);
      expect(updated.isAnimated, isTrue);
      expect(updated.addedToWhatsApp, isTrue);
    });

    test('StorageService.updatePackName sanitizes and persists renamed pack', () async {
      SharedPreferences.setMockInitialValues({});
      final storage = StorageService();
      await storage.init();

      await storage.savePack(
        SavedPack(
          identifier: 'test_pack_1',
          name: 'Original Title',
          publisher: 'StickerSwap',
          trayImagePath: 'tray.png',
          stickerPaths: ['1.webp', '2.webp', '3.webp'],
          emojis: ['⭐', '⭐', '⭐'],
          stickerCount: 3,
          savedAt: DateTime(2026, 11, 11),
          addedToWhatsApp: true,
        ),
      );

      final renamed = await storage.updatePackName(
        'test_pack_1',
        'Şahane Kediler 🐱',
      );
      expect(renamed, isNotNull);
      expect(renamed!.name, 'Sahane Kediler');
      expect(renamed.addedToWhatsApp, isTrue);

      final persisted = storage.getSavedPacks();
      expect(persisted.length, 1);
      expect(persisted.first.name, 'Sahane Kediler');

      // Blank or symbol-only input keeps existing pack name instead of wiping it
      final blankFallback = await storage.updatePackName('test_pack_1', '  🔥  ');
      expect(blankFallback!.name, 'Sahane Kediler');

      // Unknown identifier returns null
      final missing = await storage.updatePackName('does_not_exist', 'New Name');
      expect(missing, isNull);
    });
  });

  group('PackMetadataDialog Widget Tests', () {
    testWidgets('pre-fills title, shows sanitized multi-part preview, and resets', (
      tester,
    ) async {
      PackMetadataEditResult? result;

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  result = await showPackMetadataDialog(
                    context: context,
                    defaultTitle: 'Telegram Orjinal',
                    initialPackName: 'Telegram Orjinal',
                    totalParts: 2,
                    showPublisherField: true,
                    defaultPublisher: 'StickerSwap',
                    initialPublisher: 'StickerSwap',
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Paket Bilgilerini Düzenle'), findsOneWidget);
      expect(find.text('Telegram Orjinal Part 1'), findsOneWidget);

      final fields = find.byType(TextField);
      expect(fields, findsNWidgets(2));

      await tester.enterText(fields.at(0), 'Özel Paket 🔥');
      await tester.enterText(fields.at(1), 'Benim Yayıncım');
      await tester.pumpAndSettle();

      expect(find.text('Ozel Paket Part 1'), findsOneWidget);
      expect(find.text('WhatsApp yayıncı adı: Benim Yayincim'), findsOneWidget);

      // Reset pack name back to default
      await tester.tap(find.text('Varsayılana Dön').first);
      await tester.pumpAndSettle();
      expect(find.text('Telegram Orjinal Part 1'), findsOneWidget);

      await tester.enterText(fields.at(0), 'Son Ad');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Kaydet'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.packName, 'Son Ad');
      expect(result!.publisher, 'Benim Yayıncım');
      expect(result!.exportImmediately, isFalse);
    });
  });

  group('PackPreviewScreen & MyPacksScreen Pack Name UI Tests', () {
    testWidgets('PackPreviewScreen allows editing pack name & publisher pre-export', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({'publisher_name': 'GlobalPub'});

      final stickers = List.generate(
        35,
        (i) => TelegramSticker(
          fileId: 'file_$i',
          fileUniqueId: 'uniq_$i',
          width: 512,
          height: 512,
          emoji: '🐱',
        ),
      );
      final set = TelegramStickerSet(
        name: 'cat_pack',
        title: 'Default Cats',
        stickers: stickers,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: PackPreviewScreen(stickerSet: set),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Default Cats'), findsOneWidget);
      expect(
        find.text('Paket Adı: Default Cats Part 1 (1/2)'),
        findsOneWidget,
      );
      expect(find.text('Yayıncı: GlobalPub'), findsOneWidget);

      // Open editor via the bottom customization chip
      await tester.tap(find.text('Düzenle'));
      await tester.pumpAndSettle();

      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'Özel Kedilerim');
      await tester.enterText(fields.at(1), 'Kedi Dostu');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Kaydet'));
      await tester.pumpAndSettle();

      expect(find.text('Özel Kedilerim'), findsOneWidget);
      expect(
        find.text('Paket Adı: Ozel Kedilerim Part 1 (1/2)'),
        findsOneWidget,
      );
      expect(find.text('Yayıncı: Kedi Dostu'), findsOneWidget);

      // Unmount first so no new thumbnail batch starts, then drain active batch timers
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('MyPacksScreen renames a saved pack and persists the update', (
      tester,
    ) async {
      final initialPack = SavedPack(
        identifier: 'saved_karimm',
        name: 'Karimm - fStikBot',
        publisher: 'StickerSwap',
        trayImagePath: '/nonexistent/tray.png',
        stickerPaths: const ['/nonexistent/1.webp'],
        emojis: const ['⭐'],
        stickerCount: 1,
        savedAt: DateTime(2026, 11, 11),
        addedToWhatsApp: true,
      );

      SharedPreferences.setMockInitialValues({
        'saved_packs': [initialPack.toJsonString()],
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: const MyPacksScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Karimm - fStikBot'), findsOneWidget);

      await tester.tap(find.byTooltip('Paket Adını Düzenle'));
      await tester.pumpAndSettle();

      expect(find.text('Paket Adını Düzenle'), findsOneWidget);
      expect(find.text('Kaydet ve Ekle'), findsOneWidget);

      final dialogField = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      );
      await tester.enterText(dialogField, 'Güncel Başlık 2 🔥');
      await tester.pumpAndSettle();
      expect(find.text('Guncel Baslik 2'), findsOneWidget);

      await tester.tap(find.text('Kaydet'));
      await tester.pumpAndSettle();

      expect(find.text('Guncel Baslik 2'), findsOneWidget);
      expect(find.text('Karimm - fStikBot'), findsNothing);

      final storage = StorageService();
      await storage.init();
      expect(storage.getSavedPacks().first.name, 'Guncel Baslik 2');
    });

    testWidgets(
      'resolveAnimatedPackExportIdentifier prompts for installed static renamed pack and mints versioned identifier',
      (tester) async {
        const channel = MethodChannel('com.example.stickerswap/whatsapp');
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              if (call.method == 'isPackInstalled') {
                return true;
              }
              return null;
            });
        addTearDown(() {
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(channel, null);
        });

        String? resolvedId;
        final whatsapp = WhatsAppService();

        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: ElevatedButton(
                  onPressed: () async {
                    resolvedId = await resolveAnimatedPackExportIdentifier(
                      context: context,
                      baseIdentifier: 'pepe_pack',
                      whatsappService: whatsapp,
                      isAnimated: false,
                      checkIfInstalled: true,
                      isNameUpdated: true,
                    );
                  },
                  child: const Text('Resolve'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Resolve'));
        await tester.pumpAndSettle();

        expect(find.text('Paket WhatsApp\'ta Zaten Yüklü'), findsOneWidget);
        expect(find.textContaining('eski paket adını koruyabilir'), findsOneWidget);

        await tester.tap(find.text('Yeni Güncel Kopya Ekle'));
        await tester.pumpAndSettle();

        expect(resolvedId, isNotNull);
        expect(resolvedId, isNot('pepe_pack'));
        expect(resolvedId!, startsWith('pepe_pack_'));
      },
    );
  });
}
