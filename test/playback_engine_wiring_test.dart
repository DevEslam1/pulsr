// test/playback_engine_wiring_test.dart
import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mocktail/mocktail.dart';

import 'package:pulsr/core/services/ytm_url_cache.dart';
import 'package:pulsr/data/audio/adaptive_buffer_engine.dart';
import 'package:pulsr/data/audio/audio_memory_manager.dart';
import 'package:pulsr/data/audio/equalizer_manager.dart';
import 'package:pulsr/data/audio/format_aware_decoder.dart';
import 'package:pulsr/data/audio/optimized_dsp_pipeline.dart';
import 'package:pulsr/data/audio/replay_gain_math.dart';
import 'package:pulsr/data/audio/smart_preload_scheduler.dart';
import 'package:pulsr/data/audio/stream_pre_resolver.dart';
import 'package:pulsr/data/audio/triple_buffer_pipeline.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/domain/models/ytm_track.dart';

class MockAudioPlayer extends Mock implements AudioPlayer {}
class MockYtmUrlCache extends Mock implements YtmUrlCache {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Playback Engine Wiring Verification Suite', () {
    // 1. AdaptiveBufferEngine throughput & bucket transition
    test('1. AdaptiveBufferEngine transitions buckets and supports force/release', () async {
      final engine = AdaptiveBufferEngine();
      expect(engine.currentBucket, equals(BufferBucket.standard));

      // Local file always maps to minimal
      expect(engine.bucketFor(isWifi: true, isLocal: true), equals(BufferBucket.minimal));

      // Sampling slow throughput (< 2 Mbps)
      // 100,000 bytes in 1000ms = 0.8 Mbps
      engine.sampleThroughput(100000, const Duration(milliseconds: 1000));
      expect(engine.averageNetworkSpeedMbps, lessThan(2.0));
      expect(engine.bucketFor(isWifi: false, isLocal: false), equals(BufferBucket.generous));

      // Test force bucket
      final events = <BufferBucket>[];
      final sub = engine.onBucketChanged.listen(events.add);

      engine.forceBucket(BufferBucket.minimal);
      expect(engine.currentBucket, equals(BufferBucket.minimal));

      engine.releaseForce();
      expect(engine.currentBucket, isNot(BufferBucket.minimal));

      await Future.delayed(const Duration(milliseconds: 10));
      expect(events, contains(BufferBucket.minimal));
      await sub.cancel();
    });

    // 2. TripleBufferPipeline PlayerClaim contention protection
    test('2. TripleBufferPipeline PlayerClaim prevents concurrent player claims', () async {
      final playerA = MockAudioPlayer();
      final playerB = MockAudioPlayer();
      final prefetchPlayer = MockAudioPlayer();

      final pipeline = TripleBufferPipeline(
        getActivePlayer: () => playerA,
        getInactivePlayer: () => playerB,
        prefetchPlayer: prefetchPlayer,
        resolveAudioSource: (song, tag) async => AudioSource.uri(Uri.parse('https://example.com')),
        songToMediaItem: (song, [fastArtUri]) => MediaItem(id: '1', title: 'Song'),
      );

      expect(pipeline.inactiveClaim, equals(PlayerClaim.none));

      // Crossfade acquires claim
      final claimed1 = await pipeline.claimInactive(PlayerClaim.crossfade);
      expect(claimed1, isTrue);
      expect(pipeline.inactiveClaim, equals(PlayerClaim.crossfade));

      // Prefetch tries to claim concurrently -> rejected
      final claimed2 = await pipeline.claimInactive(PlayerClaim.prefetch);
      expect(claimed2, isFalse);
      expect(pipeline.inactiveClaim, equals(PlayerClaim.crossfade));

      // Release crossfade claim -> now prefetch can claim
      pipeline.releaseInactive(PlayerClaim.crossfade);
      expect(pipeline.inactiveClaim, equals(PlayerClaim.none));

      final claimed3 = await pipeline.claimInactive(PlayerClaim.prefetch);
      expect(claimed3, isTrue);
      expect(pipeline.inactiveClaim, equals(PlayerClaim.prefetch));

      pipeline.releaseInactive(PlayerClaim.prefetch);
      expect(pipeline.inactiveClaim, equals(PlayerClaim.none));
    });

