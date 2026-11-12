import 'package:flutter_test/flutter_test.dart';
import 'package:stickerswap/models/telegram_sticker.dart';
import 'package:stickerswap/models/telegram_sticker_set.dart';
import 'package:stickerswap/services/sticker_export_orchestrator.dart';

void main() {
  TelegramStickerSet buildSampleSet({int count = 35}) {
    final stickers = List.generate(
      count,
      (i) => TelegramSticker(
        fileId: 'file_$i',
        fileUniqueId: 'uniq_$i',
        width: 512,
        height: 512,
        emoji: i.isEven ? '🐱' : '🔥',
      ),
    );
    return TelegramStickerSet(
      name: 'cat_pack',
      title: 'Original Cats',
      stickers: stickers,
    );
  }

  group('StickerExportOrchestrator Tests', () {
    test('selection, invert, and filter work cleanly', () {
      final orchestrator = StickerExportOrchestrator(
        stickerSet: buildSampleSet(count: 6),
      );
      addTearDown(orchestrator.dispose);

      expect(orchestrator.selectedCount, 6);
      expect(orchestrator.selectAll, isTrue);

      orchestrator.toggleSelectAll();
      expect(orchestrator.selectedCount, 0);
      expect(orchestrator.selectAll, isFalse);

      orchestrator.toggleStickerSelection(orchestrator.stickerSet.stickers.first);
      expect(orchestrator.selectedCount, 1);

      orchestrator.setFilterIndex(1); // Selected only
      expect(orchestrator.filteredStickers.length, 1);

      orchestrator.setFilterIndex(2); // Unselected only
      expect(orchestrator.filteredStickers.length, 5);

      orchestrator.setFilterIndex(0);
      orchestrator.setEmojiSearch('🔥');
      expect(orchestrator.filteredStickers.length, 3);

      orchestrator.setEmojiSearch('');
      orchestrator.invertSelection();
      expect(orchestrator.selectedCount, 5);
    });

    test('metadata overrides and multi-part preview name compute correctly', () {
      final orchestrator = StickerExportOrchestrator(
        stickerSet: buildSampleSet(count: 35),
      );
      addTearDown(orchestrator.dispose);

      expect(
        orchestrator.previewPackNameForSelection(),
        'Original Cats Part 1 (1/2)',
      );

      orchestrator.updateMetadataOverrides(
        packName: 'Şahane Kediler 🐱',
        publisher: 'Özel Yayıncı',
      );
      expect(orchestrator.hasCustomName, isTrue);
      expect(orchestrator.hasCustomPublisher, isTrue);
      expect(
        orchestrator.previewPackNameForSelection(),
        'Sahane Kediler Part 1 (1/2)',
      );
      expect(orchestrator.effectivePublisherSanitized, 'Ozel Yayinci');
    });

    test('preparePartsForExport rejects fewer than 3 selected stickers', () async {
      final orchestrator = StickerExportOrchestrator(
        stickerSet: buildSampleSet(count: 2),
      );
      addTearDown(orchestrator.dispose);

      await expectLater(
        orchestrator.preparePartsForExport(),
        throwsStateError,
      );
    });
  });
}
