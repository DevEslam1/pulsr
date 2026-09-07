import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
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

  group('SettingsCubit backend disabled Tests', () {
    test('setYtdlpBackendUrl is a no-op (backend decommissioned)', () async {
      final before = cubit.state.ytdlpBackendUrl;
      await cubit.setYtdlpBackendUrl('invalid-url-without-scheme');
      expect(cubit.state.errorMessage, isNull);
      expect(cubit.state.ytdlpBackendUrl, before);

      await cubit.setYtdlpBackendUrl('http://192.168.1.50:8080');
      expect(cubit.state.errorMessage, isNull);
      expect(cubit.state.ytdlpBackendUrl, before);
    });

    test('backend stays disabled and engine stays on-device', () async {
      await cubit.setYtdlpBackendEnabled(true);
      expect(cubit.state.ytdlpBackendEnabled, isFalse);

      await cubit.setExtractorEngine(
          // ignore: deprecated_member_use_from_same_package
          cubit.state.extractorEngine);
      expect(cubit.state.ytdlpBackendEnabled, isFalse);
    });
  });
}
