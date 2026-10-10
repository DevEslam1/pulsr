// Additional coverage for lib/features/settings/cubit/settings_cubit.dart:
// the preference-loader fallbacks (unknown enum names, non-finite values,
// bit-perfect boot restore), the theme/audio dirty reconciliation, the
// proxy-password secure read/migration and the scanner/index/repository
// maintenance actions.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/constants/prefs_keys.dart';
import 'package:pulsr/core/di/injection.dart';
import 'package:pulsr/core/errors/failures.dart';
import 'package:pulsr/data/audio/equalizer_manager.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/domain/repositories/music_repository_interface.dart';
import 'package:pulsr/features/player/presentation/widgets/audio_visualizer.dart';
import 'package:pulsr/features/settings/cubit/settings_cubit.dart';
import 'package:pulsr/features/settings/cubit/settings_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/settings_section_harness.dart';

class MockSecureStorage extends Mock implements FlutterSecureStorage {}

class MockEqualizerManager extends Mock implements EqualizerManager {}

class MockAppDatabase extends Mock implements AppDatabase {}

class MockMusicRepository extends Mock implements IMusicRepository {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    stubSettingsChannels();
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  tearDown(() async {
    clearSettingsChannels();
    if (getIt.isRegistered<EqualizerManager>()) {
      await getIt.unregister<EqualizerManager>();
    }
    if (getIt.isRegistered<AppDatabase>()) {
      await getIt.unregister<AppDatabase>();
    }
    if (getIt.isRegistered<IMusicRepository>()) {
      await getIt.unregister<IMusicRepository>();
    }
  });

  SettingsCubit make({FlutterSecureStorage? storage}) => SettingsCubit(
        scannerService: MockMediaScannerService(),
        secureStorage: storage ?? const FlutterSecureStorage(),
      );

  group('simple maintenance setters', () {
    test('clearError, min file size and custom radius round-trip', () async {
      final cubit = make();
      addTearDown(cubit.close);

      cubit.safeEmit(cubit.state.copyWith(errorMessage: 'nope'));
      cubit.clearError();
      expect(cubit.state.errorMessage, isNull);

      await cubit.setMinFileSizeKb(99999);
      expect(await cubit.getMinFileSizeKb(), 5000);
      await cubit.setMinFileSizeKb(-4);
      expect(await cubit.getMinFileSizeKb(), 0);

      await cubit.setCustomThemeRadius(100);
      expect(cubit.state.customThemeRadius, 48.0);

      await cubit.setThemeScheduleHours(start: 22, end: 6);
      expect(cubit.state, isNotNull);
    });
  });

