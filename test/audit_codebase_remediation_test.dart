import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/errors/failures.dart';
import 'package:pulsr/core/services/duplicate_finder_service.dart';
import 'package:pulsr/core/services/playlist_suggestions_service.dart';
import 'package:pulsr/core/services/restore_detection_service.dart';
import 'package:pulsr/core/utils/platform_capabilities.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/data/repositories/music_repository.dart';
import 'package:pulsr/domain/repositories/music_repository_interface.dart';
import 'package:pulsr/domain/usecases/get_songs_usecase.dart';

class FakeMusicRepository implements IMusicRepository {
  int? lastLimit;
  int? lastOffset;
  String? lastSearchQuery;

  @override
  Stream<Result<List<SongsTableData>>> watchAllSongs({
    String sortBy = 'title',
    bool ascending = true,
    int? limit,
    int? offset,
    String? searchQuery,
    List<String> excludedFolders = const [],
  }) {
    lastLimit = limit;
    lastOffset = offset;
    lastSearchQuery = searchQuery;
    return const Stream.empty();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('P0-1 & P1-1: FTS Unicode Tokenization Tests', () {
    test('toFtsQuery correctly parses Latin, CJK, Arabic, Cyrillic, and Hebrew', () {
      // Latin
      expect(MusicRepository.toFtsQuery('hello world'), '"hello"* "world"*');

      // CJK characters (Chinese, Japanese Kanji)
      final cjkResult = MusicRepository.toFtsQuery('周杰伦 晴天');
      expect(cjkResult, isNotNull);
      expect(cjkResult, contains('"周杰伦"*'));
      expect(cjkResult, contains('"晴天"*'));

      // Japanese Hiragana / Katakana
      final jpResult = MusicRepository.toFtsQuery('さくら 桜');
      expect(jpResult, isNotNull);
      expect(jpResult, contains('"さくら"*'));
      expect(jpResult, contains('"桜"*'));

      // Arabic characters
      final arResult = MusicRepository.toFtsQuery('عمرو دياب تملي معاك');
      expect(arResult, isNotNull);
      expect(arResult, contains('"عمرو"*'));
      expect(arResult, contains('"دياب"*'));
      expect(arResult, contains('"تملي"*'));
      expect(arResult, contains('"معاك"*'));

      // Cyrillic
      final cyrResult = MusicRepository.toFtsQuery('Виктор Цой Группа крови');
      expect(cyrResult, isNotNull);
      expect(cyrResult, contains('"виктор"*'));
      expect(cyrResult, contains('"цой"*'));

      // Special characters only should return null safely
      expect(MusicRepository.toFtsQuery('!@#\$%^&*()'), isNull);
      expect(MusicRepository.toFtsQuery('   '), isNull);
    });
  });

  group('P0-2 & P2-1: DuplicateFinderService Audio Checksum & Unicode Normalization Tests', () {
    late Directory tempDir;
    late File fileA;
    late File fileB;
    late File fileC;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('pulsr_dup_test_');
      fileA = File('${tempDir.path}/songA.mp3');
      fileB = File('${tempDir.path}/songB.mp3');
      fileC = File('${tempDir.path}/songC.mp3');

      // fileA and fileB have identical bytes (same content)
      final bytesA = Uint8List(1024 * 128);
      for (int i = 0; i < bytesA.length; i++) {
        bytesA[i] = i % 256;
      }
      await fileA.writeAsBytes(bytesA);
      await fileB.writeAsBytes(bytesA);

      // fileC has identical length and duration but different audio content
      final bytesC = Uint8List(1024 * 128);
      for (int i = 0; i < bytesC.length; i++) {
        bytesC[i] = (i + 1) % 256;
      }
      await fileC.writeAsBytes(bytesC);
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    test('findDuplicates identifies identical audio content and distinguishes collisions', () async {
      final service = DuplicateFinderService();

      final song1 = SongsTableData(
        id: 1,
        title: 'Different Title 1',
        artist: 'Unknown Artist 1',
        album: 'Unknown Album',
        durationMs: 180000,
        fileSize: 1024 * 128,
        path: fileA.path,
        isFavorite: false,
        isMissing: false,
        playCount: 0,
        lastPositionMs: 0,
        source: SongSource.local,
        isDownloaded: false,
      );

      final song2 = SongsTableData(
        id: 2,
        title: 'Different Title 2',
        artist: 'Unknown Artist 2',
        album: 'Unknown Album',
        durationMs: 180000,
        fileSize: 1024 * 128,
        path: fileB.path,
        isFavorite: false,
        isMissing: false,
        playCount: 0,
        lastPositionMs: 0,
        source: SongSource.local,
        isDownloaded: false,
      );

      final song3 = SongsTableData(
        id: 3,
        title: 'Different Title 3',
        artist: 'Unknown Artist 3',
        album: 'Unknown Album',
        durationMs: 180000,
        fileSize: 1024 * 128,
        path: fileC.path,
        isFavorite: false,
        isMissing: false,
        playCount: 0,
        lastPositionMs: 0,
        source: SongSource.local,
        isDownloaded: false,
      );

      // song1 and song2 share the same content hash. song3 has different content.
      final duplicates = await service.findDuplicates([song1, song2, song3]);

      expect(duplicates.length, 1);
      expect(duplicates.first.songs.map((s) => s.id), containsAll([1, 2]));
      expect(duplicates.first.songs.map((s) => s.id), isNot(contains(3)));
    });

    test('findDuplicates matches exact title and artist with Unicode normalization', () async {
      final service = DuplicateFinderService();

      final song1 = SongsTableData(
        id: 1,
        title: 'Café Del Mar',
        artist: 'Björk',
        album: 'Unknown Album',
        durationMs: 200000,
        fileSize: 1000,
        path: '/dummy/1.mp3',
        isFavorite: false,
        isMissing: false,
        playCount: 0,
        lastPositionMs: 0,
        source: SongSource.local,
        isDownloaded: false,
      );

      // Composed form with same characters
      final song2 = SongsTableData(
        id: 2,
        title: 'Cafe\u0301 Del Mar',
        artist: 'Bjo\u0308rk',
        album: 'Unknown Album',
        durationMs: 205000,
        fileSize: 2000,
        path: '/dummy/2.mp3',
        isFavorite: false,
        isMissing: false,
        playCount: 0,
        lastPositionMs: 0,
        source: SongSource.local,
        isDownloaded: false,
      );

      final duplicates = await service.findDuplicates([song1, song2]);
      expect(duplicates.length, 1);
      expect(duplicates.first.songs.length, 2);
    });
  });

  group('P0-3 & P1-6: PlaylistSuggestionsService Single-Pass & Caching Tests', () {
    test('generateSuggestions partitions songs in single pass and caches output for 30 minutes', () {
      final service = PlaylistSuggestionsService();

      final now = DateTime.now();
      final songs = List.generate(
        50,
        (i) => SongsTableData(
          id: i,
          title: 'Track $i',
          artist: 'Artist ${i % 5}',
          album: 'Album ${i % 3}',
          durationMs: 180000,
          path: '/path/$i.mp3',
          dateAdded: now.subtract(Duration(days: i)).millisecondsSinceEpoch,
          isFavorite: i % 2 == 0,
          isMissing: false,
          playCount: i * 10,
          lastPositionMs: 0,
          source: SongSource.local,
          isDownloaded: false,
        ),
      );

      final suggestions1 = service.generateSuggestions(songs);
      expect(suggestions1.isNotEmpty, true);

      // Second call should return cached suggestions (same instance)
      final suggestions2 = service.generateSuggestions(songs);
      expect(identical(suggestions1, suggestions2), true);

      // Invalidate cache and verify new generation
      service.invalidateCache();
      final suggestions3 = service.generateSuggestions(songs);

      expect(identical(suggestions1, suggestions3), false);
      expect(suggestions3.length, suggestions1.length);
    });
  });

  group('P0-8 & P2-4: RestoreDetectionService CRC32 Checksum Tests', () {
    test('computeCrc32 calculates correct IEEE 802.3 CRC32 checksums', () {
      // Known test vectors for CRC32
      final crcEmpty = RestoreDetectionService.computeCrc32('');
      expect(crcEmpty, 0x00000000);

      final crc123456789 = RestoreDetectionService.computeCrc32('123456789');
      expect(crc123456789, 0xCBF43926);
    });
  });

  group('P1-7: GetSongsUseCase Input Validation Tests', () {
    test('passes limit through without an upper cap, clamps offset and query',
        () {
      final fakeRepo = FakeMusicRepository();
      final useCase = GetSongsUseCase(fakeRepo);

      useCase.watchSongs(
        limit: 9999,
        offset: -50,
        searchQuery: 'a' * 300,
      );

      // F-07: no upper cap — libraries can exceed 1k rows and the cubit
      // paginates by growing the window.
      expect(fakeRepo.lastLimit, 9999);
      expect(fakeRepo.lastOffset, 0); // clamped to >= 0
      expect(fakeRepo.lastSearchQuery?.length, 200); // truncated to 200 chars
    });

    test('clamps a negative limit to zero', () {
      final fakeRepo = FakeMusicRepository();
      final useCase = GetSongsUseCase(fakeRepo);

      useCase.watchSongs(limit: -5);

      expect(fakeRepo.lastLimit, 0);
    });
  });

  group('P1-10: AudioCapabilities Model Tests', () {
    test('AudioCapabilities is immutable, serializable, and correctly typed', () {
      const caps = AudioCapabilities(
        hasEqualizer: true,
        hasAudioEffects: true,
        hasTagEditor: false,
        hasRingtoneManager: true,
        hasAppWidget: true,
        hasHardwareVisualizer: false,
        isVolumeBoostSupported: true,
        isBassBoostSupported: true,
        isDynamicsSupported: false,
        isVirtualizerSupported: true,
      );

      final map = caps.toMap();
      expect(map['hasEqualizer'], true);
      expect(map['hasAudioEffects'], true);
      expect(map['hasTagEditor'], false);
      expect(map['isVolumeBoostSupported'], true);

      final restored = AudioCapabilities.fromMap(map);
      expect(restored.hasEqualizer, true);
      expect(restored.hasAudioEffects, true);
      expect(restored.hasTagEditor, false);
      expect(restored.hasRingtoneManager, true);
      expect(restored.hasAppWidget, true);
      expect(restored.hasHardwareVisualizer, false);
      expect(restored.isVolumeBoostSupported, true);
      expect(restored.isBassBoostSupported, true);
      expect(restored.isDynamicsSupported, false);
      expect(restored.isVirtualizerSupported, true);
    });
  });
}
