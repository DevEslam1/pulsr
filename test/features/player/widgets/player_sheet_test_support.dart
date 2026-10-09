// Shared harness for Player widget/sheet tests.
//
// Not a test file (no `_test` suffix): provides mocktail mocks, a canonical
// [SongsTableData], and a host widget that wires up localization, the Aura
// theme, and optional PlayerCubit/SettingsCubit providers.
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/data/audio/equalizer_manager.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/settings/cubit/settings_cubit.dart';
import 'package:pulsr/features/settings/cubit/settings_state.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

class MockPlayerCubit extends Mock implements PlayerCubit {}

class MockSettingsCubit extends Mock implements SettingsCubit {}

class MockEqualizerManager extends Mock implements EqualizerManager {}

/// Canonical local FLAC track used across the sheet tests.
const SongsTableData testSong = SongsTableData(
  id: 42,
  title: 'Test Song',
  artist: 'Test Artist',
  album: 'Test Album',
  durationMs: 210000,
  path: '/music/test.flac',
  isFavorite: false,
  isMissing: false,
  playCount: 0,
  lastPositionMs: 0,
  source: 'local',
  isDownloaded: true,
  sampleRate: 96000,
  bitDepth: 24,
  bitrateKbps: 2300,
  codec: 'FLAC',
  fileSize: 31457280,
  loudnessRange: 8.5,
);

/// A YouTube (not downloaded) track that surfaces the streaming-quality
/// selector inside the audio quality sheet.
const SongsTableData ytSong = SongsTableData(
  id: 7,
  title: 'Stream Song',
  artist: 'Yt Artist',
  album: 'Yt Album',
  durationMs: 180000,
  path: 'ytmusic://abc123',
  isFavorite: false,
  isMissing: false,
  playCount: 0,
  lastPositionMs: 0,
  source: 'youtube',
  isDownloaded: false,
);

/// Builds a [MockPlayerCubit] with the minimum stubs every sheet touches.
MockPlayerCubit stubPlayerCubit({
  PlayerState? state,
  Stream<Duration>? positionStream,
}) {
  final cubit = MockPlayerCubit();
  when(() => cubit.state).thenReturn(state ?? const PlayerState());
  when(() => cubit.stream)
      .thenAnswer((_) => const Stream<PlayerState>.empty());
  when(() => cubit.rawPositionStream)
      .thenAnswer((_) => positionStream ?? const Stream<Duration>.empty());
  return cubit;
}

/// Builds a [MockSettingsCubit] with default state.
MockSettingsCubit stubSettingsCubit({SettingsState? state}) {
  final cubit = MockSettingsCubit();
  when(() => cubit.state).thenReturn(state ?? const SettingsState());
  when(() => cubit.stream)
      .thenAnswer((_) => const Stream<SettingsState>.empty());
  return cubit;
}

/// Host widget: MaterialApp (localized + themed) -> Scaffold -> providers.
Widget sheetHost({
  required Widget child,
  PlayerCubit? playerCubit,
  SettingsCubit? settingsCubit,
}) {
  return MaterialApp(
    theme: AuraTheme.darkTheme,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: MultiBlocProvider(
        providers: [
          if (playerCubit != null)
            BlocProvider<PlayerCubit>.value(value: playerCubit),
          if (settingsCubit != null)
            BlocProvider<SettingsCubit>.value(value: settingsCubit),
        ],
        child: child,
      ),
    ),
  );
}