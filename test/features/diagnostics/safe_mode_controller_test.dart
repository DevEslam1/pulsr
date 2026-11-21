// test/features/diagnostics/safe_mode_controller_test.dart
//
// State-machine contract: the third consecutive failure trips the fallback, the
// fallback switches the risky output path off, and a success or reset clears it.
// A recovery also drops the stored reason, the persisted DSD token stays a
// String every reader parses, and a partly applied record never leaves a
// failure counter behind.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/constants/prefs_keys.dart';
import 'package:pulsr/data/audio/dsd_transport_resolver.dart';
import 'package:pulsr/features/diagnostics/safe_mode_controller.dart';
import 'package:pulsr/features/settings/cubit/settings_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// In-memory [SharedPreferences] stand-in that rejects (or throws on) writes to
/// one key, so a partly applied safe-mode record can be reproduced.
///
/// Only the members [SafeModeController] touches are forwarded; anything else is
/// unreachable from these tests.
class _RejectingPrefs implements SharedPreferences {
  _RejectingPrefs(
    this._inner, {
    required this.rejectKey,
    this.throwOnReject = false,
  });

  final SharedPreferences _inner;
  final String rejectKey;
  final bool throwOnReject;
  int rejections = 0;

  bool _reject(String key) {
    if (key != rejectKey) return false;
    rejections++;
    if (throwOnReject) throw StateError('preferences write rejected: $key');
    return true;
  }

  @override
  Future<bool> setString(String key, String value) async =>
      _reject(key) ? false : await _inner.setString(key, value);

  @override
  Future<bool> setInt(String key, int value) async =>
      _reject(key) ? false : await _inner.setInt(key, value);

  @override
  Future<bool> setBool(String key, bool value) async =>
      _reject(key) ? false : await _inner.setBool(key, value);

  @override
  Future<bool> remove(String key) async =>
      _reject(key) ? false : await _inner.remove(key);

  @override
  bool containsKey(String key) => _inner.containsKey(key);

  @override
  Object? get(String key) => _inner.get(key);

  @override
  bool? getBool(String key) => _inner.getBool(key);

  @override
  int? getInt(String key) => _inner.getInt(key);

  @override
  String? getString(String key) => _inner.getString(key);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late SharedPreferences prefs;
  late SafeModeController controller;
  late List<SafeModeEvent> events;
  late StreamSubscription<SafeModeEvent> subscription;

  setUp(() async {
    SharedPreferences.resetStatic();
    SharedPreferences.setMockInitialValues(<String, Object>{
      PrefsKeys.aaudioOutputEnabled: true,
      PrefsKeys.usbHardwareVolumeEnabled: true,
      PrefsKeys.dsdOutputMode: 'dop',
      PrefsKeys.strictBitPerfect: true,
    });
    prefs = await SharedPreferences.getInstance();
    controller = SafeModeController(
      prefs: prefs,
      clock: () => DateTime.utc(2026, 1, 2, 3, 4, 5),
    );
    events = <SafeModeEvent>[];
    subscription = controller.events.listen(events.add);
  });

  tearDown(() async {
    await subscription.cancel();
    await controller.dispose();
  });

  test('trips only on the third consecutive failure', () async {
    await controller.recordFailure('Pixel 8', 'sink underrun');
    await controller.recordFailure('Pixel 8', 'sink underrun');

    expect(controller.consecutiveFailures('Pixel 8'), 2);
    expect(controller.shouldFallback('Pixel 8'), isFalse);

    await controller.recordFailure('Pixel 8', 'sink underrun');
    await Future<void>.delayed(Duration.zero);

    expect(controller.shouldFallback('Pixel 8'), isTrue);
    expect(
      events.map((event) => event.type).toList(),
      <SafeModeEventType>[
        SafeModeEventType.failure,
        SafeModeEventType.failure,
        SafeModeEventType.thresholdReached,
      ],
    );
  });

