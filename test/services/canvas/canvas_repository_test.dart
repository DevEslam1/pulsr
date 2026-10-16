// test/services/canvas/canvas_repository_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/services/canvas/apple_music_canvas.dart';
import 'package:pulsr/services/canvas/canvas_repository.dart';
import 'package:pulsr/services/canvas/community_canvas.dart';
import 'package:pulsr/services/canvas/tidal_canvas.dart';

class _FakeCommunity extends CommunityCanvas {
  _FakeCommunity(this.answer);
  final CanvasArtwork? answer;

  @override
  Future<CanvasArtwork?> search(
          String title, String artist, String? album) async =>
      answer;
}

class _FakeApple extends AppleMusicCanvas {
  _FakeApple(this.answer);
  final CanvasArtwork? answer;

  @override
  Future<CanvasArtwork?> search(
          String title, String artist, String? album) async =>
      answer;
}

class _FakeTidal extends TidalCanvas {
  _FakeTidal(this.answer);
  final CanvasArtwork? answer;

  @override
  Future<CanvasArtwork?> search(
          String title, String artist, String? album) async =>
      answer;
}

class _FakeCache extends CanvasCache {
  @override
  Future<String?> getOrDownloadVideo(String videoUrl) async =>
      '/fake/cache/video.mp4';
}

void main() {
  group('CanvasRepository', () {
    test('prefers Community Canvas when available (Source 1)', () async {
      final repo = CanvasRepository(
        cache: _FakeCache(),
        communityCanvas: _FakeCommunity(
          const CanvasArtwork(
            videoUrl: 'https://community.cdn/song.mp4',
            title: 'Song',
            artist: 'Artist',
            source: 'community',
          ),
        ),
        appleMusicCanvas: _FakeApple(
          const CanvasArtwork(
            videoUrl: 'https://apple.cdn/song.mp4',
            title: 'Song',
            artist: 'Artist',
            source: 'apple_music',
          ),
        ),
        tidalCanvas: _FakeTidal(null),
      );

      final result = await repo.canvasForTrack(title: 'Song', artist: 'Artist');
      expect(result, isNotNull);
      expect(result!.source, 'community');
      expect(result.localFilePath, '/fake/cache/video.mp4');
    });

    test('falls back to Apple Music when Community misses (Source 2)',
        () async {
      final repo = CanvasRepository(
        cache: _FakeCache(),
        communityCanvas: _FakeCommunity(null),
        appleMusicCanvas: _FakeApple(
          const CanvasArtwork(
            videoUrl: 'https://apple.cdn/song.mp4',
            title: 'Song',
            artist: 'Artist',
            source: 'apple_music',
          ),
        ),
        tidalCanvas: _FakeTidal(
          const CanvasArtwork(
            videoUrl: 'https://tidal.cdn/song.mp4',
            title: 'Song',
            artist: 'Artist',
            source: 'tidal',
          ),
        ),
      );

      final result = await repo.canvasForTrack(title: 'Song', artist: 'Artist');
      expect(result, isNotNull);
      expect(result!.source, 'apple_music');
    });

    test('falls back to Tidal when Apple Music misses (Source 3)', () async {
      final repo = CanvasRepository(
        cache: _FakeCache(),
        communityCanvas: _FakeCommunity(null),
        appleMusicCanvas: _FakeApple(null),
        tidalCanvas: _FakeTidal(
          const CanvasArtwork(
            videoUrl: 'https://tidal.cdn/song.mp4',
            title: 'Song',
            artist: 'Artist',
            source: 'tidal',
          ),
        ),
      );

      final result = await repo.canvasForTrack(title: 'Song', artist: 'Artist');
      expect(result, isNotNull);
      expect(result!.source, 'tidal');
    });

    test('caches negative answers so subsequent calls do not query network',
        () async {
      final repo = CanvasRepository(
        cache: CanvasCache(),
        communityCanvas: _FakeCommunity(null),
        appleMusicCanvas: _FakeApple(null),
        tidalCanvas: _FakeTidal(null),
      );

      final result1 =
          await repo.canvasForTrack(title: 'Miss Track', artist: 'Artist');
      expect(result1, isNull);

      final result2 =
          await repo.canvasForTrack(title: 'Miss Track', artist: 'Artist');
      expect(result2, isNull);
    });
  });
}
