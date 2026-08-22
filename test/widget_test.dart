// test/widget_test.dart
import 'package:audio_service/audio_service.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/di/injection.dart';
import 'package:pulsr/core/theme/dynamic_theme_cubit.dart';
import 'package:pulsr/data/audio/audio_handler.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/data/repositories/music_repository.dart';
import 'package:pulsr/data/repositories/smart_playlist_engine.dart';
import 'package:pulsr/data/scanner/media_scanner_service.dart';
import 'package:pulsr/domain/repositories/music_repository_interface.dart';
import 'package:pulsr/domain/usecases/folder_usecases.dart';
import 'package:pulsr/domain/usecases/get_albums_usecase.dart';
import 'package:pulsr/domain/usecases/get_artists_usecase.dart';
import 'package:pulsr/domain/usecases/get_genres_usecase.dart';
import 'package:pulsr/domain/models/audio_effects_config.dart';
import 'package:pulsr/domain/models/eq_preset.dart';
import 'package:pulsr/domain/models/headphone_profile.dart';
import 'package:pulsr/domain/usecases/get_years_usecase.dart';
import 'package:pulsr/domain/usecases/get_favorites_usecase.dart';
import 'package:pulsr/domain/usecases/get_songs_usecase.dart';
import 'package:pulsr/domain/usecases/playlist_usecases.dart';
import 'package:pulsr/domain/usecases/search_music_usecase.dart';
import 'package:pulsr/domain/usecases/toggle_favorite_usecase.dart';
import 'package:pulsr/features/library/cubit/library_cubit.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/playlists/cubit/playlist_cubit.dart';
import 'package:pulsr/features/search/cubit/search_cubit.dart';
import 'package:pulsr/features/settings/cubit/settings_cubit.dart';
import 'package:pulsr/features/widgets/widget_service.dart';
import 'package:pulsr/main.dart';

import 'package:shared_preferences/shared_preferences.dart';

class MockPulsrAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler implements PulsrAudioHandler {
  MockPulsrAudioHandler() {
    playbackState.add(PlaybackState(
      controls: [],
      systemActions: const {},
      processingState: AudioProcessingState.idle,
      playing: false,
    ));
    queue.add([]);
  }

  @override
  double get volume => 1.0;
  @override
  SongsTableData? get currentSong => null;
  @override
  Future<void> setVolume(double volume) async {}
  @override
  bool get isEqualizerEnabled => false;
  @override
  EqPreset get currentPreset => EqPreset.defaultPresets.first;
  @override
  Duration get crossfadeDuration => Duration.zero;
  @override
  Stream<Duration> get positionStream => const Stream.empty();
  @override
  void setCrossfadeDuration(Duration d) {}
  @override
  Future<void> restoreLastPlaybackSession() async {}
  @override
  void saveCurrentPositionImmediate() {}
  @override
  Future<void> setEqualizerEnabled(bool enabled) async {}
  @override
  Future<void> applyPreset(EqPreset preset) async {}
  @override
  Future<void> setBandGain(int bandIndex, double gainDb) async {}
  @override
  Future<void> setBassBoost(double amount) async {}
  @override
  bool get isVirtualizerEnabled => false;
  @override
  double get virtualizerStrength => 0.0;
  @override
  bool get isDynamicsEnabled => false;
  @override
  DynamicsPreset get dynamicsPreset => DynamicsPreset.off;
  @override
  HeadphoneProfile? get selectedHeadphoneProfile => null;
  @override
  Future<void> setVirtualizerEnabled(bool enabled) async {}
  @override
  Future<void> setVirtualizerStrength(double strength) async {}
  @override
  Future<void> setDynamicsPreset(DynamicsPreset preset, {bool? enabled}) async {}
  @override
  Future<void> applyHeadphoneProfile(HeadphoneProfile? profile) async {}
  @override
  bool get isSpatializerEnabled => false;
  @override
  bool get isSpatializerSupported => false;
  @override
  Future<void> setSpatializerEnabled(bool enabled) async {}
  @override
  double get volumeBoost => 0.0;
  @override
  Future<void> setVolumeBoost(double value) async {}
  @override
  void startSleepTimer(Duration duration, {bool fadeOut = true}) {}
  @override
  void startAbsoluteSleepTimer(DateTime stopTime, {bool fadeOut = true}) {}
  @override
  void cancelSleepTimer() {}
  @override
  Future<void> insertNextInQueue(SongsTableData song) async {}
  @override
  Future<void> addToQueueEnd(SongsTableData song) async {}
  @override
  Future<void> reorderQueue(int oldIndex, int newIndex) async {}
  @override
  Future<void> removeQueueItemAt(int index) async {}
  @override
  Future<void> loadQueue(List<SongsTableData> songs, {int initialIndex = 0, Duration? initialPosition}) async {}
  @override
  Stream<Duration?> get sleepTimerRemainingStream => const Stream.empty();
  @override
  void dispose() {}
  @override
  Future<void> playSongAt(int index, {Duration? initialPosition}) async {}
}

