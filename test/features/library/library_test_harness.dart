// Shared harness + fixtures for the Library feature widget tests.
//
// The Library tabs live as mixins on `_LibraryScreenState`, so they cannot be
// exercised in isolation: every tab test pumps the real [LibraryScreen] with a
// mocked [LibraryCubit] (state supplied up-front) plus a stubbed [PlayerCubit]
// and [SettingsCubit]. SharedPreferences is seeded so the song-tile gesture
// hint never schedules its auto-dismiss timer.
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/features/library/cubit/library_cubit.dart';
import 'package:pulsr/features/library/cubit/library_state.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/settings/cubit/settings_cubit.dart';
import 'package:pulsr/features/settings/cubit/settings_state.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

/// Forces `MediaQuery.disableAnimations` on so no infinite shimmer/ticker loops
/// keep `pumpAndSettle` from settling.
void disableAnimations(WidgetTester tester) {
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
}

class MockLibraryCubit extends Mock implements LibraryCubit {}

class MockPlayerCubit extends Mock implements PlayerCubit {}

class MockSettingsCubit extends Mock implements SettingsCubit {}

/// Registers the mocktail fallback values the harness' `any()` matchers need.
void registerLibraryFallbacks() {
  registerFallbackValue(testSong(id: -1));
  registerFallbackValue(<SongsTableData>[]);
}

/// A [PlayerCubit] stub that reports [state] and yields no state events.
MockPlayerCubit stubPlayerCubit([PlayerState? state]) {
  final cubit = MockPlayerCubit();
  when(() => cubit.state).thenReturn(state ?? const PlayerState());
  when(() => cubit.stream)
      .thenAnswer((_) => const Stream<PlayerState>.empty());
  when(() => cubit.playSong(any(), queue: any(named: 'queue')))
      .thenAnswer((_) async {});
  when(() => cubit.playNext(any())).thenAnswer((_) async {});
  when(() => cubit.warmStreams(any(), count: any(named: 'count')))
      .thenAnswer((_) {});
  return cubit;
}

/// A [LibraryCubit] stub that reports [state] and no state events.
MockLibraryCubit stubLibraryCubit(
  LibraryState state, {
  bool hasMoreSongs = false,
  Stream<LibraryState>? stream,
}) {
  final cubit = MockLibraryCubit();
  when(() => cubit.state).thenReturn(state);
  when(() => cubit.stream)
      .thenAnswer((_) => stream ?? const Stream<LibraryState>.empty());
  when(() => cubit.hasMoreSongs).thenReturn(hasMoreSongs);
  when(() => cubit.init()).thenAnswer((_) async {});
  when(() => cubit.loadMoreSongs()).thenAnswer((_) {});
  when(() => cubit.toggleViewMode()).thenAnswer((_) {});
  when(() => cubit.clearSelection()).thenAnswer((_) {});
  when(() => cubit.toggleSongSelection(any())).thenAnswer((_) {});
  when(() => cubit.toggleFavorite(any())).thenAnswer((_) async {});
  when(() => cubit.selectAllSongs()).thenAnswer((_) async {});
  when(() => cubit.loadFolders()).thenAnswer((_) async {});
  when(() => cubit.getSelectedSongs())
      .thenAnswer((_) async => const <SongsTableData>[]);
  return cubit;
}

/// Sets a deterministic logical surface (1000x1600 by default) and restores it
/// after the test.
void setSurface(WidgetTester tester, {Size size = const Size(1000, 1600)}) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

MockSettingsCubit stubSettingsCubit() {
  final cubit = MockSettingsCubit();
  when(() => cubit.state).thenReturn(const SettingsState());
  when(() => cubit.stream)
      .thenAnswer((_) => const Stream<SettingsState>.empty());
  when(() => cubit.rescanLibrary()).thenAnswer((_) async => 0);
  return cubit;
}

/// Wraps [child] with the minimum scaffolding the Library screens expect:
/// Aura theme, localization delegates, and Library/Player/Settings providers.
Widget libraryHarness({
  required Widget child,
  required LibraryCubit libraryCubit,
  PlayerCubit? playerCubit,
  SettingsCubit? settingsCubit,
  Size size = const Size(1000, 1600),
}) {
  return MediaQuery(
    data: MediaQueryData(size: size, disableAnimations: true),
    child: MultiBlocProvider(
      providers: [
        BlocProvider<LibraryCubit>.value(value: libraryCubit),
        BlocProvider<PlayerCubit>.value(
            value: playerCubit ?? stubPlayerCubit()),
        BlocProvider<SettingsCubit>.value(
            value: settingsCubit ?? stubSettingsCubit()),
      ],
      child: MaterialApp(
        theme: AuraTheme.darkTheme,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: child,
      ),
    ),
  );
}

/// A plain local song fixture.
SongsTableData testSong({
  required int id,
  String title = 'Test Song',
  String artist = 'Test Artist',
  String album = 'Test Album',
  int durationMs = 180000,
  String path = '/storage/music/test.mp3',
  bool isFavorite = false,
  bool isDownloaded = false,
  String source = SongSource.local,
  String? remoteId,
  String? remoteArtworkUrl,
  int? albumId,
}) {
  return SongsTableData(
    id: id,
    title: title,
    artist: artist,
    album: album,
    durationMs: durationMs,
    path: path,
    isFavorite: isFavorite,
    isMissing: false,
    playCount: 0,
    lastPositionMs: 0,
    source: source,
    isDownloaded: isDownloaded,
    remoteId: remoteId,
    remoteArtworkUrl: remoteArtworkUrl,
    albumId: albumId,
  );
}

/// A streaming YouTube favorite with no local file (belongs to the Online tab).
SongsTableData testOnlineSong({required int id, String title = 'Online Song'}) {
  return testSong(
    id: id,
    title: title,
    source: SongSource.youtube,
    path: 'ytmusic://video$id',
    remoteId: 'video$id',
  );
}
