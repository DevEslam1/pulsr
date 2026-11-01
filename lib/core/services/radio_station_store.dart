// lib/core/services/radio_station_store.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:mutex/mutex.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../domain/models/radio_station.dart';
import '../utils/error_logger.dart';

/// Persists the user's internet radio stations as a JSON list in [SharedPreferences].
///
/// **Design Note:**
/// This class uses an intentional in-memory static store (`_stations`) across all
/// direct-constructed instances within the isolate session (e.g. between the radio
/// browsing screens and player queue mixins) to guarantee instantaneous UI consistency
/// without incurring cross-widget synchronization latency or DI graph churn.
///
/// For test isolation, use [resetForTesting] in `setUp`/`tearDown`.
class RadioStationStore {
  static const String prefsKey = 'radio_stations_v1';
  static const int maxEntries = 500;

  static const String quranCairoArtwork = 'assets/Pictures/quran_cairo.jpg';
  static const String minshawiArtwork = 'assets/Pictures/minshawi.jpg';
  static const String mustafaIsmailArtwork =
      'assets/Pictures/mustafa_ismail.jpg';
  static const String abdulBasitArtwork = 'assets/Pictures/abdulbasit.jpg';
  static const String hussaryArtwork = 'assets/Pictures/hussary.jpg';
  static const String tarteelArtwork = 'assets/Pictures/quran_tarteel.jpg';
  static const String lofiArtwork = 'assets/Pictures/radio_lofi.jpg';
  static const String ambientArtwork = 'assets/Pictures/radio_ambient.jpg';
  static const String paradiseArtwork = 'assets/Pictures/radio_paradise.jpg';
  static const String classicArtwork = 'assets/Pictures/radio_classic.jpg';
  static const String jazzArtwork = 'assets/Pictures/radio_jazz.jpg';
  static const String electroArtwork = 'assets/Pictures/radio_electro.jpg';
  static const String rockArtwork = 'assets/Pictures/radio_rock.jpg';
  static const String indieArtwork = 'assets/Pictures/radio_indie.jpg';
  static const String newsArtwork = 'assets/Pictures/radio_news.jpg';

  static const Map<String, String> _curatedArtwork = {
    'cur-quran-cairo': quranCairoArtwork,
    'cur-quran-cairo-backup': quranCairoArtwork,
    'cur-quran-hussary': hussaryArtwork,
    'cur-quran-hussary-mojawwad': hussaryArtwork,
    'cur-quran-minshawi': minshawiArtwork,
    'cur-quran-minshawi-rare': minshawiArtwork,
    'cur-quran-minshawi-murattal': minshawiArtwork,
    'cur-quran-mustafa': mustafaIsmailArtwork,
    'cur-quran-abdulbasit': abdulBasitArtwork,
    'cur-quran-abdulbasit-murattal': abdulBasitArtwork,
    'cur-quran-tarteel': tarteelArtwork,
    'cur-quran-khashia': tarteelArtwork,
    'cur-quran-sakeenah': tarteelArtwork,
    'cur-quran-banna-mojawwad': quranCairoArtwork,
    'cur-quran-banna-murattal': quranCairoArtwork,
    'cur-quran-tablaway': quranCairoArtwork,
    'cur-quran-makkah': quranCairoArtwork,
    'cur-quran-alafasi': tarteelArtwork,
    'cur-quran-muaiqly': tarteelArtwork,
    'cur-quran-dosari': tarteelArtwork,
    'cur-quran-qatami': tarteelArtwork,
    'cur-quran-sudaes': tarteelArtwork,
    'cur-quran-shuraim': tarteelArtwork,
    'cur-quran-ali-jaber': tarteelArtwork,
    'cur-quran-idrees-abkr': tarteelArtwork,
    'cur-quran-fares-abbad': tarteelArtwork,
    'cur-quran-ghamdi': tarteelArtwork,
    'cur-quran-shatri': tarteelArtwork,
    'cur-quran-ajmy': tarteelArtwork,
    'cur-quran-jileel': tarteelArtwork,
    'cur-quran-nourin': tarteelArtwork,
    'cur-lofi': lofiArtwork,
    'cur-ambient': ambientArtwork,
    'cur-paradise': paradiseArtwork,
    'cur-classic': classicArtwork,
    'cur-jazz': jazzArtwork,
    'cur-electro': electroArtwork,
    'cur-rock': rockArtwork,
    'cur-indie': indieArtwork,
    'cur-news': newsArtwork,
  };

