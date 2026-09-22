// test/property/state_property_test.dart
// FIX-B1: Property-based state machine tests and edge-case verification for Phase B
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/domain/models/audio_effects_config.dart';
import 'package:pulsr/domain/models/chapter_info.dart';
import 'package:pulsr/domain/models/download_task.dart';
import 'package:pulsr/domain/models/eq_preset.dart';
import 'package:pulsr/domain/models/headphone_profile.dart';
import 'package:pulsr/domain/models/lyrics_line.dart';
import 'package:pulsr/domain/models/quran_mode_profile.dart';
import 'package:pulsr/domain/models/smart_playlist_criteria.dart';
import 'package:pulsr/domain/repositories/music_repository_interface.dart';
import 'package:pulsr/domain/usecases/folder_usecases.dart';
import 'package:pulsr/domain/usecases/get_albums_usecase.dart';
import 'package:pulsr/domain/usecases/get_artists_usecase.dart';
import 'package:pulsr/domain/usecases/get_favorites_usecase.dart';
import 'package:pulsr/domain/usecases/get_genres_usecase.dart';
import 'package:pulsr/domain/usecases/get_songs_usecase.dart';
import 'package:pulsr/domain/usecases/get_years_usecase.dart';
import 'package:pulsr/domain/usecases/toggle_favorite_usecase.dart';
import 'package:pulsr/features/downloads/cubit/downloads_state.dart';
import 'package:pulsr/features/library/cubit/library_cubit.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';

class MockGetSongsUseCase extends Mock implements GetSongsUseCase {}
class MockGetAlbumsUseCase extends Mock implements GetAlbumsUseCase {}
class MockGetArtistsUseCase extends Mock implements GetArtistsUseCase {}
class MockGetGenresUseCase extends Mock implements GetGenresUseCase {}
class MockGetYearsUseCase extends Mock implements GetYearsUseCase {}
class MockGetFavoritesUseCase extends Mock implements GetFavoritesUseCase {}
class MockToggleFavoriteUseCase extends Mock implements ToggleFavoriteUseCase {}
class MockFolderUseCases extends Mock implements FolderUseCases {}
class MockMusicRepository extends Mock implements IMusicRepository {}

