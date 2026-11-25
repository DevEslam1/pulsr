import 'dart:typed_data';
import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/data/audio/triple_buffer_pipeline.dart';

class MockAudioPlayer extends Mock implements AudioPlayer {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TripleBufferPipeline pipeline;
  late MockAudioPlayer playerA;
  late MockAudioPlayer playerB;
  late MockAudioPlayer prefetchPlayer;

  setUp(() {
    playerA = MockAudioPlayer();
    playerB = MockAudioPlayer();
    prefetchPlayer = MockAudioPlayer();

    pipeline = TripleBufferPipeline(
      getActivePlayer: () => playerA,
      getInactivePlayer: () => playerB,
      prefetchPlayer: prefetchPlayer,
      resolveAudioSource: (song, tag) async =>
          AudioSource.uri(Uri.parse('https://example.com/audio.mp3')),
      songToMediaItem: (song, [fastArtUri]) =>
          MediaItem(id: '${song.id}', title: song.title),
    );
  });

  group('TripleBufferPipeline claim contention & background release', () {
    test('disallows re-entrant prefetch claims', () async {
      expect(pipeline.inactiveClaim, equals(PlayerClaim.none));

      final firstClaim = await pipeline.claimInactive(PlayerClaim.prefetch);
      expect(firstClaim, isTrue);
      expect(pipeline.inactiveClaim, equals(PlayerClaim.prefetch));

      // Re-entrant prefetch claim must fail
      final reentrantClaim = await pipeline.claimInactive(PlayerClaim.prefetch);
      expect(reentrantClaim, isFalse);
      expect(pipeline.inactiveClaim, equals(PlayerClaim.prefetch));

      await pipeline.releaseInactive(PlayerClaim.prefetch);
      expect(pipeline.inactiveClaim, equals(PlayerClaim.none));
    });

    test(
        'crossfade preempts prefetch and prefetch release does not clobber crossfade',
        () async {
      // 1. Prefetch acquires claim
      final prefetchClaimed =
          await pipeline.claimInactive(PlayerClaim.prefetch);
      expect(prefetchClaimed, isTrue);
      expect(pipeline.inactiveClaim, equals(PlayerClaim.prefetch));

      // 2. Crossfade preempts prefetch
      final crossfadeClaimed =
          await pipeline.claimInactive(PlayerClaim.crossfade);
      expect(crossfadeClaimed, isTrue);
      expect(pipeline.inactiveClaim, equals(PlayerClaim.crossfade));

      // 3. Prefetch background worker completes and calls releaseInactive(prefetch)
      // Because claim is currently crossfade, prefetch must NOT release crossfade's claim!
      await pipeline.releaseInactive(PlayerClaim.prefetch);
      expect(pipeline.inactiveClaim, equals(PlayerClaim.crossfade),
          reason: 'Prefetch release must not clear crossfade claim');

      // 4. Crossfade completes and releases
      await pipeline.releaseInactive(PlayerClaim.crossfade);
      expect(pipeline.inactiveClaim, equals(PlayerClaim.none));
    });

    test(
        'clearPreload resets cached metadata and header bytes for background release',
        () {
      pipeline.preloadedHeaderBytes = Uint8List.fromList([1, 2, 3, 4]);
      expect(pipeline.preloadedHeaderBytes, isNotNull);

      // Trigger background release
      pipeline.clearPreload();

      expect(pipeline.preloadedSongId, isNull);
      expect(pipeline.preloadedSource, isNull);
      expect(pipeline.preloadedHeaderBytes, isNull);
    });
  });
}