  group('preference loader fallbacks', () {
    test('unknown theme enums fall back to their defaults', () async {
      SharedPreferences.setMockInitialValues({
        'setting_theme_mode': 'bogus',
        'setting_player_theme_mode': 'bogus',
        'setting_visualizer_style': 'bogus',
        'setting_mini_player_swipe_left': 'bogus',
        'setting_mini_player_swipe_right': 'bogus',
        'setting_now_playing_double_tap': 'bogus',
        'setting_now_playing_artwork_swipe': 'bogus',
      });
      final cubit = make();
      addTearDown(cubit.close);
      await cubit.preferencesReady;

      expect(cubit.state.themeMode, AppThemeMode.dark);
      expect(cubit.state.playerThemeMode, PlayerThemeMode.classic);
      expect(cubit.state.visualizerStyle, VisualizerStyle.bar);
      expect(cubit.state.miniPlayerSwipeLeft, MiniPlayerSwipeAction.next);
      expect(cubit.state.miniPlayerSwipeRight, MiniPlayerSwipeAction.prev);
      expect(
          cubit.state.nowPlayingDoubleTap, NowPlayingDoubleTapAction.toggleFavorite);
      expect(cubit.state.nowPlayingArtworkSwipe,
          NowPlayingArtworkSwipeAction.nextPrev);
    });

    test('legacy dynamic-theme bool maps to color source when source absent',
        () async {
      SharedPreferences.setMockInitialValues({'setting_dynamic_theme': false});
      final cubit = make();
      addTearDown(cubit.close);
      await cubit.preferencesReady;

      expect(cubit.state.themeColorSource, ThemeColorSource.custom);
    });

    test('unknown theme color source falls back to artwork', () async {
      SharedPreferences.setMockInitialValues({
        'setting_theme_color_source': 'bogus',
      });
      final cubit = make();
      addTearDown(cubit.close);
      await cubit.preferencesReady;

      expect(cubit.state.themeColorSource, ThemeColorSource.artwork);
    });

    test('audio fallbacks, crossfade normalization and bit-perfect restore',
        () async {
      SharedPreferences.setMockInitialValues({
        'setting_replay_gain_mode': 'bogus',
        'setting_replay_gain_preamp_with_rg': double.infinity,
        PrefsKeys.dsdOutputMode: 'bogus',
        PrefsKeys.bitPerfectOutput: true,
        'setting_crossfade': 5.0,
        'target_output_sample_rate': 96000,
        'target_output_bit_depth': 24,
      });
      final cubit = make();
      addTearDown(cubit.close);
      await cubit.preferencesReady;

      // An unknown stored mode falls back to the first-launch default: DoP is
      // the preferred DSD transport (gated at playback by the native probe).
      expect(cubit.state.replayGainMode, ReplayGainMode.off);
      expect(cubit.state.replayGainPreampWithRg, 0.0);
      expect(cubit.state.dsdOutputMode, DsdOutputMode.dop);
      // Bit-perfect + crossfade > 0 is normalized to 0 and persisted.
      expect(cubit.state.crossfadeSeconds, 0.0);
      // The stubbed native layer refuses exclusive mode, so it must be off.
      expect(cubit.state.bitPerfectOutput, isFalse);
    });

    test('unknown quality names fall back to high', () async {
      SharedPreferences.setMockInitialValues({
        'setting_streaming_quality': 'bogus',
        'setting_download_quality': 'bogus',
      });
      final cubit = make();
      addTearDown(cubit.close);
      await cubit.preferencesReady;

      expect(cubit.state.streamingQuality, YtmAudioQuality.high);
      expect(cubit.state.downloadQuality, YtmAudioQuality.high);
    });

    test('a registered EqualizerManager owns the DSP load/restore', () async {
      final manager = MockEqualizerManager();
      when(() => manager.isCrossfeedEnabled).thenReturn(false);
      when(() => manager.crossfeedDelayUs).thenReturn(0.0);
      when(() => manager.crossfeedFeedDb).thenReturn(0.0);
      when(() => manager.isLimiterEnabled).thenReturn(false);
      when(() => manager.limiterLookaheadMs).thenReturn(0.0);
      when(() => manager.limiterThresholdDb).thenReturn(0.0);
      when(() => manager.limiterReleaseMs).thenReturn(0.0);
      when(() => manager.isReverbEnabled).thenReturn(false);
      when(() => manager.reverbPreset).thenReturn(0);
      when(() => manager.reverbWetDry).thenReturn(0.0);
      when(() => manager.stereoBalance).thenReturn(0.0);
      when(() => manager.monoMix).thenReturn(false);
      when(() => manager.isSincResamplerEnabled).thenReturn(false);
      when(() => manager.setDspPreference(any())).thenAnswer((_) async {});
      when(() => manager.setBypassDspForBitPerfect(any()))
          .thenAnswer((_) async {});
      getIt.registerSingleton<EqualizerManager>(manager);

      final cubit = make();
      addTearDown(cubit.close);
      await cubit.preferencesReady;

      verify(() => manager.setDspPreference(any())).called(greaterThanOrEqualTo(1));
      verify(() => manager.setBypassDspForBitPerfect(any()))
          .called(greaterThanOrEqualTo(1));
    });
  });

