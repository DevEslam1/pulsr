// test/data/audio/bluetooth_edge_case_harness_test.dart
//
// Bluetooth / edge-case regression harness for the audio hardening program.
// It exercises the four wiring layers touched here — route, interruption,
// settings persistence and telemetry — without a device or a real player:
//
//   * route change  -> session survives, route is recorded, no speaker fallback
//   * Bluetooth     -> stays playing and the codec/rate are observable
//   * interruption  -> duck/pause/unknown/becoming-noisy contracts + resume pref
//   * settings      -> persisted and restored across a simulated restart
//   * dither        -> engine sees the BT route and the agreed target depth
//
// Everything here is pure Dart + mocked platform channels, so it is
// CI-runnable on any host (see tool/run_audio_suites.sh).
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/constants/prefs_keys.dart';
import 'package:pulsr/core/telemetry/audio_session_log.dart';
import 'package:pulsr/data/audio/audio_session_id_router.dart';
import 'package:pulsr/data/audio/ducking_controller.dart';
import 'package:pulsr/data/audio/equalizer_manager.dart';
import 'package:pulsr/data/audio/output_format_negotiation.dart';
import 'package:pulsr/data/scanner/media_scanner_service.dart';
import 'package:pulsr/domain/models/audio_output_info.dart';
import 'package:pulsr/features/settings/cubit/settings_cubit.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockMediaScannerService extends Mock implements MediaScannerService {}

const AudioOutputInfo _btInfo = AudioOutputInfo(
  deviceName: 'LDAC Buds',
  isUsbDac: false,
  sampleRate: 96000,
  bitDepth: 24,
  isBitPerfectActive: false,
  activeDeviceType: 'bluetooth',
  isBluetooth: true,
  btCodecName: 'LDAC',
  btSampleRateHz: 96000,
  btBitDepth: 24,
);

