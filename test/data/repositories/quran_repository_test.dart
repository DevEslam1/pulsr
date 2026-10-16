// test/data/repositories/quran_repository_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pulsr/domain/models/quran_metadata.dart';
import 'package:pulsr/data/repositories/quran_repository_impl.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('QuranRepositoryImpl', () {
    test('returns null when no metadata exists (no inference/guessing)',
        () async {
      final repo = QuranRepositoryImpl();
      final metadata = await repo.getMetadataForTrack('file:///music/001.mp3');
      expect(metadata, isNull);
    });

    test('saves and retrieves Quran metadata safely', () async {
      final repo = QuranRepositoryImpl();
      const meta = QuranMetadata(
        surahNumber: 36,
        surahName: 'Ya-Sin',
        ayahStart: 1,
        ayahEnd: 83,
        reciter: 'Ali Jaber',
      );

      await repo.saveMetadataForTrack('quran://surah36', meta);
      final retrieved = await repo.getMetadataForTrack('quran://surah36');

      expect(retrieved, isNotNull);
      expect(retrieved!.surahName, 'Ya-Sin');
      expect(retrieved.surahNumber, 36);

      await repo.removeMetadataForTrack('quran://surah36');
      expect(await repo.getMetadataForTrack('quran://surah36'), isNull);
    });

    test('saves and clears Quran bookmarks independently from music', () async {
      final repo = QuranRepositoryImpl();
      const meta = QuranMetadata(
        surahNumber: 55,
        surahName: 'Ar-Rahman',
        ayahStart: 1,
        ayahEnd: 78,
        reciter: 'Husary',
      );

      final bookmark = QuranBookmark(
        trackUri: 'quran://surah55',
        metadata: meta,
        currentAyah: 13,
        position: const Duration(minutes: 1, seconds: 30),
        timestamp: DateTime(2026, 10, 16),
      );

      await repo.saveBookmark(bookmark);
      final fetched = await repo.getBookmark('quran://surah55');

      expect(fetched, isNotNull);
      expect(fetched!.currentAyah, 13);
      expect(fetched.position, const Duration(minutes: 1, seconds: 30));

      final all = await repo.getAllBookmarks();
      expect(all.length, 1);

      await repo.clearBookmark('quran://surah55');
      expect(await repo.getBookmark('quran://surah55'), isNull);
      expect(await repo.getAllBookmarks(), isEmpty);
    });

    test('recovers safely from corrupt JSON', () async {
      SharedPreferences.setMockInitialValues({
        QuranRepositoryImpl.prefsMetadataKey: 'corrupt json{',
        QuranRepositoryImpl.prefsBookmarksKey: 'corrupt json{',
      });

      final repo = QuranRepositoryImpl();
      expect(await repo.getMetadataForTrack('any'), isNull);
      expect(await repo.getBookmark('any'), isNull);
      expect(await repo.getAllBookmarks(), isEmpty);
    });

    test('provides canonical Surahs, reciters, and Ayah texts', () {
      final repo = QuranRepositoryImpl();
      expect(repo.getSurahs().length, 114);
      expect(repo.getSurah(1)?.nameTransliteration, 'Al-Fatihah');
      expect(repo.getReciters(), isNotEmpty);

      final fatihahAyahs = repo.getAyahsForSurah(1);
      expect(fatihahAyahs.length, 7);
      expect(
          fatihahAyahs.first.textArabic, contains('الرَّحْمَٰنِ الرَّحِيمِ'));

      final nasAyahs = repo.getAyahsForSurah(114);
      expect(nasAyahs.length, 6);
      expect(nasAyahs.last.textArabic, contains('النَّاسِ'));
    });
  });
}
