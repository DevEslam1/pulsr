// TagEditorCubit unit suite.
//
// Exercises tag loading, field editing + undo, artwork handling, online
// metadata search/apply/auto-fetch and both single-track and batch saves,
// including the native-bridge result classification paths.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/constants/channels.dart';
import 'package:pulsr/core/services/metadata_search_service.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/data/scanner/media_scanner_service.dart';
import 'package:pulsr/features/tag_editor/tag_editor_cubit.dart';
import 'package:pulsr/features/tag_editor/tag_editor_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/test_song_factory.dart';

class _Scanner extends Mock implements MediaScannerService {}

class _Metadata extends Mock implements MetadataSearchService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Scanner scanner;
  late _Metadata metadata;
  late MethodChannel channel;
  dynamic Function(MethodCall call)? handler;

  SongsTableData song({int id = 1, String title = 'Song'}) => createTestSong(
        id: id,
        title: title,
        artist: 'Artist',
        album: 'Album',
        path: '/music/$title.mp3',
      );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    scanner = _Scanner();
    metadata = _Metadata();
    when(() => scanner.rescanSingleFile(any())).thenAnswer((_) async {});
    when(() => metadata.searchMetadata(
          title: any(named: 'title'),
          artist: any(named: 'artist'),
          album: any(named: 'album'),
        )).thenAnswer((_) async => <OnlineTrackMetadata>[]);
    when(() => metadata.downloadArtworkToTemp(any()))
        .thenAnswer((_) async => null);

    channel = MethodChannel(PulsrChannels.tagEditor);
    handler = (call) async => <String, dynamic>{};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) => handler!(call));
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
  });

  TagEditorCubit single({SongsTableData? s}) => TagEditorCubit(
        song: s ?? song(),
        scannerService: scanner,
        metadataSearchService: metadata,
      );

  group('TagEditorCubit loading', () {
    test('reads tags through the channel and applies them', () async {
      handler = (call) async {
        if (call.method == 'readTags') {
          return <dynamic, dynamic>{
            'title': 'Loaded Title',
            'artist': 'Loaded Artist',
            'album': 'Loaded Album',
            'genre': 'Rock',
            'year': '1999',
            'trackNumber': '3',
            'discNumber': '1',
            'comment': 'hi',
            'lyrics': 'la la',
          };
        }
        return true;
      };

      final cubit = single(s: song(title: 'orig'));
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(cubit.state.status, TagEditorStatus.loaded);
      expect(cubit.state.title, 'Loaded Title');
      expect(cubit.state.artist, 'Loaded Artist');
      expect(cubit.state.genre, 'Rock');
      expect(cubit.state.year, '1999');
      expect(cubit.state.trackNumber, '3');
      expect(cubit.state.comment, 'hi');
      expect(cubit.state.lyrics, 'la la');
      await cubit.close();
    });

    test('a null channel response still settles on loaded', () async {
      handler = (call) async => null;
      final cubit = single();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(cubit.state.status, TagEditorStatus.loaded);
      await cubit.close();
    });

    test('a channel failure settles on loaded', () async {
      handler = (call) async => throw PlatformException(code: 'boom');
      final cubit = single();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(cubit.state.status, TagEditorStatus.loaded);
      await cubit.close();
    });

    test('batch constructor marks loaded and derives shared fields', () {
      final a = createTestSong(id: 1, title: 'A', artist: 'Same');
      final b = createTestSong(id: 2, title: 'B', artist: 'Same');
      final cubit = TagEditorCubit(
        song: a,
        batchSongs: [a, b],
        scannerService: scanner,
        metadataSearchService: metadata,
      );
      expect(cubit.state.isBatchMode, isTrue);
      expect(cubit.state.status, TagEditorStatus.loaded);
      expect(cubit.state.artist, 'Same');
      expect(cubit.state.title, isEmpty);
      cubit.close();
    });

    test('loadTags does not overwrite fields the user already edited',
        () async {
      handler = (call) async {
        if (call.method == 'readTags') {
          return <dynamic, dynamic>{'title': 'From File'};
        }
        return true;
      };
      final cubit = single(s: song(title: 'orig'));
      cubit.updateTitle('User Edited');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(cubit.state.title, 'User Edited');
      await cubit.close();
    });
  });

  group('field editing and undo', () {
    test('updates every field and undo restores before the edit', () async {
      final cubit = single();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      cubit.updateTitle('T');
      cubit.updateAlbum('Al');
      cubit.updateGenre('G');
      cubit.updateYear('2020');
      cubit.updateTrackNumber('5');
      cubit.updateDiscNumber('2');
      cubit.updateComment('C');
      cubit.updateLyrics('L');
      expect(cubit.canUndo, isTrue);

      expect(cubit.undo(), isTrue);
      expect(cubit.state.lyrics, isNot('L'));
      await cubit.close();
    });

    test('history is bounded at its maximum', () async {
      final cubit = single();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      for (var i = 0; i < 40; i++) {
        cubit.updateTitle('v$i');
      }
      // Undo 15 times (the cap) and then it must report empty.
      for (var i = 0; i < 15; i++) {
        expect(cubit.undo(), isTrue);
      }
      expect(cubit.undo(), isFalse);
      await cubit.close();
    });

    test('removeArtworkImage flags removal and clears artwork', () async {
      final cubit = single();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      cubit.removeArtworkImage();
      expect(cubit.state.removeArtwork, isTrue);
      expect(cubit.state.newArtworkPath, isNull);
      await cubit.close();
    });
  });

  group('online metadata', () {
    test('searchOnlineMatches returns service output', () async {
      when(() => metadata.searchMetadata(
            title: any(named: 'title'),
            artist: any(named: 'artist'),
            album: any(named: 'album'),
          )).thenAnswer((_) async => const [
            OnlineTrackMetadata(title: 'X', artist: 'Y', album: 'Z'),
          ]);
      final cubit = single();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final res = await cubit.searchOnlineMatches();
      expect(res.length, 1);
      expect(res.first.title, 'X');
      await cubit.close();
    });

    test('applyMetadataResult applies fields and artwork', () async {
      when(() => metadata.downloadArtworkToTemp(any()))
          .thenAnswer((_) async => '/tmp/art.jpg');
      final cubit = single();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      final ok = await cubit.applyMetadataResult(const OnlineTrackMetadata(
        title: 'New Title',
        artist: 'New Artist',
        album: 'New Album',
        genre: 'Jazz',
        releaseYear: '2001',
        trackNumber: '7',
        artworkUrl: 'https://example.com/a.jpg',
      ));

      expect(ok, isTrue);
      expect(cubit.state.title, 'New Title');
      expect(cubit.state.genre, 'Jazz');
      expect(cubit.state.year, '2001');
      expect(cubit.state.newArtworkPath, '/tmp/art.jpg');
      await cubit.close();
    });

    test('applyMetadataResult reports failure when the service throws',
        () async {
      when(() => metadata.downloadArtworkToTemp(any()))
          .thenThrow(Exception('net'));
      final cubit = single();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final ok = await cubit.applyMetadataResult(const OnlineTrackMetadata(
        title: 'T',
        artist: 'A',
        album: 'B',
        artworkUrl: 'https://example.com/a.jpg',
      ));
      expect(ok, isFalse);
      expect(cubit.state.errorMessage, contains('Failed to apply metadata'));
      await cubit.close();
    });

    test('autoFetchOnlineTags fails when nothing matches', () async {
      final cubit = single();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final ok = await cubit.autoFetchOnlineTags();
      expect(ok, isFalse);
      expect(cubit.state.errorMessage, contains('No matching'));
      await cubit.close();
    });

    test('autoFetchOnlineTags applies the first match', () async {
      when(() => metadata.searchMetadata(
            title: any(named: 'title'),
            artist: any(named: 'artist'),
            album: any(named: 'album'),
          )).thenAnswer((_) async => const [
            OnlineTrackMetadata(title: 'Hit', artist: 'Band', album: 'Rec'),
          ]);
      final cubit = single();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final ok = await cubit.autoFetchOnlineTags();
      expect(ok, isTrue);
      expect(cubit.state.title, 'Hit');
      await cubit.close();
    });
  });

  group('batch auto-fetch', () {
    test('is a no-op outside batch mode', () async {
      final cubit = single();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(await cubit.autoFetchBatchTags(), 0);
      await cubit.close();
    });

    test('fills unanimous fields across the batch', () async {
      when(() => metadata.searchMetadata(
            title: any(named: 'title'),
            artist: any(named: 'artist'),
            album: any(named: 'album'),
          )).thenAnswer((_) async => const [
            OnlineTrackMetadata(
                title: 't',
                artist: 'Same Artist',
                album: 'Same Album',
                genre: 'Rock',
                releaseYear: '2010'),
          ]);
      final a = createTestSong(id: 1, title: 'A', artist: 'X');
      final b = createTestSong(id: 2, title: 'B', artist: 'Y');
      final cubit = TagEditorCubit(
        song: a,
        batchSongs: [a, b],
        scannerService: scanner,
        metadataSearchService: metadata,
      );
      final resolved = await cubit.autoFetchBatchTags();
      expect(resolved, 2);
      expect(cubit.state.artist, 'Same Artist');
      expect(cubit.state.genre, 'Rock');
      await cubit.close();
    });

    test('leaves mixed fields untouched and reports no matches', () async {
      var call = 0;
      when(() => metadata.searchMetadata(
            title: any(named: 'title'),
            artist: any(named: 'artist'),
            album: any(named: 'album'),
          )).thenAnswer((_) async {
        call++;
        if (call == 1) {
          return const [
            OnlineTrackMetadata(title: 't', artist: 'One', album: 'A'),
          ];
        }
        return const [
          OnlineTrackMetadata(title: 't', artist: 'Two', album: 'B'),
        ];
      });
      final a = createTestSong(id: 1, title: 'A', artist: 'X');
      final b = createTestSong(id: 2, title: 'B', artist: 'Y');
      final cubit = TagEditorCubit(
        song: a,
        batchSongs: [a, b],
        scannerService: scanner,
        metadataSearchService: metadata,
      );
      final resolved = await cubit.autoFetchBatchTags();
      expect(resolved, 2);
      // Mixed artists are not applied, so the pre-batch value stays.
      expect(cubit.state.artist, isEmpty);
      await cubit.close();
    });

    test('reports when no track resolves', () async {
      final a = createTestSong(id: 1, title: 'A', artist: 'X');
      final b = createTestSong(id: 2, title: 'B', artist: 'Y');
      final cubit = TagEditorCubit(
        song: a,
        batchSongs: [a, b],
        scannerService: scanner,
        metadataSearchService: metadata,
      );
      final resolved = await cubit.autoFetchBatchTags();
      expect(resolved, 0);
      expect(cubit.state.errorMessage, contains('No matching'));
      await cubit.close();
    });
  });

  group('saveTags single', () {
    test('validates the year range', () async {
      final cubit = single();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      cubit.updateYear('99');
      await cubit.saveTags();
      expect(cubit.state.status, TagEditorStatus.failure);
      expect(cubit.state.errorMessage, contains('Year'));
      await cubit.close();
    });

    test('validates the track number', () async {
      final cubit = single();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      cubit.updateTrackNumber('-3');
      await cubit.saveTags();
      expect(cubit.state.status, TagEditorStatus.failure);
      expect(cubit.state.errorMessage, contains('Track number'));
      await cubit.close();
    });

    test('succeeds when the bridge returns true', () async {
      handler = (call) async =>
          call.method == 'readTags' ? <String, dynamic>{} : true;
      final cubit = single();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await cubit.saveTags();
      expect(cubit.state.status, TagEditorStatus.success);
      verify(() => scanner.rescanSingleFile(any())).called(1);
      await cubit.close();
    });

    test('succeeds when the bridge returns {verified: true}', () async {
      handler = (call) async => call.method == 'readTags'
          ? <String, dynamic>{}
          : <String, dynamic>{'verified': true};
      final cubit = single();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await cubit.saveTags();
      expect(cubit.state.status, TagEditorStatus.success);
      await cubit.close();
    });

    test('treats {verified: false} as unverified', () async {
      handler = (call) async => call.method == 'readTags'
          ? <String, dynamic>{}
          : <String, dynamic>{'verified': false};
      final cubit = single();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await cubit.saveTags();
      expect(cubit.state.status, TagEditorStatus.failure);
      expect(cubit.state.errorMessage, contains('could not be verified'));
      await cubit.close();
    });

    test('treats {ok: false} as rejected', () async {
      handler = (call) async => call.method == 'readTags'
          ? <String, dynamic>{}
          : <String, dynamic>{'ok': false};
      final cubit = single();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await cubit.saveTags();
      expect(cubit.state.status, TagEditorStatus.failure);
      expect(cubit.state.errorMessage, contains('rejected'));
      await cubit.close();
    });

    test('treats a false result as a failed write', () async {
      handler = (call) async =>
          call.method == 'readTags' ? <String, dynamic>{} : false;
      final cubit = single();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await cubit.saveTags();
      expect(cubit.state.status, TagEditorStatus.failure);
      expect(cubit.state.errorMessage, contains('could not be updated'));
      await cubit.close();
    });

    test('treats a null response as unavailable', () async {
      handler = (call) async => call.method == 'readTags' ? null : null;
      final cubit = single();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await cubit.saveTags();
      expect(cubit.state.status, TagEditorStatus.failure);
      expect(cubit.state.errorMessage, contains('unavailable'));
      await cubit.close();
    });

    test('maps a scoped-storage PlatformException to a helpful message',
        () async {
      handler = (call) async {
        if (call.method == 'readTags') return <String, dynamic>{};
        throw PlatformException(
            code: 'WRITE_TAGS_ERROR',
            message: 'Permission denied for write');
      };
      final cubit = single();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await cubit.saveTags();
      expect(cubit.state.status, TagEditorStatus.failure);
      expect(cubit.state.errorMessage, contains('scoped storage'));
      await cubit.close();
    });

    test('truncates oversized lyrics', () async {
      handler = (call) async =>
          call.method == 'readTags' ? <String, dynamic>{} : true;
      final cubit = single();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      cubit.updateLyrics('x' * 9000);
      await cubit.saveTags();
      expect(cubit.state.status, TagEditorStatus.success);
      expect(cubit.state.errorMessage, contains('truncated'));
      await cubit.close();
    });
  });

  group('saveTags batch', () {
    test('tags every track and reports success', () async {
      handler = (call) async =>
          call.method == 'readTags' ? <String, dynamic>{} : true;
      final a = createTestSong(id: 1, title: 'A', artist: 'X');
      final b = createTestSong(id: 2, title: 'B', artist: 'Y');
      final cubit = TagEditorCubit(
        song: a,
        batchSongs: [a, b],
        scannerService: scanner,
        metadataSearchService: metadata,
      );
      await cubit.saveTags();
      expect(cubit.state.status, TagEditorStatus.success);
      verify(() => scanner.rescanSingleFile(any())).called(2);
      await cubit.close();
    });

    test('collects failures without aborting the batch', () async {
      handler = (call) async {
        if (call.method == 'readTags') return <String, dynamic>{};
        // Reject only the first file's write by path.
        final path = (call.arguments as Map)['path'] as String;
        return path.contains('A') ? false : true;
      };
      final a = createTestSong(
          id: 1, title: 'A', artist: 'X', path: '/music/A.mp3');
      final b = createTestSong(
          id: 2, title: 'B', artist: 'Y', path: '/music/B.mp3');
      final cubit = TagEditorCubit(
        song: a,
        batchSongs: [a, b],
        scannerService: scanner,
        metadataSearchService: metadata,
      );
      await cubit.saveTags();
      expect(cubit.state.status, TagEditorStatus.success);
      expect(cubit.state.errorMessage, contains('Failed to tag 1 file'));
      await cubit.close();
    });
  });
}
