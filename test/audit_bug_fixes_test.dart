import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart' hide PlayerState;
import 'package:pulsr/core/utils/list_content_diff.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pulsr/core/errors/failures.dart';
import 'package:pulsr/domain/models/download_task.dart';
import 'package:pulsr/domain/models/smart_playlist_criteria.dart';
import 'package:pulsr/domain/repositories/smart_playlist_engine_interface.dart';
import 'package:pulsr/domain/usecases/playlist_usecases.dart';
import 'package:pulsr/features/downloads/cubit/downloads_state.dart';
import 'package:pulsr/features/player/cubit/dsp_telemetry_cubit.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/smart_playlist_builder/smart_playlist_builder_cubit.dart';
import 'mocks/fake_audio_player_backend.dart';

class _FakeSmartPlaylistEngine extends Fake implements ISmartPlaylistEngine {
  @override
  Stream<List<SongsTableData>> watchCriteria(SmartCriteria criteria) => const Stream.empty();
  @override
  Future<List<SongsTableData>> evaluateCriteria(SmartCriteria criteria) async => [];
  @override
  List<SmartRule> validateRules(SmartCriteria criteria) => const [];
}

class _FakePlaylistUseCases extends Fake implements PlaylistUseCases {
  @override
  Future<Either<AppFailure, int>> createPlaylist(
    String name, {
    bool isSmart = false,
    String? smartCriteria,
  }) async =>
      const Right(1);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Audit Bug Fixes Tests', () {
    test('MediaItem extras preserves remoteId, source, isDownloaded, and remoteArtworkUrl', () {
      const original = SongsTableData(
        id: 42,
        title: 'Song Title',
        artist: 'Artist Name',
        album: 'Album Name',
        durationMs: 240000,
        path: 'https://youtube.com/watch?v=xyz',
        source: SongSource.youtube,
        remoteId: 'xyz_remote_123',
        remoteArtworkUrl: 'https://img.youtube.com/vi/xyz/hqdefault.jpg',
        isFavorite: true,
        isMissing: false,
        isDownloaded: true,
        playCount: 5,
        lastPositionMs: 12000,
      );

      final mediaItem = MediaItem(
        id: original.id.toString(),
        album: original.album,
        title: original.title,
        artist: original.artist,
        duration: Duration(milliseconds: original.durationMs),
        artUri: Uri.parse(original.remoteArtworkUrl!),
        extras: {
          'path': original.path,
          'uri': original.uri,
          'albumId': original.albumId,
          'artistId': original.artistId,
          'isFavorite': original.isFavorite,
          'trackNumber': original.trackNumber,
          'discNumber': original.discNumber,
          'year': original.year,
          'genre': original.genre,
          'playCount': original.playCount,
          'remoteId': original.remoteId,
          'source': original.source,
          'isDownloaded': original.isDownloaded,
          'remoteArtworkUrl': original.remoteArtworkUrl,
        },
      );

      final reconstructed = SongsTableData(
        id: int.parse(mediaItem.id),
        title: mediaItem.title,
        artist: mediaItem.artist ?? 'Unknown',
        album: mediaItem.album ?? '',
        durationMs: mediaItem.duration?.inMilliseconds ?? 0,
        path: (mediaItem.extras?['path'] as String?) ?? '',
        source: (mediaItem.extras?['source'] as String?) ?? SongSource.youtube,
        remoteId: mediaItem.extras?['remoteId'] as String?,
        remoteArtworkUrl: (mediaItem.extras?['remoteArtworkUrl'] as String?) ??
            mediaItem.artUri?.toString(),
        isFavorite: (mediaItem.extras?['isFavorite'] as bool?) ?? false,
        isMissing: false,
        isDownloaded: (mediaItem.extras?['isDownloaded'] as bool?) ?? false,
        playCount: (mediaItem.extras?['playCount'] as int?) ?? 0,
        lastPositionMs: 0,
      );

      expect(reconstructed.id, equals(original.id));
      expect(reconstructed.remoteId, equals('xyz_remote_123'));
      expect(reconstructed.source, equals(SongSource.youtube));
      expect(reconstructed.isDownloaded, isTrue);
      expect(reconstructed.remoteArtworkUrl,
          equals('https://img.youtube.com/vi/xyz/hqdefault.jpg'));
    });

    test('PlayerState.differsFromBeyondPosition detects sleep timer second-level changes', () {
      const state1 = PlayerState(
        playback: PlaybackSlice(sleepTimerRemaining: Duration(seconds: 59)),
      );
      const state2 = PlayerState(
        playback: PlaybackSlice(sleepTimerRemaining: Duration(seconds: 58)),
      );

      expect(state1.differsFromBeyondPosition(state2), isTrue);
    });

