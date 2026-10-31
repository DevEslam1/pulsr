import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/domain/models/quran_metadata.dart';
import 'package:pulsr/domain/models/quran_surah.dart';

void main() {
  group('QuranAyahTiming', () {
    test('rejects negative and empty timing intervals', () {
      expect(
          const QuranAyahTiming(
                  ayahNumber: 1,
                  start: Duration(seconds: -1),
                  end: Duration(seconds: 2))
              .isValid,
          isFalse);
      expect(
          const QuranAyahTiming(
                  ayahNumber: 1, start: Duration.zero, end: Duration.zero)
              .isValid,
          isFalse);
    });
    test('instantiates and serializes accurately', () {
      const timing = QuranAyahTiming(
        ayahNumber: 1,
        start: Duration(seconds: 0),
        end: Duration(seconds: 5),
      );
      final map = timing.toMap();
      final restored = QuranAyahTiming.fromMap(map);
      expect(restored.ayahNumber, 1);
      expect(restored.start, Duration.zero);
      expect(restored.end, const Duration(seconds: 5));
      expect(restored, timing);
    });
  });

  group('QuranMetadata', () {
    test('rejects verses beyond the canonical surah length', () {
      const meta = QuranMetadata(
          surahNumber: 1,
          surahName: 'Al-Fatihah',
          ayahStart: 1,
          ayahEnd: 8,
          reciter: 'Reciter');
      expect(meta.isValid, isFalse);
    });

    test('rejects overlapping, unordered, and out-of-range verse timings', () {
      const meta = QuranMetadata(
          surahNumber: 1,
          surahName: 'Al-Fatihah',
          ayahStart: 1,
          ayahEnd: 7,
          reciter: 'Reciter');
      const first = QuranAyahTiming(
          ayahNumber: 1, start: Duration.zero, end: Duration(seconds: 5));
      const overlap = QuranAyahTiming(
          ayahNumber: 2,
          start: Duration(seconds: 4),
          end: Duration(seconds: 8));
      const outside = QuranAyahTiming(
          ayahNumber: 8,
          start: Duration(seconds: 6),
          end: Duration(seconds: 9));
      expect(meta.copyWith(ayahTimings: [first, overlap]).isValid, isFalse);
      expect(meta.copyWith(ayahTimings: [outside]).isValid, isFalse);
      expect(meta.copyWith(ayahTimings: [overlap, first]).isValid, isFalse);
    });

    test('validates correct Surah range and fields', () {
      const valid = QuranMetadata(
        surahNumber: 1,
        surahName: 'Al-Fatihah',
        ayahStart: 1,
        ayahEnd: 7,
        reciter: 'Mishary Alafasy',
      );
      expect(valid.isValid, isTrue);
      expect(valid.totalAyahs, 7);

      const invalidSurahLow = QuranMetadata(
        surahNumber: 0,
        surahName: 'Invalid',
        ayahStart: 1,
        ayahEnd: 5,
        reciter: 'Reciter',
      );
      expect(invalidSurahLow.isValid, isFalse);

      const invalidSurahHigh = QuranMetadata(
        surahNumber: 115,
        surahName: 'Invalid',
        ayahStart: 1,
        ayahEnd: 5,
        reciter: 'Reciter',
      );
      expect(invalidSurahHigh.isValid, isFalse);

      const invalidAyahEnd = QuranMetadata(
        surahNumber: 2,
        surahName: 'Al-Baqarah',
        ayahStart: 10,
        ayahEnd: 5,
        reciter: 'Reciter',
      );
      expect(invalidAyahEnd.isValid, isFalse);
    });

    test('serializes and deserializes accurately', () {
      const original = QuranMetadata(
        surahNumber: 114,
        surahName: 'An-Nas',
        ayahStart: 1,
        ayahEnd: 6,
        reciter: 'Abdul Basit',
        source: 'Tanzil',
        ayahTimings: [
          QuranAyahTiming(
            ayahNumber: 1,
            start: Duration(seconds: 0),
            end: Duration(seconds: 4),
          ),
          QuranAyahTiming(
            ayahNumber: 2,
            start: Duration(seconds: 4),
            end: Duration(seconds: 8),
          ),
        ],
      );

      final map = original.toMap();
      final restored = QuranMetadata.fromMap(map);

      expect(restored, original);
      expect(restored.timingForAyah(1)?.end, const Duration(seconds: 4));
      expect(restored.timingForAyah(2)?.start, const Duration(seconds: 4));
      expect(restored.timingForAyah(99), isNull);
    });
  });

  group('QuranBookmark', () {
    test('validates bookmark fields and isolation', () {
      const metadata = QuranMetadata(
        surahNumber: 18,
        surahName: 'Al-Kahf',
        ayahStart: 1,
        ayahEnd: 110,
        reciter: 'Minshawi',
      );

      final bookmark = QuranBookmark(
        trackUri: 'content://quran/surah18.mp3',
        metadata: metadata,
        currentAyah: 10,
        position: const Duration(minutes: 2, seconds: 15),
        timestamp: DateTime(2026, 10, 16),
      );

      expect(bookmark.isValid, isTrue);

      final map = bookmark.toMap();
      final restored = QuranBookmark.fromMap(map);
      expect(restored, bookmark);
    });
  });

  group('QuranSurah & Reciters Catalog', () {
    test('contains all 114 canonical Surahs with valid fields', () {
      expect(QuranSurah.canonicalSurahs.length, 114);

      final fatihah = QuranSurah.byNumber(1);
      expect(fatihah, isNotNull);
      expect(fatihah!.nameTransliteration, 'Al-Fatihah');
      expect(fatihah.nameArabic, 'الفاتحة');
      expect(fatihah.totalAyahs, 7);
      expect(fatihah.isMeccan, isTrue);
      expect(fatihah.revelationPlace, 'Meccan');

      final baqarah = QuranSurah.byNumber(2);
      expect(baqarah, isNotNull);
      expect(baqarah!.totalAyahs, 286);
      expect(baqarah.isMeccan, isFalse);
      expect(baqarah.revelationPlace, 'Medinan');

      final nas = QuranSurah.byNumber(114);
      expect(nas, isNotNull);
      expect(nas!.nameTransliteration, 'An-Nas');

      expect(QuranSurah.byNumber(0), isNull);
      expect(QuranSurah.byNumber(115), isNull);
    });

    test('contains renowned reciters with valid Riwayah', () {
      expect(QuranReciter.canonicalReciters, isNotEmpty);
      final alafasy =
          QuranReciter.canonicalReciters.firstWhere((r) => r.id == 'alafasy');
      expect(alafasy.nameEnglish, contains('Alafasy'));
      expect(alafasy.riwayah, contains('Hafs'));

      final warsh = QuranReciter.canonicalReciters
          .firstWhere((r) => r.id == 'yassin_warsh');
      expect(warsh.riwayah, contains('Warsh'));
    });
  });
}
