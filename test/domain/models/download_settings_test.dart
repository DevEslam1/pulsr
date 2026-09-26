// test/domain/models/download_settings_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/domain/models/download_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DownloadSettings Tests (B1 & roundtrip)', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('load prefers setting_download_quality over setting_streaming_quality (B1)', () async {
      SharedPreferences.setMockInitialValues({
        'setting_streaming_quality': 'low',
        'setting_download_quality': 'high',
      });

      final settings = await DownloadSettings.load();
      expect(settings.quality, equals('high'),
          reason: 'Explicit download quality choice must take precedence over streaming quality');
    });

    test('load falls back to setting_streaming_quality when download quality not set', () async {
      SharedPreferences.setMockInitialValues({
        'setting_streaming_quality': 'medium',
      });

      final settings = await DownloadSettings.load();
      expect(settings.quality, equals('medium'));
    });

    test('save writes to setting_download_quality and round-trips correctly', () async {
      SharedPreferences.setMockInitialValues({
        'setting_streaming_quality': 'low',
      });

      const settings = DownloadSettings(
        wifiOnly: true,
        quality: 'high',
        maxConcurrent: 4,
        downloadLocation: '/storage/music',
      );

      await settings.save();

      final reloaded = await DownloadSettings.load();
      expect(reloaded.wifiOnly, isTrue);
      expect(reloaded.quality, equals('high'));
      expect(reloaded.maxConcurrent, equals(4));
      expect(reloaded.downloadLocation, equals('/storage/music'));
    });
  });
}
