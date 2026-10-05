import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/data/audio/audio_effects_channel.dart';
import 'package:pulsr/domain/models/dsp_telemetry.dart';
import 'package:pulsr/features/player/cubit/dsp_telemetry_cubit.dart';

class MockAudioEffectsChannel extends Mock implements AudioEffectsChannel {}

void main() {
  test('a throwing channel backs off instead of spamming unhandled errors (B3)',
      () async {
    final channel = MockAudioEffectsChannel();
    when(() => channel.getTelemetry()).thenThrow(Exception('engine not ready'));

    final cubit = DspTelemetryCubit(
      channel: channel,
      pollingInterval: const Duration(milliseconds: 1),
    );
    cubit.subscribe();

    // Let several polls fail; an unhandled async error would fail this test.
    await Future<void>.delayed(const Duration(milliseconds: 25));

    expect(cubit.state, const DspTelemetry.zero());

    cubit.unsubscribe();
    await cubit.close();
  });

  test('a successful poll after failures resumes normal emission (B3)',
      () async {
    final channel = MockAudioEffectsChannel();
    var calls = 0;
    when(() => channel.getTelemetry()).thenAnswer((_) async {
      calls++;
      if (calls <= 3) throw Exception('flaky');
      return const DspTelemetry(
        limiterGrDb: -1.0,
        dynEqGrDb: [0, 0, 0, 0, 0, 0, 0, 0],
        multibandGrDb: [0, 0, 0, 0],
        rollingRtf: 0.2,
        autoDegradedStages: 0,
      );
    });

    final cubit = DspTelemetryCubit(
      channel: channel,
      pollingInterval: const Duration(milliseconds: 1),
    );
    cubit.subscribe();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    // Timer is parked after 3 failures; a manual refresh must recover.
    await cubit.refreshOnce();
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(cubit.state.limiterGrDb, -1.0);

    cubit.unsubscribe();
    await cubit.close();
  });

  test(
      'H-12: automatically recovers via retry timer after consecutive polling failures',
      () async {
    final channel = MockAudioEffectsChannel();
    var calls = 0;
    when(() => channel.getTelemetry()).thenAnswer((_) async {
      calls++;
      if (calls <= 3) throw Exception('engine transient error');
      return const DspTelemetry(
        limiterGrDb: -2.5,
        dynEqGrDb: [0, 0, 0, 0, 0, 0, 0, 0],
        multibandGrDb: [0, 0, 0, 0],
        rollingRtf: 0.15,
        autoDegradedStages: 0,
      );
    });

    final cubit = DspTelemetryCubit(
      channel: channel,
      pollingInterval: const Duration(milliseconds: 1),
      retryInterval: const Duration(milliseconds: 20),
    );

    cubit.subscribe();

    // 1. Initial 3 failures park the timer and schedule retry
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(cubit.consecutiveFailures, greaterThanOrEqualTo(3));
    expect(cubit.isRetryTimerActive, isTrue);

    // 2. Wait for retry timer to trigger recovery
    await Future<void>.delayed(const Duration(milliseconds: 35));

    // 3. Telemetry recovered automatically without manual refresh
    expect(cubit.state.limiterGrDb, equals(-2.5));
    expect(cubit.isPollingTimerActive, isTrue);
    expect(cubit.isRetryTimerActive, isFalse);

    // 4. Unsubscribe cleans up all timers
    cubit.unsubscribe();
    expect(cubit.isPollingTimerActive, isFalse);
    expect(cubit.isRetryTimerActive, isFalse);

    await cubit.close();
  });

  test(
      'M-25: listenerCount never drops below 0 and excess unsubscribes are idempotent',
      () async {
    final channel = MockAudioEffectsChannel();
    when(() => channel.getTelemetry())
        .thenAnswer((_) async => const DspTelemetry.zero());

    final cubit = DspTelemetryCubit(
      channel: channel,
      pollingInterval: const Duration(milliseconds: 100),
    );

    expect(cubit.listenerCount, 0);

    // Excess unsubscribes when listenerCount is 0
    cubit.unsubscribe();
    cubit.unsubscribe();
    cubit.unsubscribe();
    expect(cubit.listenerCount, 0);

    // Exactly one subscribe sets listenerCount to 1 and starts polling
    cubit.subscribe();
    expect(cubit.listenerCount, 1);
    expect(cubit.isPollingTimerActive, isTrue);

    // Unsubscribing decrements to 0 and stops polling
    cubit.unsubscribe();
    expect(cubit.listenerCount, 0);
    expect(cubit.isPollingTimerActive, isFalse);

    // Further unsubscribe remains at 0
    cubit.unsubscribe();
    expect(cubit.listenerCount, 0);

    await cubit.close();
  });
}
