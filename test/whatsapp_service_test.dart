import 'package:flutter_test/flutter_test.dart';
import 'package:stickerswap/services/whatsapp_service.dart';

void main() {
  group('WhatsAppService Tests', () {
    final service = WhatsAppService();

    test('splitIntoPacks correctly divides stickers into chunks of 30', () {
      final items = List.generate(75, (i) => 'sticker_$i');
      final chunks = service.splitIntoPacks(items, maxPerPack: 30);

      expect(chunks.length, 3);
      expect(chunks[0].length, 30);
      expect(chunks[1].length, 30);
      expect(chunks[2].length, 15);
    });

    test('splitIntoPacks handles exactly 30 items without extra pack', () {
      final items = List.generate(30, (i) => 'sticker_$i');
      final chunks = service.splitIntoPacks(items, maxPerPack: 30);

      expect(chunks.length, 1);
      expect(chunks[0].length, 30);
    });

    test('splitIntoPacks handles fewer than 30 items', () {
      final items = List.generate(12, (i) => 'sticker_$i');
      final chunks = service.splitIntoPacks(items, maxPerPack: 30);

      expect(chunks.length, 1);
      expect(chunks[0].length, 12);
    });

    group('sanitizeEmojis Tests', () {
      test('keeps single valid emoji', () {
        expect(WhatsAppService.sanitizeEmojis('🐱'), ['🐱']);
        expect(WhatsAppService.sanitizeEmojis('🔥'), ['🔥']);
        expect(WhatsAppService.sanitizeEmojis('⭐'), ['⭐']);
      });

      test('keeps up to 3 valid emojis and trims excess', () {
        expect(WhatsAppService.sanitizeEmojis('🐱🐶🐭'), ['🐱', '🐶', '🐭']);
        expect(WhatsAppService.sanitizeEmojis('😀😁😂🤣😃'), ['😀', '😁', '😂']);
      });

      test('handles empty or whitespace strings with safe fallback ⭐', () {
        expect(WhatsAppService.sanitizeEmojis(''), ['⭐']);
        expect(WhatsAppService.sanitizeEmojis('   '), ['⭐']);
        expect(WhatsAppService.sanitizeEmojis(null), ['⭐']);
      });

      test('extracts emojis from mixed text', () {
        expect(WhatsAppService.sanitizeEmojis('cat 🐱 dog 🐶 hello'), ['🐱', '🐶']);
        expect(WhatsAppService.sanitizeEmojis('no emojis here'), ['⭐']);
      });

      test('correctly handles multi-codepoint emojis', () {
        expect(WhatsAppService.sanitizeEmojis('🤷‍♂️'), ['🤷‍♂️']);
        expect(WhatsAppService.sanitizeEmojis('👍🏻'), ['👍🏻']);
        expect(WhatsAppService.sanitizeEmojis('❤️'), ['❤️']);
      });
    });

    group('sanitizeForWhatsApp & buildPackName Tests', () {
      test('transliterates Turkish characters and cleans unsupported symbols', () {
        expect(
          WhatsAppService.sanitizeForWhatsApp('Çiçek Şirin Öğle Üzüm ğüşiöçİ 🔥'),
          'Cicek Sirin Ogle Uzum gusiocI',
        );
        expect(
          WhatsAppService.sanitizeForWhatsApp('Karimm::fStikBot @test..1'),
          'Karimm - fStikBot test.1',
        );
      });

      test('caps single-part pack names at 120 characters', () {
        final longName = 'A' * 140;
        final built = WhatsAppService.buildPackName(
          customName: longName,
          defaultTitle: 'Default',
        );
        expect(built.length, 120);
        expect(built, 'A' * 120);
      });

      test('falls back to defaultTitle when customName is blank or stripped', () {
        expect(
          WhatsAppService.buildPackName(
            customName: '   ',
            defaultTitle: 'Şirin Kediler',
          ),
          'Sirin Kediler',
        );
        expect(
          WhatsAppService.buildPackName(
            customName: '🔥🔥🔥@@@',
            defaultTitle: 'Karimm - fStikBot',
          ),
          'Karimm - fStikBot',
        );
        expect(
          WhatsAppService.buildPackName(
            customName: null,
            defaultTitle: '🔥🔥🔥',
            partIndex: 1,
            totalParts: 2,
          ),
          'Sticker Pack 2',
        );
      });

      test('preserves Part X suffixes on multi-part packs even at 120 chars', () {
        final longCustom = 'B' * 130;
        final part1 = WhatsAppService.buildPackName(
          customName: longCustom,
          defaultTitle: 'Orig',
          partIndex: 0,
          totalParts: 2,
        );
        final part2 = WhatsAppService.buildPackName(
          customName: longCustom,
          defaultTitle: 'Orig',
          partIndex: 1,
          totalParts: 2,
        );

        expect(part1.length, 120);
        expect(part2.length, 120);
        expect(part1.endsWith(' Part 1'), isTrue);
        expect(part2.endsWith(' Part 2'), isTrue);
        expect(part1, isNot(equals(part2)));
      });

      test('appends Part X suffix to Turkish custom pack names', () {
        final part1 = WhatsAppService.buildPackName(
          customName: 'Özel Paketim 🐱',
          defaultTitle: 'Telegram Pack',
          partIndex: 0,
          totalParts: 3,
        );
        final part3 = WhatsAppService.buildPackName(
          customName: 'Özel Paketim 🐱',
          defaultTitle: 'Telegram Pack',
          partIndex: 2,
          totalParts: 3,
        );

        expect(part1, 'Ozel Paketim Part 1');
        expect(part3, 'Ozel Paketim Part 3');
      });
    });
  });
}
