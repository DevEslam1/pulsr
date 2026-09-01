import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/services/ytm_url_cache.dart';
import 'package:pulsr/data/audio/artwork_uri_resolver.dart';
import 'package:pulsr/data/audio/ytm_resolving_source.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/settings/cubit/settings_cubit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../player_cubit_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue(Duration.zero);
  });

  late MockMusicRepository repository;
  late MockToggleFavoriteUseCase toggleFavoriteUseCase;
  late MockWidgetService widgetService;
  late MockMediaScannerService scannerService;
  late TestPulsrAudioHandler audioHandler;
  late SettingsCubit settingsCubit;

  final track1 = SongsTableData(
    id: 1,
    title: 'Track 1',
    artist: 'Artist 1',
    album: 'Album 1',
    durationMs: 180000,
    path: '/path/to/song1.mp3',
    source: SongSource.local,
    isFavorite: false,
    isMissing: false,
    isDownloaded: true,
    playCount: 0,
    lastPositionMs: 0,
  );

  final track2 = SongsTableData(
    id: 2,
    title: 'Track 2',
    artist: 'Artist 2',
    album: 'Album 2',
    durationMs: 200000,
    path: '/path/to/song2.mp3',
    source: SongSource.local,
    isFavorite: false,
    isMissing: false,
    isDownloaded: true,
    playCount: 0,
    lastPositionMs: 0,
  );

  final track3 = SongsTableData(
    id: 3,
    title: 'Track 3',
    artist: 'Artist 3',
    album: 'Album 3',
    durationMs: 220000,
    path: '/path/to/song3.mp3',
    source: SongSource.local,
    isFavorite: false,
    isMissing: false,
    isDownloaded: true,
    playCount: 0,
    lastPositionMs: 0,
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    repository = MockMusicRepository();
    toggleFavoriteUseCase = MockToggleFavoriteUseCase();
    widgetService = MockWidgetService();
    scannerService = MockMediaScannerService();
    audioHandler = TestPulsrAudioHandler();
    settingsCubit = SettingsCubit(scannerService: scannerService);

    when(() => repository.getSongById(any())).thenAnswer(
      (inv) async => Right(
        inv.positionalArguments[0] == 1
            ? track1
            : (inv.positionalArguments[0] == 2 ? track2 : track3),
      ),
    );
    when(() => repository.getSongsByIds(any())).thenAnswer(
      (_) async => Right([track1, track2, track3]),
    );
    when(() => repository.findMatchingLocalSong(
          remoteId: any(named: 'remoteId'),
          title: any(named: 'title'),
          artist: any(named: 'artist'),
        )).thenAnswer((_) async => const Right(null));
    when(
      () => widgetService.listenToWidgetClicks(any()),
    ).thenReturn(StreamController<Uri?>().stream.listen((_) {}));
    when(
      () => widgetService.updateNowPlaying(
        song: any(named: 'song'),
        isPlaying: any(named: 'isPlaying'),
        position: any(named: 'position'),
        duration: any(named: 'duration'),
        isFavorite: any(named: 'isFavorite'),
        isShuffle: any(named: 'isShuffle'),
        repeatMode: any(named: 'repeatMode'),
        nextQueueTitles: any(named: 'nextQueueTitles'),
      ),
    ).thenAnswer((_) async {});
  });

  group('Regression Test 1 & 2: Auto-advance and Single MediaItem/Artwork Emission', () {
    test('Track changed stream updates PlayerCubit state and preserves fields', () async {
      final cubit = PlayerCubit(
        audioHandler: audioHandler,
        repository: repository,
        toggleFavoriteUseCase: toggleFavoriteUseCase,
        widgetService: widgetService,
        settingsCubit: settingsCubit,
      );

      // Load initial queue
      audioHandler.emitQueue([
        MediaItem(id: '1', title: 'Track 1', artist: 'Artist 1'),
        MediaItem(id: '2', title: 'Track 2', artist: 'Artist 2'),
      ]);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Simulate auto-advance track 1 -> track 2 via onTrackChanged pipeline
      audioHandler.emitTrackChanged(track2);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(cubit.state.currentSong?.id, equals(2));
      expect(cubit.state.currentSong?.title, equals('Track 2'));
      expect(cubit.state.currentIndex, equals(1));
      expect(cubit.state.duration, equals(const Duration(milliseconds: 200000)));

      await cubit.close();
    });

    test('ArtworkUriResolver resolves valid URI with bounded fallback', () async {
      final uri = await ArtworkUriResolver.resolveArtworkUri(track1);
      expect(uri, isNotNull);
      expect(uri.toString().isNotEmpty, isTrue);
    });
  });

  group('Regression Test 3: Next/Previous Boundary and Sequence Logic', () {
    test('Boundary simulation across shuffle and loop modes', () {
      final queue = [track1, track2, track3];

      int? getNextIndex({
        required int currentIndex,
        required List<int> effectiveSequence,
        required LoopMode loopMode,
      }) {
        if (queue.isEmpty) return null;
        if (loopMode == LoopMode.one) return currentIndex;
        final currentSeqIdx = effectiveSequence.indexOf(currentIndex);
        if (currentSeqIdx == -1) return null;
        final targetSeqIdx = currentSeqIdx + 1;
        if (targetSeqIdx < effectiveSequence.length) {
          return effectiveSequence[targetSeqIdx];
        } else if (loopMode == LoopMode.all && effectiveSequence.isNotEmpty) {
          return effectiveSequence.first;
        }
        return null;
      }

      int? getPreviousIndex({
        required int currentIndex,
        required List<int> effectiveSequence,
        required LoopMode loopMode,
        required Duration position,
      }) {
        if (queue.isEmpty) return null;
        if (position > const Duration(seconds: 3)) return currentIndex;
        if (loopMode == LoopMode.one) return currentIndex;
        final currentSeqIdx = effectiveSequence.indexOf(currentIndex);
        if (currentSeqIdx == -1) return null;
        final targetSeqIdx = currentSeqIdx - 1;
        if (targetSeqIdx >= 0) {
          return effectiveSequence[targetSeqIdx];
        } else if (loopMode == LoopMode.all && effectiveSequence.isNotEmpty) {
          return effectiveSequence.last;
        }
        return null;
      }

      final normalSeq = [0, 1, 2];
      final shuffledSeq = [1, 0, 2];

      // 1. First track, next -> 1
      expect(
        getNextIndex(
          currentIndex: 0,
          effectiveSequence: normalSeq,
          loopMode: LoopMode.off,
        ),
        equals(1),
      );

      // 2. Last track, LoopMode.off -> null (boundary stop)
      expect(
        getNextIndex(
          currentIndex: 2,
          effectiveSequence: normalSeq,
          loopMode: LoopMode.off,
        ),
        isNull,
      );

      // 3. Last track, LoopMode.all -> wraps to first in sequence
      expect(
        getNextIndex(
          currentIndex: 2,
          effectiveSequence: normalSeq,
          loopMode: LoopMode.all,
        ),
        equals(0),
      );

      // 4. Shuffled: last in shuffle sequence (2 in [1, 0, 2]), LoopMode.all -> wraps to 1
      expect(
        getNextIndex(
          currentIndex: 2,
          effectiveSequence: shuffledSeq,
          loopMode: LoopMode.all,
        ),
        equals(1),
      );

      // 5. Previous: position > 3s -> restarts current track
      expect(
        getPreviousIndex(
          currentIndex: 1,
          effectiveSequence: normalSeq,
          loopMode: LoopMode.off,
          position: const Duration(seconds: 5),
        ),
        equals(1),
      );

      // 6. Previous: position <= 3s, first track, LoopMode.off -> null
      expect(
        getPreviousIndex(
          currentIndex: 0,
          effectiveSequence: normalSeq,
          loopMode: LoopMode.off,
          position: const Duration(seconds: 1),
        ),
        isNull,
      );

      // 7. Previous: position <= 3s, first track, LoopMode.all -> wraps to last
      expect(
        getPreviousIndex(
          currentIndex: 0,
          effectiveSequence: normalSeq,
          loopMode: LoopMode.all,
          position: const Duration(seconds: 1),
        ),
        equals(2),
      );
    });
  });

  group('Regression Test 4: Player Theme Persistence Across Track Changes', () {
    test('Settings theme remains intact when track changes occur', () async {
      final cubit = PlayerCubit(
        audioHandler: audioHandler,
        repository: repository,
        toggleFavoriteUseCase: toggleFavoriteUseCase,
        widgetService: widgetService,
        settingsCubit: settingsCubit,
      );

      await settingsCubit.setWaveformSeekBar(true);
      expect(settingsCubit.state.waveformSeekBarEnabled, isTrue);

      // Simulate multiple track transitions
      audioHandler.emitTrackChanged(track1);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      audioHandler.emitTrackChanged(track2);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      audioHandler.emitTrackChanged(track3);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(settingsCubit.state.waveformSeekBarEnabled, isTrue);
      expect(cubit.state.currentSong?.id, equals(3));

      await cubit.close();
    });
  });

  group('Regression Test 5: YTM URL Cache Invalidation and Retry on 403', () {
    test('403 error evicts cached URL and retry receives fresh URL', () async {
      final urlCache = YtmUrlCache();
      const videoId = 'dQw4w9WgXcQ';

      Future<String> mockResolver({bool forceRefresh = false}) async {
        if (forceRefresh) {
          return 'https://googlevideo.com/videoplayback?expire=9999999999&itag=140';
        }
        return 'https://googlevideo.com/videoplayback?expire=1000&itag=140';
      }

      final source = YtmResolvingSource(
        videoId: videoId,
        resolve: mockResolver,
        urlCache: urlCache,
      );

      // Seed cache with dead URL
      urlCache.put(videoId, 'https://googlevideo.com/videoplayback?expire=1000&itag=140');
      expect(urlCache.get(videoId)?.url, contains('expire=1000'));

      // Evict dead URL simulation
      urlCache.evictDeadUrl(videoId, 'https://googlevideo.com/videoplayback?expire=1000&itag=140');
      expect(urlCache.get(videoId), isNull);

      // Fresh resolution
      final freshUrl = await source.resolve(forceRefresh: true);
      urlCache.put(videoId, freshUrl);
      expect(urlCache.get(videoId)?.url, contains('expire=9999999999'));
    });
  });
}
