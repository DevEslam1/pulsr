import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pulsr/data/scanner/media_scanner_service.dart';
import 'package:pulsr/domain/models/audio_output_info.dart';
import 'package:pulsr/data/services/hires_audio_service.dart';
import 'package:pulsr/features/settings/cubit/settings_cubit.dart';

class _Scanner extends Mock implements MediaScannerService {}

class _OutputService extends Mock implements HiResAudioService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const output = AudioOutputInfo(
    deviceName: 'Phone',
    isUsbDac: false,
    sampleRate: 44100,
    bitDepth: 16,
    isBitPerfectActive: false,
  );
  late _OutputService service;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    service = _OutputService();
    when(() => service.outputDeviceStream)
        .thenAnswer((_) => const Stream.empty());
    when(() => service.currentOutputInfo).thenReturn(output);
    when(() => service.getAudioOutputInfo()).thenAnswer((_) async => output);
    when(() => service.setTargetOutputFormat(
          sampleRate: any(named: 'sampleRate'),
          bitDepth: any(named: 'bitDepth'),
        )).thenAnswer((_) async => false);
  });

  test('unknown platform reports stay unknown without invented capabilities',
      () {
    final unknown = AudioOutputInfo.fromMap({});
    expect(unknown.sampleRate, 0);
    expect(unknown.bitDepth, 0);
    expect(unknown.supportedSampleRates, isEmpty);
    final device = AudioDeviceEntry.fromMap({'id': 1});
    expect(device.sampleRates, isEmpty);
    expect(device.maxBitDepth, 0);
  });

  test('rejected rate/depth are neither persisted nor presented as selected',
      () async {
    final cubit =
        SettingsCubit(scannerService: _Scanner(), hiResAudioService: service);
    try {
      await cubit.setTargetOutputSampleRate(192000);
      await cubit.setTargetOutputBitDepth(32);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('target_output_sample_rate'), isNull);
      expect(prefs.getInt('target_output_bit_depth'), isNull);
      expect(cubit.state.currentOutputDevice?.targetSampleRate, 0);
      expect(cubit.state.currentOutputDevice?.targetBitDepth, 0);
    } finally {
      await cubit.close();
    }
  });

  test('a rejected Phone request does not launch a settings page', () async {
    when(() => service.selectOutputDevice(1)).thenAnswer((_) async =>
        const OutputRouteResult(
            success: false, error: 'unavailable', requiresSystemPicker: true));
    final cubit =
        SettingsCubit(scannerService: _Scanner(), hiResAudioService: service);
    try {
      expect(await cubit.selectOutputDevice(1), isFalse);
      verifyNever(() => service.openOutputSwitcher());
    } finally {
      await cubit.close();
    }
  });
}
