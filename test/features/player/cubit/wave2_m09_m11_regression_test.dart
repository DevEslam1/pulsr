// test/features/player/cubit/wave2_m09_m11_regression_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/constants/prefs_keys.dart';
import 'package:pulsr/data/audio/audio_effects_channel.dart';
import 'package:pulsr/data/audio/dsp_chain_validator.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/features/audio_profiles/audio_profile.dart';
import 'package:pulsr/features/audio_profiles/audio_profile_keys.dart';
import 'package:pulsr/features/diagnostics/diagnostics_bundle_service.dart';
import 'package:pulsr/features/player/cubit/controllers/queue_slot_data.dart';
import 'package:pulsr/features/system_behavior/system_behavior_policy.dart';
import 'package:pulsr/features/system_behavior/system_behavior_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../player_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('H-55 & M-11 AudioProfileKeys schema validation & HRTF/LFE keys', () {
    test('validates HRTF, LFE, and core keys with strict per-key types', () {
      expect(
        AudioProfileKeys.whitelist.contains(PrefsKeys.hrtfBinauralEnabled),
        isTrue,
      );
      expect(
        AudioProfileKeys.whitelist.contains(PrefsKeys.lfeCrossoverHz),
        isTrue,
      );
      expect(
        AudioProfileKeys.validate(PrefsKeys.hrtfBinauralEnabled, true).valid,
        isTrue,
      );
      expect(
        AudioProfileKeys.validate(
          PrefsKeys.hrtfBinauralEnabled,
          'not-a-bool',
        ).valid,
        isFalse,
      );
      expect(
        AudioProfileKeys.validate(PrefsKeys.lfeCrossoverHz, 80.0).valid,
        isTrue,
      );
      expect(
        AudioProfileKeys.validate(PrefsKeys.lfeCrossoverHz, true).valid,
        isFalse,
      );
      expect(
        AudioProfileKeys.validate(
          PrefsKeys.eqGains,
          const <String>['0.0', '1.5'],
        ).valid,
        isTrue,
      );
      expect(
        AudioProfileKeys.validate(
          PrefsKeys.eqGains,
          const <int>[0, 1],
        ).valid,
        isFalse,
      );
    });

    test('AudioProfile drops wrong-typed whitelisted keys safely', () {
      final profile = AudioProfile(
        id: 'p1',
        name: 'Test Profile',
        appVersion: '1.0.0',
        createdAt: DateTime.utc(2026, 1, 1),
        values: {
          PrefsKeys.eqEnabled: 'invalid_bool_string',
          PrefsKeys.hrtfBinauralEnabled: true,
          PrefsKeys.lfeCrossoverHz: 90.0,
        },
      );
      expect(
        profile.values.containsKey(PrefsKeys.eqEnabled),
        isFalse,
      );
      expect(
        profile.values[PrefsKeys.hrtfBinauralEnabled],
        isTrue,
      );
      expect(
        profile.values[PrefsKeys.lfeCrossoverHz],
        90.0,
      );
    });
  });

  group('M-11 DiagnosticsBundleService _boolValue & liveProgCode redaction',
      () {
    test('tolerates wrong-typed bool prefs and redacts liveProgCode', () async {
      SharedPreferences.setMockInitialValues({
        PrefsKeys.eqEnabled: 'corrupted_not_bool',
        PrefsKeys.liveProgEnabled: true,
        PrefsKeys.liveProgCode: '@sample\nspl0 = spl0 * 2;',
      });
      final prefs = await SharedPreferences.getInstance();
      final service = DiagnosticsBundleService(prefs: prefs);

      final bundle = await service.build();
      final liveProg = bundle.dspStages.firstWhere(
        (stage) => stage['detail'] == '[REDACTED]',
      );
      expect(liveProg['detail'], '[REDACTED]');
      expect(bundle.preferences[PrefsKeys.liveProgCode], '[REDACTED]');
    });
  });

  group('M-09 QueueSlotData Q2/Q3 pinned song preservation during LRU eviction',
      () {
    test('cacheSlotSongs never evicts pinned inactive slot song IDs', () {
      final cache = <int, SongsTableData>{};
      for (var i = 1; i <= maxSlotLookupCacheEntries; i++) {
        cache[i] = buildSong(i);
      }

      // Song 1 and 2 are oldest in insertion order, but song 1 is pinned by Q2.
      final nextA = maxSlotLookupCacheEntries + 1;
      final nextB = maxSlotLookupCacheEntries + 2;
      cacheSlotSongs(
        cache,
        [buildSong(nextA), buildSong(nextB)],
        pinnedSongIds: const {1},
      );

      expect(cache.containsKey(1), isTrue);
      expect(cache.containsKey(2), isFalse);
      expect(cache.containsKey(nextA), isTrue);
      expect(cache.containsKey(nextB), isTrue);
    });
  });

  group('L-03 DspChainValidator & Phase 4.3 PlatformAudioCapabilities', () {
    test(
        'DspChainValidator reports 0.0 saturation THD and latency when disabled and uses honest synthetic labels',
        () async {
      final report = await DspChainValidator.runDiagnosticSweep();
      final sat = report.stages['tube_saturation']!;
      expect(sat.thdPercent, 0.0);
      expect(sat.latencyMs, 0.0);
      expect(sat.message!.toLowerCase(), contains('bypassed'));

      final eq = report.stages['biquad_eq']!;
      expect(eq.message!.toLowerCase(), contains('synthetic'));
    });

    test(
        'AudioEffectsChannel exposes typed PlatformAudioCapabilities and returns false on non-Android stubs',
        () async {
      final channel = AudioEffectsChannel();
      final desktopCaps = PlatformAudioCapabilities.detect(isAndroid: false);
      expect(desktopCaps.nativeDsp, CapabilitySupport.unsupported);
      expect(desktopCaps.eqBands, CapabilitySupport.unsupported);

      final androidUsbPending = PlatformAudioCapabilities.detect(
        isAndroid: true,
        usbAttached: true,
        usbPermissionGranted: false,
      );
      expect(
        androidUsbPending.usbExclusiveDac,
        CapabilitySupport.requiresPermission,
      );
      expect(
        androidUsbPending.nativeDsp,
        CapabilitySupport.supported,
      );

      expect(await channel.awaitControlUpdates(), isFalse);
      expect(await channel.setEqBandGain(0, 1.5), isFalse);
      expect(await channel.setEqBandGains([0.0, 1.0]), isFalse);
      expect(await channel.setNativeEqBandCount(10), isFalse);
      expect(await channel.sendWarmupBuffer(), isFalse);
    });
  });

  group('M-11 SystemBehavior volume curve & fine steps', () {
    test('nextVolume applies logarithmic curve and custom step counts', () {
      const settings = SystemBehaviorSettingsSnapshot(
        volumeStepPercent: 2,
        softwareVolumeCurve: SoftwareVolumeCurve.logarithmic,
      );
      final steppedUp = nextVolume(
        current: 0.5,
        direction: 1,
        settings: settings,
      );
      expect(steppedUp, greaterThan(0.5));
      expect(steppedUp, lessThan(0.6));
    });
  });
}
