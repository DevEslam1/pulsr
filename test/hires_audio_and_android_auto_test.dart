// test/hires_audio_and_android_auto_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/domain/models/audio_output_info.dart';
import 'package:pulsr/features/settings/cubit/settings_cubit.dart';
import 'package:pulsr/core/services/hires_audio_service.dart';
import 'package:pulsr/data/scanner/media_scanner_service.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockMediaScannerService extends Mock implements MediaScannerService {}
class MockHiResAudioService extends Mock implements HiResAudioService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('AudioOutputInfo Model Tests', () {
    test('AudioOutputInfo fromMap correctly parses USB DAC details', () {
      final map = {
        'deviceName': 'Fiio Q3 (USB DAC)',
        'isUsbDac': true,
        'sampleRate': 192000,
        'bitDepth': 24,
        'isBitPerfectActive': true,
        'isBitPerfectSupported': true,
        'supportedSampleRates': [44100, 48000, 96000, 192000],
      };

      final info = AudioOutputInfo.fromMap(map);

      expect(info.deviceName, equals('Fiio Q3 (USB DAC)'));
      expect(info.isUsbDac, isTrue);
      expect(info.sampleRate, equals(192000));
      expect(info.bitDepth, equals(24));
      expect(info.isBitPerfectActive, isTrue);
      expect(info.isBitPerfectSupported, isTrue);
      expect(info.supportedSampleRates, contains(192000));
    });

    test('AudioOutputInfo fallback when map is empty', () {
      final info = AudioOutputInfo.fromMap({});
      expect(info.deviceName, equals('Default Audio Output'));
      expect(info.isUsbDac, isFalse);
      expect(info.sampleRate, equals(44100));
      expect(info.bitDepth, equals(16));
      expect(info.isBitPerfectActive, isFalse);
    });

    test('AudioOutputInfo copyWith and equality', () {
      const info1 = AudioOutputInfo(
        deviceName: 'Headphones',
        isUsbDac: false,
        sampleRate: 48000,
        bitDepth: 16,
        isBitPerfectActive: false,
      );

      final info2 = info1.copyWith(isUsbDac: true, bitDepth: 24, isBitPerfectActive: true);

      expect(info2.isUsbDac, isTrue);
      expect(info2.bitDepth, equals(24));
      expect(info2.isBitPerfectActive, isTrue);
      expect(info1 == info2, isFalse);
    });
  });

  group('SettingsCubit Bit-Perfect Mode Tests', () {
    late MockMediaScannerService mockScanner;
    late MockHiResAudioService mockHiRes;
    late SettingsCubit cubit;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      mockScanner = MockMediaScannerService();
      mockHiRes = MockHiResAudioService();
      when(() => mockHiRes.outputDeviceStream).thenAnswer((_) => const Stream.empty());
      when(() => mockHiRes.currentOutputInfo).thenReturn(const AudioOutputInfo(
        deviceName: 'Built-in Speaker',
        isUsbDac: false,
        sampleRate: 48000,
        bitDepth: 16,
        isBitPerfectActive: false,
      ));
      when(() => mockHiRes.setBitPerfectMode(any())).thenAnswer((_) async => true);
      when(() => mockHiRes.getAudioOutputInfo()).thenAnswer((_) async => const AudioOutputInfo(
        deviceName: 'Fiio BTR5 (USB DAC)',
        isUsbDac: true,
        sampleRate: 96000,
        bitDepth: 24,
        isBitPerfectActive: true,
      ));

      cubit = SettingsCubit(
        scannerService: mockScanner,
        hiResAudioService: mockHiRes,
      );
      await pumpEventQueue();
    });

    tearDown(() {
      cubit.close();
    });

    test('setBitPerfectOutput toggles bit-perfect state', () async {
      await cubit.setBitPerfectOutput(true);
      expect(cubit.state.bitPerfectOutput, isTrue);
      verify(() => mockHiRes.setBitPerfectMode(true)).called(1);
    });

    test('setBypassDspOnBitPerfect updates bypass state', () async {
      await cubit.setBypassDspOnBitPerfect(false);
      expect(cubit.state.bypassDspOnBitPerfect, isFalse);
    });
  });
}
