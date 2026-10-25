// Offline cache for online library playlists: ordering, merge semantics and
// lifecycle. The custom order must survive remote refreshes because the UI
// lets the user organise a streamed playlist by hand.
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/data/repositories/music_repository.dart';
import 'package:pulsr/domain/models/ytm_track.dart';

void main() {
  late AppDatabase db;
  late MusicRepository repo;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await db.customStatement('PRAGMA foreign_keys = ON;');
    repo = MusicRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  YtmTrack track(String id) => YtmTrack(
        videoId: id,
        title: 'Title $id',
        artist: 'Artist $id',
        duration: const Duration(minutes: 1),
        artworkUrl: 'https://img/$id.jpg',
      );

  Future<void> cache(
    String playlistId,
    List<String> ids, {
    bool fullSnapshot = true,
    String kind = 'custom',
    String title = 'Playlist',
  }) async {
    final result = await repo.cacheOnlinePlaylist(
      playlistId: playlistId,
      kind: kind,
      title: title,
      author: 'Uploader',
      tracks: [for (final id in ids) track(id)],
      fullSnapshot: fullSnapshot,
    );
    expect(result.isRight(), isTrue);
  }

  Future<List<String>> order(String playlistId) async {
    final result = await repo.getOnlinePlaylistTracks(playlistId);
    return result.fold((_) => <String>[], (tracks) {
      return [for (final track in tracks) track.videoId];
    });
  }

  group('canonicalYtmPlaylistId', () {
    test('extracts list ids and normalises VL prefixes', () {
      expect(
        canonicalYtmPlaylistId('https://music.youtube.com/playlist?list=PL123'),
        'PL123',
      );
      expect(canonicalYtmPlaylistId('VLPL123'), 'PL123');
      expect(canonicalYtmPlaylistId('PL123'), 'PL123');
    });

    test('folds every liked-music alias onto one cache id', () {
      for (final alias in [
        'VLLM',
        'LM',
        'LL',
        'VLSE',
        'FEmusic_liked_videos',
        'FEmusic_liked_tracks',
      ]) {
        expect(canonicalYtmPlaylistId(alias), kLikedMusicPlaylistId,
            reason: '$alias must share the liked cache');
      }
    });
  });

  group('cacheOnlinePlaylist', () {
    test('stores full metadata and ordered tracks', () async {
      await cache('PL1', ['a', 'b', 'c']);

      expect(await order('PL1'), ['a', 'b', 'c']);
      final meta = (await repo.getOnlinePlaylist('PL1')).getOrElse((_) => null);
      expect(meta, isNotNull);
      expect(meta!.kind, 'custom');
      expect(meta.hasCustomOrder, isFalse);
      expect(meta.cachedAt, isNotNull);

      final watched = await repo.watchOnlinePlaylistTracks('PL1').first;
      expect(
        watched.fold((_) => <String>[], (t) => [for (final x in t) x.videoId]),
        ['a', 'b', 'c'],
      );
    });

    test('remote refresh replaces order while no custom order exists',
        () async {
      await cache('PL1', ['a', 'b', 'c']);
      await cache('PL1', ['c', 'b', 'a']);

      expect(await order('PL1'), ['c', 'b', 'a']);
    });

    test('custom order survives a refresh and new tracks append', () async {
      await cache('PL1', ['a', 'b', 'c']);
      final reorder =
          await repo.reorderOnlinePlaylistTracks('PL1', ['c', 'a', 'b']);
      expect(reorder.isRight(), isTrue);

      // Remote now also has `d` and returns its own order.
      await cache('PL1', ['b', 'c', 'd', 'a']);

      expect(await order('PL1'), ['c', 'a', 'b', 'd']);
      final meta = (await repo.getOnlinePlaylist('PL1')).getOrElse((_) => null);
      expect(meta!.hasCustomOrder, isTrue);
    });

    test('a removed remote track disappears from the saved order', () async {
      await cache('PL1', ['a', 'b', 'c']);
      await repo.reorderOnlinePlaylistTracks('PL1', ['c', 'a', 'b']);
      await cache('PL1', ['a', 'c']);

      expect(await order('PL1'), ['c', 'a']);
    });

    test('an empty response keeps the cached list instead of wiping it',
        () async {
      await cache('PL1', ['a', 'b']);
      await cache('PL1', const []);

      expect(await order('PL1'), ['a', 'b']);
    });

    test('classification is not downgraded by a later cache write', () async {
      await cache('PL1', ['a'], kind: 'account');
      await cache('PL1', ['a'], kind: 'custom');

      final meta = (await repo.getOnlinePlaylist('PL1')).getOrElse((_) => null);
      expect(meta!.kind, 'account');
    });

    test('duplicate video ids collapse to one slot', () async {
      await cache('PL1', ['a', 'a', 'b']);

      expect(await order('PL1'), ['a', 'b']);
    });
  });

  group('reorderOnlinePlaylistTracks', () {
    test('appends tracks missing from the supplied order', () async {
      await cache('PL1', ['a', 'b', 'c']);

      final result = await repo.reorderOnlinePlaylistTracks('PL1', ['c']);
      expect(result.isRight(), isTrue);

      expect(await order('PL1'), ['c', 'a', 'b']);
    });

    test('ignores ids that are not in the playlist', () async {
      await cache('PL1', ['a', 'b']);

      await repo.reorderOnlinePlaylistTracks('PL1', ['b', 'ghost', 'a']);

      expect(await order('PL1'), ['b', 'a']);
    });
  });

  group('lifecycle', () {
    test('removeOnlinePlaylist drops metadata and entries', () async {
      await cache('PL1', ['a', 'b']);
      final removed = await repo.removeOnlinePlaylist('PL1');
      expect(removed.isRight(), isTrue);

      expect(await order('PL1'), isEmpty);
      final meta = (await repo.getOnlinePlaylist('PL1')).getOrElse((_) => null);
      expect(meta, isNull);
    });

    test('clearOnlineLibraryCache drops every playlist', () async {
      await cache('PL1', ['a']);
      await cache('PL2', ['b']);

      await repo.clearOnlineLibraryCache();

      expect(await order('PL1'), isEmpty);
      expect(await order('PL2'), isEmpty);
      final all = await repo.getOnlinePlaylists();
      expect(all.fold((_) => <OnlinePlaylistsTableData>[], (x) => x), isEmpty);
    });
  });
}