  test('tracks each device separately and derives safe prefs keys', () async {
    for (var i = 0; i < 3; i++) {
      await controller.recordFailure('Pixel 8', 'sink underrun');
    }

    expect(controller.shouldFallback('Pixel 8'), isTrue);
    expect(controller.shouldFallback('WH-1000XM5'), isFalse);
    expect(
      SafeModeController.failuresKey('Pixel 8'),
      'safe_mode_failures_pixel_8',
    );
  });

  test('a success clears the consecutive counter', () async {
    await controller.recordFailure('Pixel 8', 'sink underrun');
    await controller.recordFailure('Pixel 8', 'sink underrun');

    await controller.recordSuccess('Pixel 8');

    expect(controller.consecutiveFailures('Pixel 8'), 0);
    expect(controller.shouldFallback('Pixel 8'), isFalse);
  });

  test('a recovery also clears the stored failure reason', () async {
    await controller.recordFailure('Pixel 8', 'sink underrun -5');
    expect(controller.lastFailureReason('Pixel 8'), 'sink underrun -5');

    await controller.recordSuccess('Pixel 8');

    expect(controller.consecutiveFailures('Pixel 8'), 0);
    expect(controller.lastFailureReason('Pixel 8'), isNull);
    expect(
      prefs.containsKey(SafeModeController.reasonKey('Pixel 8')),
      isFalse,
    );
  });

  test('a recovery with no counter still drops a stale reason', () async {
    await prefs.setString(
      SafeModeController.reasonKey('Pixel 8'),
      'stale reason',
    );

    await controller.recordSuccess('Pixel 8');

    expect(
      prefs.containsKey(SafeModeController.reasonKey('Pixel 8')),
      isFalse,
    );
  });

  test('applyFallback turns off the risky output path', () async {
    for (var i = 0; i < 3; i++) {
      await controller.recordFailure('Pixel 8', 'sink underrun');
    }

    final description = await controller.applyFallback('Pixel 8');
    await Future<void>.delayed(Duration.zero);

    expect(prefs.getBool(PrefsKeys.aaudioOutputEnabled), isFalse);
    expect(prefs.getBool(PrefsKeys.usbHardwareVolumeEnabled), isFalse);
    expect(prefs.getString(PrefsKeys.dsdOutputMode), 'pcm');
    expect(prefs.getBool(PrefsKeys.strictBitPerfect), isFalse);
    expect(controller.isFallbackActive('Pixel 8'), isTrue);
    expect(description, contains('AAudio'));
    expect(description, contains('3 consecutive'));
    expect(
      events.last.type,
      SafeModeEventType.fallbackApplied,
    );
  });

  test('reset clears counters, the active flag and the reason', () async {
    for (var i = 0; i < 3; i++) {
      await controller.recordFailure('Pixel 8', 'sink underrun');
    }
    await controller.applyFallback('Pixel 8');

    await controller.reset('Pixel 8');
    await Future<void>.delayed(Duration.zero);

    expect(controller.consecutiveFailures('Pixel 8'), 0);
    expect(controller.shouldFallback('Pixel 8'), isFalse);
    expect(controller.isFallbackActive('Pixel 8'), isFalse);
    expect(controller.lastFailureReason('Pixel 8'), isNull);
    expect(
      prefs.containsKey(SafeModeController.reasonKey('Pixel 8')),
      isFalse,
    );
    expect(events.last.type, SafeModeEventType.reset);
  });

  test('keeps the last failure reason and truncates long ones', () async {
    await controller.recordFailure('Pixel 8', 'sink underrun -5');

    expect(controller.lastFailureReason('Pixel 8'), 'sink underrun -5');

    await controller.recordFailure('Pixel 8', 'x' * 400);

    expect(controller.lastFailureReason('Pixel 8')!.length, 200);
  });

