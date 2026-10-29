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
  });
}