  static const Map<String, ({String ar, String en})> _localizedStationNames = {
    'cur-quran-minshawi': (
      ar: 'إذاعة الشيخ محمد صديق المنشاوي (مجود)',
      en: 'Sheikh Mohamed Siddiq El-Minshawi (Mujawwad)',
    ),
    'cur-quran-khashia': (
      ar: 'إذاعة تلاوات خاشعة نادرة',
      en: 'Rare Khashia Recitations Radio',
    ),
    'cur-quran-minshawi-rare': (
      ar: 'إذاعة الشيخ محمد صديق المنشاوي (تلاوات نادرة)',
      en: 'Sheikh Mohamed Siddiq El-Minshawi (Rare Recitations)',
    ),
    'cur-quran-cairo': (
      ar: 'إذاعة القرآن الكريم المصرية - القاهرة',
      en: 'Holy Quran Radio - Cairo',
    ),
    'cur-quran-cairo-backup': (
      ar: 'إذاعة القرآن الكريم - القاهرة (بث بديل)',
      en: 'Holy Quran Radio - Cairo (Backup)',
    ),
    'cur-quran-abdulbasit': (
      ar: 'إذاعة الشيخ عبد الباسط عبد الصمد (مجود)',
      en: 'Sheikh Abdulbasit Abdulsamad (Mujawwad)',
    ),
    'cur-quran-hussary': (
      ar: 'إذاعة الشيخ محمود خليل الحصري (مرتل)',
      en: 'Sheikh Mahmoud Khalil Al-Hussary (Murattal)',
    ),
    'cur-quran-mustafa': (
      ar: 'إذاعة الشيخ مصطفى إسماعيل (مجود)',
      en: 'Sheikh Mustafa Ismail (Mujawwad)',
    ),
    'cur-quran-tarteel': (
      ar: 'إذاعة تراتيل قصيرة متميزة',
      en: 'Distinguished Short Recitations Radio',
    ),
    'cur-quran-minshawi-murattal': (
      ar: 'إذاعة الشيخ محمد صديق المنشاوي (مرتل)',
      en: 'Sheikh Mohamed Siddiq El-Minshawi (Murattal)',
    ),
    'cur-quran-abdulbasit-murattal': (
      ar: 'إذاعة الشيخ عبد الباسط عبد الصمد (مرتل)',
      en: 'Sheikh Abdulbasit Abdulsamad (Murattal)',
    ),
    'cur-quran-hussary-mojawwad': (
      ar: 'إذاعة الشيخ محمود خليل الحصري (مجود)',
      en: 'Sheikh Mahmoud Khalil Al-Hussary (Mujawwad)',
    ),
    'cur-quran-banna-mojawwad': (
      ar: 'إذاعة الشيخ محمود علي البنا (مجود)',
      en: 'Sheikh Mahmoud Ali Al-Banna (Mujawwad)',
    ),
    'cur-quran-banna-murattal': (
      ar: 'إذاعة الشيخ محمود علي البنا (مرتل)',
      en: 'Sheikh Mahmoud Ali Al-Banna (Murattal)',
    ),
    'cur-quran-tablaway': (
      ar: 'إذاعة الشيخ محمد محمود الطبلاوي',
      en: 'Sheikh Mohammad Al-Tablaway Radio',
    ),
    'cur-quran-sakeenah': (
      ar: 'إذاعة آيات السكينة وتلاوات خاشعة',
      en: 'Verses of Serenity & Tranquility Radio',
    ),
    'cur-quran-makkah': (
      ar: 'إذاعة القرآن الكريم - مكة المكرمة (السعودية)',
      en: 'Holy Quran Radio - Mecca Live Stream',
    ),
    'cur-quran-alafasi': (
      ar: 'إذاعة الشيخ مشاري العفاسي',
      en: 'Sheikh Mishary Alafasi Radio',
    ),
    'cur-quran-muaiqly': (
      ar: 'إذاعة الشيخ ماهر المعيقلي',
      en: 'Sheikh Maher Al-Muaiqly Radio',
    ),
    'cur-quran-dosari': (
      ar: 'إذاعة الشيخ ياسر الدوسري',
      en: 'Sheikh Yasser Al-Dosari Radio',
    ),
    'cur-quran-qatami': (
      ar: 'إذاعة الشيخ ناصر القطامي',
      en: 'Sheikh Nasser Al-Qatami Radio',
    ),
    'cur-quran-sudaes': (
      ar: 'إذاعة الشيخ عبد الرحمن السديس',
      en: 'Sheikh Abdulrahman Al-Sudais Radio',
    ),
    'cur-quran-shuraim': (
      ar: 'إذاعة الشيخ سعود الشريم',
      en: 'Sheikh Saud Al-Shuraim Radio',
    ),
    'cur-quran-ali-jaber': (
      ar: 'إذاعة الشيخ علي جابر',
      en: 'Sheikh Ali Jaber Radio',
    ),
    'cur-quran-idrees-abkr': (
      ar: 'إذاعة الشيخ إدريس أبكر',
      en: 'Sheikh Idrees Abkar Radio',
    ),
    'cur-quran-fares-abbad': (
      ar: 'إذاعة الشيخ فارس عباد',
      en: 'Sheikh Fares Abbad Radio',
    ),
    'cur-quran-ghamdi': (
      ar: 'إذاعة الشيخ سعد الغامدي',
      en: 'Sheikh Saad Al-Ghamdi Radio',
    ),
    'cur-quran-shatri': (
      ar: 'إذاعة الشيخ أبو بكر الشاطري',
      en: 'Sheikh Abu Bakr Al-Shatri Radio',
    ),
    'cur-quran-ajmy': (
      ar: 'إذاعة الشيخ أحمد بن علي العجمي',
      en: 'Sheikh Ahmed Al-Ajmy Radio',
    ),
    'cur-quran-jileel': (
      ar: 'إذاعة الشيخ خالد الجليل',
      en: 'Sheikh Khalid Al-Jaleel Radio',
    ),
    'cur-quran-nourin': (
      ar: 'إذاعة الشيخ نورين محمد صديق',
      en: 'Sheikh Nourin Mohamed Siddig Radio',
    ),
    'cur-lofi': (
      ar: 'سوما إف إم - سالاد لوفاي هادئ',
      en: 'SomaFM Groove Salad (Lofi Chill)',
    ),
    'cur-ambient': (
      ar: 'سوما إف إم - دروون زون (أمبينت)',
      en: 'SomaFM Drone Zone (Ambient)',
    ),
    'cur-paradise': (
      ar: 'راديو بارادايس (الميكس الرئيسي)',
      en: 'Radio Paradise (Main Mix)',
    ),
    'cur-classic': (
      ar: 'الموسيقى الكلاسيكية والفلكلور',
      en: 'The Thistle & Shamrock (Classical Folk)',
    ),
    'cur-jazz': (
      ar: 'سوما إف إم - سونيك يونيفرس (جاز)',
      en: 'SomaFM Sonic Universe (Jazz)',
    ),
    'cur-electro': (
      ar: 'سوما إف إم - ديف كون (إلكتروني)',
      en: 'SomaFM DEF CON (Electronic)',
    ),
    'cur-rock': (
      ar: 'سوما إف إم - روك السبعينيات الكلاسيكي',
      en: 'SomaFM Left Coast 70s (Classic Rock)',
    ),
    'cur-indie': (
      ar: 'سوما إف إم - إندي بوب روكس',
      en: 'SomaFM Indie Pop Rocks',
    ),
    'cur-news': (
      ar: 'بي بي سي الإخبارية العالمية',
      en: 'BBC World Service News',
    ),
  };

