import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/constants/channels.dart';
import 'package:pulsr/core/errors/failures.dart';
import 'package:pulsr/core/services/metadata_search_service.dart';
import 'package:pulsr/core/services/ytm_service.dart';
import 'package:pulsr/data/audio/audio_handler.dart';
import 'package:pulsr/data/audio/bpm_override_store.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/data/lyrics/lyrics_translation_service.dart';
import 'package:pulsr/data/repositories/music_repository.dart';
import 'package:pulsr/data/repositories/smart_playlist_engine.dart';
import 'package:pulsr/data/scanner/media_scanner_service.dart';
import 'package:pulsr/data/services/spotify_importer_service.dart';
import 'package:pulsr/data/usecases/backup_usecases.dart';
import 'package:pulsr/domain/models/lyrics_line.dart';
import 'package:pulsr/domain/models/smart_playlist_criteria.dart';
import 'package:pulsr/domain/models/ytm_track.dart';
import 'package:pulsr/domain/usecases/playlist_usecases.dart';
import 'package:pulsr/features/tag_editor/tag_editor_cubit.dart';
import 'package:pulsr/features/tag_editor/tag_editor_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/test_song_factory.dart';

class _MockYtmService extends Mock implements YtmService {}

class _MockMetadataSearch extends Mock implements MetadataSearchService {}

class _MockScanner extends Mock implements MediaScannerService {}

class _FailingAddPlaylistUseCases extends PlaylistUseCases {
  _FailingAddPlaylistUseCases(super.repo, super.engine);

