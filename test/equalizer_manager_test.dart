// test/equalizer_manager_test.dart
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/audio/audio_session_id_router.dart';
import 'package:pulsr/data/audio/equalizer_manager.dart';
import 'package:pulsr/domain/models/audio_effects_config.dart';
import 'package:pulsr/domain/models/eq_preset.dart';
import 'package:pulsr/domain/models/headphone_profile.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final List<MethodCall> channelCalls = [];

  setUp(() {
    channelCalls.clear();
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.pulsr.music/audio_effects'),
      (MethodCall call) async {
        channelCalls.add(call);
        switch (call.method) {
          case 'isVirtualizerSupported':
          case 'isDynamicsSupported':
          case 'isVolumeBoostSupported':
          case 'isBassBoostSupported':
          case 'setAudioSessionId':
          case 'setVolumeBoost':
          case 'setBassBoost':
          case 'setVirtualizerEnabled':
          case 'setVirtualizerStrength':
          case 'setDynamicsPreset':
          case 'setSpatializerEnabled':
          case 'setEqEnabled':
          case 'setEqBands':
          case 'setEqBandGain':
          case 'setEqBandGains':
          case 'setEqPreamp':
          case 'releaseEffects':
            return true;
          case 'getSpatializerState':
            return {
              'isSupported': true,
              'isEnabled': false,
              'isHeadTrackerAvailable': true,
            };
          default:
            return null;
        }
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.pulsr.music/audio_effects'),
      null,
    );
  });

  const testProfile = HeadphoneProfile(
    id: 'test_id',
    name: 'Test Headphone',
    brand: 'TestBrand',
    model: 'ModelX',
    category: 'Over-Ear',
    gains: [1.0, 2.0, 3.0, 4.0, 5.0, 4.0, 3.0, 2.0, 1.0, 0.0],
    bassBoost: 0.35,
    preampGain: -2.5,
  );

  const testProfileWith4dBPreamp = HeadphoneProfile(
    id: 'test_preamp_4db',
    name: 'High Preamp Headphone',
    brand: 'TestBrand',
    model: 'ModelHot',
    category: 'In-Ear',
    gains: [2.0, 2.0, 2.0, 2.0, 2.0, 2.0, 2.0, 2.0, 2.0, 2.0],
    bassBoost: 0.2,
    preampGain: 4.0,
  );

  group('EqualizerManager Hardened DSP Tests', () {
    test('setBandGain clamps to -15..+15 dB range', () async {
      final manager = EqualizerManager();
      await manager.setBandGain(0, 20.0);
      expect(manager.currentPreset.gains[0], 15.0);

      await manager.setBandGain(0, -25.0);
      expect(manager.currentPreset.gains[0], -15.0);
    });

    test(
        'setBandGain clears headphone profile and resets profile bass boost and preamp',
        () async {
      final manager = EqualizerManager();
      await manager.applyHeadphoneProfile(testProfile);
      expect(manager.selectedHeadphoneProfile, isNotNull);
      expect(manager.currentPreset.bassBoost, 0.35);

      await manager.setBandGain(3, 5.0);
      expect(manager.selectedHeadphoneProfile, isNull);
      expect(manager.currentPreset.name, 'Custom');
      expect(manager.currentPreset.gains[3], 5.0);
    });

    test('resetToFlat zeros all gains and clears active headphone profile',
        () async {
      final manager = EqualizerManager();
      await manager.applyHeadphoneProfile(testProfile);
      await manager.setBandGain(0, 10.0);

      await manager.resetToFlat();
      expect(manager.currentPreset.gains.every((g) => g == 0.0), isTrue);
      expect(manager.selectedHeadphoneProfile, isNull);
      expect(manager.currentPreset.bassBoost, 0.0);
    });

    test(
        'volumeBoost caps when combined with preamp exceeds +6dB safe headroom',
        () async {
      final manager = EqualizerManager();
      await manager.applyHeadphoneProfile(testProfileWith4dBPreamp);

      // Preamp is +4.0 dB. Setting boost to 0.8 would add +8.0 dB (Total = +12.0 dB).
      // Should cap boost so total is <= +6.0 dB, meaning boost is capped to +2.0 dB (0.2).
      await manager.setVolumeBoost(0.8);
      expect(manager.volumeBoost, closeTo(0.2, 0.001));
    });

    test('applyPreset carries preset bass boost and clears active profile',
        () async {
      final manager = EqualizerManager();
      await manager.applyHeadphoneProfile(testProfile);

      const bassPreset = EqPreset(
        name: 'Bass Heavy',
        gains: [6, 5, 4, 3, 2, 1, 0, 0, 0, 0],
        bassBoost: 0.8,
      );

      await manager.applyPreset(bassPreset);
      expect(manager.selectedHeadphoneProfile, isNull);
      expect(manager.currentPreset.name, 'Bass Heavy');
      expect(manager.currentPreset.bassBoost, 0.8);
    });

    test('A/B comparison toggles state and manages comparison lifecycle',
        () async {
      final manager = EqualizerManager();
      const customGains = [2.0, 3.0, 4.0, 5.0, 4.0, 3.0, 2.0, 1.0, 0.0, -1.0];
      await manager
          .applyPreset(const EqPreset(name: 'Custom', gains: customGains));

      expect(manager.isAbComparisonActive, isFalse);
      await manager.startAbComparison();
      expect(manager.isAbComparisonActive, isTrue);

      await manager.endAbComparison();
      expect(manager.isAbComparisonActive, isFalse);
      expect(manager.currentPreset.gains, customGains);
    });

    test(
        'toggleDynamicsBypass neutralizes dynamics without altering selected preset',
        () async {
      final manager = EqualizerManager();
      await manager.setDynamicsPreset(DynamicsPreset.studioPunch,
          enabled: true);
      expect(manager.isDynamicsEnabled, isTrue);
      expect(manager.dynamicsPreset, DynamicsPreset.studioPunch);

      await manager.toggleDynamicsBypass();
      expect(manager.isDynamicsBypassed, isTrue);

      await manager.toggleDynamicsBypass();
      expect(manager.isDynamicsBypassed, isFalse);
      expect(manager.dynamicsPreset, DynamicsPreset.studioPunch);
    });

    test('custom frequencies layout updates and persists', () async {
      final manager = EqualizerManager();
      final customFreqs = [
        30.0,
        60.0,
        120.0,
        240.0,
        480.0,
        960.0,
        1920.0,
        3840.0,
        7680.0,
        15360.0
      ];
      await manager.setCustomFrequencies(customFreqs);
      expect(manager.customFrequencies, customFreqs);

      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('eq_custom_frequencies');
      expect(saved, isNotNull);
    });
  });

  group('EqualizerManager session re-attachment (FIX: DSP Session Detached)', () {
    test(
        'reapplyToSession orders release -> setAudioSessionId -> re-apply bands/enables',
        () async {
      final manager = EqualizerManager();
      manager.isEnabled = true;

      await manager.reapplyToSession(5);

      final methods = channelCalls.map((c) => c.method).toList();
      final releaseIdx = methods.indexOf('releaseEffects');
      final setSessionIdx = methods.indexOf('setAudioSessionId');
      final bulkBandsIdx = methods.indexOf('setNativeEqBandsBulk');
      final eqEnabledIdx = methods.indexOf('setEqEnabled');
      final nativeEqEnabledIdx = methods.indexOf('setNativeEqEnabled');

      expect(releaseIdx, greaterThanOrEqualTo(0),
          reason: 'old-session effects must be released first');
      expect(setSessionIdx, greaterThan(releaseIdx),
          reason: 'session id must be pushed after release');
      expect(
        channelCalls[setSessionIdx].arguments,
        {'audioSessionId': 5},
      );
      expect(bulkBandsIdx, greaterThan(setSessionIdx),
          reason: 'band config re-applied only after session switch');
      expect(eqEnabledIdx, greaterThan(bulkBandsIdx),
          reason: 'enable flags re-pushed after bands');
      expect(nativeEqEnabledIdx, greaterThan(eqEnabledIdx));
    });

    test('repeated same-id event does not trigger a recreate', () async {
      final manager = EqualizerManager();
      manager.isEnabled = true;

      await manager.reapplyToSession(5);
      final callsAfterFirst = channelCalls.length;

      await manager.reapplyToSession(5);
      await manager.reapplyToSession(5);

      final setSessionCalls =
          channelCalls.where((c) => c.method == 'setAudioSessionId').length;
      expect(setSessionCalls, 1);
      expect(channelCalls.length, callsAfterFirst,
          reason: 'same-id re-emit must be a complete no-op');
    });

    test('session id 5 -> 7 (route change) releases, re-pushes, and re-applies',
        () async {
      final manager = EqualizerManager();
      manager.isEnabled = true;

      await manager.reapplyToSession(5);
      await manager.reapplyToSession(7);

      final sessionCalls =
          channelCalls.where((c) => c.method == 'setAudioSessionId').toList();
      expect(sessionCalls, hasLength(2));
      expect(sessionCalls.last.arguments, {'audioSessionId': 7});

      // The second attach must be a full cycle: release before the new id.
      final methods = channelCalls.map((c) => c.method).toList();
      final lastRelease = methods.lastIndexOf('releaseEffects');
      final lastSetSession = methods.lastIndexOf('setAudioSessionId');
      final lastBulkBands = methods.lastIndexOf('setNativeEqBandsBulk');
      expect(lastRelease, greaterThan(0));
      expect(lastSetSession, greaterThan(lastRelease));
      expect(lastBulkBands, greaterThan(lastSetSession));
    });

    test('invalid session ids (0 / negative) are ignored entirely', () async {
      final manager = EqualizerManager();
      manager.isEnabled = true;
      final before = channelCalls.length;

      await manager.reapplyToSession(0);
      await manager.reapplyToSession(-1);
      expect(channelCalls.length, before);
    });

    test('out-of-order concurrent requests collapse to the latest session id',
        () async {
      final manager = EqualizerManager();
      manager.isEnabled = true;

      // Fired in the same event-loop turn: only the newest id must survive.
      final f1 = manager.reapplyToSession(9);
      final f2 = manager.reapplyToSession(7);
      await Future.wait([f1, f2]);

      final sessionCalls =
          channelCalls.where((c) => c.method == 'setAudioSessionId').toList();
      expect(sessionCalls, hasLength(1),
          reason: 'intermediate/stale session ids must be collapsed');
      expect(sessionCalls.single.arguments, {'audioSessionId': 7});
      expect(
        channelCalls.where((c) => c.method == 'releaseEffects').length,
        1,
      );
    });

    test('resyncActiveEffects re-pushes state without releasing the session',
        () async {
      final manager = EqualizerManager();
      manager.isEnabled = true;

      await manager.reapplyToSession(5);
      final afterAttach = channelCalls.length;

      await manager.resyncActiveEffects();

      final methods = channelCalls.map((c) => c.method).toList();
      expect(methods.sublist(afterAttach).contains('releaseEffects'), isFalse,
          reason: 'route change on the same session must not release effects');
      expect(methods.sublist(afterAttach).contains('setAudioSessionId'), isFalse);
      expect(methods.sublist(afterAttach).contains('setNativeEqBandsBulk'), isTrue,
          reason: 'effect state must be re-pushed after a route change');
      expect(methods.sublist(afterAttach).contains('setEqEnabled'), isTrue);
    });

    test(
        'audio-session-id emission after player init reaches setAudioSessionId via the router',
        () async {
      final manager = EqualizerManager();
      manager.isEnabled = true;
      final tracked = <Future<void>>[];
      final router = AudioSessionIdRouter(
        onSessionChanged: (id) {
          tracked.add(manager.reapplyToSession(id));
        },
        onRouteChanged: () {
          tracked.add(manager.resyncActiveEffects());
        },
      );

      // just_audio emits null / 0 until the platform assigns a session.
      router.handleSessionId(null);
      router.handleSessionId(0);
      await router.idleForTest;
      expect(
        channelCalls.where((c) => c.method == 'setAudioSessionId'),
        isEmpty,
      );

      // First non-zero id right after player init must be routed end-to-end.
      router.handleSessionId(42);
      await router.idleForTest;
      await Future.wait(tracked);

      final sessionCalls =
          channelCalls.where((c) => c.method == 'setAudioSessionId').toList();
      expect(sessionCalls, hasLength(1));
      expect(sessionCalls.single.arguments, {'audioSessionId': 42});
      expect(router.currentSessionId, 42);

      // Same-id re-emission (BehaviorSubject replay) must not recreate.
      router.handleSessionId(42);
      await router.idleForTest;
      expect(
        channelCalls.where((c) => c.method == 'setAudioSessionId').length,
        1,
      );

      // Route change on the same session triggers a state resync, not a release.
      router.handleRouteChanged();
      await router.idleForTest;
      await Future.wait(tracked);
      final resyncSends = channelCalls
          .where((c) => c.method == 'setNativeEqBandsBulk')
          .length;
      expect(resyncSends, greaterThanOrEqualTo(2));
      expect(
        channelCalls.where((c) => c.method == 'setAudioSessionId').length,
        1,
      );
    });
  });
}