  /// Resolves the localized display name for a curated station according to the
  /// given language code ('ar', 'en', etc.). For custom stations or unmapped IDs,
  /// returns [station.name].
  static String localizedStationName(RadioStation station, String languageCode) {
    final entry = _localizedStationNames[station.id];
    if (entry != null) {
      return languageCode == 'ar' ? entry.ar : entry.en;
    }
    return station.name;
  }

  /// Resolves matching curated Sheikh/station artwork from assets by ID, URL, or name keywords.
  static String? resolveArtworkForStation({
    String? id,
    String? name,
    String? url,
  }) {
    final lowerId = id?.toLowerCase().trim() ?? '';
    final lowerUrl = url?.toLowerCase().trim() ?? '';
    final lowerName = name?.toLowerCase().trim() ?? '';

    // Cairo Quran Radio & Makkah
    if (lowerId == 'cur-quran-cairo' ||
        lowerId == 'cur-quran-cairo-backup' ||
        lowerId == 'cur-quran-makkah' ||
        lowerUrl.contains('8s5u') ||
        lowerUrl.contains('quran-cairo') ||
        lowerName.contains('القاهرة') ||
        lowerName.contains('القرآن الكريم') ||
        lowerName.contains('القران الكريم')) {
      return quranCairoArtwork;
    }

    // Hussary
    if (lowerId == 'cur-quran-hussary' ||
        lowerId == 'cur-quran-hussary-mojawwad' ||
        lowerUrl.contains('hussary') ||
        lowerUrl.contains('alhussary') ||
        lowerName.contains('الحصري') ||
        lowerName.contains('حصري') ||
        lowerName.contains('hussary')) {
      return hussaryArtwork;
    }

    // Minshawi
    if (lowerId == 'cur-quran-minshawi' ||
        lowerId == 'cur-quran-minshawi-murattal' ||
        lowerUrl.contains('minshawi') ||
        lowerName.contains('منشاوي') ||
        lowerName.contains('المنشاوي') ||
        lowerName.contains('minshawi')) {
      return minshawiArtwork;
    }

    // Abdulbasit
    if (lowerId == 'cur-quran-abdulbasit' ||
        lowerId == 'cur-quran-abdulbasit-murattal' ||
        lowerUrl.contains('abdulbasit') ||
        lowerUrl.contains('abdulsamad') ||
        lowerName.contains('عبد الباسط') ||
        lowerName.contains('عبدالباسط') ||
        lowerName.contains('عبد الصمد') ||
        lowerName.contains('عبدالصمد') ||
        lowerName.contains('abdulbasit')) {
      return abdulBasitArtwork;
    }

    // Mustafa Ismail
    if (lowerId == 'cur-quran-mustafa' ||
        lowerUrl.contains('mustafa_ismail') ||
        lowerName.contains('مصطفى إسماعيل') ||
        lowerName.contains('مصطفي اسماعيل') ||
        lowerName.contains('مسطفي اسماعيل') ||
        lowerName.contains('مصطفى اسماعيل') ||
        lowerName.contains('mustafa')) {
      return mustafaIsmailArtwork;
    }

    // Quran Tarateel & Khashia / Sakeenah & Other Reciters fallback
    if (lowerId == 'cur-quran-tarteel' ||
        lowerId == 'cur-quran-khashia' ||
        lowerId == 'cur-quran-sakeenah' ||
        lowerUrl.contains('tarteel') ||
        lowerUrl.contains('tarateel') ||
        lowerUrl.contains('salma') ||
        lowerUrl.contains('sakeenah') ||
        lowerName.contains('تراتيل') ||
        lowerName.contains('خاشع') ||
        lowerName.contains('سكينة')) {
      return tarteelArtwork;
    }

    // Any other Quran station fallback to quranCairoArtwork or tarteelArtwork
    if (lowerId.startsWith('cur-quran') ||
        lowerUrl.contains('qurango.net') ||
        lowerName.contains('القرآن') ||
        lowerName.contains('القران')) {
      return tarteelArtwork;
    }

    // Lofi
    if (lowerId == 'cur-lofi' ||
        lowerUrl.contains('groovesalad') ||
        lowerName.contains('lofi') ||
        lowerName.contains('lo-fi')) {
      return lofiArtwork;
    }

    // Ambient / Drone Zone
    if (lowerId == 'cur-ambient' ||
        lowerUrl.contains('dronezone') ||
        lowerName.contains('ambient') ||
        lowerName.contains('drone zone')) {
      return ambientArtwork;
    }

    // Radio Paradise
    if (lowerId == 'cur-paradise' ||
        lowerUrl.contains('radioparadise') ||
        lowerName.contains('paradise')) {
      return paradiseArtwork;
    }

    // Classical Folk
    if (lowerId == 'cur-classic' ||
        lowerUrl.contains('thistle') ||
        lowerName.contains('classic') ||
        lowerName.contains('folk')) {
      return classicArtwork;
    }

    // Smooth Jazz
    if (lowerId == 'cur-jazz' ||
        lowerUrl.contains('sonicuniverse') ||
        lowerName.contains('jazz')) {
      return jazzArtwork;
    }

    // Electronic / DEF CON
    if (lowerId == 'cur-electro' ||
        lowerUrl.contains('defcon') ||
        lowerName.contains('electronic') ||
        lowerName.contains('def con')) {
      return electroArtwork;
    }

    // Classic Rock 70s
    if (lowerId == 'cur-rock' ||
        lowerUrl.contains('seventies') ||
        lowerName.contains('rock') ||
        lowerName.contains('70s')) {
      return rockArtwork;
    }

    // Indie Pop Rocks
    if (lowerId == 'cur-indie' ||
        lowerUrl.contains('indiepop') ||
        lowerName.contains('indie')) {
      return indieArtwork;
    }

    // BBC News
    if (lowerId == 'cur-news' ||
        lowerUrl.contains('bbc') ||
        lowerName.contains('bbc') ||
        lowerName.contains('news')) {
      return newsArtwork;
    }

    if (id != null && _curatedArtwork.containsKey(id)) {
      return _curatedArtwork[id];
    }

    return null;
  }

