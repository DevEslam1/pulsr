// test/core/telemetry/dsp_reliability_tracker_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pulsr/core/telemetry/dsp_reliability_tracker.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    DspReliabilityTracker.resetInstanceForTesting();
  });

  group('DspReliabilityCounters', () {
    test('default zero counters', () {
      const counters = DspReliabilityCounters.zero();
      expect(counters.nativeSetterRejection, 0);
      expect(counters.bridgeTimeoutFailure, 0);
      expect(counters.routeResyncFailure, 0);
      expect(counters.sessionReattachFailure, 0);
      expect(counters.autoDegradeActivation, 0);
      expect(counters.autoDegradeRecovery, 0);
      expect(counters.lastRedactedError, isNull);
      expect(counters.lastErrorTimestamp, isNull);
    });

    test('clamping to maxCounterValue', () {
      var counters = const DspReliabilityCounters.zero();
      counters = counters.copyWith(
        nativeSetterRejection: 2000000,
        bridgeTimeoutFailure: -5,
      );
      expect(counters.nativeSetterRejection,
          DspReliabilityCounters.maxCounterValue);
      expect(counters.bridgeTimeoutFailure, 0);
    });

    test('serialization roundtrip', () {
      final now = DateTime.now();
      final original = DspReliabilityCounters(
        nativeSetterRejection: 5,
        bridgeTimeoutFailure: 2,
        routeResyncFailure: 1,
        sessionReattachFailure: 3,
        autoDegradeActivation: 4,
        autoDegradeRecovery: 2,
        lastRedactedError: 'Test error',
        lastErrorTimestamp: now,
      );

      final map = original.toMap();
      final restored = DspReliabilityCounters.fromMap(map);

      expect(restored.nativeSetterRejection, 5);
      expect(restored.bridgeTimeoutFailure, 2);
      expect(restored.routeResyncFailure, 1);
      expect(restored.sessionReattachFailure, 3);
      expect(restored.autoDegradeActivation, 4);
      expect(restored.autoDegradeRecovery, 2);
      expect(restored.lastRedactedError, 'Test error');
      expect(restored.lastErrorTimestamp?.toIso8601String(),
          now.toIso8601String());
    });

    test('safe deserialization with invalid data', () {
      final invalidMap = <String, dynamic>{
        'nativeSetterRejection': 'not-a-number',
        'bridgeTimeoutFailure': null,
        'lastErrorTimestamp': 'invalid-date',
      };
      final restored = DspReliabilityCounters.fromMap(invalidMap);
      expect(restored.nativeSetterRejection, 0);
      expect(restored.bridgeTimeoutFailure, 0);
      expect(restored.lastErrorTimestamp, isNull);
    });

    test('non-string persisted last error is coerced instead of failing', () {
      final restored = DspReliabilityCounters.fromMap(
          <String, dynamic>{'lastRedactedError': 42});
      expect(restored.lastRedactedError, '42');
    });
  });

  group('DspReliabilityTracker', () {
    test('redacts sensitive information in error messages', () {
      expect(
        DspReliabilityTracker.redactErrorMessage(
            'Error reading /data/user/0/com.pulsr.music/files/secret.key'),
        'Error reading [REDACTED_APP_PATH]',
      );
      expect(
        DspReliabilityTracker.redactErrorMessage(
            'Failed at /storage/emulated/0/Music/track.mp3'),
        'Failed at [REDACTED_STORAGE_PATH]',
      );
      expect(
        DspReliabilityTracker.redactErrorMessage(
            r'Crash in C:\Users\Admin\AppData\Local\secret'),
        'Crash in [REDACTED_LOCAL_PATH]',
      );
      expect(
        DspReliabilityTracker.redactErrorMessage(
            'Failed with token=secret_token_12345&other=1'),
        'Failed with token=[REDACTED]&other=1',
      );
    });

    test('records rejections and failures properly', () async {
      final tracker = DspReliabilityTracker.instance;
      await tracker.ensureInitialized();

      tracker.recordNativeSetterRejection('setEqBandGain', 'Internal error');
      expect(tracker.counters.nativeSetterRejection, 1);
      expect(tracker.counters.lastRedactedError,
          contains('Native setter setEqBandGain rejected'));

      tracker.recordBridgeTimeoutFailure('resyncForTrack', 'Timeout after 5s');
      expect(tracker.counters.bridgeTimeoutFailure, 1);

      tracker.recordRouteResyncFailure('Route change failed');
      expect(tracker.counters.routeResyncFailure, 1);

      tracker.recordSessionReattachFailure('AudioTrack dead');
      expect(tracker.counters.sessionReattachFailure, 1);

      tracker.recordAutoDegradeActivation(0x01);
      expect(tracker.counters.autoDegradeActivation, 1);

      tracker.recordAutoDegradeRecovery();
      expect(tracker.counters.autoDegradeRecovery, 1);

      await tracker.resetCounters();
      expect(tracker.counters.nativeSetterRejection, 0);
      expect(tracker.counters.bridgeTimeoutFailure, 0);
      expect(tracker.counters.routeResyncFailure, 0);
      expect(tracker.counters.sessionReattachFailure, 0);
      expect(tracker.counters.autoDegradeActivation, 0);
      expect(tracker.counters.autoDegradeRecovery, 0);
      expect(tracker.counters.lastRedactedError, isNull);
    });

    test('handles corrupt preferences by falling back to zero', () async {
      SharedPreferences.setMockInitialValues({
        DspReliabilityTracker.prefsKey: '{corrupt json...',
      });
      DspReliabilityTracker.resetInstanceForTesting();
      final tracker = DspReliabilityTracker.instance;
      await tracker.ensureInitialized();

      expect(tracker.counters.nativeSetterRejection, 0);
      expect(tracker.counters.bridgeTimeoutFailure, 0);
    });
  });
}
