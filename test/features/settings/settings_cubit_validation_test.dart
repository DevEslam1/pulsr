import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/constants/prefs_keys.dart';
import 'package:pulsr/data/scanner/media_scanner_service.dart';
import 'package:pulsr/features/settings/cubit/settings_cubit.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockMediaScannerService extends Mock implements MediaScannerService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockMediaScannerService mockScanner;
  late SettingsCubit cubit;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    mockScanner = MockMediaScannerService();
    cubit = SettingsCubit(scannerService: mockScanner);
  });

  tearDown(() async {
    await cubit.close();
  });

  group('SettingsCubit legacy backend migration', () {
    test('reloadSettings purges legacy remote-backend preferences', () async {
      SharedPreferences.setMockInitialValues({
        PrefsKeys.ytdlpBackendEnabled: true,
        PrefsKeys.ytdlpBackendUrl: 'https://old-backend.example',
        PrefsKeys.ytdlpBackendToken: 'legacy-token',
        PrefsKeys.extractorEngine: 'remoteYtdlp',
        PrefsKeys.syncCookiesToBackend: true,
      });

      await cubit.reloadSettings();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey(PrefsKeys.ytdlpBackendEnabled), isFalse);
      expect(prefs.containsKey(PrefsKeys.ytdlpBackendUrl), isFalse);
      expect(prefs.containsKey(PrefsKeys.ytdlpBackendToken), isFalse);
      expect(prefs.containsKey(PrefsKeys.extractorEngine), isFalse);
      expect(prefs.containsKey(PrefsKeys.syncCookiesToBackend), isFalse);
      expect(cubit.state.errorMessage, isNull);
    });
  });
}