  /// Checks whether a station is a Quran or recitation station.
  static bool isQuranStation(RadioStation station) {
    final genre = (station.genre ?? '').toLowerCase().trim();
    if (genre == 'quran' || genre.contains('قرآن') || genre.contains('قران')) {
      return true;
    }
    final id = station.id.toLowerCase();
    if (id.startsWith('cur-quran')) return true;
    final name = station.name.toLowerCase();
    if (name.contains('قرآن') ||
        name.contains('قران') ||
        name.contains('quran') ||
        name.contains('المنشاوي') ||
        name.contains('منشاوي') ||
        name.contains('عبد الباسط') ||
        name.contains('عبدالباسط') ||
        name.contains('الحصري') ||
        name.contains('حصري') ||
        name.contains('مصطفى إسماعيل') ||
        name.contains('البنا') ||
        name.contains('الطبلاوي') ||
        name.contains('خاشع') ||
        name.contains('سكينة') ||
        name.contains('العفاسي') ||
        name.contains('المعيقلي') ||
        name.contains('الدوسري') ||
        name.contains('القطامي') ||
        name.contains('السديس') ||
        name.contains('الشريم') ||
        name.contains('علي جابر') ||
        name.contains('إدريس أبكر') ||
        name.contains('فارس عباد') ||
        name.contains('الغامدي') ||
        name.contains('الشاطري') ||
        name.contains('العجمي') ||
        name.contains('خالد الجليل') ||
        name.contains('نورين') ||
        name.contains('تراتيل')) {
      return true;
    }
    final url = station.url.toLowerCase();
    if (url.contains('qurango.net') || url.contains('quran')) {
      return true;
    }
    return false;
  }

  /// Partitions and sorts stations so that Quran stations are ALWAYS displayed first.
  static List<RadioStation> sortWithQuranFirst(
      Iterable<RadioStation> stations) {
    final quran = <RadioStation>[];
    final others = <RadioStation>[];
    for (final s in stations) {
      if (isQuranStation(s)) {
        quran.add(s);
      } else {
        others.add(s);
      }
    }
    const curatedOrder = [
      'cur-quran-cairo',
      'cur-quran-cairo-backup',
      'cur-quran-hussary',
      'cur-quran-minshawi',
      'cur-quran-minshawi-rare',
      'cur-quran-abdulbasit',
      'cur-quran-mustafa',
      'cur-quran-tarteel',
      'cur-quran-khashia',
      'cur-quran-minshawi-murattal',
      'cur-quran-abdulbasit-murattal',
      'cur-quran-hussary-mojawwad',
      'cur-quran-banna-mojawwad',
      'cur-quran-banna-murattal',
      'cur-quran-tablaway',
      'cur-quran-sakeenah',
      'cur-quran-makkah',
      'cur-quran-alafasi',
      'cur-quran-muaiqly',
      'cur-quran-dosari',
      'cur-quran-qatami',
      'cur-quran-sudaes',
      'cur-quran-shuraim',
      'cur-quran-ali-jaber',
      'cur-quran-idrees-abkr',
      'cur-quran-fares-abbad',
      'cur-quran-ghamdi',
      'cur-quran-shatri',
      'cur-quran-ajmy',
      'cur-quran-jileel',
      'cur-quran-nourin',
    ];
    quran.sort((a, b) {
      final idxA = curatedOrder.indexOf(a.id);
      final idxB = curatedOrder.indexOf(b.id);
      if (idxA != -1 && idxB != -1) return idxA.compareTo(idxB);
      if (idxA != -1) return -1;
      if (idxB != -1) return 1;
      return 0;
    });
    return [...quran, ...others];
  }