void main() {
  setUp(() async {
    await getIt.reset();
  });

  testWidgets('App smoke test', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final repo = MusicRepository(db);
    final smartEngine = SmartPlaylistEngine(db);
    final audioHandler = MockPulsrAudioHandler();
    final scannerService = MediaScannerService(repo);

    final getSongsUseCase = GetSongsUseCase(repo);
    final getAlbumsUseCase = GetAlbumsUseCase(repo);
    final getArtistsUseCase = GetArtistsUseCase(repo);
    final getGenresUseCase = GetGenresUseCase(repo);
    final getYearsUseCase = GetYearsUseCase(repo);
    final getFavoritesUseCase = GetFavoritesUseCase(repo);
    final toggleFavoriteUseCase = ToggleFavoriteUseCase(repo);
    final searchMusicUseCase = SearchMusicUseCase(repo);
    final playlistUseCases = PlaylistUseCases(repo, smartEngine);
    final folderUseCases = FolderUseCases(repo);
    final widgetService = WidgetService();

    getIt.registerSingleton<AppDatabase>(db);
    getIt.registerSingleton<IMusicRepository>(repo);
    getIt.registerSingleton<MusicRepository>(repo);
    getIt.registerSingleton<PulsrAudioHandler>(audioHandler);
    getIt.registerSingleton<MediaScannerService>(scannerService);
    getIt.registerSingleton<GetSongsUseCase>(getSongsUseCase);
    getIt.registerSingleton<GetAlbumsUseCase>(getAlbumsUseCase);
    getIt.registerSingleton<GetArtistsUseCase>(getArtistsUseCase);
    getIt.registerSingleton<GetGenresUseCase>(getGenresUseCase);
    getIt.registerSingleton<GetYearsUseCase>(getYearsUseCase);
    getIt.registerSingleton<GetFavoritesUseCase>(getFavoritesUseCase);
    getIt.registerSingleton<ToggleFavoriteUseCase>(toggleFavoriteUseCase);
    getIt.registerSingleton<SearchMusicUseCase>(searchMusicUseCase);
    getIt.registerSingleton<PlaylistUseCases>(playlistUseCases);
    getIt.registerSingleton<FolderUseCases>(folderUseCases);
    getIt.registerSingleton<WidgetService>(widgetService);

    getIt.registerSingleton<DynamicThemeCubit>(DynamicThemeCubit());
    getIt.registerFactory<PlayerCubit>(() => PlayerCubit(
          audioHandler: audioHandler,
          repository: repo,
          toggleFavoriteUseCase: toggleFavoriteUseCase,
        ));
    getIt.registerFactory<LibraryCubit>(() => LibraryCubit(
          getSongsUseCase: getSongsUseCase,
          getAlbumsUseCase: getAlbumsUseCase,
          getArtistsUseCase: getArtistsUseCase,
          getGenresUseCase: getGenresUseCase,
          getYearsUseCase: getYearsUseCase,
          getFavoritesUseCase: getFavoritesUseCase,
          toggleFavoriteUseCase: toggleFavoriteUseCase,
          folderUseCases: folderUseCases,
        ));
    getIt.registerFactory<SearchCubit>(
        () => SearchCubit(searchUseCase: searchMusicUseCase, folderUseCases: folderUseCases));
    getIt.registerFactory<PlaylistCubit>(
        () => PlaylistCubit(playlistUseCases: playlistUseCases));
    getIt.registerSingleton<SettingsCubit>(
        SettingsCubit(scannerService: scannerService));

    await tester.runAsync(() async {
      await tester.pumpWidget(const PulsrApp());
      await tester.pump();
      expect(find.byType(PulsrApp), findsOneWidget);
      // Splash shows first
      expect(find.text('Pulsr Music'), findsOneWidget);
      await Future.delayed(const Duration(milliseconds: 100));
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      await audioHandler.stop();
      await db.close();
    });
  });
}
