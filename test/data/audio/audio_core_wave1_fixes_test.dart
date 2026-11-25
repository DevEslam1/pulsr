import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/constants/channels.dart';
import 'package:pulsr/core/telemetry/dsp_reliability_tracker.dart';
import 'package:pulsr/data/audio/audio_effects_channel.dart';
import 'package:pulsr/data/audio/dsp_chain_validator.dart';
import 'package:pulsr/data/audio/native_dsd_file_source.dart';
import 'package:pulsr/data/audio/native_dsd_producer.dart';
import 'package:pulsr/data/audio/playback_queue_state_machine.dart';
import 'package:pulsr/data/audio/silence_skip_controller.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/data/services/usb_exclusive_service.dart';
import 'package:pulsr/domain/models/abx_session.dart';
import 'package:pulsr/domain/models/dsp_telemetry.dart';
import 'package:pulsr/features/player/cubit/abx_cubit.dart';
import 'package:pulsr/features/player/cubit/dsp_telemetry_cubit.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _ThrowingFileSource implements NativeDsdFileSource {
  @override
  Future<NativeDsdChunk?> readChunk(int maxBytes) async {
    throw const FileSystemException('USB storage unmounted');
  }

  @override
  Future<void> close() async {}

  @override
  int get totalBytes => 4096;

  @override
  int get position => 0;

  @override
  bool get isClosed => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoopUsbService extends UsbExclusiveService {
  _NoopUsbService() : super.forTest();

  @override
  Future<bool> writeDsd(Uint8List left, Uint8List right,
          {int producerId = 0}) async =>
      true;

  @override
  Future<bool> stopStreaming() async => true;
}

class _MockEffectsChannel extends Mock implements AudioEffectsChannel {}

SongsTableData _song(int id) => SongsTableData(
      id: id,
      title: 'Track $id',
      artist: 'Artist',
      album: 'Album',
      path: '/music/$id.flac',
      durationMs: 180000,
      isFavorite: false,
      playCount: 0,
      isMissing: false,
      lastPositionMs: 0,
      source: SongSource.local,
      isDownloaded: false,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel(PulsrChannels.audioEffects),
      null,
    );
  });

  test(
      'BUG-P1-4: NativeDsdProducer catches readChunk I/O error, transitions to error state, and signals fallback',
      () async {
    final producer = NativeDsdProducer(
      service: _NoopUsbService(),
      backpressureDelay: Duration.zero,
    );
    var endedCalled = false;
    producer.onPumpEnded = () => endedCalled = true;
    producer.prepareSource(
      _ThrowingFileSource(),
      dsdRate: 64,
      msbFirst: false,
    );

    await producer.startPumping(chunkSize: 512);

    expect(producer.state, NativeDsdProducerState.error);
    expect(producer.fallbackRequested, isTrue);
    expect(endedCalled, isTrue);
  });

  test('BUG-P2-7: AbxCubit close() waits for in-flight playCondition via mutex',
      () async {
    final events = <String>[];
    final firstSwitchGate = Completer<void>();

    final cubit = AbxCubit(
      switchCondition: (bypass) async {
        events.add(bypass ? 'bypass:start' : 'restore:start');
        if (bypass) {
          await firstSwitchGate.future;
        }
        events.add(bypass ? 'bypass:end' : 'restore:end');
      },
      isReady: () => true,
    );
    expect(cubit.start(), isTrue);

    final playFuture = cubit.playCondition(AbxStimulus.a);
    await Future<void>.delayed(Duration.zero);
    final closeFuture = cubit.close();
    await Future<void>.delayed(Duration.zero);

    // close() must wait for playCondition's switch to finish before restoring
    expect(events, ['bypass:start']);

    firstSwitchGate.complete();
    await Future.wait([playFuture, closeFuture]);

    expect(
        events, ['bypass:start', 'bypass:end', 'restore:start', 'restore:end']);
  });

  test(
      'BUG-P2-10: DspChainValidator.runDiagnosticSweep marks isSyntheticSelfCheck',
      () async {
    final channel = _MockEffectsChannel();
    when(() => channel.getDspDebugStatus()).thenAnswer((_) async => null);

    final report = await DspChainValidator.runDiagnosticSweep(channel: channel);
    expect(report.isSyntheticSelfCheck, isTrue);
    expect(report.toMap()['isSyntheticSelfCheck'], isTrue);
  });

  test(
      'BUG-P3-1: SilenceSkipController.load preserves saved sensitivity when disabled',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      SilenceSkipController.prefsEnabledKey: false,
      SilenceSkipController.prefsSensitivityKey: 82,
    });
    final controller = SilenceSkipController();
    await controller.load();
    expect(controller.enabled, isFalse);
    expect(controller.sensitivity, 82);
  });

  test(
      'BUG-P3-1: DspTelemetryCubit.refreshOnce emits even when listenerCount == 0',
      () async {
    final channel = _MockEffectsChannel();
    when(() => channel.getTelemetry()).thenAnswer(
      (_) async => const DspTelemetry(
        limiterGrDb: -3.5,
        dynEqGrDb: [0, 0, 0, 0, 0, 0, 0, 0],
        multibandGrDb: [0, 0, 0, 0],
        rollingRtf: 0.12,
        autoDegradedStages: 0,
      ),
    );

    final cubit = DspTelemetryCubit(channel: channel);
    expect(cubit.listenerCount, 0);
    await cubit.refreshOnce();
    expect(cubit.state.limiterGrDb, closeTo(-3.5, 0.001));
    await cubit.close();
  });

  test('BUG-P3-1: AudioEffectsChannel setter rejection is not double-counted',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    SharedPreferences.setMockInitialValues({});
    await DspReliabilityTracker.instance.resetCounters();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel(PulsrChannels.audioEffects),
      (call) async => false,
    );

    await expectLater(
      AudioEffectsChannel().setArbitraryEqEnabled(true),
      throwsA(isA<PlatformException>()),
    );
    expect(DspReliabilityTracker.instance.counters.nativeSetterRejection, 1);
  });

  test(
      'BUG-P3-1: PlaybackQueueStateMachine shuffle offset 2 returns distinct N+2 pick',
      () {
    final sm = PlaybackQueueStateMachine(
      initialSongs: [_song(1), _song(2), _song(3), _song(4), _song(5)],
      initialIndex: 0,
      random: math.Random(123),
    );
    final n1 = sm.peekNextIndex(offset: 1, shuffleModeEnabled: true);
    final n2 = sm.peekNextIndex(offset: 2, shuffleModeEnabled: true);
    expect(n1, isNotNull);
    expect(n2, isNotNull);
    expect(n2, isNot(equals(0)));
    expect(n2, isNot(equals(n1)));

    // Advancing once consumes n1 and promotes n2 to be the next shuffle pick
    final advanced1 = sm.getNextIndex(offset: 1, shuffleModeEnabled: true);
    expect(advanced1, n1);
    final nextAfter = sm.peekNextIndex(offset: 1, shuffleModeEnabled: true);
    expect(nextAfter, n2);
  });
}
