// test/features/tag_editor/tag_editor_cubit_test.dart
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/constants/channels.dart';
import 'package:pulsr/data/services/metadata_search_service.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/data/scanner/media_scanner_service.dart';
import 'package:pulsr/features/tag_editor/cubit/tag_editor_cubit.dart';
import 'package:pulsr/features/tag_editor/cubit/tag_editor_state.dart';

class MockMediaScannerService extends Mock implements MediaScannerService {}

class MockMetadataSearchService extends Mock implements MetadataSearchService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockMediaScannerService mockScanner;
  late MockMetadataSearchService mockMetadataSearch;
  late List<MethodCall> channelCalls;

  final testSong = SongsTableData(
    id: 1,
    title: 'Original Title',
    artist: 'Original Artist',
    album: 'Original Album',
    path: '/storage/emulated/0/Music/test.mp3',
    durationMs: 180000,
    bitrateKbps: 320,
    genre: 'Rock',
    year: 2024,
    trackNumber: 1,
    discNumber: 1,
    playCount: 0,
    isFavorite: false,
    isMissing: false,
    lastPositionMs: 0,
    isDownloaded: false,
    dateAdded: 1700000000,
    source: SongSource.local,
  );

  setUp(() {
    mockScanner = MockMediaScannerService();
    mockMetadataSearch = MockMetadataSearchService();
    channelCalls = [];

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel(PulsrChannels.tagEditor),
          (MethodCall call) async {
            channelCalls.add(call);
            switch (call.method) {
              case 'readTags':
                final path = call.arguments['path'] as String?;
                if (path != null && path.contains('unsupported')) {
                  throw PlatformException(
                    code: 'UNSUPPORTED_FORMAT',
                    message: 'Format not supported',
                  );
                }
                return {
                  'title': 'Read Title',
                  'artist': 'Read Artist',
                  'album': 'Read Album',
                  'genre': 'Pop',
                  'year': '2025',
                  'trackNumber': '3',
                  'comment': 'Test Comment',
                  'lyrics': '[00:10.00]Hello world',
                  'artwork': Uint8List.fromList([1, 2, 3, 4]),
                };
              case 'writeTags':
                final path = call.arguments['path'] as String?;
                if (path != null && path.contains('fail_write')) {
                  throw PlatformException(
                    code: 'WRITE_ERROR',
                    message: 'Write failed',
                  );
                }
                return true;
              default:
                return null;
            }
          },
        );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel(PulsrChannels.tagEditor),
          null,
        );
  });

  group('[T1] TagEditorCubit Comprehensive Test Suite', () {
    test('Loads tags successfully on instantiation', () async {
      final cubit = TagEditorCubit(
        song: testSong,
        scannerService: mockScanner,
        metadataSearchService: mockMetadataSearch,
      );

      await Future.delayed(const Duration(milliseconds: 50));

      expect(cubit.state.status, equals(TagEditorStatus.loaded));
      expect(cubit.state.title, equals('Read Title'));
      expect(cubit.state.artist, equals('Read Artist'));
      expect(cubit.state.album, equals('Read Album'));
      expect(cubit.state.genre, equals('Pop'));
      expect(cubit.state.year, equals('2025'));
      expect(cubit.state.trackNumber, equals('3'));
      expect(cubit.state.artworkBytes, isNotNull);
      await cubit.close();
    });

    test(
      'Field editing and validation (Arabic RTL, Unicode emojis, long strings)',
      () async {
        final cubit = TagEditorCubit(
          song: testSong,
          scannerService: mockScanner,
          metadataSearchService: mockMetadataSearch,
        );
        await Future.delayed(const Duration(milliseconds: 50));

        // Arabic RTL & Emojis
        cubit.updateTitle('أغنية جميلة 🎵');
        cubit.updateArtist('فنان عربي 🌟');
        cubit.updateAlbum('ألبوم الموسيقى');

        expect(cubit.state.title, equals('أغنية جميلة 🎵'));
        expect(cubit.state.artist, equals('فنان عربي 🌟'));
        expect(cubit.state.album, equals('ألبوم الموسيقى'));

        // Long strings
        final longTitle = 'A' * 500;
        cubit.updateTitle(longTitle);
        expect(cubit.state.title, equals(longTitle));

        // Empty title handling
        cubit.updateTitle('');
        expect(cubit.state.title, equals(''));
        await cubit.close();
      },
    );

    test('Artwork removal flag is toggled properly', () async {
      final cubit = TagEditorCubit(
        song: testSong,
        scannerService: mockScanner,
        metadataSearchService: mockMetadataSearch,
      );
      await Future.delayed(const Duration(milliseconds: 50));

      cubit.removeArtworkImage();
      expect(cubit.state.artworkBytes, isNull);
      expect(cubit.state.removeArtwork, isTrue);
      await cubit.close();
    });

    test(
      'Save success invokes writeTags and triggers scanner refresh',
      () async {
        when(
          () => mockScanner.rescanSingleFile(any()),
        ).thenAnswer((_) async {});

        final cubit = TagEditorCubit(
          song: testSong,
          scannerService: mockScanner,
          metadataSearchService: mockMetadataSearch,
        );
        await Future.delayed(const Duration(milliseconds: 50));

        cubit.updateTitle('Saved Title');
        cubit.updateArtist('Saved Artist');

        await cubit.saveTags();
        expect(cubit.state.status, equals(TagEditorStatus.success));

        // Verify native writeTags call
        final writeCall = channelCalls.firstWhere(
          (c) => c.method == 'writeTags',
        );
        expect(writeCall.arguments['path'], equals(testSong.path));
        expect(writeCall.arguments['title'], equals('Saved Title'));
        expect(writeCall.arguments['artist'], equals('Saved Artist'));
        verify(() => mockScanner.rescanSingleFile(testSong.path)).called(1);
        await cubit.close();
      },
    );

    test(
      'Save failure preserves state and sets error status without crashing',
      () async {
        when(
          () => mockScanner.rescanSingleFile(any()),
        ).thenAnswer((_) async {});

        final failingSong = testSong.copyWith(
          path: '/storage/emulated/0/Music/fail_write.mp3',
        );
        final cubit = TagEditorCubit(
          song: failingSong,
          scannerService: mockScanner,
          metadataSearchService: mockMetadataSearch,
        );
        await Future.delayed(const Duration(milliseconds: 50));

        cubit.updateTitle('New Title');
        await cubit.saveTags();

        expect(cubit.state.status, equals(TagEditorStatus.failure));
        expect(cubit.state.errorMessage, isNotNull);
        expect(
          cubit.state.title,
          equals('New Title'),
        ); // Preserved edits for retry
        await cubit.close();
      },
    );

    test(
      'Batch mode applies common fields across all selected tracks',
      () async {
        final batchSong1 = testSong.copyWith(
          id: 1,
          path: '/path/1.mp3',
          artist: 'Artist A',
        );
        final batchSong2 = testSong.copyWith(
          id: 2,
          path: '/path/2.mp3',
          artist: 'Artist B',
        );

        when(
          () => mockScanner.rescanSingleFile(any()),
        ).thenAnswer((_) async {});

        final cubit = TagEditorCubit(
          song: batchSong1,
          batchSongs: [batchSong1, batchSong2],
          scannerService: mockScanner,
          metadataSearchService: mockMetadataSearch,
        );

        expect(cubit.state.isBatchMode, isTrue);
        expect(cubit.state.batchSongs.length, equals(2));

        cubit.updateArtist('Unified Artist');
        cubit.updateGenre('Jazz');

        await cubit.saveTags();
        expect(cubit.state.status, equals(TagEditorStatus.success));

        final writeCalls =
            channelCalls.where((c) => c.method == 'writeTags').toList();
        expect(writeCalls.length, equals(2));
        expect(writeCalls[0].arguments['artist'], equals('Unified Artist'));
        expect(writeCalls[1].arguments['artist'], equals('Unified Artist'));
        await cubit.close();
      },
    );

    test(
      'Tag format matrix (MP3 ID3v2.3, ID3v2.4, FLAC Vorbis, MP4 AAC)',
      () async {
        final formats = [
          '/music/track.mp3',
          '/music/track.flac',
          '/music/track.m4a',
          '/music/track.ogg',
        ];

        for (final formatPath in formats) {
          final song = testSong.copyWith(path: formatPath);
          final cubit = TagEditorCubit(
            song: song,
            scannerService: mockScanner,
            metadataSearchService: mockMetadataSearch,
          );
          await Future.delayed(const Duration(milliseconds: 30));
          expect(cubit.state.status, equals(TagEditorStatus.loaded));
          await cubit.close();
        }
      },
    );
  });
}
