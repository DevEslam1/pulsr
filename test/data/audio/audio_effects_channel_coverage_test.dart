// test/data/audio/audio_effects_channel_coverage_test.dart
//
// Error/fallback branch coverage for AudioEffectsChannel. Every native call is
// stubbed; the point is the failure surface: rejected setters, platform
// exceptions, null answers, malformed DSD payloads and the native route
// callback. Complements audio_effects_channel_test.dart / _extended_test.dart.
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/constants/channels.dart';
import 'package:pulsr/data/audio/audio_effects_channel.dart';
import 'package:pulsr/domain/models/audio_effects_config.dart';
import 'package:pulsr/domain/models/dsp_telemetry.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(PulsrChannels.audioEffects);
  final calls = <MethodCall>[];

  void stub(Future<Object?> Function(MethodCall call) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) {
      calls.add(call);
      return handler(call);
    });
  }

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    calls.clear();
    AudioEffectsChannel.lastPushedBypassDspForBitPerfect = null;
    stub((_) async => null);
  });

  tearDown(() {
    AudioEffectsChannel().dispose();
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('awaitControlUpdates', () {
    test('null native answer reports false', () async {
      stub((_) async => null);
      expect(await AudioEffectsChannel().awaitControlUpdates(), isFalse);
    });
  });

  group('rejected native setters', () {
    test('a false from _invokeNativeSetter becomes a DSP_NOT_APPLIED error',
        () async {
      stub((_) async => false);
      await expectLater(
        AudioEffectsChannel().setCrossfeedEnabled(true),
        throwsA(isA<PlatformException>()
            .having((e) => e.code, 'code', 'DSP_NOT_APPLIED')),
      );
    });

    test('setBypassDspForBitPerfect rethrows on an explicit false', () async {
      stub((call) async =>
          call.method == 'setBypassDspForBitPerfect' ? false : null);
      await expectLater(
        AudioEffectsChannel().setBypassDspForBitPerfect(true),
        throwsA(isA<StateError>()),
      );
    });

    test('setBypassDspForBitPerfect rethrows on applied=false map', () async {
      stub((call) async => call.method == 'setBypassDspForBitPerfect'
          ? <Object?, Object?>{'applied': false}
          : null);
      await expectLater(
        AudioEffectsChannel().setBypassDspForBitPerfect(true),
        throwsA(isA<StateError>()),
      );
    });

    test('setAudioSessionId rethrows a platform failure', () async {
      stub((_) async => throw PlatformException(code: 'NOPE'));
      await expectLater(
        AudioEffectsChannel().setAudioSessionId(7),
        throwsA(isA<PlatformException>()),
      );
    });
  });

  group('bool setters fall back to false on failure', () {
    setUp(() {
      stub((_) async => throw PlatformException(code: 'BOOM'));
    });

    test('every failure-tolerant setter reports false', () async {
      final effects = AudioEffectsChannel();
      expect(await effects.setVolumeBoost(300), isFalse);
      expect(await effects.isDvcSupported(), isFalse);
      expect(await effects.setDvcEnabled(true), isFalse);
      expect(await effects.setDvcGain(0.5), isFalse);
      expect(await effects.setBassBoost(100), isFalse);
      expect(await effects.setVirtualizerEnabled(true), isFalse);
      expect(await effects.setVirtualizerStrength(0.5), isFalse);
      expect(await effects.setDynamicsPreset(DynamicsPreset.off, true), isFalse);
      expect(await effects.setSpatializerEnabled(true), isFalse);
      expect(await effects.setEqBands([1.0]), isFalse);
      expect(await effects.setEqBandGain(0, 1.0), isFalse);
      expect(await effects.setEqBandGains([1.0]), isFalse);
      expect(await effects.setNativeEqBand(0, 100, 1.0, 1.0), isFalse);
      expect(
        await effects.setNativeEqBandsBulk(
            frequencies: [100.0], gains: [1.0]),
        isFalse,
      );
      expect(await effects.setNativeEqBandCount(1), isFalse);
      expect(
        await effects.setReplayGainParams(
          mode: 1,
          trackGainDb: 0,
          albumGainDb: 0,
          trackPeak: 1,
          albumPeak: 1,
          preAmpDb: 0,
          enabled: true,
        ),
        isFalse,
      );
      expect(await effects.setReplayGainEnabled(true), isFalse);
      expect(
        await effects.setDitherParams(
            enabled: true, targetBitDepth: 16, isBluetooth: false),
        isFalse,
      );
      expect(await effects.resetWeeklyDose(), isFalse);
      expect(await effects.isSafetyAttenuationActive(), isFalse);
      expect(await effects.hasActiveEffects(), isFalse);
      expect(await effects.loadViperDdc(ddcContent: 'x', profileName: 'p'),
          isFalse);
      expect(await effects.loadArbitraryEq(eqString: 'x'), isFalse);
      expect(await effects.loadImpulseResponse(const [1.0]), isFalse);
      expect(await effects.sendWarmupBuffer(), isFalse);
    });

    test('setDvcGain rejects a non-finite gain without a channel call', () async {
      expect(await AudioEffectsChannel().setDvcGain(double.infinity), isFalse);
      expect(await AudioEffectsChannel().setDvcGain(double.nan), isFalse);
      expect(calls.where((c) => c.method == 'setDvcGain'), isEmpty);
    });
  });

  group('probe fallbacks', () {
    test('throwing probes report their defaults', () async {
      stub((_) async => throw PlatformException(code: 'BOOM'));
      final effects = AudioEffectsChannel();
      expect(await effects.getRtfGovernorStatus(),
          containsPair('isDegraded', false));
      expect(await effects.getThermalStatus(), 0);
      expect(await effects.getPipelineLatencyFrames(), 0);
      expect(await effects.getAppliedSampleRate(), 48000.0);
      expect(await effects.getWeeklyDose(), 0.0);
      expect(await effects.getAutoDegradedStages(), 0);
      expect(await effects.getDspDebugStatus(), isNull);
      expect(await effects.getDspDebugReport(), isNull);
      expect(await effects.getDspBatteryDrainEstimate(), isEmpty);
      expect(await effects.getChainOfCustodyReport(), isEmpty);
      expect(await effects.verifyState(), isNull);
      expect(await effects.detectOemAudio(),
          containsPair('hasOemAudio', false));
      expect(await effects.detectSystemEffects(),
          containsPair('status', 'unknown'));
      expect(await effects.getSystemEffectsStatus(),
          containsPair('status', 'unknown'));
      expect(await effects.setSystemEffectsPolicy('auto'), 'unknown');
    });

    test('non-numeric probe answers collapse to defaults', () async {
      stub((call) async => switch (call.method) {
            'getPipelineLatencyFrames' => 'fast',
            'getAppliedSampleRate' => -1.0,
            'getWeeklyDose' => 'lots',
            _ => null,
          });
      final effects = AudioEffectsChannel();
      expect(await effects.getPipelineLatencyFrames(), 0);
      expect(await effects.getAppliedSampleRate(), 48000.0);
      expect(await effects.getWeeklyDose(), 0.0);
    });

    test('loadLiveProgCode returns the error string on failure', () async {
      stub((_) async => throw PlatformException(code: 'COMPILE', message: 'bad'));
      final result = await AudioEffectsChannel().loadLiveProgCode('@init');
      expect(result, contains('PlatformException'));
    });
  });

  group('setNativeEqBandsBulk defaults', () {
    test('supplies default q and type arrays sized to the frequency list',
        () async {
      stub((_) async => null);
      expect(
        await AudioEffectsChannel().setNativeEqBandsBulk(
            frequencies: [100.0, 1000.0, 5000.0], gains: [1.0, 2.0, 3.0]),
        isTrue,
      );
      final call = calls.singleWhere((c) => c.method == 'setNativeEqBandsBulk');
      final args = (call.arguments as Map).cast<String, Object?>();
      expect((args['qs'] as List).length, 3);
      expect((args['types'] as List).length, 3);
      expect((args['qs'] as List).every((q) => q == 1.414), isTrue);
    });
  });

  group('setDspPreference retry', () {
    test('retries once after a transient first failure', () async {
      var attempts = 0;
      stub((call) async {
        if (call.method == 'setDspPreference') {
          attempts++;
          if (attempts == 1) throw PlatformException(code: 'NOT_READY');
        }
        return null;
      });
      await AudioEffectsChannel().setDspPreference('native');
      expect(attempts, 2);
    });

    test('gives up quietly after two failures', () async {
      var attempts = 0;
      stub((call) async {
        if (call.method == 'setDspPreference') {
          attempts++;
          throw PlatformException(code: 'NOT_READY');
        }
        return null;
      });
      await AudioEffectsChannel().setDspPreference('native');
      expect(attempts, 2);
    });
  });

  group('decodeDsd', () {
    test('returns null when a chunked reply is null', () async {
      var callCount = 0;
      stub((call) async {
        if (call.method != 'decodeDsd') return null;
        callCount++;
        return callCount == 1 ? <double>[0.0] : null;
      });
      final big = Uint8List(70 * 1024);
      expect(await AudioEffectsChannel().decodeDsd(big, big), isNull);
      expect(callCount, 2);
    });

    test('rejects mismatched channel lengths and decodes an empty payload',
        () async {
      stub((_) async => <double>[0.0]);
      final effects = AudioEffectsChannel();
      expect(await effects.decodeDsd(Uint8List(8), Uint8List(4)), isNull);
      expect(await effects.decodeDsd(Uint8List(0), Uint8List(0)), isEmpty);
    });

    test('returns null when the native call throws', () async {
      stub((_) async => throw PlatformException(code: 'DSD'));
      final bytes = Uint8List(16);
      expect(await AudioEffectsChannel().decodeDsd(bytes, bytes), isNull);
    });
  });

  group('native route callback', () {
    test('onRouteChanged emits when the platform pushes onRouteChanged',
        () async {
      final effects = AudioEffectsChannel();
      final events = <void>[];
      final sub = effects.onRouteChanged.listen(events.add);

      const codec = StandardMethodCodec();
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
        PulsrChannels.audioEffects,
        codec.encodeMethodCall(const MethodCall('onRouteChanged')),
        (_) {},
      );
      await Future<void>.delayed(Duration.zero);
      expect(events, hasLength(1));
      await sub.cancel();
    });
  });

  group('dispose', () {
    test('resets capability state and detaches the singleton', () {
      final effects = AudioEffectsChannel();
      effects.dispose();
      expect(effects.isVirtualizerSupported, isFalse);
      expect(effects.isFloatOutputSupported, isTrue);
      expect(AudioEffectsChannel(), isNot(same(effects)));
    });
  });

  group('telemetry', () {
    test('a list payload parses and a non-list throws', () async {
      stub((call) async => call.method == 'getTelemetry'
          ? List<dynamic>.filled(17, 0.0)
          : null);
      final telemetry = await AudioEffectsChannel().getTelemetry();
      expect(telemetry, isA<DspTelemetry>());
      expect(telemetry.autoDegradedStages, 0);
    });
  });
}
