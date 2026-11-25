import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pulsr/core/constants/audio_feature_info.dart';
import 'package:pulsr/core/constants/channels.dart';
import 'package:pulsr/core/di/injection.dart';
import 'package:pulsr/core/services/ambient_sound_service.dart';
import 'package:pulsr/data/audio/audio_handler.dart';
import 'package:pulsr/data/audio/equalizer_manager.dart';
import 'package:pulsr/data/scanner/media_scanner_service.dart';
import 'package:pulsr/domain/models/audio_output_info.dart';
import 'package:pulsr/features/settings/cubit/settings_cubit.dart';

import 'support/settings_section_harness.dart';

class _MockAmbientSoundService extends Mock implements AmbientSoundService {}

class _MockMediaScannerService extends Mock implements MediaScannerService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const hiresChannel = MethodChannel(PulsrChannels.hiresDac);
  const usbChannel = MethodChannel(PulsrChannels.usbExclusive);
  const usbEvents = MethodChannel(PulsrChannels.usbExclusiveEvents);

  setUp(() {
    stubSettingsChannels();
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  tearDown(() async {
    AmbientSoundService.testInstance = null;
    clearSettingsChannels();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(hiresChannel, null);
    messenger.setMockMethodCallHandler(usbChannel, null);
    messenger.setMockMethodCallHandler(usbEvents, null);
    if (getIt.isRegistered<PulsrAudioHandler>()) {
      await getIt.unregister<PulsrAudioHandler>();
    }
    if (getIt.isRegistered<EqualizerManager>()) {
      await getIt.unregister<EqualizerManager>();
    }
  });

  group('Bit-Perfect activation fixes', () {
    test('bitPerfectSourceBlockedReason allows MP3 for Bit-Perfect mode', () {
      // MP3 allows bit-perfect
      expect(
        AudioConflicts.bitPerfectSourceBlockedReason(
            path: '/music/song.mp3', bitDepth: 16),
        isNull,
      );
      expect(
        AudioConflicts.bitPerfectSourceBlockedReason(
            codec: 'mp3', bitDepth: 16),
        isNull,
      );
      expect(
        AudioConflicts.bitPerfectSourceBlockedReason(
            mimeType: 'audio/mpeg', bitDepth: 16),
        isNull,
      );
      // But radio is still blocked
      expect(
        AudioConflicts.bitPerfectSourceBlockedReason(
            path: '/music/song.mp3', isRadio: true),
        contains('Live radio and lossy streams'),
      );
      // Other lossy codecs remain blocked
      expect(
        AudioConflicts.bitPerfectSourceBlockedReason(
            codec: 'aac', bitDepth: 16),
        contains('Live radio and lossy streams'),
      );
      expect(
        AudioConflicts.bitPerfectSourceBlockedReason(
            codec: 'opus', bitDepth: 16),
        contains('Live radio and lossy streams'),
      );
      // strictBitPerfect or requireConfirmedCodec requires confirmed codec on ambiguous containers
      expect(
        AudioConflicts.bitPerfectSourceBlockedReason(
            path: '/music/song.m4a', bitDepth: 16),
        isNull,
      );
      expect(
        AudioConflicts.bitPerfectSourceBlockedReason(
          path: '/music/song.m4a',
          bitDepth: 16,
          strictBitPerfect: true,
        ),
        isNotNull,
      );
      expect(
        AudioConflicts.bitPerfectSourceBlockedReason(
          path: '/music/song.m4a',
          bitDepth: 16,
          requireConfirmedCodec: true,
        ),
        isNotNull,
      );
    });

    test(
        'producerChannels == 1 does not force mono when DAC only advertises stereo formats',
        () async {
      int? streamingChannels;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(hiresChannel, (call) async {
        if (call.method == 'setBitPerfectModeDetailed') {
          return <String, dynamic>{
            'success': false,
            'reason': 'no_supported_mixer_attributes',
          };
        }
        if (call.method == 'getAudioOutputInfo') {
          return <String, dynamic>{
            'deviceName': 'SPACETOUCH USB Audio',
            'isUsbDac': true
          };
        }
        if (call.method == 'setOutputDevice') {
          return <String, dynamic>{'success': true};
        }
        return null;
      });
      messenger.setMockMethodCallHandler(usbEvents, (call) async => null);
      messenger.setMockMethodCallHandler(usbChannel, (call) async {
        final args = call.arguments is Map
            ? (call.arguments as Map).cast<String, dynamic>()
            : <String, dynamic>{};
        switch (call.method) {
          case 'getStatus':
            return <String, dynamic>{
              'attached': true,
              'permitted': true,
              'streamingSupported': true,
              'streamingActive': false,
              'deviceId': 42,
              'supportedRates': <int>[48000],
              'advertisedFormats': <Map<String, dynamic>>[
                {'channels': 2, 'bitResolution': 16},
              ],
            };
          case 'getProducerChannels':
            return 1; // Native producer had mono ambient sound running!
          case 'startStreaming':
            streamingChannels = args['channels'] as int?;
            return <String, dynamic>{'success': true};
          default:
            return null;
        }
      });

      final cubit = SettingsCubit(scannerService: _MockMediaScannerService());
      addTearDown(cubit.close);
      await cubit.preferencesReady;
      cubit.safeEmit(cubit.state.copyWith(
        currentOutputDevice: const AudioOutputInfo(
          deviceName: 'SPACETOUCH USB Audio',
          isUsbDac: true,
          sampleRate: 48000,
          bitDepth: 16,
          isBitPerfectActive: false,
        ),
      ));

      await cubit.setBitPerfectOutput(true);
      // Effective channels must default to 2 (stereo), not 1 (mono), because DAC only advertises stereo
      expect(streamingChannels, 2);
    });

    test('_pushBitPerfectBypass disables AmbientSoundService when enabled',
        () async {
      final mockAmbient = _MockAmbientSoundService();
      when(() => mockAmbient.isEnabled).thenReturn(true);
      when(() => mockAmbient.setEnabled(false)).thenAnswer((_) async {});
      AmbientSoundService.testInstance = mockAmbient;

      var started = false;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(hiresChannel, (call) async {
        if (call.method == 'setBitPerfectModeDetailed') {
          return <String, dynamic>{
            'success': false,
            'reason': 'no_supported_mixer_attributes',
          };
        }
        if (call.method == 'getAudioOutputInfo') {
          return <String, dynamic>{
            'deviceName': 'SPACETOUCH USB Audio',
            'isUsbDac': true
          };
        }
        if (call.method == 'setOutputDevice') {
          return <String, dynamic>{'success': true};
        }
        return null;
      });
      messenger.setMockMethodCallHandler(usbEvents, (call) async => null);
      messenger.setMockMethodCallHandler(usbChannel, (call) async {
        switch (call.method) {
          case 'getStatus':
            return <String, dynamic>{
              'attached': true,
              'permitted': true,
              'streamingSupported': true,
              'streamingActive': started,
              'deviceId': 42,
              'supportedRates': <int>[48000],
              'streamingSampleRate': started ? 48000 : 0,
              'streamingBitDepth': started ? 16 : 0,
              'streamingChannels': started ? 2 : 0,
              'advertisedFormats': <Map<String, dynamic>>[
                {'channels': 2, 'bitResolution': 16},
              ],
            };
          case 'getProducerChannels':
            return 2;
          case 'startStreaming':
            started = true;
            return <String, dynamic>{'success': true};
          default:
            return null;
        }
      });

      final cubit = SettingsCubit(scannerService: _MockMediaScannerService());
      addTearDown(cubit.close);
      await cubit.preferencesReady;
      cubit.safeEmit(cubit.state.copyWith(
        currentOutputDevice: const AudioOutputInfo(
          deviceName: 'SPACETOUCH USB Audio',
          isUsbDac: true,
          sampleRate: 48000,
          bitDepth: 16,
          isBitPerfectActive: false,
        ),
      ));

      await cubit.setBitPerfectOutput(true);
      verify(() => mockAmbient.setEnabled(false))
          .called(greaterThanOrEqualTo(1));
    });
  });
}