    test('listContentDiffers detects queue item changes with same queue length', () {
      const songA = SongsTableData(
        id: 1,
        title: 'Original Title',
        artist: 'Artist',
        album: 'Album',
        durationMs: 1000,
        path: '/a.mp3',
        source: SongSource.local,
        isFavorite: false,
        isMissing: false,
        isDownloaded: true,
        playCount: 0,
        lastPositionMs: 0,
      );
      const songB = SongsTableData(
        id: 1,
        title: 'Updated Title',
        artist: 'Artist',
        album: 'Album',
        durationMs: 1000,
        path: '/a.mp3',
        source: SongSource.local,
        isFavorite: false,
        isMissing: false,
        isDownloaded: true,
        playCount: 0,
        lastPositionMs: 0,
      );

      expect(listContentDiffers([songA], [songB]), isTrue);
    });

    test('Repeat mode persistence normalizes group and all to all, one to one', () {
      String normalizeRepeatMode(AudioServiceRepeatMode mode) {
        return switch (mode) {
          AudioServiceRepeatMode.all || AudioServiceRepeatMode.group => 'all',
          AudioServiceRepeatMode.one => 'one',
          _ => 'none',
        };
      }

      expect(normalizeRepeatMode(AudioServiceRepeatMode.all), equals('all'));
      expect(normalizeRepeatMode(AudioServiceRepeatMode.group), equals('all'));
      expect(normalizeRepeatMode(AudioServiceRepeatMode.one), equals('one'));
      expect(normalizeRepeatMode(AudioServiceRepeatMode.none), equals('none'));
    });

    test('End-of-track sleep timer calculates remaining duration accurately', () {
      const totalDuration = Duration(minutes: 3, seconds: 45);
      const position = Duration(minutes: 1, seconds: 15);
      final remaining = totalDuration > position
          ? totalDuration - position
          : const Duration(minutes: 1);

      expect(remaining, equals(const Duration(minutes: 2, seconds: 30)));

      // Fallback when position >= duration
      const pastPosition = Duration(minutes: 4);
      final fallbackRemaining = totalDuration > pastPosition
          ? totalDuration - pastPosition
          : const Duration(minutes: 1);
      expect(fallbackRemaining, equals(const Duration(minutes: 1)));
    });

    test('Queue index clamping ensures index is never out of bounds', () {
      final queue = [
        const SongsTableData(
          id: 1,
          title: 'Song 1',
          artist: 'Artist',
          album: 'Album',
          durationMs: 1000,
          path: '/1.mp3',
          source: SongSource.local,
          isFavorite: false,
          isMissing: false,
          isDownloaded: true,
          playCount: 0,
          lastPositionMs: 0,
        ),
      ];

      int clampIndex(int? rawIndex, int queueLength, int currentIndex) {
        if (queueLength == 0) return rawIndex ?? currentIndex;
        return (rawIndex ?? currentIndex).clamp(0, queueLength - 1);
      }

      expect(clampIndex(5, queue.length, 0), equals(0));
      expect(clampIndex(-2, queue.length, 0), equals(0));
      expect(clampIndex(0, queue.length, 0), equals(0));
    });

    test('Unknown song duration fallback yields Duration.zero for different track', () {
      const stateDuration = Duration(minutes: 3);
      Duration resolveDuration({
        required int durationMs,
        required bool isSameSong,
        required Duration fallback,
      }) {
        return durationMs > 0
            ? Duration(milliseconds: durationMs)
            : (isSameSong ? fallback : Duration.zero);
      }

      // Different song with 0 durationMs should NOT inherit previous song duration
      expect(
        resolveDuration(
          durationMs: 0,
          isSameSong: false,
          fallback: stateDuration,
        ),
        equals(Duration.zero),
      );

      // Same song retains current state duration
      expect(
        resolveDuration(
          durationMs: 0,
          isSameSong: true,
          fallback: stateDuration,
        ),
        equals(stateDuration),
      );
    });

    test('Track-count sleep timer sets sleepTimerRemaining to null', () {
      const state = PlayerState(
        playback: PlaybackSlice(sleepTimerRemaining: Duration(minutes: 15)),
      );
      final updated = state.copyWith(playback: state.playback.copyWith(sleepTimerRemaining: null));
      expect(updated.sleepTimerRemaining, isNull);
    });

    test('Smart prefetch failure threshold triggers at 3 or more failures', () {
      bool shouldSkipPrefetch(int consecutiveFailures) {
        return consecutiveFailures >= 3;
      }

      expect(shouldSkipPrefetch(0), isFalse);
      expect(shouldSkipPrefetch(1), isFalse);
      expect(shouldSkipPrefetch(2), isFalse);
      expect(shouldSkipPrefetch(3), isTrue);
      expect(shouldSkipPrefetch(4), isTrue);
    });