const AudioOutputInfo _speakerInfo = AudioOutputInfo(
  deviceName: 'Phone speaker',
  isUsbDac: false,
  sampleRate: 48000,
  bitDepth: 16,
  isBitPerfectActive: false,
  activeDeviceType: 'builtin',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late AudioSessionLog log;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('bt_edge_harness');
    log = AudioSessionLog(
      directoryProvider: () async => tempDir,
      enabledProvider: () async => true,
      clock: DateTime.now,
    );
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  group('route change -> engine behaves, no speaker fallback', () {
    test('Bluetooth route classifies as bluetooth, never speaker', () {
      expect(
          AudioSessionLog.routeTypeForInfo(_btInfo), AudioRouteType.bluetooth);
      expect(AudioSessionLog.routeTypeForInfo(_speakerInfo),
          AudioRouteType.speaker);
      expect(OutputRoute.fromOutputInfo(_btInfo), OutputRoute.bluetooth);
    });

    test('a live session survives a speaker -> Bluetooth route change',
        () async {
      await log.startSession(
        trackId: '77',
        trackTitle: 'Route Track',
        routeType: AudioSessionLog.routeTypeForInfo(_speakerInfo),
        sampleRate: _speakerInfo.sampleRate,
        bitDepth: _speakerInfo.bitDepth,
      );
      expect(log.hasActiveSession, isTrue);

      // devicesStream fires: mirror the new route exactly as the handler does.
      await log.updateOutputInfo(
        routeType: AudioSessionLog.routeTypeForInfo(_btInfo),
        bluetoothCodec: _btInfo.btCodecName,
        sampleRate: _btInfo.sampleRate,
        bitDepth: _btInfo.bitDepth,
      );

      expect(log.activeSessionId, isNotNull,
          reason: 'a route change must not end/pause the session');
      await log.endSession();

      final record = (await log.readAll()).single;
      expect(record.routeType, AudioRouteType.bluetooth);
      expect(record.routeChanges, hasLength(1));
      expect(record.routeChanges.single.from, AudioRouteType.speaker);
      expect(record.routeChanges.single.to, AudioRouteType.bluetooth);
      expect(record.interruptions, isEmpty,
          reason: 'a route change is not a playback interruption');
    });

    test('router resync keeps accepting session ids after a route change',
        () async {
      final seen = <int>[];
      final router = AudioSessionIdRouter(onSessionChanged: seen.add);

      router.handleRouteChanged();
      router.handleSessionId(101);
      await router.idleForTest;
      router.handleRouteChanged();
      router.handleSessionId(202);
      await router.idleForTest;

      expect(router.currentSessionId, 202);
      expect(seen, [101, 202]);
    });
  });

  group('interruption -> correct duck/pause/unknown/becoming-noisy contract',
      () {
    test('every interruption kind is recorded with a stable wire value',
        () async {
      await log.startSession(trackId: '5', trackTitle: 'Interrupted');
      await log.recordInterruption(AudioInterruptionKind.duck);
      await log.recordInterruption(AudioInterruptionKind.pause);
      await log.recordInterruption(AudioInterruptionKind.unknown);
      await log.recordInterruption(AudioInterruptionKind.becomingNoisy);
      await log.endSession();

      final record = (await log.readAll()).single;
      expect(
        record.interruptions.map((e) => e.type),
        [
          AudioInterruptionKind.duck,
          AudioInterruptionKind.pause,
          AudioInterruptionKind.unknown,
          AudioInterruptionKind.becomingNoisy,
        ],
      );
      // becoming-noisy is the one multi-word wire value; round-trips as such.
      final json = record.interruptions.last.toJson();
      expect(json['type'], 'becoming-noisy');
      expect(AudioInterruptionKind.fromWire('becoming-noisy'),
          AudioInterruptionKind.becomingNoisy);
      expect(AudioInterruptionKind.fromWire('garbage'),
          AudioInterruptionKind.unknown);
    });

    test('ducking mode decides duck vs pause vs ignore', () {
      final controller = DuckingController(mode: DuckingMode.duck, level: 0.3);
      expect(controller.shouldDuck, isTrue);
      expect(controller.shouldPause, isFalse);
      expect(controller.shouldIgnore, isFalse);
      expect(controller.duckedVolume(1.0), closeTo(0.3, 1e-9));

      controller.setMode(DuckingMode.pause);
      expect(controller.shouldPause, isTrue);
      controller.setMode(DuckingMode.ignore);
      expect(controller.shouldIgnore, isTrue);
      // Level is clamped to a sane audible floor.
      controller.setLevel(0.0);
      expect(controller.duckFactor, 0.05);
      controller.setLevel(2.0);
      expect(controller.duckFactor, 1.0);
    });

    test('ducking mode persists and restores across a restart', () async {
      final first = DuckingController(mode: DuckingMode.pause, level: 0.5);
      await first.persist();

      final restored = DuckingController();
      await restored.load();
      expect(restored.mode, DuckingMode.pause);
      expect(restored.level, 0.5);
    });
  });

  group('settings persistence / restore across restart', () {
    late MockMediaScannerService scanner;

    setUp(() => scanner = MockMediaScannerService());

    test('output-format negotiation defaults ON and persists OFF/ON',
        () async {
      final cubit = SettingsCubit(scannerService: scanner);
      await pumpEventQueue();
      expect(cubit.state.outputFormatNegotiationEnabled, isTrue,
          reason: 'hi-res-first: negotiation is on by default');

      await cubit.setOutputFormatNegotiationEnabled(false);
      expect(cubit.state.outputFormatNegotiationEnabled, isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(PrefsKeys.outputFormatNegotiationEnabled), isFalse);

      await cubit.setOutputFormatNegotiationEnabled(true);
      expect(prefs.getBool(PrefsKeys.outputFormatNegotiationEnabled), isTrue,
          reason: 're-enabling must persist on disk');
      await cubit.close();
    });

    test('resume-after-interruption and session-log flags survive a restart',
        () async {
      final first = SettingsCubit(scannerService: scanner);
      await pumpEventQueue();
      // Documented default: resume after a transient interruption.
      expect(first.state.resumeAfterInterruption, isTrue);
      await first.setResumeAfterInterruption(false);
      await first.setSessionLogEnabled(false);
      await first.close();

      // "Restart": a fresh cubit reads the same on-disk prefs.
      final second = SettingsCubit(scannerService: scanner);
      await pumpEventQueue();
      expect(second.state.resumeAfterInterruption, isFalse);
      expect(second.state.sessionLogEnabled, isFalse);
      await second.close();
    });
  });

  group('Bluetooth codec / rate observability (AudioSessionLog)', () {
    test('records codec, negotiated rate/depth and bitrate per session',
        () async {
      await log.startSession(
        trackId: '900',
        trackTitle: 'BT Track',
        routeType: AudioRouteType.bluetooth,
        bluetoothCodec: _btInfo.btCodecName,
        sampleRate: _btInfo.sampleRate,
        bitDepth: _btInfo.bitDepth,
        bitrateKbps: 990,
      );
      await log.endSession();

      final file = File('${tempDir.path}/${AudioSessionLog.defaultFileName}');
      expect(await file.exists(), isTrue,
          reason: 'a session record is persisted');

      final record = (await log.readAll()).single;
      expect(record.routeType, AudioRouteType.bluetooth);
      expect(record.bluetoothCodec, 'LDAC');
      expect(record.sampleRate, 96000);
      expect(record.bitDepth, 24);
      expect(record.bitrateKbps, 990);
    });
  });

  group('dither wiring mirrors the live route + agreed depth', () {
    const channel = MethodChannel('com.pulsr.music/audio_effects');
    final calls = <MethodCall>[];

    setUp(() {
      calls.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return true;
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('default dither depth is 16-bit on both sides of the bridge', () {
      final manager = EqualizerManager();
      expect(manager.ditherTargetBitDepth, 16);
    });

    test('setDither pushes enable + depth + Bluetooth route to native',
        () async {
      final manager = EqualizerManager();
      manager.isBluetoothRoute = true;
      await manager.setDither(true, targetBitDepth: 24);

      final call = calls.lastWhere((c) => c.method == 'setDitherParams');
      expect(call.arguments['enabled'], isTrue);
      expect(call.arguments['targetBitDepth'], 24);
      expect(call.arguments['isBluetooth'], isTrue,
          reason:
              'native skips dither on BT — the route flag must be truthful');

      // Let the 350 ms debounced preference write flush so no timer is left
      // pending at test teardown.
      await Future<void>.delayed(const Duration(milliseconds: 400));
    });
  });
}
