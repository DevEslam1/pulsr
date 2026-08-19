// test/settings_cubit_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/data/scanner/media_scanner_service.dart';
import 'package:pulsr/features/settings/cubit/settings_cubit.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockMediaScannerService extends Mock implements MediaScannerService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MockMediaScannerService mockScannerService;

  setUp(() {
    mockScannerService = MockMediaScannerService();
    SharedPreferences.setMockInitialValues({});
  });

  group('SettingsCubit', () {
    test('initial state defaults are correct', () {
      final cubit = SettingsCubit(scannerService: mockScannerService);

      expect(cubit.state.gaplessPlayback, true);
      expect(cubit.state.crossfadeSeconds, 0.0);
      expect(cubit.state.minDurationSec, 30);
      expect(cubit.state.dynamicThemingEnabled, true);
      expect(cubit.state.resumeAfterInterruption, true);
      expect(cubit.state.isScanning, false);

      cubit.close();
    });

    test('setResumeAfterInterruption updates state and SharedPreferences', () async {
      final cubit = SettingsCubit(scannerService: mockScannerService);

      await cubit.setResumeAfterInterruption(false);
      expect(cubit.state.resumeAfterInterruption, false);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('setting_resume_after_interruption'), false);

      cubit.close();
    });

    test('setGapless, setCrossfade, setMinDuration, setDynamicTheming update state', () async {
      final cubit = SettingsCubit(scannerService: mockScannerService);

      await cubit.setGapless(false);
      expect(cubit.state.gaplessPlayback, false);

      await cubit.setCrossfade(5.0);
      expect(cubit.state.crossfadeSeconds, 5.0);

      await cubit.setMinDuration(15);
      expect(cubit.state.minDurationSec, 15);

      await cubit.setDynamicTheming(false);
      expect(cubit.state.dynamicThemingEnabled, false);

      cubit.close();
    });
  });
}
