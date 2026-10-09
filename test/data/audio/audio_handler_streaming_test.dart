// test/data/audio/audio_handler_streaming_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:pulsr/data/audio/adaptive_buffer_engine.dart';
import 'package:pulsr/data/audio/audio_handler.dart';

import 'handler_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final originalPlatform = JustAudioPlatform.instance;
  late FakeJustAudioPlatform platform;
  late MockMusicRepository repo;
  late MockYtmService ytm;
  PulsrAudioHandler? handler;

  setUp(() {
    platform = FakeJustAudioPlatform();
    JustAudioPlatform.instance = platform;
    installHandlerChannelStubs();
    repo = MockMusicRepository();
    stubDefaultRepository(repo);
    ytm = MockYtmService();
    stubDefaultYtm(ytm);
  });

  tearDown(() async {
    await handler?.dispose();
    handler = null;
    removeHandlerChannelStubs();
    JustAudioPlatform.instance = originalPlatform;
  });

  test('audio load configuration is exposed', () async {
    handler = await buildTestHandler(repository: repo, ytmService: ytm);
    expect(handler!.currentAudioLoadConfiguration, isNotNull);
  });

  test('float output and AAudio preferences are pushed', () async {
    handler = await buildTestHandler(repository: repo, ytmService: ytm);
    await handler!.setFloatOutputEnabled(true);
    await handler!.setFloatOutputEnabled(false);
    expect(await handler!.setAaudioOutputEnabled(true), isA<bool>());
    expect(await handler!.setAaudioOutputEnabled(false), isA<bool>());
  });

  test('sinc resampler quality is a safe no-op when unsupported', () async {
    handler = await buildTestHandler(repository: repo, ytmService: ytm);
    await handler!.setSincResamplerQuality(3);
  });

  test('BPM sync crossfade toggle', () async {
    handler = await buildTestHandler(repository: repo, ytmService: ytm);
    await handler!.setBpmSyncCrossfadeEnabled(true);
    await handler!.setBpmSyncCrossfadeEnabled(false);
  });

  test('per-track BPM overrides respect the 40-240 range', () async {
    handler = await buildTestHandler(repository: repo, ytmService: ytm);
    final song = localSong(1);
    expect(await handler!.setTrackBpm(song, 128), isTrue);
    expect(await handler!.setTrackBpm(song, 999), isFalse);
    expect(await handler!.setTrackBpm(song, null), isTrue);
  });

  test('audio normalization toggles and reports state', () async {
    handler = await buildTestHandler(repository: repo, ytmService: ytm);
    expect(handler!.isAudioNormalizationEnabled, isFalse);
    await handler!.setAudioNormalizationEnabled(true);
    expect(handler!.isAudioNormalizationEnabled, isTrue);
    await handler!.setAudioNormalizationEnabled(false);
    expect(handler!.isAudioNormalizationEnabled, isFalse);
  });

  test('skip silence toggles on both players', () async {
    handler = await buildTestHandler(repository: repo, ytmService: ytm);
    expect(handler!.skipSilenceEnabled, isA<bool>());
    await handler!.setSkipSilenceEnabled(true);
    await handler!.setSkipSilenceEnabled(false);
  });

  test('network caches and prefetches can be cleared', () async {
    handler = await buildTestHandler(repository: repo, ytmService: ytm);
    handler!.clearNetworkCaches();
    handler!.cancelPrefetches();
    expect(handler!.streamResolutionPipeline, isNotNull);
  });

  test('loadQueue resolves local sources through the streaming pipeline',
      () async {
    handler = await buildTestHandler(repository: repo, ytmService: ytm);
    await handler!.loadQueue(
      [
        localSong(1, path: '/music/a.mp3'),
        localSong(2, path: '/music/b.flac'),
        localSong(3, path: '/music/c.wav'),
      ],
      autoPlay: false,
    );
    expect(handler!.queue.value.length, 3);
  });

  test('content and stream-url paths build URI sources', () async {
    handler = await buildTestHandler(repository: repo, ytmService: ytm);
    await handler!.loadQueue(
      [
        localSong(1, path: 'content://media/external/audio/media/1'),
        localSong(2, path: 'https://stream.example/radio.mp3'),
      ],
      autoPlay: false,
    );
    expect(handler!.queue.value.length, 2);
  });

  test('buffer bucket transitions push a new load configuration', () async {
    handler = await buildTestHandler(repository: repo, ytmService: ytm);
    final before = handler!.currentAudioLoadConfiguration;

    handler!.adaptiveBufferEngine.forceBucket(BufferBucket.minimal);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(handler!.currentAudioLoadConfiguration, isNotNull);
    expect(identical(handler!.currentAudioLoadConfiguration, before), isFalse);

    handler!.adaptiveBufferEngine.releaseForce();
    await Future<void>.delayed(const Duration(milliseconds: 20));
  });

  test('smart prefetch runs when playback approaches the track end',
      () async {
    handler = await buildTestHandler(repository: repo, ytmService: ytm);
    await handler!.loadQueue(
      [localSong(1, durationMs: 200000), localSong(2, durationMs: 200000)],
      autoPlay: true,
    );
    await Future<void>.delayed(const Duration(milliseconds: 30));

    // Push the active player near the 70% prefetch threshold.
    for (final p in platform.players.values) {
      p.duration = const Duration(seconds: 200);
      p.emitPlayback(updatePosition: const Duration(seconds: 150));
    }
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(handler!.preloadScheduler, isNotNull);
  });

  test('youtube rows resolve lazily without touching the network', () async {
    handler = await buildTestHandler(repository: repo, ytmService: ytm);
    await handler!.loadQueue(
      [ytSong(1, remoteId: 'dQw4w9WgXcQ')],
      autoPlay: false,
    );
    expect(handler!.mediaItem.value, isNotNull);
  });
}
