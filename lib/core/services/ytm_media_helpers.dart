// lib/core/services/ytm_media_helpers.dart
import '../errors/ytm_error_classifier.dart';

/// Pure artwork/playability parsing used by [YtmService].
class YtmMediaHelpers {
  /// Picks the largest thumbnail from an InnerTube `thumbnail` object.
  /// Mirrors the native `extractThumbnailUrl` so the Dart fallback yields the
  /// same artwork as the native extractor.
  static String? extractThumbnailUrl(dynamic thumbnailObj) {
    if (thumbnailObj is! Map) return null;
    final thumbs = thumbnailObj['thumbnails'];
    if (thumbs is! List) return null;
    String? best;
    var maxPixels = -1;
    for (final item in thumbs) {
      if (item is! Map) continue;
      final url = (item['url'] as String?)?.trim();
      if (url == null || url.isEmpty) continue;
      final w = (item['width'] as num?)?.toInt() ?? 0;
      final h = (item['height'] as num?)?.toInt() ?? 0;
      final pixels = w * h;
      if (best == null || pixels > maxPixels) {
        maxPixels = pixels;
        best = url;
      }
    }
    return best;
  }

  /// First run that reads like an artist name rather than a separator,
  /// media-type badge, duration, year, or view count.
  static String? firstArtistRun(List<dynamic>? runs) {
    if (runs == null) return null;
    for (final run in runs) {
      if (run is! Map) continue;
      final text = (run['text'] as String?)?.trim();
      if (text == null || text.isEmpty) continue;
      if (const {'•', '·', '-', '–', '—', '|'}.contains(text)) continue;
      final lower = text.toLowerCase();
      if (const {
        'song',
        'video',
        'single',
        'album',
        'ep',
        'playlist',
        'artist',
        'explicit',
      }.contains(lower)) {
        continue;
      }
      if (lower.endsWith(' views') ||
          lower.endsWith(' plays') ||
          lower.endsWith(' subscribers') ||
          lower.endsWith(' likes')) {
        continue;
      }
      if (RegExp(r'^\d{1,2}:\d{2}(:\d{2})?$').hasMatch(text)) continue;
      if (RegExp(r'^(19|20)\d{2}$').hasMatch(text)) continue;
      return text;
    }
    return null;
  }

  static String? innertubeArtwork(Map<String, dynamic> renderer) {
    final responsive = ((renderer['thumbnail']
        as Map?)?['musicThumbnailRenderer'] as Map?)?['thumbnail'];
    final fromResponsive = extractThumbnailUrl(responsive);
    if (fromResponsive != null) return fromResponsive;
    final twoRow = ((renderer['thumbnailRenderer']
            as Map?)?['musicThumbnailRenderer'] as Map?)?['thumbnail'] ??
        ((renderer['thumbnail'] as Map?)?['musicThumbnailRenderer']
            as Map?)?['thumbnail'];
    return extractThumbnailUrl(twoRow);
  }

  /// Whether [error] means the track itself cannot play (auth/geo/gone), as
  /// opposed to a transient transport or extraction failure.
  static bool isPlayabilityOrRestrictedError(Object error) {
    if (error is YtmException) {
      if (error.isAuth || error.isUnavailable) return true;
      final code = error.code.toUpperCase();
      if (code == 'SIGN_IN_REQUIRED' ||
          code == 'LOGIN_REQUIRED' ||
          code == 'AGE_RESTRICTED' ||
          code == 'VIDEO_GONE' ||
          code == 'CONTENT_GONE' ||
          code == 'YTM_UNAVAILABLE' ||
          code == 'UNPLAYABLE') {
        return true;
      }
    }
    final info = YtmErrorClassifier.classify(error);
    return info.signal == YtmBlockSignal.signInRequired ||
        info.signal == YtmBlockSignal.videoGone ||
        info.signal == YtmBlockSignal.geoBlocked;
  }
}