  @override
  Future<Result<void>> addSongsToPlaylist(
      int playlistId, List<int> songIds) async {
    return const Left(DatabaseFailure('simulated add failure'));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SmartPlaylistEngine fixes (BUG-P1-19, BUG-P2-31)', () {
    late AppDatabase db;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      db = AppDatabase.forTesting(NativeDatabase.memory());
      await db.batch((b) {
        b.insertAll(db.songsTable, [
          SongsTableCompanion.insert(
            id: const Value(1),
            title: 'Alpha Sunrise',
            artist: const Value('Pink Floyd'),
            album: const Value('Animals'),
            genre: const Value('Rock'),
            path: '/music/1.flac',
          ),
          SongsTableCompanion.insert(
            id: const Value(2),
            title: 'Beta Night',
            artist: const Value('Miles Davis'),
            album: const Value('Kind of Blue'),
            genre: const Value('Jazz'),
            path: '/music/2.flac',
          ),
          SongsTableCompanion.insert(
            id: const Value(3),
            title: 'Café Bleu',
            artist: const Value('Édith Piaf'),
            album: const Value('Chansons'),
            genre: const Value(null),
            path: '/music/3.flac',
          ),
        ]);
      });
    });

    tearDown(() async => db.close());

    test(
        'notContains and startsWith evaluate accurately in SQL and Unicode Dart',
        () async {
      final engine = SmartPlaylistEngine(db);

      final startsRes = await engine.evaluateCriteria(const SmartCriteria(
        rules: [
          SmartRule(
            field: SmartRuleField.title,
            operator: SmartOperator.startsWith,
            value: 'Alpha',
          ),
        ],
      ));
      expect(startsRes.map((s) => s.id), [1]);

      final notContainsRes = await engine.evaluateCriteria(const SmartCriteria(
        rules: [
          SmartRule(
            field: SmartRuleField.genre,
            operator: SmartOperator.notContains,
            value: 'Rock',
          ),
        ],
      ));
      expect(notContainsRes.map((s) => s.id).toSet(), {2, 3});

      final unicodeNotContains =
          await engine.evaluateCriteria(const SmartCriteria(
        rules: [
          SmartRule(
            field: SmartRuleField.title,
            operator: SmartOperator.notContains,
            value: 'Café',
          ),
        ],
      ));
      expect(unicodeNotContains.map((s) => s.id).toSet(), {1, 2});

      final unicodeStartsWith =
          await engine.evaluateCriteria(const SmartCriteria(
        rules: [
          SmartRule(
            field: SmartRuleField.artist,
            operator: SmartOperator.startsWith,
            value: 'Édith',
          ),
        ],
      ));
      expect(unicodeStartsWith.map((s) => s.id), [3]);
    });

    test('uses injected BpmOverrideStore even when audioHandler is absent',
        () async {
      final bpmStore = BpmOverrideStore();
      await bpmStore.load();
      final songs = await db.select(db.songsTable).get();
      await bpmStore.setBpmForTrack(
          PulsrAudioHandler.trackKeyFor(songs.first), 128);

      final engine = SmartPlaylistEngine(db, bpmOverrideStore: bpmStore);
      final matches = await engine.evaluateCriteria(const SmartCriteria(
        rules: [
          SmartRule(
            field: SmartRuleField.bpm,
            operator: SmartOperator.greaterThanOrEqual,
            value: '120',
          ),
        ],
      ));
      expect(matches.map((s) => s.id), [1]);
    });
  });

  group(
      'MediaScanner & MusicRepository fixes (BUG-P1-20, BUG-P2-36, BUG-P2-37)',
      () {
    late AppDatabase db;
    late MusicRepository repo;
    late MediaScannerService scanner;
    const tagChannel = MethodChannel(PulsrChannels.tagEditor);

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      repo = MusicRepository(db);
      scanner = MediaScannerService(repo);
    });

    tearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(tagChannel, null);
      scanner.dispose();
      await db.close();
    });

    test(
        'rescanSingleFile parses N/M track/disc and ISO year and persists discNumber',
        () async {
      await db.into(db.songsTable).insert(
            SongsTableCompanion.insert(
              id: const Value(10),
              title: 'Old Title',
              path: '/music/disc2_track3.flac',
            ),
          );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(tagChannel, (call) async {
        if (call.method == 'readTags') {
          return <String, dynamic>{
            'title': 'Track Three',
            'artist': 'Artist X',
            'album': 'Double Album',
            'genre': 'Prog',
            'year': '2023-05-12',
            'trackNumber': '3/12',
            'discNumber': '2/2',
          };
        }
        return null;
      });

      await scanner.rescanSingleFile('/music/disc2_track3.flac');
      final row = await (db.select(db.songsTable)
            ..where((t) => t.id.equals(10)))
          .getSingle();
      expect(row.year, 2023);
      expect(row.trackNumber, 3);
      expect(row.discNumber, 2);
    });

    test('watchGenreSongs and watchYearSongs filter excluded folders from DB',
        () async {
      await db.batch((b) {
        b.insertAll(db.songsTable, [
          SongsTableCompanion.insert(
            id: const Value(1),
            title: 'Visible Rock',
            genre: const Value('Rock'),
            year: const Value(2024),
            path: '/music/visible/a.flac',
          ),
          SongsTableCompanion.insert(
            id: const Value(2),
            title: 'Hidden Rock',
            genre: const Value('Rock'),
            year: const Value(2024),
            path: '/music/hidden/b.flac',
          ),
        ]);
      });
      await repo.toggleFolderExclusion('/music/hidden');

      final genreSongs =
          (await repo.watchGenreSongs('Rock').first).getOrElse((_) => const []);
      expect(genreSongs.map((s) => s.id), [1]);

      final yearSongs =
          (await repo.watchYearSongs(2024).first).getOrElse((_) => const []);
      expect(yearSongs.map((s) => s.id), [1]);
    });
  });

  group('TagEditorCubit fixes (BUG-P1-22, BUG-P2-40)', () {
    late _MockScanner scanner;
    late _MockMetadataSearch metadata;
    const channel = MethodChannel(PulsrChannels.tagEditor);

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      scanner = _MockScanner();
      metadata = _MockMetadataSearch();
      when(() => scanner.rescanSingleFile(any())).thenAnswer((_) async {});
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('validates discNumber and restores dirty state on undo()', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
              channel, (call) async => <String, dynamic>{});

      final cubit = TagEditorCubit(
        song: createTestSong(id: 1, title: 'Song', path: '/music/s.mp3'),
        scannerService: scanner,
        metadataSearchService: metadata,
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(cubit.hasUnsavedChanges, isFalse);
      cubit.updateDiscNumber('abc');
      expect(cubit.hasUnsavedChanges, isTrue);

      await cubit.saveTags();
      expect(cubit.state.status, TagEditorStatus.failure);
      expect(cubit.state.errorMessage, contains('Disc number'));

      expect(cubit.undo(), isTrue);
      expect(cubit.hasUnsavedChanges, isFalse);
      await cubit.close();
    });

    test('persists and restores batch edit payload in checkpoint', () async {
      final written = <Map<Object?, Object?>>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'writeTags') {
          final args = call.arguments as Map<Object?, Object?>;
          written.add(args);
          return (args['path'] as String).contains('A') ? false : true;
        }
        return <String, dynamic>{};
      });

      final a = createTestSong(
          id: 1, title: 'A', artist: 'Old', path: '/music/A.mp3');
      final b = createTestSong(
          id: 2, title: 'B', artist: 'Old', path: '/music/B.mp3');

      final cubit1 = TagEditorCubit(
        song: a,
        batchSongs: [a, b],
        scannerService: scanner,
        metadataSearchService: metadata,
      );
      cubit1.updateArtist('New Band');
      cubit1.updateGenre('Synthwave');
      await cubit1.saveTags();
      await cubit1.close();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList(TagEditorCubit.batchCheckpointKey),
          ['/music/A.mp3']);
      expect(
          prefs.getString(TagEditorCubit.batchCheckpointPayloadKey), isNotNull);

      final cubit2 = TagEditorCubit(
        song: a,
        batchSongs: [a],
        scannerService: scanner,
        metadataSearchService: metadata,
      );
      await cubit2.restoreBatchCheckpoint(prefs);
      expect(cubit2.state.artist, 'New Band');
      expect(cubit2.state.genre, 'Synthwave');
      await cubit2.close();
    });
  });

  group('BackupUseCases fixes (BUG-P2-34, BUG-P2-35)', () {
    late AppDatabase db;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      db = AppDatabase.forTesting(NativeDatabase.memory());
    });

    tearDown(() async => db.close());

    test(
        'matches Windows backslash paths and allocates negative IDs for YTM tracks',
        () async {
      await db.into(db.songsTable).insert(
            SongsTableCompanion.insert(
              id: const Value(50),
              title: 'Win Track',
              path: r'C:\Music\Artist\Track.flac',
            ),
          );

      final backupJson = jsonEncode({
        'version': 2,
        'onlineTracks': [
          {
            'remoteId': 'yt_abc_123',
            'path': 'ytmusic://yt_abc_123',
            'title': 'Cloud Song',
            'artist': 'Cloud Artist',
            'durationMs': 180000,
          },
        ],
        'favorites': [
          r'D:\OtherDrive\Artist\Track.flac',
          'ytmusic://yt_abc_123',
        ],
      });

      final restore = ImportBackupUseCase(MusicRepository(db), db);
      final report = await restore.execute(backupJson);
      expect(report.restoredFavoritesCount, 2);

      final ytmRow = await (db.select(db.songsTable)
            ..where((t) => t.remoteId.equals('yt_abc_123')))
          .getSingle();
      expect(ytmRow.id, lessThan(0));
      expect(ytmRow.isFavorite, isTrue);
    });
  });

  group('LyricsTranslationService fixes (BUG-P3-8)', () {
    test('skips romanization API for English lyrics containing emojis',
        () async {
      var requests = 0;
      final client = MockClient((req) async {
        requests++;
        return http.Response('[]', 200);
      });
      final service = LyricsTranslationService(client: client);
      final res = await service.romanizeLyrics(
        lines: const [
          LyricsLine(timestamp: Duration.zero, text: 'Hello world 🎵✨'),
        ],
      );
      expect(res.isRomanized, isTrue);
      expect(requests, 0);
      service.dispose();
    });
  });

  group('SpotifyImporterService fixes (BUG-P3-9)', () {
    test('rolls back playlist creation when adding songs fails', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = MusicRepository(db);
      final engine = SmartPlaylistEngine(db);
      final failingPlaylists = _FailingAddPlaylistUseCases(repo, engine);
      final ytm = _MockYtmService();
      when(() => ytm.search(any(), limit: any(named: 'limit'))).thenAnswer(
        (_) async => const [
          YtmTrack(
            videoId: 'vid_tx_1',
            title: 'Song',
            artist: 'Artist',
            duration: Duration(seconds: 200),
          ),
        ],
      );
      final mockClient = MockClient((req) async {
        const nextData = {
          'props': {
            'pageProps': {
              'state': {
                'data': {
                  'entity': {
                    'name': 'Atomic Playlist',
                    'trackList': [
                      {'title': 'Song', 'subtitle': 'Artist'},
                    ],
                  },
                },
              },
            },
          },
        };
        return http.Response(
          '<script id="__NEXT_DATA__" type="application/json">${jsonEncode(nextData)}</script>',
          200,
        );
      });

      final service = SpotifyImporterService(
        httpClient: mockClient,
        ytmService: ytm,
        playlistUseCases: failingPlaylists,
        db: db,
      );

      await expectLater(
        () => service.importPlaylist(
            'https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M'),
        throwsException,
      );

      final playlists = await db.select(db.playlistsTable).get();
      expect(playlists, isEmpty,
          reason: 'failed import must not leave an orphan empty playlist');
    });
  });
}
