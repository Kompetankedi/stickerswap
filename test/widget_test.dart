import 'package:flutter_test/flutter_test.dart';
import 'package:stickerswap/models/curated_pack.dart';
import 'package:stickerswap/models/saved_pack.dart';
import 'package:stickerswap/models/telegram_sticker.dart';
import 'package:stickerswap/models/telegram_sticker_set.dart';
import 'package:stickerswap/services/telegram_service.dart';
import 'package:stickerswap/services/storage_service.dart';

void main() {
  group('TelegramService.extractSetName Tests', () {
    test('extracts set name from various link formats', () {
      expect(
        TelegramService.extractSetName('https://t.me/addstickers/pepethefrog'),
        'pepethefrog',
      );
      expect(
        TelegramService.extractSetName('https://telegram.me/addstickers/HotCherry'),
        'HotCherry',
      );
      expect(
        TelegramService.extractSetName('tg://addstickers?set=Animals'),
        'Animals',
      );
      expect(
        TelegramService.extractSetName('simple_pack'),
        'simple_pack',
      );
      expect(
        TelegramService.extractSetName('   spaced_pack   '),
        'spaced_pack',
      );
    });
  });

  group('Model Tests', () {
    test('TelegramSticker.fromJson works correctly', () {
      final sticker = TelegramSticker.fromJson({
        'file_id': 'file_123',
        'file_unique_id': 'uniq_123',
        'width': 512,
        'height': 512,
        'emoji': '🐸',
        'is_animated': false,
        'is_video': false,
      });

      expect(sticker.fileId, 'file_123');
      expect(sticker.emoji, '🐸');
      expect(sticker.isAnimated, false);
      expect(sticker.isVideo, false);
    });

    test('TelegramStickerSet computes properties correctly', () {
      final set = TelegramStickerSet(
        name: 'pepe',
        title: 'Pepe The Frog',
        stickers: [
          TelegramSticker(fileId: '1', fileUniqueId: 'u1', width: 512, height: 512),
          TelegramSticker(fileId: '2', fileUniqueId: 'u2', width: 512, height: 512),
        ],
      );

      expect(set.stickers.length, 2);
      expect(set.title, 'Pepe The Frog');
      expect(set.isStatic, true);
      expect(set.typeLabel, 'Statik');
    });

    test('SavedPack serialization roundtrip works', () {
      final pack = SavedPack(
        identifier: 'pepe_1',
        name: 'Pepe',
        publisher: 'StickerSwap',
        trayImagePath: 'tray.png',
        stickerPaths: ['s1.webp', 's2.webp', 's3.webp'],
        emojis: ['🐸', '😂', '😎'],
        stickerCount: 3,
        savedAt: DateTime(2026, 1, 1),
      );

      final json = pack.toJsonString();
      final restored = SavedPack.fromJsonString(json);

      expect(restored.identifier, 'pepe_1');
      expect(restored.name, 'Pepe');
      expect(restored.stickerPaths.length, 3);
      expect(restored.emojis.length, 3);
      expect(restored.stickerCount, 3);
    });

    test('CuratedPack provides popular packs and categories', () {
      expect(CuratedPack.popularPacks.isNotEmpty, true);
      expect(CuratedPack.categories.contains('Memeler'), true);
      expect(CuratedPack.categories.contains('Sevimli'), true);
    });

    test('StorageService.formatBytes formats correctly', () {
      expect(StorageService.formatBytes(0), '0 B');
      expect(StorageService.formatBytes(512), '512 B');
      expect(StorageService.formatBytes(2048), '2.0 KB');
      expect(StorageService.formatBytes(5 * 1024 * 1024), '5.0 MB');
    });
  });
}