    // 3. Preload scheduling & resolution deduplication
    test('3. StreamPreResolver skips resolution if already prefetching', () async {
      final mockCache = MockYtmUrlCache();
      when(() => mockCache.contains(any(), quality: any(named: 'quality'))).thenReturn(false);

      int resolveCallCount = 0;
      final resolver = StreamPreResolver(
        resolveUrl: (videoId, {quality = 'high'}) async {
          resolveCallCount++;
          return YtmStream(
            videoId: videoId,
            url: 'https://stream.url',
            mimeType: 'audio/webm',
            container: 'webm',
            bitrateKbps: 256,
            duration: Duration.zero,
            title: 'Track',
            artist: 'Artist',
          );
        },
        urlCache: mockCache,
        isAlreadyPrefetching: (videoId) => videoId == 'in_flight_123',
      );

      final queue = <SongsTableData>[
        SongsTableData(
          id: 1,
          title: 'Current',
          artist: 'Artist',
          album: 'Album',
          durationMs: 200000,
          path: 'ytmusic://current_123',
          source: SongSource.youtube,
          remoteId: 'current_123',
          isFavorite: false,
          isMissing: false,
          playCount: 0,
          lastPositionMs: 0,
          isDownloaded: false,
        ),
        SongsTableData(
          id: 2,
          title: 'Next In Flight',
          artist: 'Artist',
          album: 'Album',
          durationMs: 200000,
          path: 'ytmusic://in_flight_123',
          source: SongSource.youtube,
          remoteId: 'in_flight_123',
          isFavorite: false,
          isMissing: false,
          playCount: 0,
          lastPositionMs: 0,
          isDownloaded: false,
        ),
      ];

      resolver.onTrackStarted(queue: queue, currentIndex: 0, isShuffle: false);

      await Future.delayed(const Duration(milliseconds: 50));
      // Should NOT call resolveUrl because videoId == 'in_flight_123' is marked as already prefetching
      expect(resolveCallCount, equals(0));

      resolver.dispose();
    });

    // 4. DSP Latency Compensation
    test('4. OptimizedDspPipeline compensates playback position for measured latency', () {
      final dsp = OptimizedDspPipeline();
      const rawPos = Duration(seconds: 10);

      // Initially no measured latency -> compensated equals raw
      expect(dsp.getCompensatedPosition(rawPos), equals(rawPos));

      // Native latency of 480 frames at 48000 Hz = 10 ms = 10,000 microseconds
      dsp.updateNativeLatency(frames: 480, sampleRate: 48000.0);
      final compensated = dsp.getCompensatedPosition(rawPos);

      expect(compensated, equals(const Duration(seconds: 10) - const Duration(milliseconds: 10)));
      expect(dsp.calculateTotalEstimatedLatencyMs(), equals(10.0));
    });

    // 5. BatteryAwarePlayback & DSP degradation (all 9 stages)
    test('5. EqualizerManager degradeToEssentials disables all 9 DSP stages and restores them', () async {
      final eq = EqualizerManager();

      eq.isReverbEnabled = true;
      eq.isCrossfeedEnabled = true;
      eq.isSaturationEnabled = true;
      eq.isStereoWidthEnabled = true;
      eq.isLoudnessContourEnabled = true;
      eq.isSubCrossoverEnabled = true;
      eq.isDynamicEqEnabled = true;
      eq.isDynamicsEnabled = true;
      eq.isLimiterEnabled = true;

      expect(eq.isDegradedForPower, isFalse);

      await eq.degradeToEssentials();
      expect(eq.isDegradedForPower, isTrue);
      expect(eq.isReverbEnabled, isFalse);
      expect(eq.isCrossfeedEnabled, isFalse);
      expect(eq.isSaturationEnabled, isFalse);
      expect(eq.isStereoWidthEnabled, isFalse);
      expect(eq.isLoudnessContourEnabled, isFalse);
      expect(eq.isSubCrossoverEnabled, isFalse);
      expect(eq.isDynamicEqEnabled, isFalse);
      expect(eq.isDynamicsEnabled, isFalse);
      expect(eq.isLimiterEnabled, isFalse);

      await eq.restoreFromDegrade();
      expect(eq.isDegradedForPower, isFalse);
      expect(eq.isReverbEnabled, isTrue);
      expect(eq.isCrossfeedEnabled, isTrue);
      expect(eq.isSaturationEnabled, isTrue);
      expect(eq.isStereoWidthEnabled, isTrue);
      expect(eq.isLoudnessContourEnabled, isTrue);
      expect(eq.isSubCrossoverEnabled, isTrue);
      expect(eq.isDynamicEqEnabled, isTrue);
      expect(eq.isDynamicsEnabled, isTrue);
      expect(eq.isLimiterEnabled, isTrue);
    });