  test('reset restores the pre-fallback output settings', () async {
    final description = await controller.applyFallback('Pixel 8');
    expect(description, contains('AAudio'));

    expect(prefs.getBool(PrefsKeys.aaudioOutputEnabled), isFalse);
    expect(prefs.getString(PrefsKeys.dsdOutputMode), 'pcm');

    await controller.reset('Pixel 8');

    expect(prefs.getBool(PrefsKeys.aaudioOutputEnabled), isTrue);
    expect(prefs.getBool(PrefsKeys.usbHardwareVolumeEnabled), isTrue);
    expect(prefs.getString(PrefsKeys.dsdOutputMode), 'dop');
    expect(prefs.getBool(PrefsKeys.strictBitPerfect), isTrue);
    expect(
      prefs.containsKey(SafeModeController.snapshotKey('Pixel 8')),
      isFalse,
    );
  });

  test('a repeated fallback never replaces the original snapshot', () async {
    await controller.applyFallback('Pixel 8');
    // Simulate the user turning AAudio back on before the fallback is applied
    // a second time for the same device.
    await prefs.setBool(PrefsKeys.aaudioOutputEnabled, true);

    await controller.applyFallback('Pixel 8');
    await controller.reset('Pixel 8');

    expect(prefs.getBool(PrefsKeys.aaudioOutputEnabled), isTrue);
  });

  test('reset restores an originally absent setting to absent', () async {
    SharedPreferences.resetStatic();
    SharedPreferences.setMockInitialValues(<String, Object>{
      PrefsKeys.aaudioOutputEnabled: true,
      PrefsKeys.dsdOutputMode: 'dop',
    });
    final fresh = await SharedPreferences.getInstance();
    final local = SafeModeController(prefs: fresh);
    addTearDown(local.dispose);

    await local.applyFallback('Pixel 8');
    expect(
      fresh.containsKey(PrefsKeys.usbHardwareVolumeEnabled),
      isTrue,
    );

    await local.reset('Pixel 8');
    expect(
      fresh.containsKey(PrefsKeys.usbHardwareVolumeEnabled),
      isFalse,
    );
    expect(
      fresh.containsKey(PrefsKeys.strictBitPerfect),
      isFalse,
    );
  });

  test('apply and reset notify the settings reloader', () async {
    var reloads = 0;
    final local = SafeModeController(
      prefs: prefs,
      reloadSettings: () async => reloads++,
    );
    addTearDown(local.dispose);

    await local.applyFallback('Pixel 8');
    expect(reloads, 1);

    await local.reset('Pixel 8');
    expect(reloads, 2);
  });

  test('the DSD fallback persists a String every reader parses', () async {
    await controller.applyFallback('Pixel 8');

    // Type contract: the typed getters cast blindly, so the persisted value has
    // to stay a String. An enum or bool written here would throw in both the
    // settings loader and the playback resolver.
    final stored = prefs.get(PrefsKeys.dsdOutputMode);
    expect(stored, isA<String>());
    final restored = stored! as String;
    expect(restored, DsdOutputMode.pcm.name);

    // SettingsCubit.load() resolves the token by enum name.
    expect(
      DsdOutputMode.values.firstWhere(
        (mode) => mode.name == restored,
        orElse: () => DsdOutputMode.dop,
      ),
      DsdOutputMode.pcm,
    );

    // The playback path hands the same token to the transport resolver.
    final plan = resolveDsdTransport(
      mode: restored,
      bitPerfectActive: true,
      dopCapable: true,
      nativeCapable: true,
      dsdRateMultiple: 64,
    );
    expect(plan.requested, DsdTransport.pcm);
    expect(plan.transport, DsdTransport.pcm);
    expect(plan.reason, DsdTransportReason.userPcm);
  });

  test('every DsdOutputMode name is a token both readers understand', () async {
    for (final mode in DsdOutputMode.values) {
      await prefs.setString(PrefsKeys.dsdOutputMode, mode.name);

      final stored = prefs.getString(PrefsKeys.dsdOutputMode);
      expect(stored, mode.name);
      expect(
        DsdOutputMode.values.firstWhere(
          (candidate) => candidate.name == stored,
          orElse: () => DsdOutputMode.dop,
        ),
        mode,
      );

      final plan = resolveDsdTransport(
        mode: stored!,
        bitPerfectActive: true,
        dopCapable: true,
        nativeCapable: true,
        dsdRateMultiple: 64,
      );
      expect(plan.requested.name, mode.name);
    }
  });