  static final List<RadioStation> _stations = [];

  /// Single-writer guard for the process-static station list.
  ///
  /// Every mutation is a read-modify-write over [_stations] followed by a
  /// persist pass. Without serialisation two concurrent adds could each compute
  /// their list from the same snapshot and the later persist would drop the
  /// earlier station. The constructor's initial [load] takes the same lock, so
  /// a mutation queued before the disk read finishes can never be erased by it.
  final Mutex _writeMutex = Mutex();

  late final Future<void> ready;
  bool _loadFailed = false;
  bool get loadFailed => _loadFailed;

  @visibleForTesting
  static void resetForTesting() {
    _stations.clear();
  }

  RadioStationStore() {
    ready = load();
  }

  /// Stations in display order: Quran stations ALWAYS first, then other stations.
  List<RadioStation> get list =>
      List.unmodifiable(sortWithQuranFirst(_stations));

  Future<void> add(RadioStation station) async {
    if (!RadioStation.isHttpUrl(station.url)) return;
    await ready;
    await _writeMutex.protect(() async {
      final effectiveStation =
          (station.artworkUrl == null || station.artworkUrl!.isEmpty)
              ? station.copyWith(
                  artworkUrl: resolveArtworkForStation(
                    id: station.id,
                    name: station.name,
                    url: station.url,
                  ),
                )
              : station;
      _stations.removeWhere(
          (s) => s.id == effectiveStation.id || s.url == effectiveStation.url);
      _stations.insert(0, effectiveStation);
      final sorted = sortWithQuranFirst(_stations);
      _stations
        ..clear()
        ..addAll(sorted);
      if (_stations.length > maxEntries) {
        _stations.removeRange(maxEntries, _stations.length);
      }
      await _persistLocked();
    });
  }

  /// True when a station other than [exceptId] already uses [url]. Callers use
  /// this to refuse an edit that would silently delete another station.
  bool hasUrlCollision(String url, {String? exceptId}) {
    final normalized = url.trim();
    return _stations.any((s) => s.id != exceptId && s.url == normalized);
  }

  /// Atomically replaces [previous] with [updated] in a single persist pass,
  /// so a rejected update can never leave the list missing the old entry.
  /// Returns false (touching nothing) when [updated] is not a valid URL.
  Future<bool> replace(RadioStation previous, RadioStation updated) async {
    if (!RadioStation.isHttpUrl(updated.url)) return false;
    await ready;
    return _writeMutex.protect(() async {
      final effectiveUpdated =
          (updated.artworkUrl == null || updated.artworkUrl!.isEmpty)
              ? updated.copyWith(
                  artworkUrl: resolveArtworkForStation(
                    id: updated.id,
                    name: updated.name,
                    url: updated.url,
                  ),
                )
              : updated;
      _stations.removeWhere((s) => s.id == previous.id);
      _stations.removeWhere(
          (s) => s.id == effectiveUpdated.id || s.url == effectiveUpdated.url);
      _stations.insert(0, effectiveUpdated);
      final sorted = sortWithQuranFirst(_stations);
      _stations
        ..clear()
        ..addAll(sorted);
      if (_stations.length > maxEntries) {
        _stations.removeRange(maxEntries, _stations.length);
      }
      await _persistLocked();
      return true;
    });
  }

  /// Adds many stations with a single persist pass. Returns the number of
  /// accepted (valid `http(s)`) stations.
  Future<int> addAll(Iterable<RadioStation> stations) async {
    final valid = stations
        .where((station) => RadioStation.isHttpUrl(station.url))
        .toList(growable: false);
    if (valid.isEmpty) return 0;
    await ready;
    return _writeMutex.protect(() async {
      var accepted = 0;
      for (final station in valid) {
        final effectiveStation =
            (station.artworkUrl == null || station.artworkUrl!.isEmpty)
                ? station.copyWith(
                    artworkUrl: resolveArtworkForStation(
                      id: station.id,
                      name: station.name,
                      url: station.url,
                    ),
                  )
                : station;
        _stations.removeWhere((s) =>
            s.id == effectiveStation.id || s.url == effectiveStation.url);
        _stations.insert(0, effectiveStation);
        accepted++;
      }
      final sorted = sortWithQuranFirst(_stations);
      _stations
        ..clear()
        ..addAll(sorted);
      if (_stations.length > maxEntries) {
        _stations.removeRange(maxEntries, _stations.length);
      }
      if (accepted > 0) await _persistLocked();
      return accepted;
    });
  }

  Future<void> remove(String id) async {
    await ready;
    await _writeMutex.protect(() async {
      final before = _stations.length;
      _stations.removeWhere((s) => s.id == id);
      if (_stations.length != before) await _persistLocked();
    });
  }

  Future<void> markPlayed(String id, int timestampMs) async {
    await ready;
    await _writeMutex.protect(() async {
      final index = _stations.indexWhere((s) => s.id == id);
      if (index == -1) return;
      _stations[index] = _stations[index].copyWith(lastPlayed: timestampMs);
      await _persistLocked();
    });
  }

  Future<void> load() => _writeMutex.protect(_loadFromDisk);

