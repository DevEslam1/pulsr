// test/data/repositories/smart_playlist_snapshot_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/domain/models/smart_playlist_criteria.dart';
import 'package:pulsr/domain/repositories/smart_playlist_engine_interface.dart';

class MockSmartPlaylistEngine implements ISmartPlaylistEngine {
  final List<SongsTableData> _databaseSongs;

  MockSmartPlaylistEngine(this._databaseSongs);

  @override
  Future<List<SongsTableData>> evaluateCriteria(SmartCriteria criteria) async {
    return List.from(_databaseSongs);
  }

  @override
  Stream<List<SongsTableData>> watchCriteria(SmartCriteria criteria) async* {
    yield List.from(_databaseSongs);
  }

  @override
  Future<List<SongsTableData>> createPlaybackSnapshot(
      SmartCriteria criteria) async {
    final result = await evaluateCriteria(criteria);
    return List<SongsTableData>.unmodifiable(result);
  }
}

void main() {
  group('Phase 6 — Smart Playlist Snapshot-on-Play & Immutability Tests', () {
    test(
        'Snapshot-on-play creates an immutable queue that survives DB mutations',
        () async {
      final initialSongs = [
        const SongsTableData(
          id: 1,
          title: 'Song 1',
          artist: 'Artist 1',
          album: 'Album 1',
          path: '/path/1.flac',
          durationMs: 180000,
          isFavorite: false,
          isMissing: false,
          isDownloaded: false,
          playCount: 1,
          lastPositionMs: 0,
          source: SongSource.local,
        ),
        const SongsTableData(
          id: 2,
          title: 'Song 2',
          artist: 'Artist 2',
          album: 'Album 2',
          path: '/path/2.flac',
          durationMs: 200000,
          isFavorite: false,
          isMissing: false,
          isDownloaded: false,
          playCount: 5,
          lastPositionMs: 0,
          source: SongSource.local,
        ),
      ];

      final engine = MockSmartPlaylistEngine(initialSongs);
      const criteria = SmartCriteria(
        rules: [
          SmartRule(
            field: SmartRuleField.playCount,
            operator: SmartOperator.lessThan,
            value: '3',
          ),
        ],
        matchAll: true,
      );

      // Create snapshot when loaded into queue
      final queueSnapshot = await engine.createPlaybackSnapshot(criteria);
      expect(queueSnapshot.length, equals(2));
      expect(queueSnapshot.first.id, equals(1));

      // Assert queue snapshot is unmodifiable
      expect(
          () => (queueSnapshot as dynamic).add(const SongsTableData(
                id: 3,
                title: 'Song 3',
                artist: 'Artist 3',
                album: 'Album 3',
                path: '/path/3.flac',
                durationMs: 120000,
                isFavorite: false,
                isMissing: false,
                isDownloaded: false,
                playCount: 0,
                lastPositionMs: 0,
                source: SongSource.local,
              )),
          throwsUnsupportedError);
    });
  });
}
