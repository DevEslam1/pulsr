// lib/core/utils/song_classification.dart
import '../../data/db/app_database.dart';
import '../../domain/models/radio_station.dart';
import '../services/radio_station_store.dart';
import 'search_algorithm_utils.dart';

/// Single source of truth for splitting favorites/downloads into Local vs
/// Online buckets. Previously the Library favorites tab and the standalone
/// `/favorites` screen each had their own (diverging) predicate.

/// True when a favorite belongs in the "Online" bucket: a streaming YouTube
/// row with no local file on disk. A downloaded YouTube track (real local
/// path or `content:` URI) stays Local because it plays offline.
bool isOnlineFavorite(SongsTableData s) {
  if (s.source == SongSource.youtube) {
    final hasLocalFile = s.path.isNotEmpty &&
        !s.path.startsWith('ytmusic://') &&
        (s.path.startsWith('content:') || s.isDownloaded == true);
    return !hasLocalFile;
  }
  return s.remoteId != null && s.remoteId!.isNotEmpty;
}

/// True when a local song originated from an online download (used by the
/// Library "Downloaded" tab). Streaming `ytmusic://` sentinels are excluded.
bool isDownloadedOnlineTrack(SongsTableData s) {
  if (s.path.isEmpty || s.path.startsWith('ytmusic://')) return false;
  if (s.isDownloaded == true) return true;
  return s.source == SongSource.local &&
      s.remoteId != null &&
      s.remoteId!.isNotEmpty;
}

/// Checks whether [song] is a Holy Quran recitation, recitation sheikh,
/// or Quran radio broadcast.
bool isQuranTrack(SongsTableData? song) {
  if (song == null) return false;

  // 1. Radio source checks
  if (song.source == SongSource.radio) {
    if (RadioStationStore.isQuranStation(RadioStation(
      id: '',
      name: song.title,
      url: song.path,
      genre: song.artist,
    ))) {
      return true;
    }
  }

  // 2. Artwork heuristics for curated Quran radio stations
  final art = (song.remoteArtworkUrl ?? '').toLowerCase();
  if (art.contains('quran_cairo') ||
      art.contains('hussary') ||
      art.contains('minshawi') ||
      art.contains('abdulbasit') ||
      art.contains('mustafa_ismail') ||
      art.contains('quran_tarteel')) {
    return true;
  }

  // 3. Genre check
  final genre = (song.genre ?? '').toLowerCase();
  if (genre == 'quran' || genre.contains('قران') || genre.contains('قرآن')) {
    return true;
  }

  // 4. Normalized metadata keyword matching
  final metadataText = '${song.title} ${song.artist} ${song.album}'.trim();
  final rawText = metadataText.isNotEmpty ? metadataText : song.path;
  final norm = SearchAlgorithmUtils.normalize(rawText);

  const keywords = [
    'قران',
    'تلاوه',
    'تلاوات',
    'مصحف',
    'تجويد',
    'ترتيل',
    'تراتيل',
    'سوره',
    'quran',
    'koran',
    'surah',
    'tilawat',
    'recitation',
    // Reciters
    'المنشاوي',
    'منشاوي',
    'minshawi',
    'عبد الباسط',
    'عبدالباسط',
    'عبد الصمد',
    'عبدالصمد',
    'abdulbasit',
    'abdelbasset',
    'الحصري',
    'حصري',
    'hussary',
    'hossary',
    'مصطفي اسماعيل',
    'مصطفى اسماعيل',
    'mustafa ismail',
    'mostafa ismail',
    'البنا',
    'الطبلاوي',
    'طبلاوي',
    'الشحات',
    'محمد رفعت',
    'المعيقلي',
    'معيقلي',
    'muaiqly',
    'العفاسي',
    'عفاسي',
    'alafasy',
    'mishary',
    'الغامدي',
    'ghamdi',
    'الدوسري',
    'dossari',
    'القطامي',
    'qatami',
    'الشاطري',
    'shatri',
    'علي جابر',
    'محمد جبريل',
    'ادريس ابكر',
    'هزاع البلوشي',
    'فارس عباد',
    'العجمي',
    'ajmi',
    'الشريم',
    'shuraim',
    'السديس',
    'سديس',
    'sudais',
    'بندر بليله',
    'خالد الجليل',
    'وديع اليمني',
    'اسلام صبحي',
    'رعد الكردي',
  ];

  for (final kw in keywords) {
    if (norm.contains(kw)) {
      return true;
    }
  }

  return false;
}