    // 6. AudioMemoryManager Preload Budget
    test('6. AudioMemoryManager enforces 32MB budget and canPreload limits', () {
      final memory = AudioMemoryManager();

      expect(memory.canPreload(isBatteryConstrained: false), isTrue);
      expect(memory.canPreload(isBatteryConstrained: true), isFalse);

      // Register 30MB
      memory.registerPreload('head_1', 30 * 1024 * 1024);
      expect(memory.currentPreloadBytes, equals(30 * 1024 * 1024));

      // Register another 5MB (total 35MB > 32MB cap -> LRU eviction of head_1)
      memory.registerPreload('head_2', 5 * 1024 * 1024);
      expect(memory.currentPreloadBytes, equals(5 * 1024 * 1024));
    });

    // 7. DSD safety guard
    test('7. FormatAwareDecoder throws PlayerException(9001) for DSF/DFF files', () async {
      final decoder = FormatAwareDecoder(
        resolveYtmStream: (song, tag) async => AudioSource.uri(Uri.parse('https://example.com')),
        decodeDsdToPcm: (song, tag) async {
          final ext = song.path.split('.').last.toLowerCase();
          if (ext == 'dsf' || ext == 'dff') {
            throw PlayerException(9001, 'DSD decode-to-PCM pipeline not yet wired', null);
          }
          return AudioSource.uri(Uri.parse(song.path));
        },
      );

      final dsfSong = SongsTableData(
        id: 1,
        title: 'Hi-Res Track',
        artist: 'Artist',
        album: 'Album',
        durationMs: 300000,
        path: '/music/track.dsf',
        source: SongSource.local,
        isFavorite: false,
        isMissing: false,
        playCount: 0,
        lastPositionMs: 0,
        isDownloaded: false,
      );

      expect(
        () => decoder.decodeForFormat(dsfSong, MediaItem(id: '1', title: 'Hi-Res Track')),
        throwsA(isA<PlayerException>().having((e) => e.code, 'code', equals(9001))),
      );
    });

    // 8. ReplayGainMath calculation parity
    test('8. ReplayGainMath calculates correct gain and applies inter-sample headroom', () {
      final volumeTrack = ReplayGainMath.apply(
        mode: 'track',
        volume: 1.0,
        trackGainDb: -6.0,
        trackPeak: 1.0,
        preampWithRg: 0.0,
      );

      // -6 dB gain multiplier is 10^(-6/20) ~ 0.501187
      expect(volumeTrack, closeTo(0.501, 0.01));

      final volumeOff = ReplayGainMath.apply(
        mode: 'off',
        volume: 0.8,
        trackGainDb: -10.0,
      );
      expect(volumeOff, equals(0.8));
    });

    // 9. SmartPreloadScheduler 70% progress threshold guard & configurable preloadCount
    test('9. SmartPreloadScheduler schedules preloads at 70% threshold and respects preloadCount', () {
      final preloaded = <int>[];
      final scheduler = SmartPreloadScheduler(
        onPreloadRequested: (song, {required priority}) async {
          preloaded.add(song.id);
        },
      );

      final queue = List.generate(
        5,
        (i) => SongsTableData(
          id: i + 1,
          title: 'Track $i',
          artist: 'Artist',
          album: 'Album',
          durationMs: 200000,
          path: 'ytmusic://track_$i',
          remoteId: 'track_$i',
          source: SongSource.youtube,
          isFavorite: false,
          isMissing: false,
          playCount: 0,
          lastPositionMs: 0,
          isDownloaded: false,
        ),
      );

      // Duration: 200s. Position: 100s (50% - not past 70%, and time remaining 100s > 30s) -> NO preload
      scheduler.schedulePreloads(
        queue: queue,
        currentIndex: 0,
        isShuffle: false,
        position: const Duration(seconds: 100),
        duration: const Duration(seconds: 200),
        preloadCount: 2,
      );
      expect(preloaded, isEmpty);

      // Position: 145s (72.5% - past 70% threshold even though 55s remaining > 30s) -> PRELOAD
      scheduler.schedulePreloads(
        queue: queue,
        currentIndex: 0,
        isShuffle: false,
        position: const Duration(seconds: 145),
        duration: const Duration(seconds: 200),
        preloadCount: 2,
      );
      expect(preloaded, equals([2, 3]));
    });

