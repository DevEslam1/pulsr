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

/// Inserts or refreshes [key] -> [value] in [map] and evicts the oldest
/// entries once [map] exceeds [YtmService._maxVideoFailureKeys] (FIFO/LRU
/// bound from the hardening pass).
void _capMap<V>(Map<String, V> map, String key, V value) {
  map.remove(key);
  map[key] = value;
  while (map.length > YtmService._maxVideoFailureKeys) {
    map.remove(map.keys.first);
  }
}

extension _YtmServiceGuard on YtmService {
  Future<T?> _guard<T>(
    Future<T?> Function() call, {
    required Duration timeout,
    int maxRetries = 1,
  }) async {
    for (var attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        final adaptiveTimeout = timeout + Duration(seconds: attempt * 5);
        return await call().timeout(adaptiveTimeout);
      } on TimeoutException {
        if (attempt == maxRetries) {
          throw const YtmException('YTM_TIMEOUT', 'Request timed out');
        }
        // Back off before a retry: a tight loop hammers a struggling route.
        await Future.delayed(Duration(milliseconds: 800 * (1 << attempt)));
      } on MissingPluginException {
        throw const YtmException('YTM_UNSUPPORTED');
      } on SocketException catch (e) {
        // Offline/DNS failure — retry with backoff like YTM_TIMEOUT, surface offline
        if (attempt == maxRetries) {
          ErrorLogger.log('YTM network failure (offline): $e', category: 'YTM');
          throw YtmException('YTM_OFFLINE', 'No internet: ${e.message}');
        }
        await Future.delayed(Duration(milliseconds: 800 * (1 << attempt)));
      } on PlatformException catch (e) {
        // The native side packages `{signal, traceId}` in `details` for every
        // InnertubeException. Both used to be dropped on the floor, so a
        // structured verdict degraded into a substring guess at the message and
        // the trace id never reached the log line that was meant to carry it.
        final detailsMap = e.details is Map ? e.details as Map : null;
        final signalCode = detailsMap?['signal'] as String?;
        final traceId = detailsMap?['traceId'] as String?;
        // Prefer whichever of the two the Dart enum actually recognises: the
        // plugin sets code = signal.code for Innertube failures, but a wrapper
        // higher up can replace the code with a generic one.
        final resolvedCode = YtmBlockSignal.fromCode(e.code) != null
            ? e.code
            : (signalCode ?? e.code);

        final codeUpper = resolvedCode.toUpperCase();
        // Feed 429s into the shared Dart limiter so search/resolve/download
        // all cool down together instead of each retrying against the same IP.
        if (codeUpper.contains('429') ||
            codeUpper.contains('RATE_LIMIT') ||
            (e.message?.toUpperCase().contains('429') ?? false)) {
          YtmRateLimiter.shared.onRateLimited();
        }
        // A full native chain already tried every client: blindly replaying
        // the whole chain 2x more triples thread-pool load and turns one
        // IP-flag into cascading timeouts. Fail fast to the next engine.
        final failure = YtmException(resolvedCode, e.message, traceId);
        final isFatalCode = failure.isTerminalResolveFailure;

        if (attempt == maxRetries || isFatalCode) {
          ErrorLogger.log(
              'YTM call failed: ${failure.code}'
              '${traceId == null ? '' : ' [trace=$traceId]'} ${e.message}',
              category: 'YTM');
          // Only an unambiguous auth verdict pings the UI: SIGN_IN_REQUIRED is
          // also what a private or members-only track returns, and prompting a
          // re-login for one of those trains the user to ignore the prompt.
          if (resolvedCode == 'LOGIN_REQUIRED' || resolvedCode == 'YTM_AUTH') {
            notifyAuthExpired();
          }
          throw failure;
        }
        await Future.delayed(Duration(milliseconds: 500 * (1 << attempt)));
      }
    }
    throw const YtmException('YTM_FAILED', 'Max retries exhausted');
  }
}