  group('a partly applied failure record', () {
    SafeModeController buildController(SharedPreferences failing) {
      final local = SafeModeController(
        prefs: failing,
        clock: () => DateTime.utc(2026, 1, 2, 3, 4, 5),
      );
      addTearDown(local.dispose);
      return local;
    }

    test('leaves no counter when the reason write is rejected', () async {
      final failing = _RejectingPrefs(
        prefs,
        rejectKey: SafeModeController.reasonKey('Pixel 8'),
      );
      final local = buildController(failing);

      await expectLater(
        local.recordFailure('Pixel 8', 'sink underrun'),
        throwsA(isA<SafeModeError>()),
      );

      expect(failing.rejections, 1);
      expect(
        prefs.containsKey(SafeModeController.failuresKey('Pixel 8')),
        isFalse,
      );
      expect(
        prefs.containsKey(SafeModeController.reasonKey('Pixel 8')),
        isFalse,
      );
    });

    test('keeps the earlier counter and reason when the stamp fails', () async {
      await prefs.setInt(SafeModeController.failuresKey('Pixel 8'), 2);
      await prefs.setString(
        SafeModeController.reasonKey('Pixel 8'),
        'earlier failure',
      );
      final failing = _RejectingPrefs(
        prefs,
        rejectKey: SafeModeController.updatedKey('Pixel 8'),
      );
      final local = buildController(failing);

      await expectLater(
        local.recordFailure('Pixel 8', 'sink underrun'),
        throwsA(isA<SafeModeError>()),
      );

      expect(prefs.getInt(SafeModeController.failuresKey('Pixel 8')), 2);
      expect(
        prefs.getString(SafeModeController.reasonKey('Pixel 8')),
        'earlier failure',
      );
      expect(
        prefs.containsKey(SafeModeController.updatedKey('Pixel 8')),
        isFalse,
      );
    });

    test('rolls the reason and stamp back when the counter fails', () async {
      final failing = _RejectingPrefs(
        prefs,
        rejectKey: SafeModeController.failuresKey('Pixel 8'),
      );
      final local = buildController(failing);

      await expectLater(
        local.recordFailure('Pixel 8', 'sink underrun'),
        throwsA(isA<SafeModeError>()),
      );

      expect(
        prefs.containsKey(SafeModeController.failuresKey('Pixel 8')),
        isFalse,
      );
      expect(
        prefs.containsKey(SafeModeController.reasonKey('Pixel 8')),
        isFalse,
      );
      expect(
        prefs.containsKey(SafeModeController.updatedKey('Pixel 8')),
        isFalse,
      );
    });

    test('treats a throwing preferences write as a rejection', () async {
      final failing = _RejectingPrefs(
        prefs,
        rejectKey: SafeModeController.reasonKey('Pixel 8'),
        throwOnReject: true,
      );
      final local = buildController(failing);

      await expectLater(
        local.recordFailure('Pixel 8', 'sink underrun'),
        throwsA(isA<SafeModeError>()),
      );

      expect(
        prefs.containsKey(SafeModeController.failuresKey('Pixel 8')),
        isFalse,
      );
    });

    test('SafeModeController concurrent recordFailure calls preserving exact count', () async {
      final futures = <Future<void>>[];
      for (var i = 0; i < 10; i++) {
        futures.add(controller.recordFailure('Pixel 8', 'failure-$i'));
      }
      await Future.wait(futures);

      expect(prefs.getInt(SafeModeController.failuresKey('Pixel 8')), 10);
      expect(controller.consecutiveFailures('Pixel 8'), 10);
    });
  });
}