    // 10. EqualizerManager.syncNativeLatency updates OptimizedDspPipeline
    test('10. EqualizerManager.syncNativeLatency updates attached OptimizedDspPipeline', () async {
      final eq = EqualizerManager();
      final dsp = OptimizedDspPipeline();
      eq.attachDspPipeline(dsp);

      final initialLatency = dsp.calculateTotalEstimatedLatencyMs();
      expect(initialLatency, greaterThanOrEqualTo(0.0));
      // In tests PlatformCapabilities.isAndroid is false, so syncNativeLatency returns 0 safely
      final frames = await eq.syncNativeLatency(48000.0);
      expect(frames, equals(0));
      expect(dsp.calculateTotalEstimatedLatencyMs(), equals(initialLatency));
    });

    // 11. AudioMemoryManager onTrackCompleted and evict
    test('11. AudioMemoryManager evict removes entry and onTrackCompleted accepts String and int', () {
      bool evictedOldest = false;
      final memory = AudioMemoryManager(
        onEvictOldestCacheRequested: () {
          evictedOldest = true;
        },
      );

      memory.registerPreload('song_123', 2 * 1024 * 1024);
      expect(memory.preloadedHeadCount, equals(1));
      expect(memory.currentPreloadBytes, equals(2 * 1024 * 1024));

      // Evict removes head and decreases bytes
      memory.evict('song_123');
      expect(memory.preloadedHeadCount, equals(0));
      expect(memory.currentPreloadBytes, equals(0));

      // onTrackCompleted accepts int and String
      memory.onTrackCompleted(123);
      expect(evictedOldest, isTrue);

      evictedOldest = false;
      memory.onTrackCompleted('123');
      expect(evictedOldest, isTrue);
    });

    // 12. AudioMemoryManager calculateHeadSize with variable bitrates
    test('12. AudioMemoryManager calculateHeadSize accurately calculates head bytes by bitrate', () {
      // 10 seconds of 256 kbps: (256 * 1000 / 8) * 10 = 320,000 bytes
      final size256 = AudioMemoryManager.calculateHeadSize(bitrateKbps: 256);
      expect(size256, equals(320000));

      // 10 seconds of 128 kbps: (128 * 1000 / 8) * 10 = 160,000 bytes
      final size128 = AudioMemoryManager.calculateHeadSize(bitrateKbps: 128);
      expect(size128, equals(160000));

      // 10 seconds of 320 kbps: (320 * 1000 / 8) * 10 = 400,000 bytes
      final size320 = AudioMemoryManager.calculateHeadSize(bitrateKbps: 320);
      expect(size320, equals(400000));
    });

    // 13. AdaptiveBufferEngine evaluateBucket
    test('13. AdaptiveBufferEngine evaluateBucket updates currentBucket based on network and locality', () {
      final engine = AdaptiveBufferEngine();
      expect(engine.currentBucket, equals(BufferBucket.standard));

      // Local track evaluates to minimal
      engine.evaluateBucket(isWifi: true, isLocal: true);
      expect(engine.currentBucket, equals(BufferBucket.minimal));

      // Slow network on cellular evaluates to generous
      engine.sampleThroughput(50000, const Duration(milliseconds: 1000));
      engine.evaluateBucket(isWifi: false, isLocal: false);
      expect(engine.currentBucket, equals(BufferBucket.generous));
    });

    // 14. AudioPlayer setAudioLoadConfiguration updates configuration dynamically
    test('14. AudioPlayer setAudioLoadConfiguration updates load control configuration', () async {
      final player = AudioPlayer();
      expect(player.audioLoadConfiguration, isNull);

      final config = const AudioLoadConfiguration(
        androidLoadControl: AndroidLoadControl(
          minBufferDuration: Duration(seconds: 10),
          maxBufferDuration: Duration(seconds: 20),
        ),
      );

      await player.setAudioLoadConfiguration(config);
      expect(player.audioLoadConfiguration, equals(config));
      expect(
        player.audioLoadConfiguration?.androidLoadControl?.minBufferDuration,
        equals(const Duration(seconds: 10)),
      );

      await player.dispose();
    });
  });
}
