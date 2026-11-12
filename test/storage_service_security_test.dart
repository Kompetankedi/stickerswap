import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stickerswap/services/storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('StorageService Bot Token Security & Migration', () {
    test('setBotToken stores token in secure storage and removes legacy SharedPreferences key', () async {
      SharedPreferences.setMockInitialValues({'bot_token': 'old_plain_token'});
      FlutterSecureStorage.setMockInitialValues({});

      final storage = StorageService();
      await storage.init();

      await storage.setBotToken('  123456:ABC-DEF  ');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('bot_token'), isNull);
      expect(await storage.getBotToken(), '123456:ABC-DEF');

      const secure = FlutterSecureStorage(
        aOptions: AndroidOptions(encryptedSharedPreferences: true),
      );
      expect(await secure.read(key: 'bot_token'), '123456:ABC-DEF');
    });

    test('getBotToken migrates legacy plaintext token from SharedPreferences to secure storage', () async {
      SharedPreferences.setMockInitialValues({'bot_token': '  legacy_123:XYZ  '});
      FlutterSecureStorage.setMockInitialValues({});

      final storage = StorageService();
      await storage.init();

      final migrated = await storage.getBotToken();
      expect(migrated, 'legacy_123:XYZ');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('bot_token'), isNull);

      const secure = FlutterSecureStorage(
        aOptions: AndroidOptions(encryptedSharedPreferences: true),
      );
      expect(await secure.read(key: 'bot_token'), 'legacy_123:XYZ');
    });

    test('getBotToken prefers secure storage and purges leftover legacy SharedPreferences token', () async {
      SharedPreferences.setMockInitialValues({'bot_token': 'stale_plain'});
      FlutterSecureStorage.setMockInitialValues({'bot_token': 'secure_fresh'});

      final storage = StorageService();
      await storage.init();

      expect(await storage.getBotToken(), 'secure_fresh');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('bot_token'), isNull);
    });

    test('clearBotToken removes token from both secure storage and SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({'bot_token': 'legacy_plain'});
      FlutterSecureStorage.setMockInitialValues({'bot_token': 'secure_token'});

      final storage = StorageService();
      await storage.init();

      await storage.clearBotToken();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('bot_token'), isNull);
      expect(await storage.getBotToken(), isNull);

      const secure = FlutterSecureStorage(
        aOptions: AndroidOptions(encryptedSharedPreferences: true),
      );
      expect(await secure.read(key: 'bot_token'), isNull);
    });
  });
}
