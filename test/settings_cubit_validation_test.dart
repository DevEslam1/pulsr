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

  group('SettingsCubit URL Validation Tests', () {
    test('rejects invalid backend URLs and sets error message in state', () async {
      await cubit.setYtdlpBackendUrl('invalid-url-without-scheme');
      expect(cubit.state.errorMessage, contains('Invalid backend URL format'));

      await cubit.setYtdlpBackendUrl('ftp://example.com/api');
      expect(cubit.state.errorMessage, contains('Invalid backend URL format'));
    });

    test('accepts valid http and https backend URLs', () async {
      await cubit.setYtdlpBackendUrl('http://192.168.1.50:8080');
      expect(cubit.state.errorMessage, isNull);
      expect(cubit.state.ytdlpBackendUrl, 'http://192.168.1.50:8080');

      await cubit.setYtdlpBackendUrl('https://yt-backend.example.com');
      expect(cubit.state.errorMessage, isNull);
      expect(cubit.state.ytdlpBackendUrl, 'https://yt-backend.example.com');
    });
  });
}
