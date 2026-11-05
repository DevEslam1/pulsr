// InnerTube search parsing and locale plumbing, extracted from YtmService so the
// service file keeps shrinking (ratchet 01-4). Part of the same library, so the
// private names and every existing call site stay valid.
part of 'ytm_service.dart';

/// Descriptor for one client in the pure-Dart (desktop / native-fallback)
/// InnerTube player chain.
typedef _DartPlayerClient = ({
  String name,
  String version,
  String clientNameId,
  String ua,
  String host,
});

Map<String, String> _localeArgs() {
  final locale = ui.PlatformDispatcher.instance.locale;
  final country = locale.countryCode;
  final lang = locale.languageCode;
  return {
    if (country != null && country.isNotEmpty) 'country': country,
    if (lang.isNotEmpty) 'lang': lang,
  };
}

List<YtmTrack> _parseTracks(List<Object?>? raw) {
  if (raw == null) return const [];
  final tracks = <YtmTrack>[];
  for (final entry in raw) {
    if (entry is! Map) continue;
    final track = YtmTrack.fromChannel(entry);
    if (track != null) tracks.add(track);
  }
  return tracks;
}

void _collectSearchTracks(dynamic node, List<YtmTrack> tracks) {
  if (node is Map<String, dynamic>) {
    if (node.containsKey('musicResponsiveListItemRenderer')) {
      try {
        final r =
            node['musicResponsiveListItemRenderer'] as Map<String, dynamic>;
        final flexCols = r['flexColumns'] as List<dynamic>? ?? [];
        String? videoId;
        String title = L10nHolder.current?.ytmUnknownTitle ?? 'Unknown Title';
        String artist = L10nHolder.current?.unknownArtist ?? 'Unknown Artist';

        final pData = r['playlistItemData'] as Map<String, dynamic>?;
        videoId = pData?['videoId'] as String?;

        if (flexCols.isNotEmpty) {
          final c0 = flexCols[0]['musicResponsiveListItemFlexColumnRenderer']
              ?['text']?['runs'] as List<dynamic>?;
          if (c0 != null && c0.isNotEmpty) {
            title = c0[0]['text'] as String? ?? title;
            final nav = c0[0]['navigationEndpoint'] as Map<String, dynamic>?;
            videoId ??= nav?['watchEndpoint']?['videoId'] as String?;
          }
        }
        if (flexCols.length > 1) {
          final c1 = flexCols[1]['musicResponsiveListItemFlexColumnRenderer']
              ?['text']?['runs'] as List<dynamic>?;
          final parsedArtist = YtmMediaHelpers.firstArtistRun(c1);
          if (parsedArtist != null) artist = parsedArtist;
        }

        if (videoId != null && videoId.length == 11) {
          tracks.add(YtmTrack(
            videoId: videoId,
            title: title,
            artist: artist,
            duration: Duration.zero,
            artworkUrl: YtmMediaHelpers.innertubeArtwork(r),
          ));
        }
        return;
      } catch (_) {
        // One malformed renderer must not discard the whole page.
        return;
      }
    }
    if (node.containsKey('musicTwoRowItemRenderer')) {
      try {
        final r = node['musicTwoRowItemRenderer'] as Map<String, dynamic>;
        final nav = r['navigationEndpoint'] as Map<String, dynamic>?;
        String? videoId = nav?['watchEndpoint']?['videoId'] as String?;
        final titleObj = r['title'] as Map<String, dynamic>?;
        final titleRuns = titleObj?['runs'] as List<dynamic>?;
        String title = L10nHolder.current?.ytmUnknownTitle ?? 'Unknown Title';
        if (titleRuns != null && titleRuns.isNotEmpty) {
          title = titleRuns[0]['text'] as String? ?? title;
          videoId ??= (titleRuns[0]['navigationEndpoint']
                  as Map<String, dynamic>?)?['watchEndpoint']?['videoId']
              as String?;
        }
        final subObj = r['subtitle'] as Map<String, dynamic>?;
        final subRuns = subObj?['runs'] as List<dynamic>?;
        final parsedArtist = YtmMediaHelpers.firstArtistRun(subRuns);
        final artist = parsedArtist ?? 'Unknown Artist';
        if (videoId != null && videoId.length == 11) {
          tracks.add(YtmTrack(
            videoId: videoId,
            title: title,
            artist: artist,
            duration: Duration.zero,
            artworkUrl: YtmMediaHelpers.innertubeArtwork(r),
          ));
        }
        return;
      } catch (_) {
        return;
      }
    }
    for (final val in node.values) {
      _collectSearchTracks(val, tracks);
    }
  } else if (node is List) {
    for (final item in node) {
      _collectSearchTracks(item, tracks);
    }
  }
}