  group('dirty reconciliation for theme fields', () {
    test('theme edits made during an in-flight load are preserved', () async {
      final storage = MockSecureStorage();
      final gate = Completer<String?>();
      var served = false;
      when(() => storage.read(key: any(named: 'key'))).thenAnswer((_) {
        if (!served) {
          served = true;
          return gate.future;
        }
        return Future<String?>.value(null);
      });
      when(() => storage.delete(key: any(named: 'key')))
          .thenAnswer((_) async {});
      when(() => storage.write(
            key: any(named: 'key'),
            value: any(named: 'value'),
          )).thenAnswer((_) async {});

      final cubit = make(storage: storage);
      addTearDown(cubit.close);

      await cubit.setThemeMode(AppThemeMode.light);
      await cubit.setCustomAccentColor(const Color(0xFF123456));
      await cubit.setWaveformSeekBar(true);
      await cubit.setHighContrast(true);
      await cubit.setDimWhitePoint(true);
      await cubit.setLiquidGlassTint(0.2);
      await cubit.setLanguage('fr');
      await cubit.setCustomThemeRadius(10);
      await cubit.setCustomThemeGlow(false);
      await cubit.setPlayerThemeMode(PlayerThemeMode.vinyl);
      await cubit.setVisualizerStyle(VisualizerStyle.wave);
      await cubit.setMiniPlayerSwipeLeft(MiniPlayerSwipeAction.volume);
      await cubit.setMiniPlayerSwipeRight(MiniPlayerSwipeAction.next);
      await cubit
          .setNowPlayingDoubleTap(NowPlayingDoubleTapAction.toggleLyrics);
      await cubit.setNowPlayingArtworkSwipe(NowPlayingArtworkSwipeAction.none);
      await cubit.setExperienceMode(ExperienceMode.professional);
      await cubit.setReplayGainMode(ReplayGainMode.album);
      await cubit.setThemeColorSource(ThemeColorSource.custom);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('setting_theme_mode', 'amoled');
      await prefs.setInt('setting_custom_accent', 0xFF000000);
      await prefs.setBool('setting_waveform_seek_bar', false);
      await prefs.setBool('setting_high_contrast', false);
      await prefs.setBool('setting_dim_white_point', false);
      await prefs.setDouble('setting_liquid_glass_tint', 0.9);
      await prefs.setString(PrefsKeys.languageCode, 'de');
      await prefs.setDouble('setting_custom_theme_radius', 40);
      await prefs.setBool('setting_custom_theme_glow', true);
      await prefs.setString('setting_player_theme_mode', 'classic');
      await prefs.setString('setting_visualizer_style', 'bar');
      await prefs.setString('setting_mini_player_swipe_left', 'next');
      await prefs.setString('setting_mini_player_swipe_right', 'prev');
      await prefs.setString('setting_now_playing_double_tap', 'toggleFavorite');
      await prefs.setString('setting_now_playing_artwork_swipe', 'nextPrev');
      await prefs.setString(PrefsKeys.experienceMode, 'normal');
      await prefs.setString('setting_replay_gain_mode', 'track');
      await prefs.setString('setting_theme_color_source', 'artwork');

      gate.complete(null);
      await cubit.preferencesReady;

      expect(cubit.state.themeMode, AppThemeMode.light);
      expect(cubit.state.customAccentColorValue, 0xFF123456);
      expect(cubit.state.waveformSeekBarEnabled, isTrue);
      expect(cubit.state.highContrast, isTrue);
      expect(cubit.state.dimWhitePoint, isTrue);
      expect(cubit.state.liquidGlassTint, 0.2);
      expect(cubit.state.languageCode, 'fr');
      expect(cubit.state.customThemeRadius, 10);
      expect(cubit.state.customThemeGlow, isFalse);
      expect(cubit.state.playerThemeMode, PlayerThemeMode.vinyl);
      expect(cubit.state.visualizerStyle, VisualizerStyle.wave);
      expect(cubit.state.miniPlayerSwipeLeft, MiniPlayerSwipeAction.volume);
      expect(cubit.state.miniPlayerSwipeRight, MiniPlayerSwipeAction.next);
      expect(cubit.state.nowPlayingDoubleTap,
          NowPlayingDoubleTapAction.toggleLyrics);
      expect(cubit.state.nowPlayingArtworkSwipe,
          NowPlayingArtworkSwipeAction.none);
      expect(cubit.state.experienceMode, ExperienceMode.professional);
      expect(cubit.state.replayGainMode, ReplayGainMode.album);
      expect(cubit.state.themeColorSource, ThemeColorSource.custom);
    });
  });

