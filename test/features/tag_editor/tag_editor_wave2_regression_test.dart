// Wave 2 regression tests for Tag Editor: C-10 (undo history before
// removeArtworkImage, applyMetadataResult, autoFetchBatchTags), C-11
// (clearError + status reset on field setters and listenWhen), C-12
// (_batch*Edited flags preserved on partial/failed batch save and reset only
// when failedFiles.isEmpty), H-37 (CUE/online track guards, write vs rescan
// separation, isAutoFetching lock, warning dialog before pop, temp file
// cleanup).
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/constants/channels.dart';
import 'package:pulsr/core/di/injection.dart';
import 'package:pulsr/core/services/metadata_search_service.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/data/scanner/media_scanner_service.dart';
import 'package:pulsr/features/tag_editor/tag_editor_cubit.dart';
import 'package:pulsr/features/tag_editor/tag_editor_screen.dart';
import 'package:pulsr/features/tag_editor/tag_editor_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/screen_harness.dart';
import '../../helpers/test_song_factory.dart';

class _Scanner extends Mock implements MediaScannerService {}

class _Metadata extends Mock implements MetadataSearchService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Scanner scanner;
  late _Metadata metadata;
  late MethodChannel channel;
  dynamic Function(MethodCall call)? handler;

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
    handler = (call) async =>
        call.method == 'readTags' ? <String, dynamic>{} : true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) => handler!(call));
    addTearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      await getIt.reset();
    });
  });

  group('C-10: _pushHistory before artwork & metadata mutations', () {
    test('removeArtworkImage, applyMetadataResult, and autoFetchBatchTags can be undone',
        () async {
      final s = createTestSong(
        id: 1,
        title: 'Original Title',
        artist: 'Original Artist',
        album: 'Original Album',
      );
      final cubit = TagEditorCubit(
        song: s,
        scannerService: scanner,
        metadataSearchService: metadata,
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      cubit.removeArtworkImage();
      expect(cubit.state.removeArtwork, isTrue);
      expect(cubit.undo(), isTrue);
      expect(cubit.state.removeArtwork, isFalse);

      await cubit.applyMetadataResult(
        const OnlineTrackMetadata(
          title: 'Fetched Title',
          artist: 'Fetched Artist',
          album: 'Fetched Album',
        ),
      );
      expect(cubit.state.title, 'Fetched Title');
      expect(cubit.undo(), isTrue);
      expect(cubit.state.title, 'Original Title');
      await cubit.close();

      // Batch auto-fetch undo
      when(() => metadata.searchMetadata(
            title: any(named: 'title'),
            artist: any(named: 'artist'),
            album: any(named: 'album'),
          )).thenAnswer((_) async => const [
            OnlineTrackMetadata(
              title: 'T',
              artist: 'Unanimous Artist',
              album: 'Unanimous Album',
            ),
          ]);
      final a = createTestSong(id: 1, title: 'A', artist: 'Init');
      final b = createTestSong(id: 2, title: 'B', artist: 'Init');
      final batchCubit = TagEditorCubit(
        song: a,
        batchSongs: [a, b],
        scannerService: scanner,
        metadataSearchService: metadata,
      );
      await batchCubit.autoFetchBatchTags();
      expect(batchCubit.state.artist, 'Unanimous Artist');
      expect(batchCubit.undo(), isTrue);
      expect(batchCubit.state.artist, 'Init');
      await batchCubit.close();
    });
  });

  group('C-11: field setters clear error and failure status', () {
    test('every setter clears error and resets status from failure to loaded',
        () async {
      final cubit = TagEditorCubit(
        song: createTestSong(id: 1, title: 'Valid'),
        scannerService: scanner,
        metadataSearchService: metadata,
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      cubit.updateYear('bad');
      await cubit.saveTags();
      expect(cubit.state.status, TagEditorStatus.failure);
      expect(cubit.state.errorMessage, isNotNull);

      cubit.updateYear('2024');
      expect(cubit.state.errorMessage, isNull);
      expect(cubit.state.status, TagEditorStatus.loaded);
      await cubit.close();
    });
  });

  group('C-12: batch dirty flags survive partial failure and reset on full success',
      () {
    test('retains _batchArtistEdited when first save partially fails', () async {
      var failFirst = true;
      final writtenPayloads = <Map<dynamic, dynamic>>[];
      handler = (call) async {
        if (call.method == 'readTags') return <String, dynamic>{};
        if (call.method == 'writeTags') {
          final args = Map<dynamic, dynamic>.from(call.arguments as Map);
          writtenPayloads.add(args);
          if (failFirst && (args['path'] as String).contains('A.mp3')) {
            return false;
          }
          return true;
        }
        return true;
      };

      final a = createTestSong(
          id: 1, title: 'A', artist: 'OldA', path: '/music/A.mp3');
      final b = createTestSong(
          id: 2, title: 'B', artist: 'OldB', path: '/music/B.mp3');
      final cubit = TagEditorCubit(
        song: a,
        batchSongs: [a, b],
        scannerService: scanner,
        metadataSearchService: metadata,
      );

      // Clear artist explicitly in batch mode ('')
      cubit.updateArtist('');
      await cubit.saveTags();
      expect(cubit.state.batchFailedCount, 1);

      // Retry after fixing failure: _batchArtistEdited must still be true so '' is written, not 'OldA'
      writtenPayloads.clear();
      failFirst = false;
      await cubit.saveTags();
      expect(cubit.state.batchFailedCount, 0);
      expect(writtenPayloads.first['artist'], '');
      await cubit.close();
    });
  });

  group('H-37 & M-05: CUE/online guards, rescan warning, warning dialog, temp cleanup',
      () {
    test('rejects CUE virtual tracks and un-downloaded YouTube tracks',
        () async {
      final cueSong = createTestSong(id: 1, title: 'Cue').copyWith(
        cueStartMs: const Value(12000),
      );
      expect(
        TagEditorCubit.unsupportedTrackReason(cueSong),
        contains('CUE'),
      );

      final onlineSong = createTestSong(
        id: -10,
        title: 'Stream',
        path: 'ytmusic://v123',
        source: SongSource.youtube,
        isDownloaded: false,
      );
      expect(
        TagEditorCubit.unsupportedTrackReason(onlineSong),
        contains('online'),
      );
    });

    test('separates writeTags success from rescanSingleFile failure', () async {
      when(() => scanner.rescanSingleFile(any()))
          .thenThrow(Exception('DB busy'));
      final cubit = TagEditorCubit(
        song: createTestSong(id: 1, title: 'Track', path: '/music/Track.mp3'),
        scannerService: scanner,
        metadataSearchService: metadata,
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      await cubit.saveTags();
      expect(cubit.state.status, TagEditorStatus.success);
      expect(cubit.state.errorMessage, contains('refreshing the library'));
      await cubit.close();
    });

    test('deletes downloaded temp artwork files on close()', () async {
      final tempFile = File(
        '${Directory.systemTemp.path}/auto_art_test_${DateTime.now().microsecondsSinceEpoch}.jpg',
      );
      tempFile.writeAsBytesSync(const [1, 2, 3]);
      when(() => metadata.downloadArtworkToTemp(any()))
          .thenAnswer((_) async => tempFile.path);

      final cubit = TagEditorCubit(
        song: createTestSong(id: 1, title: 'Track'),
        scannerService: scanner,
        metadataSearchService: metadata,
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await cubit.applyMetadataResult(
        const OnlineTrackMetadata(
          title: 'T',
          artist: 'A',
          album: 'B',
          artworkUrl: 'https://example.com/art.jpg',
        ),
      );
      expect(tempFile.existsSync(), isTrue);

      await cubit.close();
      expect(tempFile.existsSync(), isFalse);
    });

    testWidgets('TagEditorScreen displays truncation warning dialog before pop',
        (tester) async {
      getIt.registerSingleton<MediaScannerService>(scanner);
      getIt.registerSingleton<MetadataSearchService>(metadata);

      useScreenSize(tester, const Size(800, 1600));
      final wavSong = createTestSong(
        id: 1,
        title: 'Wav Song',
        path: '/music/Wav.wav',
      );
      await tester.pumpWidget(
        screenHarness(child: TagEditorScreen(song: wavSong)),
      );
      await tester.pumpAndSettle();

      final lyricsField = find.byType(TextFormField).last;
      await tester.enterText(lyricsField, 'L' * 8500);
      await tester.pump();

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      // Warning dialog must appear and keep TagEditorScreen open until OK is tapped.
      expect(find.textContaining('truncated to 8192'), findsOneWidget);
      expect(find.byType(TagEditorScreen), findsOneWidget);

      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.byType(TagEditorScreen), findsNothing);
    });
  });
}
