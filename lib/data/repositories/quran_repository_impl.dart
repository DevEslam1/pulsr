// lib/data/repositories/quran_repository_impl.dart
import 'dart:convert';
import 'package:injectable/injectable.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/utils/error_logger.dart';
import '../../domain/models/quran_metadata.dart';
import '../../domain/repositories/quran_repository.dart';

@LazySingleton(as: QuranRepository)
class QuranRepositoryImpl implements QuranRepository {
  static const String prefsMetadataKey = 'quran_metadata_catalog_v1';
  static const String prefsBookmarksKey = 'quran_bookmarks_v1';

  final SharedPreferences? _prefsOverride;

  QuranRepositoryImpl([SharedPreferences? prefs]) : _prefsOverride = prefs;

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
}