  group('proxy password secure handling', () {
    test('concurrent getProxyPassword shares the in-flight read', () async {
      final storage = MockSecureStorage();
      when(() => storage.read(key: any(named: 'key')))
          .thenAnswer((_) async => 'secret');
      when(() => storage.delete(key: any(named: 'key')))
          .thenAnswer((_) async {});
      when(() => storage.write(
            key: any(named: 'key'),
            value: any(named: 'value'),
          )).thenAnswer((_) async {});

      final cubit = make(storage: storage);
      addTearDown(cubit.close);

      final first = cubit.getProxyPassword();
      final second = cubit.getProxyPassword();
      expect(await first, 'secret');
      expect(await second, 'secret');
      await cubit.preferencesReady;
    });

    test('legacy plaintext proxy password migrates into secure storage',
        () async {
      SharedPreferences.setMockInitialValues({
        'setting_proxy_password': 'legacy',
      });
      final storage = MockSecureStorage();
      final store = <String, String>{};
      when(() => storage.read(key: any(named: 'key'))).thenAnswer((inv) async =>
          store[inv.namedArguments[#key] as String]);
      when(() => storage.write(
            key: any(named: 'key'),
            value: any(named: 'value'),
          )).thenAnswer((inv) async {
        store[inv.namedArguments[#key] as String] =
            inv.namedArguments[#value] as String;
      });
      when(() => storage.delete(key: any(named: 'key'))).thenAnswer((inv) async {
        store.remove(inv.namedArguments[#key] as String);
      });

      final cubit = make(storage: storage);
      addTearDown(cubit.close);
      await cubit.preferencesReady;

      expect(cubit.state.hasProxyPassword, isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('setting_proxy_password'), isFalse);
      expect(store.values, contains('legacy'));
    });

    test('a secure-storage verify mismatch still adopts the legacy password',
        () async {
      SharedPreferences.setMockInitialValues({
        'setting_proxy_password': 'legacy',
      });
      final storage = MockSecureStorage();
      when(() => storage.read(key: any(named: 'key')))
          .thenAnswer((_) async => null);
      when(() => storage.write(
            key: any(named: 'key'),
            value: any(named: 'value'),
          )).thenAnswer((_) async {});
      when(() => storage.delete(key: any(named: 'key')))
          .thenAnswer((_) async {});

      final cubit = make(storage: storage);
      addTearDown(cubit.close);
      await cubit.preferencesReady;

      expect(cubit.state.hasProxyPassword, isTrue);
    });
  });

  group('library maintenance actions', () {
    test('a scan failure surfaces an error and returns 0', () async {
      final scanner = MockMediaScannerService();
      when(() => scanner.scanDeviceLibrary(
            ignoreShortFiles: any(named: 'ignoreShortFiles'),
            minDurationSec: any(named: 'minDurationSec'),
            minSizeKb: any(named: 'minSizeKb'),
            autoHideSystemMedia: any(named: 'autoHideSystemMedia'),
          )).thenThrow(Exception('scan boom'));
      final cubit = SettingsCubit(scannerService: scanner);
      addTearDown(cubit.close);
      await cubit.preferencesReady;

      expect(await cubit.rescanLibrary(), 0);
      expect(cubit.state.errorMessage, isNotNull);
      expect(cubit.state.isScanning, isFalse);
    });

    test('rebuildSearchIndex delegates to the registered database', () async {
      final db = MockAppDatabase();
      when(() => db.repairFtsIndex(force: any(named: 'force')))
          .thenAnswer((_) async => true);
      getIt.registerSingleton<AppDatabase>(db);

      final cubit = make();
      addTearDown(cubit.close);

      expect(await cubit.rebuildSearchIndex(), isTrue);
      verify(() => db.repairFtsIndex(force: true)).called(1);
    });

    test('removeMissingFiles folds the repository result', () async {
      final repo = MockMusicRepository();
      when(() => repo.hardDeleteMissingSongs())
          .thenAnswer((_) async => const Right<AppFailure, int>(3));
      getIt.registerSingleton<IMusicRepository>(repo);

      final cubit = make();
      addTearDown(cubit.close);

      expect(await cubit.removeMissingFiles(), 3);
    });
  });
}