  Future<void> _loadFromDisk() async {
    _loadFailed = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(prefsKey);
      // The station list is process-static, so an empty/missing store must
      // clear it — otherwise stations from a previous session (or a cleared
      // store) leak back into the current one.
      if (raw == null || raw.isEmpty) {
        _stations.clear();
        return;
      }

      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      _stations.clear();
      var migrated = false;
      for (final item in decoded) {
        if (item is! Map) continue;
        var station = RadioStation.fromJson(Map<String, dynamic>.from(item));
        final migratedStation = _migrateLegacyStation(station);
        if (migratedStation != null) {
          station = migratedStation;
          migrated = true;
        }
        if (station.artworkUrl == null || station.artworkUrl!.isEmpty) {
          final autoArt = resolveArtworkForStation(
            id: station.id,
            name: station.name,
            url: station.url,
          );
          if (autoArt != null) {
            station = station.copyWith(artworkUrl: autoArt);
            migrated = true;
          }
        }
        if (station.url.isNotEmpty && RadioStation.isHttpUrl(station.url)) {
          _stations.add(station);
        }
        if (_stations.length >= maxEntries) break;
      }

      final sorted = sortWithQuranFirst(_stations);
      _stations.clear();
      _stations.addAll(sorted);

      if (migrated) {
        await _persistLocked();
      }
    } catch (e, st) {
      _loadFailed = true;
      ErrorLogger.log('Failed to load radio stations',
          error: e, stackTrace: st, category: 'RadioStationStore');
    }
  }

  static RadioStation? _migrateLegacyStation(RadioStation station) {
    var updated = station;
    if (station.id == 'cur-quran-cairo' ||
        station.url == 'https://stream.radiojar.com/8s5u8tpdtwzuv') {
      const updatedUrl = 'https://stream.radiojar.com/8s5u5tpdtwzuv';
      const updatedName = 'إذاعة القرآن الكريم المصرية - القاهرة';
      if (station.url != updatedUrl || station.name != updatedName) {
        updated = updated.copyWith(name: updatedName, url: updatedUrl);
      }
    }
    if (station.id == 'cur-quran-tarteel' ||
        station.url == 'https://stream.qurango.net/radio/tarteel') {
      const updatedUrl = 'https://backup.qurango.net/radio/tarateel';
      const updatedName = 'إذاعة تراتيل القرآن الكريم';
      if (station.url != updatedUrl || station.name != updatedName) {
        updated = updated.copyWith(name: updatedName, url: updatedUrl);
      }
    }
    final artwork = resolveArtworkForStation(
      id: updated.id,
      name: updated.name,
      url: updated.url,
    );
    if (artwork != null &&
        (updated.artworkUrl == null || updated.artworkUrl!.isEmpty)) {
      updated = updated.copyWith(artworkUrl: artwork);
    }
    return identical(updated, station) ? null : updated;
  }

  Future<void> persist() async {
    await ready;
    await _writeMutex.protect(_persistLocked);
  }

  Future<void> _persistLocked() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        prefsKey,
        jsonEncode(_stations.map((s) => s.toJson()).toList()),
      );
    } catch (e, st) {
      ErrorLogger.log('Failed to persist radio stations',
          error: e, stackTrace: st, category: 'RadioStationStore');
    }
  }

  /// Curated starter directory (all public free streams). Imported on demand
  /// via [importCurated] — never auto-added, so user lists stay theirs.
  static List<RadioStation> curatedDirectory() => [
        RadioStation(
            id: 'cur-quran-cairo',
            name: 'إذاعة القرآن الكريم المصرية - القاهرة',
            url: 'https://stream.radiojar.com/8s5u5tpdtwzuv',
            genre: 'Quran',
            artworkUrl: quranCairoArtwork),
        RadioStation(
            id: 'cur-quran-cairo-backup',
            name: 'إذاعة القرآن الكريم - القاهرة (بث بديل)',
            url: 'https://radio.xecod.com/station/quran-cairo',
            genre: 'Quran',
            artworkUrl: quranCairoArtwork),
        RadioStation(
            id: 'cur-quran-hussary',
            name: 'إذاعة الشيخ محمود خليل الحصري (مرتل)',
            url: 'https://backup.qurango.net/radio/mahmoud_khalil_alhussary',
            genre: 'Quran',
            artworkUrl: hussaryArtwork),
        RadioStation(
            id: 'cur-quran-minshawi',
            name: 'إذاعة الشيخ محمد صديق المنشاوي (مجود)',
            url:
                'https://backup.qurango.net/radio/mohammed_siddiq_alminshawi_mojawwad',
            genre: 'Quran',
            artworkUrl: minshawiArtwork),
        RadioStation(
            id: 'cur-quran-minshawi-rare',
            name: 'إذاعة الشيخ محمد صديق المنشاوي (تلاوات نادرة)',
            url: 'https://radio.xecod.com/station/alminshawi',
            genre: 'Quran',
            artworkUrl: minshawiArtwork),
        RadioStation(
            id: 'cur-quran-abdulbasit',
            name: 'إذاعة الشيخ عبد الباسط عبد الصمد (مجود)',
            url:
                'https://backup.qurango.net/radio/abdulbasit_abdulsamad_mojawwad',
            genre: 'Quran',
            artworkUrl: abdulBasitArtwork),
        RadioStation(
            id: 'cur-quran-mustafa',
            name: 'إذاعة الشيخ مصطفى إسماعيل (مجود)',
            url: 'https://backup.qurango.net/radio/mustafa_ismail',
            genre: 'Quran',
            artworkUrl: mustafaIsmailArtwork),
        RadioStation(
            id: 'cur-quran-tarteel',
            name: 'إذاعة تراتيل قصيرة متميزة',
            url: 'https://backup.qurango.net/radio/tarateel',
            genre: 'Quran',
            artworkUrl: tarteelArtwork),
        RadioStation(
            id: 'cur-quran-khashia',
            name: 'إذاعة تلاوات خاشعة نادرة',
            url: 'https://backup.qurango.net/radio/salma',
            genre: 'Quran',
            artworkUrl: tarteelArtwork),
        RadioStation(
            id: 'cur-quran-minshawi-murattal',
            name: 'إذاعة الشيخ محمد صديق المنشاوي (مرتل)',
            url:
                'https://backup.qurango.net/radio/mohammed_siddiq_alminshawi',
            genre: 'Quran',
            artworkUrl: minshawiArtwork),
        RadioStation(
            id: 'cur-quran-abdulbasit-murattal',
            name: 'إذاعة الشيخ عبد الباسط عبد الصمد (مرتل)',
            url:
                'https://backup.qurango.net/radio/abdulbasit_abdulsamad',
            genre: 'Quran',
            artworkUrl: abdulBasitArtwork),
        RadioStation(
            id: 'cur-quran-hussary-mojawwad',
            name: 'إذاعة الشيخ محمود خليل الحصري (مجود)',
            url:
                'https://backup.qurango.net/radio/mahmoud_khalil_alhussary_mojawwad',
            genre: 'Quran',
            artworkUrl: hussaryArtwork),
        RadioStation(
            id: 'cur-quran-banna-mojawwad',
            name: 'إذاعة الشيخ محمود علي البنا (مجود)',
            url:
                'https://backup.qurango.net/radio/mahmoud_ali__albanna_mojawwad',
            genre: 'Quran',
            artworkUrl: quranCairoArtwork),
        RadioStation(
            id: 'cur-quran-banna-murattal',
            name: 'إذاعة الشيخ محمود علي البنا (مرتل)',
            url:
                'https://backup.qurango.net/radio/mahmoud_ali__albanna',
            genre: 'Quran',
            artworkUrl: quranCairoArtwork),
        RadioStation(
            id: 'cur-quran-tablaway',
            name: 'إذاعة الشيخ محمد محمود الطبلاوي',
            url: 'https://backup.qurango.net/radio/mohammad_altablaway',
            genre: 'Quran',
            artworkUrl: quranCairoArtwork),
        RadioStation(
            id: 'cur-quran-sakeenah',
            name: 'إذاعة آيات السكينة وتلاوات خاشعة',
            url: 'https://backup.qurango.net/radio/sakeenah',
            genre: 'Quran',
            artworkUrl: tarteelArtwork),
        RadioStation(
            id: 'cur-quran-makkah',
            name: 'إذاعة القرآن الكريم - مكة المكرمة (السعودية)',
            url: 'https://stream.radiojar.com/0tpy1h0kxtzuv',
            genre: 'Quran',
            artworkUrl: quranCairoArtwork),
        RadioStation(
            id: 'cur-quran-alafasi',
            name: 'إذاعة الشيخ مشاري العفاسي',
            url: 'https://backup.qurango.net/radio/mishary_alafasi',
            genre: 'Quran',
            artworkUrl: tarteelArtwork),
        RadioStation(
            id: 'cur-quran-muaiqly',
            name: 'إذاعة الشيخ ماهر المعيقلي',
            url: 'https://backup.qurango.net/radio/maher',
            genre: 'Quran',
            artworkUrl: tarteelArtwork),
        RadioStation(
            id: 'cur-quran-dosari',
            name: 'إذاعة الشيخ ياسر الدوسري',
            url: 'https://backup.qurango.net/radio/yasser_aldosari',
            genre: 'Quran',
            artworkUrl: tarteelArtwork),
        RadioStation(
            id: 'cur-quran-qatami',
            name: 'إذاعة الشيخ ناصر القطامي',
            url: 'https://backup.qurango.net/radio/nasser_alqatami',
            genre: 'Quran',
            artworkUrl: tarteelArtwork),
        RadioStation(
            id: 'cur-quran-sudaes',
            name: 'إذاعة الشيخ عبد الرحمن السديس',
            url: 'https://backup.qurango.net/radio/abdulrahman_alsudaes',
            genre: 'Quran',
            artworkUrl: tarteelArtwork),
        RadioStation(
            id: 'cur-quran-shuraim',
            name: 'إذاعة الشيخ سعود الشريم',
            url: 'https://backup.qurango.net/radio/saud_alshuraim',
            genre: 'Quran',
            artworkUrl: tarteelArtwork),
        RadioStation(
            id: 'cur-quran-ali-jaber',
            name: 'إذاعة الشيخ علي جابر',
            url: 'https://backup.qurango.net/radio/ali_jaber',
            genre: 'Quran',
            artworkUrl: tarteelArtwork),
        RadioStation(
            id: 'cur-quran-idrees-abkr',
            name: 'إذاعة الشيخ إدريس أبكر',
            url: 'https://backup.qurango.net/radio/idrees_abkr',
            genre: 'Quran',
            artworkUrl: tarteelArtwork),
        RadioStation(
            id: 'cur-quran-fares-abbad',
            name: 'إذاعة الشيخ فارس عباد',
            url: 'https://backup.qurango.net/radio/fares_abbad',
            genre: 'Quran',
            artworkUrl: tarteelArtwork),
        RadioStation(
            id: 'cur-quran-ghamdi',
            name: 'إذاعة الشيخ سعد الغامدي',
            url: 'https://backup.qurango.net/radio/saad_alghamdi',
            genre: 'Quran',
            artworkUrl: tarteelArtwork),
        RadioStation(
            id: 'cur-quran-shatri',
            name: 'إذاعة الشيخ أبو بكر الشاطري',
            url: 'https://backup.qurango.net/radio/shaik_abu_bakr_al_shatri',
            genre: 'Quran',
            artworkUrl: tarteelArtwork),
        RadioStation(
            id: 'cur-quran-ajmy',
            name: 'إذاعة الشيخ أحمد العجمي',
            url: 'https://backup.qurango.net/radio/ahmad_alajmy',
            genre: 'Quran',
            artworkUrl: tarteelArtwork),
        RadioStation(
            id: 'cur-quran-jileel',
            name: 'إذاعة الشيخ خالد الجليل',
            url: 'https://backup.qurango.net/radio/khalid_aljileel',
            genre: 'Quran',
            artworkUrl: tarteelArtwork),
        RadioStation(
            id: 'cur-quran-nourin',
            name: 'إذاعة الشيخ نورين محمد صديق',
            url: 'https://backup.qurango.net/radio/nourin_siddig',
            genre: 'Quran',
            artworkUrl: tarteelArtwork),
        RadioStation(
            id: 'cur-lofi',
            name: 'Lofi Hip Hop',
            url: 'https://ice1.somafm.com/groovesalad-128-mp3',
            genre: 'Chill',
            artworkUrl: lofiArtwork),
        RadioStation(
            id: 'cur-ambient',
            name: 'Drone Zone (Ambient)',
            url: 'https://ice1.somafm.com/dronezone-128-mp3',
            genre: 'Ambient',
            artworkUrl: ambientArtwork),
        RadioStation(
            id: 'cur-paradise',
            name: 'Radio Paradise (Eclectic HQ)',
            url: 'https://stream.radioparadise.com/mp3-320',
            genre: 'Eclectic',
            artworkUrl: paradiseArtwork),
        RadioStation(
            id: 'cur-classic',
            name: 'Classical Folk',
            url: 'https://ice1.somafm.com/thistle-128-mp3',
            genre: 'Classical',
            artworkUrl: classicArtwork),
        RadioStation(
            id: 'cur-jazz',
            name: 'Smooth Jazz',
            url: 'https://ice1.somafm.com/sonicuniverse-128-mp3',
            genre: 'Jazz',
            artworkUrl: jazzArtwork),
        RadioStation(
            id: 'cur-electro',
            name: 'DEF CON Radio (Electronic)',
            url: 'https://ice1.somafm.com/defcon-128-mp3',
            genre: 'Electronic',
            artworkUrl: electroArtwork),
        RadioStation(
            id: 'cur-rock',
            name: 'Classic Rock 70s',
            url: 'https://ice1.somafm.com/seventies-128-mp3',
            genre: 'Rock',
            artworkUrl: rockArtwork),
        RadioStation(
            id: 'cur-indie',
            name: 'Indie Pop Rocks',
            url: 'https://ice1.somafm.com/indiepop-128-mp3',
            genre: 'Indie',
            artworkUrl: indieArtwork),
        RadioStation(
            id: 'cur-news',
            name: 'BBC World Service',
            url: 'https://stream.live.vc.bbcmedia.co.uk/bbc_world_service',
            genre: 'News',
            artworkUrl: newsArtwork),
      ];

  /// Adds curated stations missing from the user list. Returns added count.
  Future<int> importCurated() async {
    await ready;
    return _writeMutex.protect(() async {
      for (var i = 0; i < _stations.length; i++) {
        final migrated = _migrateLegacyStation(_stations[i]);
        if (migrated != null) {
          _stations[i] = migrated;
        }
      }
      final existingUrls = _stations.map((s) => s.url).toSet();
      final existingIds = _stations.map((s) => s.id).toSet();
      var added = 0;
      for (final s in curatedDirectory()) {
        // Respect the same cap as add()/load so importing onto a near-full
        // user list can't push the store past maxEntries.
        if (_stations.length >= maxEntries) break;
        if (!existingUrls.contains(s.url) && !existingIds.contains(s.id)) {
          _stations.add(s);
          existingUrls.add(s.url);
          existingIds.add(s.id);
          added++;
        }
      }
      final sorted = sortWithQuranFirst(_stations);
      _stations
        ..clear()
        ..addAll(sorted);
      if (added > 0) await _persistLocked();
      return added;
    });
  }

  /// Extracts the absolute `http(s)://` stream URLs from `.m3u` / `.m3u8`  /// playlist content, mirroring the line parser used for local playlists:
  /// blank lines and `#` directives are skipped, quotes are stripped, and
  /// only absolute stream URLs are kept (relative paths are local files).
  static List<String> extractStreamUrls(String content) {
    final urls = <String>[];
    final seen = <String>{};
    for (final line in content.split(RegExp(r'\r?\n'))) {
      var trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
      if (trimmed.length >= 2 &&
          ((trimmed.startsWith('"') && trimmed.endsWith('"')) ||
              (trimmed.startsWith("'") && trimmed.endsWith("'")))) {
        trimmed = trimmed.substring(1, trimmed.length - 1).trim();
      }
      if (!RadioStation.isHttpUrl(trimmed)) continue;
      if (seen.add(trimmed)) urls.add(trimmed);
    }
    return urls;
  }
}
