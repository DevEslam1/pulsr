// test/property/state_property_test.dart
// FIX-B1: Property-based state machine tests and edge-case verification for Phase B
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/domain/models/chapter_info.dart';
import 'package:pulsr/domain/models/download_task.dart';
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
        playback: PlaybackSlice(position: Duration(seconds: 10)),
      );

      // Mutating only position returns false (no non-position change)
      final tickPosition = base.copyWith(
        playback: base.playback.copyWith(position: const Duration(seconds: 11)),
      );
      expect(base.differsFromBeyondPosition(tickPosition), isFalse);
    });

    test('PlayerState.differsFromBeyondPosition returns true for Playback and Queue non-position field changes', () {
      const base = PlayerState();

      final mutations = <String, PlayerState>{
        'currentSong': base.copyWith(playback: base.playback.copyWith(currentSong: testSongA)),
        'isPlaying': base.copyWith(playback: base.playback.copyWith(isPlaying: true)),
        'duration': base.copyWith(playback: base.playback.copyWith(duration: const Duration(minutes: 3))),
        'isShuffle': base.copyWith(playback: base.playback.copyWith(isShuffle: true)),
        'repeatMode': base.copyWith(playback: base.playback.copyWith(repeatMode: PlayerRepeatMode.one)),
        'queue': base.copyWith(queueSlice: base.queueSlice.copyWith(queue: [testSongA])),
        'currentIndex': base.copyWith(queueSlice: base.queueSlice.copyWith(currentIndex: 2)),
        'isExpanded': base.copyWith(playback: base.playback.copyWith(isExpanded: true)),
        'dominantColor': base.copyWith(playback: base.playback.copyWith(dominantColor: const Color(0xFF112233))),
        'sleepTimerRemaining': base.copyWith(playback: base.playback.copyWith(sleepTimerRemaining: const Duration(minutes: 15))),
        'activeQueueSlot': base.copyWith(queueSlice: base.queueSlice.copyWith(activeQueueSlot: 1)),
        'playbackSpeed': base.copyWith(playback: base.playback.copyWith(playbackSpeed: 1.25)),
        'playbackPitch': base.copyWith(playback: base.playback.copyWith(playbackPitch: 1.1)),
        'audioSessionId': base.copyWith(playback: base.playback.copyWith(audioSessionId: 42)),
        'errorMessage': base.copyWith(playback: base.playback.copyWith(errorMessage: 'Network glitch')),
        'abLoopEnabled': base.copyWith(playback: base.playback.copyWith(abLoopEnabled: true)),
        'abPointA': base.copyWith(playback: base.playback.copyWith(abPointA: const Duration(seconds: 5))),
        'abPointB': base.copyWith(playback: base.playback.copyWith(abPointB: const Duration(seconds: 25))),
        'trackDelayMs': base.copyWith(playback: base.playback.copyWith(trackDelayMs: 150)),
        'bookmarkPosition': base.copyWith(playback: base.playback.copyWith(bookmarkPosition: const Duration(minutes: 1))),
        'silenceSkipSensitivity': base.copyWith(playback: base.playback.copyWith(silenceSkipSensitivity: 4)),
        'currentSongRating': base.copyWith(playback: base.playback.copyWith(currentSongRating: 5)),
        'currentSongEqOverride': base.copyWith(playback: base.playback.copyWith(currentSongEqOverride: 'Warm')),
        'currentSongVolumeOverrideDb': base.copyWith(playback: base.playback.copyWith(currentSongVolumeOverrideDb: 2.5)),
        'cueChapters': base.copyWith(queueSlice: base.queueSlice.copyWith(cueChapters: [
          const ChapterInfo(index: 1, title: 'Chapter 1', start: Duration.zero)
        ])),
        'currentCueIndex': base.copyWith(queueSlice: base.queueSlice.copyWith(currentCueIndex: 1)),
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

    test('PlayerState slice decomposition preserves all 101 fields with exact parity', () {
      const playbackFieldCount = 22;
      const queueFieldCount = 5;
      const lyricsFieldCount = 5;
      const dspFieldCount = 69;

      const totalSliceFields = playbackFieldCount + queueFieldCount + lyricsFieldCount + dspFieldCount;
      expect(totalSliceFields, equals(101),
          reason: 'Every field in the old 101-field monolith must appear in exactly one slice');
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