void main() {
  group('Phase B: Property-Based State Tests', () {
    const testSongA = SongsTableData(
      id: 1,
      title: 'Track A',
      artist: 'Artist A',
      album: 'Album A',
      durationMs: 180000,
      path: '/path/a.mp3',
      source: SongSource.local,
      playCount: 0,
      dateAdded: 0,
      isFavorite: false,
      isMissing: false,
      lastPositionMs: 0,
      isDownloaded: false,
    );

    test('PlayerState.differsFromBeyondPosition ignores position ticks', () {
      const base = PlayerState(
        position: Duration(seconds: 10),
      );

      // Mutating only position returns false (no non-position change)
      final tickPosition = base.copyWith(position: const Duration(seconds: 11));
      expect(base.differsFromBeyondPosition(tickPosition), isFalse);
    });

    test('PlayerState.differsFromBeyondPosition returns true for every single non-position field change', () {
      const base = PlayerState();

      final mutations = <String, PlayerState>{
        'currentSong': base.copyWith(currentSong: testSongA),
        'isPlaying': base.copyWith(isPlaying: true),
        'duration': base.copyWith(duration: const Duration(minutes: 3)),
        'isShuffle': base.copyWith(isShuffle: true),
        'repeatMode': base.copyWith(repeatMode: PlayerRepeatMode.one),
        'queue': base.copyWith(queue: [testSongA]),
        'currentIndex': base.copyWith(currentIndex: 2),
        'isExpanded': base.copyWith(isExpanded: true),
        'dominantColor': base.copyWith(dominantColor: const Color(0xFF112233)),
        'sleepTimerRemaining': base.copyWith(sleepTimerRemaining: const Duration(minutes: 15)),
        'lyrics': base.copyWith(lyrics: [
          const LyricsLine(timestamp: Duration(seconds: 1), text: 'Lyrics line')
        ]),
        'lyricsSource': base.copyWith(lyricsSource: LyricsSource.embedded),
        'isLoadingLyrics': base.copyWith(isLoadingLyrics: true),
        'isLyricsVisible': base.copyWith(isLyricsVisible: true),
        'isQueueVisible': base.copyWith(isQueueVisible: true),
        'eqPreset': base.copyWith(eqPreset: const EqPreset(name: 'Rock', gains: [1.0, 2.0])),
        'isEqEnabled': base.copyWith(isEqEnabled: true),
        'isVirtualizerEnabled': base.copyWith(isVirtualizerEnabled: true),
        'virtualizerStrength': base.copyWith(virtualizerStrength: 0.8),
        'isVirtualizerSupported': base.copyWith(isVirtualizerSupported: true),
        'isDynamicsEnabled': base.copyWith(isDynamicsEnabled: true),
        'isDynamicsSupported': base.copyWith(isDynamicsSupported: true),
        'dynamicsPreset': base.copyWith(dynamicsPreset: DynamicsPreset.nightLeveller),
        'selectedHeadphoneProfile': base.copyWith(
          selectedHeadphoneProfile: const HeadphoneProfile(
            id: 'dt990',
            name: 'Audiophile 990',
            brand: 'Beyerdynamic',
            model: 'DT 990',
            category: 'Over-Ear',
            gains: [0.0],
          ),
        ),
        'isSpatializerSupported': base.copyWith(isSpatializerSupported: true),
        'isSpatializerEnabled': base.copyWith(isSpatializerEnabled: true),
        'volumeBoost': base.copyWith(volumeBoost: 1.5),
        'isVolumeBoostSupported': base.copyWith(isVolumeBoostSupported: true),
        'isBassBoostSupported': base.copyWith(isBassBoostSupported: true),
        'isCrossfeedEnabled': base.copyWith(isCrossfeedEnabled: true),
        'crossfeedDelayUs': base.copyWith(crossfeedDelayUs: 250.0),
        'crossfeedFeedDb': base.copyWith(crossfeedFeedDb: -6.0),
        'crossfeedMode': base.copyWith(crossfeedMode: 2),
        'isLimiterEnabled': base.copyWith(isLimiterEnabled: true),
        'limiterThresholdDb': base.copyWith(limiterThresholdDb: -0.5),
        'limiterReleaseMs': base.copyWith(limiterReleaseMs: 40.0),
        'isReverbEnabled': base.copyWith(isReverbEnabled: true),
        'reverbPreset': base.copyWith(reverbPreset: 3),
        'reverbWetDry': base.copyWith(reverbWetDry: 0.4),
        'stereoBalance': base.copyWith(stereoBalance: -0.2),
        'monoMix': base.copyWith(monoMix: true),
        'isSincResamplerEnabled': base.copyWith(isSincResamplerEnabled: false),
        'isDitherEnabled': base.copyWith(isDitherEnabled: true),
        'ditherTargetBitDepth': base.copyWith(ditherTargetBitDepth: 24),
        'isSaturationEnabled': base.copyWith(isSaturationEnabled: true),
        'saturationDrive': base.copyWith(saturationDrive: 0.7),
        'saturationMix': base.copyWith(saturationMix: 0.85),
        'saturationTilt': base.copyWith(saturationTilt: 0.1),
        'saturationMultiband': base.copyWith(saturationMultiband: true),
        'isStereoWidthEnabled': base.copyWith(isStereoWidthEnabled: true),
        'stereoWidth': base.copyWith(stereoWidth: 1.2),
        'isLoudnessContourEnabled': base.copyWith(isLoudnessContourEnabled: true),
        'loudnessContourIntensity': base.copyWith(loudnessContourIntensity: 0.6),
        'isSubCrossoverEnabled': base.copyWith(isSubCrossoverEnabled: true),
        'subCrossoverCornerHz': base.copyWith(subCrossoverCornerHz: 120.0),
        'subCrossoverSlopeDbPerOct': base.copyWith(subCrossoverSlopeDbPerOct: 18.0),
        'subCrossoverGain': base.copyWith(subCrossoverGain: 1.0),
        'subCrossoverBassMono': base.copyWith(subCrossoverBassMono: true),
        'subCrossoverAntiPop': base.copyWith(subCrossoverAntiPop: false),
        'stereoWidthMultiband': base.copyWith(stereoWidthMultiband: true),
        'stereoWidthLow': base.copyWith(stereoWidthLow: 0.9),
        'stereoWidthMid': base.copyWith(stereoWidthMid: 1.1),
        'stereoWidthHigh': base.copyWith(stereoWidthHigh: 1.3),
        'stereoWidthLowCrossoverHz': base.copyWith(stereoWidthLowCrossoverHz: 200.0),
        'stereoWidthHighCrossoverHz': base.copyWith(stereoWidthHighCrossoverHz: 3000.0),
        'multibandCompressorF0': base.copyWith(multibandCompressorF0: 180.0),
        'multibandCompressorF1': base.copyWith(multibandCompressorF1: 1200.0),
        'multibandCompressorF2': base.copyWith(multibandCompressorF2: 6000.0),
        'isDynamicEqEnabled': base.copyWith(isDynamicEqEnabled: true),
        'isViperDdcEnabled': base.copyWith(isViperDdcEnabled: true),
        'viperDdcProfileName': base.copyWith(viperDdcProfileName: 'HD650.vdc'),
        'isArbitraryEqEnabled': base.copyWith(isArbitraryEqEnabled: true),
        'arbitraryEqString': base.copyWith(arbitraryEqString: '100:2.0;1000:-1.5'),
        'isLiveProgEnabled': base.copyWith(isLiveProgEnabled: true),
        'liveProgCode': base.copyWith(liveProgCode: 'y=x*0.9;'),
        'liveProgStatus': base.copyWith(liveProgStatus: 'Running'),
        'isDynamicBassEnabled': base.copyWith(isDynamicBassEnabled: true),
        'dynamicBassStrength': base.copyWith(dynamicBassStrength: 0.75),
        'dynamicBassPreset': base.copyWith(dynamicBassPreset: 2),
        'hasOemAudio': base.copyWith(hasOemAudio: true),
        'detectedOemEngines': base.copyWith(detectedOemEngines: ['DolbyAtmos']),
        'activeQueueSlot': base.copyWith(activeQueueSlot: 1),
        'playbackSpeed': base.copyWith(playbackSpeed: 1.25),
        'playbackPitch': base.copyWith(playbackPitch: 1.1),
        'audioSessionId': base.copyWith(audioSessionId: 42),
        'errorMessage': base.copyWith(errorMessage: 'Network glitch'),
        'abLoopEnabled': base.copyWith(abLoopEnabled: true),
        'abPointA': base.copyWith(abPointA: const Duration(seconds: 5)),
        'abPointB': base.copyWith(abPointB: const Duration(seconds: 25)),
        'trackDelayMs': base.copyWith(trackDelayMs: 150),
        'bookmarkPosition': base.copyWith(bookmarkPosition: const Duration(minutes: 1)),
        'silenceSkipSensitivity': base.copyWith(silenceSkipSensitivity: 4),
        'currentSongRating': base.copyWith(currentSongRating: 5),
        'currentSongEqOverride': base.copyWith(currentSongEqOverride: 'Warm'),
        'currentSongVolumeOverrideDb': base.copyWith(currentSongVolumeOverrideDb: 2.5),
        'cueChapters': base.copyWith(cueChapters: [
          const ChapterInfo(index: 1, title: 'Chapter 1', start: Duration.zero)
        ]),
        'currentCueIndex': base.copyWith(currentCueIndex: 1),
        'isQuranModeEnabled': base.copyWith(isQuranModeEnabled: true),
        'quranReciterStyle': base.copyWith(quranReciterStyle: QuranReciterStyle.mujawwad),
      };

      for (final entry in mutations.entries) {
        final fieldName = entry.key;
        final mutatedState = entry.value;
        expect(
          base.differsFromBeyondPosition(mutatedState),
          isTrue,
          reason: 'Field $fieldName change should be detected by differsFromBeyondPosition',
        );
      }
    });

    test('DownloadsState & DownloadStatus state machine transitions and predicates', () {
      expect(DownloadStatus.queued.isActive, isTrue);
      expect(DownloadStatus.downloading.isActive, isTrue);
      expect(DownloadStatus.tagging.isActive, isTrue);
      expect(DownloadStatus.paused.isActive, isFalse);
      expect(DownloadStatus.failed.isActive, isFalse);
      expect(DownloadStatus.complete.isActive, isFalse);

      expect(DownloadStatus.complete.isTerminal, isTrue);
      expect(DownloadStatus.failed.isTerminal, isTrue);
      expect(DownloadStatus.downloading.isTerminal, isFalse);

      expect(DownloadStatus.downloading.canPause, isTrue);
      expect(DownloadStatus.paused.canResume, isTrue);
      expect(DownloadStatus.failed.canRetry, isTrue);
      expect(DownloadStatus.complete.canRetry, isFalse);

      final task = DownloadTask(
        id: 'dl_1',
        videoId: 'vid_123',
        title: 'Downloading Song',
        artist: 'Artist',
        createdAt: DateTime.now(),
      );

      final state = DownloadsState(tasks: {'dl_1': task});
      expect(state.activeCount, 1);
      expect(state.completedCount, 0);

      final completedState = state.copyWith(tasks: {
        'dl_1': task.copyWith(status: DownloadStatus.complete, progress: 1.0),
      });
      expect(completedState.activeCount, 0);
      expect(completedState.completedCount, 1);
    });

    test('SmartCriteria operator x field combinatorial matrix produces valid JSON', () {
      for (final field in SmartRuleField.values) {
        for (final op in SmartOperator.values) {
          final rule = SmartRule(
            field: field,
            operator: op,
            value: 'test_value',
          );
          final criteria = SmartCriteria(rules: [rule], limit: 25, sortBy: 'playCount');
          final jsonString = criteria.toJsonString();
          final decoded = SmartCriteria.fromJsonString(jsonString);

          expect(decoded.rules.length, equals(1));
          expect(decoded.rules.first.field, equals(field));
          expect(decoded.rules.first.operator, equals(op));
          expect(decoded.rules.first.value, equals('test_value'));
          expect(decoded.limit, equals(25));
        }
      }
    });

    test('Edge case: LibraryCubit.toggleFavorite is a no-op when closed', () async {
      final mockSongs = MockGetSongsUseCase();
      final mockAlbums = MockGetAlbumsUseCase();
      final mockArtists = MockGetArtistsUseCase();
      final mockGenres = MockGetGenresUseCase();
      final mockYears = MockGetYearsUseCase();
      final mockFavorites = MockGetFavoritesUseCase();
      final mockToggle = MockToggleFavoriteUseCase();
      final mockFolders = MockFolderUseCases();

      when(() => mockSongs.watchSongs(limit: any(named: 'limit'), sortBy: any(named: 'sortBy'), ascending: any(named: 'ascending')))
          .thenAnswer((_) => const Stream.empty());
      when(() => mockAlbums.watchAlbums())
          .thenAnswer((_) => const Stream.empty());
      when(() => mockArtists.watchArtists())
          .thenAnswer((_) => const Stream.empty());
      when(() => mockGenres.watchGenres()).thenAnswer((_) => const Stream.empty());
      when(() => mockYears.watchYears()).thenAnswer((_) => const Stream.empty());
      when(() => mockFavorites.watchFavorites()).thenAnswer((_) => const Stream.empty());
      when(() => mockFolders.getExcludedFolders()).thenAnswer((_) async => const Right([]));

      final cubit = LibraryCubit(
        getSongsUseCase: mockSongs,
        getAlbumsUseCase: mockAlbums,
        getArtistsUseCase: mockArtists,
        getGenresUseCase: mockGenres,
        getYearsUseCase: mockYears,
        getFavoritesUseCase: mockFavorites,
        toggleFavoriteUseCase: mockToggle,
        folderUseCases: mockFolders,
      );

      await cubit.close();
      // Calling toggleFavorite on closed cubit must not throw and must not call use case
      await cubit.toggleFavorite(999);
      verifyNever(() => mockToggle.call(any()));
    });
  });
}