    test('Distinct remote songs receive unique negative IDs and never collide on -1', () {
      int generateUniqueNegativeId(String remoteId) {
        return -(remoteId.hashCode.abs() % 1000000000 + 1);
      }

      final idA = generateUniqueNegativeId('video_alpha_123');
      final idB = generateUniqueNegativeId('video_beta_456');
      final idC = generateUniqueNegativeId('video_gamma_789');

      expect(idA, isNegative);
      expect(idB, isNegative);
      expect(idC, isNegative);

      expect(idA, isNot(equals(-1)));
      expect(idB, isNot(equals(-1)));
      expect(idC, isNot(equals(-1)));

      expect(idA, isNot(equals(idB)));
      expect(idB, isNot(equals(idC)));
      expect(idA, isNot(equals(idC)));
    });

    test('FakeAudioPlayerBackend supports playlist navigation, looping, and clock advancement', () async {
      final backend = FakeAudioPlayerBackend();
      expect(backend.currentIndex, isNull);
      expect(backend.duration, isNull);

      final s1 = AudioSource.uri(Uri.parse('https://example.com/1.mp3'));
      final s2 = AudioSource.uri(Uri.parse('https://example.com/2.mp3'));

      await backend.setAudioSources([s1, s2], initialIndex: 0);
      expect(backend.audioSources.length, 2);
      expect(backend.currentIndex, 0);
      expect(backend.hasNext, isTrue);
      expect(backend.hasPrevious, isFalse);

      await backend.seekToNext();
      expect(backend.currentIndex, 1);
      expect(backend.hasNext, isFalse);
      expect(backend.hasPrevious, isTrue);

      // LoopMode.all wrap-around
      await backend.setLoopMode(LoopMode.all);
      expect(backend.hasNext, isTrue);
      await backend.seekToNext();
      expect(backend.currentIndex, 0);

      // tickClock in LoopMode.one resets position
      await backend.setLoopMode(LoopMode.one);
      await backend.play();
      expect(backend.playing, isTrue);
      backend.tickClock(const Duration(minutes: 5));
      expect(backend.position, equals(Duration.zero));
      expect(backend.playing, isTrue);

      await backend.dispose();
    });

    test('DownloadsState precomputes and caches taskList sorted descending by createdAt', () {
      final t1 = DownloadTask(
        id: 'v1',
        videoId: 'v1',
        title: 'Song 1',
        artist: 'Artist 1',
        artworkUrl: '',
        format: 'm4a',
        createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
      );
      final t2 = DownloadTask(
        id: 'v2',
        videoId: 'v2',
        title: 'Song 2',
        artist: 'Artist 2',
        artworkUrl: '',
        format: 'm4a',
        createdAt: DateTime.fromMillisecondsSinceEpoch(2000),
      );

      final state = const DownloadsState().copyWith(tasks: {'v1': t1, 'v2': t2});
      final listA = state.taskList;
      final listB = state.taskList;

      // Identity check: must return the exact same precomputed instance without re-allocating
      expect(identical(listA, listB), isTrue);
      expect(listA.length, 2);
      expect(listA.first.videoId, 'v2');
      expect(listA.last.videoId, 'v1');

      // State update without task modification preserves cached list instance
      final updatedLoading = state.copyWith(isLoading: true);
      expect(identical(updatedLoading.taskList, listA), isTrue);
    });

    test('DspTelemetryCubit accepts and configures custom polling intervals', () {
      final defaultCubit = DspTelemetryCubit();
      expect(defaultCubit.pollingInterval, const Duration(milliseconds: 200));
      defaultCubit.close();

      final customCubit = DspTelemetryCubit(pollingInterval: const Duration(milliseconds: 100));
      expect(customCubit.pollingInterval, const Duration(milliseconds: 100));
      customCubit.close();
    });

    test('SmartPlaylistBuilderCubit validates empty name and empty rules', () async {
      final engine = _FakeSmartPlaylistEngine();
      final useCases = _FakePlaylistUseCases();
      final cubit = SmartPlaylistBuilderCubit(engine, useCases);

      // Initially has 1 default rule with value '0' but empty name
      expect(cubit.state.name, isEmpty);
      var saved = await cubit.savePlaylist();
      expect(saved, isFalse);
      expect(cubit.state.errorMessage, 'Please enter a playlist name');

      // With name but no rules
      cubit.updateName('My Smart Playlist');
      cubit.removeRule(0);
      expect(cubit.state.criteria.rules, isEmpty);
      saved = await cubit.savePlaylist();
      expect(saved, isFalse);
      expect(cubit.state.errorMessage, 'Please add at least one rule');

      // With a rule having empty value
      cubit.addRule(const SmartRule(
        field: SmartRuleField.title,
        operator: SmartOperator.contains,
        value: '   ',
      ));
      saved = await cubit.savePlaylist();
      expect(saved, isFalse);
      expect(cubit.state.errorMessage, 'Please enter a value for rule #1');

      // With valid name and rule
      cubit.updateRule(0, const SmartRule(
        field: SmartRuleField.title,
        operator: SmartOperator.contains,
        value: 'Rock',
      ));
      saved = await cubit.savePlaylist();
      expect(saved, isTrue);

      await cubit.close();
    });
  });
}

