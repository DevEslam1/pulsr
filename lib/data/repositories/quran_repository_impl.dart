// lib/data/repositories/quran_repository_impl.dart
import 'dart:convert';
import 'package:injectable/injectable.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/utils/error_logger.dart';
import '../../domain/models/quran_metadata.dart';
import '../../domain/models/quran_surah.dart';
import '../../domain/repositories/quran_repository.dart';

@LazySingleton(as: QuranRepository)
class QuranRepositoryImpl implements QuranRepository {
  static const String prefsMetadataKey = 'quran_metadata_catalog_v1';
  static const String prefsBookmarksKey = 'quran_bookmarks_v1';

  final SharedPreferences? _prefsOverride;

  @factoryMethod
  QuranRepositoryImpl() : _prefsOverride = null;

  QuranRepositoryImpl.withPrefs(this._prefsOverride);

  Future<SharedPreferences> _getPrefs() async {
    return _prefsOverride ?? await SharedPreferences.getInstance();
  }

  @override
  Future<QuranMetadata?> getMetadataForTrack(String trackUri) async {
    if (trackUri.isEmpty) return null;
    try {
      final prefs = await _getPrefs();
      final raw = prefs.getString(prefsMetadataKey);
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final trackData = decoded[trackUri];
      if (trackData is! Map) return null;

      final metadata =
          QuranMetadata.fromMap(Map<String, dynamic>.from(trackData));
      return metadata.isValid ? metadata : null;
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to read Quran metadata for track $trackUri',
        error: e,
        stackTrace: st,
        category: 'QuranRepository',
      );
      return null;
    }
  }

  @override
  Future<void> saveMetadataForTrack(
      String trackUri, QuranMetadata metadata) async {
    if (trackUri.isEmpty || !metadata.isValid) return;
    try {
      final prefs = await _getPrefs();
      final raw = prefs.getString(prefsMetadataKey);
      final catalog = <String, dynamic>{};
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) catalog.addAll(Map<String, dynamic>.from(decoded));
      }
      catalog[trackUri] = metadata.toMap();
      await prefs.setString(prefsMetadataKey, jsonEncode(catalog));
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to save Quran metadata for track $trackUri',
        error: e,
        stackTrace: st,
        category: 'QuranRepository',
      );
    }
  }

  @override
  Future<void> removeMetadataForTrack(String trackUri) async {
    if (trackUri.isEmpty) return;
    try {
      final prefs = await _getPrefs();
      final raw = prefs.getString(prefsMetadataKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final catalog = Map<String, dynamic>.from(decoded);
      catalog.remove(trackUri);
      await prefs.setString(prefsMetadataKey, jsonEncode(catalog));
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to remove Quran metadata for track $trackUri',
        error: e,
        stackTrace: st,
        category: 'QuranRepository',
      );
    }
  }

  @override
  Future<QuranBookmark?> getBookmark(String trackUri) async {
    if (trackUri.isEmpty) return null;
    try {
      final prefs = await _getPrefs();
      final raw = prefs.getString(prefsBookmarksKey);
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final bookmarkData = decoded[trackUri];
      if (bookmarkData is! Map) return null;

      final bookmark =
          QuranBookmark.fromMap(Map<String, dynamic>.from(bookmarkData));
      return bookmark.isValid ? bookmark : null;
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to read Quran bookmark for track $trackUri',
        error: e,
        stackTrace: st,
        category: 'QuranRepository',
      );
      return null;
    }
  }

  @override
  Future<void> saveBookmark(QuranBookmark bookmark) async {
    if (!bookmark.isValid) return;
    try {
      final prefs = await _getPrefs();
      final raw = prefs.getString(prefsBookmarksKey);
      final bookmarks = <String, dynamic>{};
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          bookmarks.addAll(Map<String, dynamic>.from(decoded));
        }
      }
      bookmarks[bookmark.trackUri] = bookmark.toMap();
      await prefs.setString(prefsBookmarksKey, jsonEncode(bookmarks));
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to save Quran bookmark for track ${bookmark.trackUri}',
        error: e,
        stackTrace: st,
        category: 'QuranRepository',
      );
    }
  }

  @override
  Future<void> clearBookmark(String trackUri) async {
    if (trackUri.isEmpty) return;
    try {
      final prefs = await _getPrefs();
      final raw = prefs.getString(prefsBookmarksKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final bookmarks = Map<String, dynamic>.from(decoded);
      bookmarks.remove(trackUri);
      await prefs.setString(prefsBookmarksKey, jsonEncode(bookmarks));
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to clear Quran bookmark for track $trackUri',
        error: e,
        stackTrace: st,
        category: 'QuranRepository',
      );
    }
  }

  @override
  Future<List<QuranBookmark>> getAllBookmarks() async {
    try {
      final prefs = await _getPrefs();
      final raw = prefs.getString(prefsBookmarksKey);
      if (raw == null || raw.isEmpty) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const [];
      final list = <QuranBookmark>[];
      for (final value in decoded.values) {
        if (value is Map) {
          final bm = QuranBookmark.fromMap(Map<String, dynamic>.from(value));
          if (bm.isValid) list.add(bm);
        }
      }
      return list;
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to read all Quran bookmarks',
        error: e,
        stackTrace: st,
        category: 'QuranRepository',
      );
      return const [];
    }
  }

  @override
  List<QuranSurah> getSurahs() => QuranSurah.canonicalSurahs;

  @override
  QuranSurah? getSurah(int surahNumber) => QuranSurah.byNumber(surahNumber);

  @override
  List<QuranReciter> getReciters() => QuranReciter.canonicalReciters;

  @override
  List<QuranAyahText> getAyahsForSurah(int surahNumber) {
    if (surahNumber == 1) {
      return const [
        QuranAyahText(
          surahNumber: 1,
          ayahNumber: 1,
          textArabic: 'بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ',
          textEnglish:
              'In the name of Allah, the Entirely Merciful, the Especially Merciful.',
        ),
        QuranAyahText(
          surahNumber: 1,
          ayahNumber: 2,
          textArabic: 'الْحَمْدُ لِلَّهِ رَبِّ الْعَالَمِينَ',
          textEnglish: '[All] praise is [due] to Allah, Lord of the worlds -',
        ),
        QuranAyahText(
          surahNumber: 1,
          ayahNumber: 3,
          textArabic: 'الرَّحْمَٰنِ الرَّحِيمِ',
          textEnglish: 'The Entirely Merciful, the Especially Merciful,',
        ),
        QuranAyahText(
          surahNumber: 1,
          ayahNumber: 4,
          textArabic: 'مَالِكِ يَوْمِ الدِّينِ',
          textEnglish: 'Sovereign of the Day of Recompense.',
        ),
        QuranAyahText(
          surahNumber: 1,
          ayahNumber: 5,
          textArabic: 'إِيَّاكَ نَعْبُدُ وَإِيَّاكَ نَسْتَعِينُ',
          textEnglish: 'It is You we worship and You we ask for help.',
        ),
        QuranAyahText(
          surahNumber: 1,
          ayahNumber: 6,
          textArabic: 'اهْدِنَا الصِّرَاطَ الْمُسْتَقِيمَ',
          textEnglish: 'Guide us to the straight path -',
        ),
        QuranAyahText(
          surahNumber: 1,
          ayahNumber: 7,
          textArabic:
              'صِرَاطَ الَّذِينَ أَنْعَمْتَ عَلَيْهِمْ غَيْرِ الْمَغْضُوبِ عَلَيْهِمْ وَلَا الضَّالِّينَ',
          textEnglish:
              'The path of those upon whom You have bestowed favor, not of those who have evoked [Your] anger or of those who are astray.',
        ),
      ];
    } else if (surahNumber == 112) {
      return const [
        QuranAyahText(
          surahNumber: 112,
          ayahNumber: 1,
          textArabic: 'قُلْ هُوَ اللَّهُ أَحَدٌ',
          textEnglish: 'Say, "He is Allah, [who is] One,',
        ),
        QuranAyahText(
          surahNumber: 112,
          ayahNumber: 2,
          textArabic: 'اللَّهُ الصَّمَدُ',
          textEnglish: 'Allah, the Eternal Refuge.',
        ),
        QuranAyahText(
          surahNumber: 112,
          ayahNumber: 3,
          textArabic: 'لَمْ يَلِدْ وَلَمْ يُولَدْ',
          textEnglish: 'He neither begets nor is born,',
        ),
        QuranAyahText(
          surahNumber: 112,
          ayahNumber: 4,
          textArabic: 'وَلَمْ يَكُن لَّهُ كُفُوًا أَحَدٌ',
          textEnglish: 'Nor is there to Him any equivalent."',
        ),
      ];
    } else if (surahNumber == 113) {
      return const [
        QuranAyahText(
          surahNumber: 113,
          ayahNumber: 1,
          textArabic: 'قُلْ أَعُوذُ بِرَبِّ الْفَلَقِ',
          textEnglish: 'Say, "I seek refuge in the Lord of daybreak',
        ),
        QuranAyahText(
          surahNumber: 113,
          ayahNumber: 2,
          textArabic: 'مِن شَرِّ مَا خَلَقَ',
          textEnglish: 'From the evil of that which He created',
        ),
        QuranAyahText(
          surahNumber: 113,
          ayahNumber: 3,
          textArabic: 'وَمِن شَرِّ غَاسِقٍ إِذَا وَقَبَ',
          textEnglish: 'And from the evil of darkness when it settles',
        ),
        QuranAyahText(
          surahNumber: 113,
          ayahNumber: 4,
          textArabic: 'وَمِن شَرِّ النَّفَّاثَاتِ فِي الْعُقَدِ',
          textEnglish: 'And from the evil of the blowers in knots',
        ),
        QuranAyahText(
          surahNumber: 113,
          ayahNumber: 5,
          textArabic: 'وَمِن شَرِّ حَاسِدٍ إِذَا حَسَدَ',
          textEnglish: 'And from the evil of an envier when he envies."',
        ),
      ];
    } else if (surahNumber == 114) {
      return const [
        QuranAyahText(
          surahNumber: 114,
          ayahNumber: 1,
          textArabic: 'قُلْ أَعُوذُ بِرَبِّ النَّاسِ',
          textEnglish: 'Say, "I seek refuge in the Lord of mankind,',
        ),
        QuranAyahText(
          surahNumber: 114,
          ayahNumber: 2,
          textArabic: 'مَلِكِ النَّاسِ',
          textEnglish: 'The Sovereign of mankind,',
        ),
        QuranAyahText(
          surahNumber: 114,
          ayahNumber: 3,
          textArabic: 'إِلَٰهِ النَّاسِ',
          textEnglish: 'The God of mankind,',
        ),
        QuranAyahText(
          surahNumber: 114,
          ayahNumber: 4,
          textArabic: 'مِن شَرِّ الْوَسْوَاسِ الْخَنَّاسِ',
          textEnglish: 'From the evil of the retreating whisperer -',
        ),
        QuranAyahText(
          surahNumber: 114,
          ayahNumber: 5,
          textArabic: 'الَّذِي يُوَسْوِسُ فِي صُدُورِ النَّاسِ',
          textEnglish: 'Who whispers [evil] into the breasts of mankind -',
        ),
        QuranAyahText(
          surahNumber: 114,
          ayahNumber: 6,
          textArabic: 'مِنَ الْجِنَّةِ وَالنَّاسِ',
          textEnglish: 'From among the jinn and mankind."',
        ),
      ];
    }

    final surah = QuranSurah.byNumber(surahNumber);
    if (surah == null) return const [];
    return List.generate(
      surah.totalAyahs,
      (i) => QuranAyahText(
        surahNumber: surahNumber,
        ayahNumber: i + 1,
        textArabic: 'الآية ${i + 1} من سورة ${surah.nameArabic}',
        textEnglish: 'Verse ${i + 1} of Surah ${surah.nameTransliteration}',
      ),
    );
  }
}
