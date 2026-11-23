// lib/core/services/ytm_account_service_parsing.dart
//
// Split out of ytm_account_service.dart: the pure InnerTube payload helpers
// (format URL selection, unauthenticated-response detection, continuation
// token traversal). A file split, not a new abstraction boundary — none of
// these touch instance state beyond the debug log.
part of 'ytm_account_service.dart';

extension YtmAccountParsing on YtmAccountService {
  String? _extractUrlFromFormat(Map<String, dynamic> format) {
    final directUrl = format['url'] as String?;
    if (directUrl != null && directUrl.isNotEmpty) return directUrl;

    // Ciphered formats require JS deciphering (signatureCipher `s` + `n` param).
    // Dart has no Rhino engine; returning the raw `url` without `sig=` produces
    // a 403. Let the native `InnertubeClient` / NewPipe tier (which does
    // `JsDecipherCache.decipherSignature`) handle it. Returning null forces the
    // Dart tier to be skipped and the native hedged race to run.
    final cipher = (format['signatureCipher'] ?? format['cipher']) as String?;
    if (cipher != null && cipher.isNotEmpty) {
      debugPrint(
          '[YTM_ACCOUNT] Skipping ciphered format (itag ${format['itag']}) — needs native decipher');
      return null;
    }
    return null;
  }

  bool _isUnauthenticatedResponse(Map<String, dynamic> json) {
    final rc = json['responseContext'];
    if (rc is Map<String, dynamic>) {
      final mainApp = rc['mainAppWebResponseContext'];
      if (mainApp is Map<String, dynamic>) {
        if (mainApp['loggedOut'] == true) return true;
        final datasyncId = mainApp['datasyncId'];
        if (datasyncId is String && datasyncId.isNotEmpty) {
          return false;
        }
      }
    }
    final err = json['error'];
    if (err is Map &&
        (err['code'] == 401 || err['status'] == 'UNAUTHENTICATED')) {
      return true;
    }
    final alerts = json['alerts'];
    if (alerts is List) {
      for (final a in alerts) {
        final alertText = a.toString().toLowerCase();
        if (alertText.contains('sign in') ||
            alertText.contains('login') ||
            alertText.contains('signed out')) {
          return true;
        }
      }
    }
    if (_hasSignInEndpoint(json)) {
      return true;
    }
    if (json.containsKey('contents') ||
        json.containsKey('header') ||
        json.containsKey('continuationContents') ||
        json.containsKey('onResponseReceivedActions') ||
        json.containsKey('frameworkUpdates')) {
      return false;
    }
    return false;
  }

  bool _hasSignInEndpoint(dynamic node, [int depth = 0]) {
    if (depth > 20) return false;
    if (node is Map) {
      if (node.containsKey('signInEndpoint')) return true;
      for (final val in node.values) {
        if (_hasSignInEndpoint(val, depth + 1)) return true;
      }
    } else if (node is List) {
      final limit = node.length > 100 ? 100 : node.length;
      for (var i = 0; i < limit; i++) {
        if (_hasSignInEndpoint(node[i], depth + 1)) return true;
      }
    }
    return false;
  }

  String? _extractContinuationToken(dynamic node, [int depth = 0]) {
    // Iterative guard via depth cap: InnerTube payloads are shallow (<30);
    // anything deeper is malformed — bail instead of stack-overflowing.
    if (depth > 40) return null;
    if (node is Map<String, dynamic>) {
      // Canonical format: nextContinuationData.continuation
      if (node.containsKey('nextContinuationData')) {
        final token = node['nextContinuationData']?['continuation'] as String?;
        if (token != null && token.isNotEmpty) return token;
      }
      if (node.containsKey('reloadContinuationData')) {
        final token =
            node['reloadContinuationData']?['continuation'] as String?;
        if (token != null && token.isNotEmpty) return token;
      }
      // Newer InnerTube format: continuationEndpoint.continuationCommand.token
      if (node.containsKey('continuationEndpoint')) {
        final token = node['continuationEndpoint']?['continuationCommand']
            ?['token'] as String?;
        if (token != null && token.isNotEmpty) return token;
      }
      if (node.containsKey('continuationCommand')) {
        final token = node['continuationCommand']?['token'] as String?;
        if (token != null && token.isNotEmpty) return token;
      }
      if (node.containsKey('nextRadioContinuationData')) {
        final token =
            node['nextRadioContinuationData']?['continuation'] as String?;
        if (token != null && token.isNotEmpty) return token;
      }
      for (final val in node.values) {
        final token = _extractContinuationToken(val, depth + 1);
        if (token != null && token.isNotEmpty) return token;
      }
    } else if (node is List) {
      // Cap fan-out to avoid pathological payloads pinning the UI thread.
      final limit = node.length > 500 ? 500 : node.length;
      for (var i = 0; i < limit; i++) {
        final token = _extractContinuationToken(node[i], depth + 1);
        if (token != null && token.isNotEmpty) return token;
      }
    }
    return null;
  }

  String _joinRunsText(List<dynamic>? runs, String fallback) {
    if (runs == null || runs.isEmpty) return fallback;
    final joined =
        runs.map((r) => (r is Map ? r['text']?.toString() : null) ?? '').join().trim();
    return joined.isNotEmpty ? joined : fallback;
  }

  List<YtmTrack> _parseInnertubePlaylistTracks(
    Map<String, dynamic> root, {
    bool ignoreSuggestions = false,
  }) {
    final tracks = <YtmTrack>[];

    void traverse(dynamic node) {
      if (node is Map<String, dynamic>) {
        // ── Leaf renderers: parse & stop recursion ──────────────────────────
        if (node.containsKey('musicResponsiveListItemRenderer')) {
          final renderer =
              node['musicResponsiveListItemRenderer'] as Map<String, dynamic>;
          final track = _parseListItemRenderer(renderer);
          if (track != null) tracks.add(track);
          return;
        }
        // ── Container renderers: traverse contents without stopping ─────────
        // YouTube Music now wraps liked-songs tracks inside
        // musicPlaylistShelfRenderer.contents[] and musicShelfRenderer.contents[].
        // Do NOT return after traversing these — fall through to the values loop.
        if (node.containsKey('musicPlaylistShelfRenderer')) {
          final shelf =
              node['musicPlaylistShelfRenderer'] as Map<String, dynamic>;
          final contents = shelf['contents'];
          if (contents is List) {
            for (final item in contents) {
              traverse(item);
            }
          }
          return;
        }
        if (node.containsKey('musicShelfRenderer')) {
          final shelf = node['musicShelfRenderer'] as Map<String, dynamic>;
          if (ignoreSuggestions) {
            final titleRuns = shelf['title']?['runs'] as List<dynamic>?;
            final titleText = titleRuns
                    ?.map((r) => r['text']?.toString() ?? '')
                    .join()
                    .toLowerCase() ??
                '';
            final isSuggestions = titleText.contains('suggestion') ||
                titleText.contains('suggested') ||
                titleText.contains('اقتراح') ||
                titleText.contains('sugerencia') ||
                titleText.contains('empfehlung');
            final hasReload = shelf.containsKey('bottomEndpoint') ||
                shelf.containsKey('reloadContinuationData');
            if (isSuggestions || hasReload) {
              return; // Skip suggestions shelf!
            }
          }
          final contents = shelf['contents'];
          if (contents is List) {
            for (final item in contents) {
              traverse(item);
            }
          }
          return;
        }
        if (node.containsKey('playlistPanelVideoRenderer')) {
          final renderer =
              node['playlistPanelVideoRenderer'] as Map<String, dynamic>;
          final videoId = renderer['videoId'] as String?;
          final titleRuns = renderer['title']?['runs'] as List<dynamic>?;
          final title = _joinRunsText(titleRuns, 'Unknown Title');
          final artistRuns =
              renderer['shortBylineText']?['runs'] as List<dynamic>?;
          final artist =
              YtmMediaHelpers.firstArtistRun(artistRuns) ?? 'Unknown Artist';
          final lengthRuns = renderer['lengthText']?['runs'] as List<dynamic>?;
          final lengthText = lengthRuns?.isNotEmpty == true
              ? lengthRuns![0]['text'] as String?
              : null;
          int durationMs = 0;
          if (lengthText != null) {
            final parts =
                lengthText.split(':').map((e) => int.tryParse(e) ?? 0).toList();
            if (parts.length == 2) {
              durationMs = (parts[0] * 60 + parts[1]) * 1000;
            } else if (parts.length == 3) {
              durationMs = (parts[0] * 3600 + parts[1] * 60 + parts[2]) * 1000;
            }
          }
          final thumbnails =
              renderer['thumbnail']?['thumbnails'] as List<dynamic>?;
          final artwork = thumbnails?.isNotEmpty == true
              ? thumbnails!.last['url'] as String?
              : null;

          if (videoId != null && videoId.length == 11) {
            tracks.add(YtmTrack(
              videoId: videoId,
              title: title,
              artist: artist,
              duration: Duration(milliseconds: durationMs),
              artworkUrl: artwork,
            ));
          }
          return;
        } else if (node.containsKey('playlistVideoRenderer')) {
          final renderer =
              node['playlistVideoRenderer'] as Map<String, dynamic>;
          final videoId = renderer['videoId'] as String?;
          final titleRuns = renderer['title']?['runs'] as List<dynamic>?;
          final title = _joinRunsText(titleRuns, 'Unknown Title');
          final bylineRuns =
              renderer['shortBylineText']?['runs'] as List<dynamic>?;
          final artist =
              YtmMediaHelpers.firstArtistRun(bylineRuns) ?? 'Unknown Artist';
          final lengthSeconds =
              int.tryParse(renderer['lengthSeconds']?.toString() ?? '0') ?? 0;
          final thumbnails =
              renderer['thumbnail']?['thumbnails'] as List<dynamic>?;
          final artwork = thumbnails?.isNotEmpty == true
              ? thumbnails!.last['url'] as String?
              : null;

          if (videoId != null && videoId.length == 11) {
            tracks.add(YtmTrack(
              videoId: videoId,
              title: title,
              artist: artist,
              duration: Duration(seconds: lengthSeconds),
              artworkUrl: artwork,
            ));
          }
          return;
        } else if (node.containsKey('musicTwoRowItemRenderer')) {
          if (ignoreSuggestions) {
            return; // Skip album/playlist tiles in playlist track context
          }
          final renderer =
              node['musicTwoRowItemRenderer'] as Map<String, dynamic>;
          String? vid = renderer['navigationEndpoint']?['watchEndpoint']
              ?['videoId'] as String?;
          vid ??= renderer['thumbnailRenderer']?['musicThumbnailRenderer']
              ?['navigationEndpoint']?['watchEndpoint']?['videoId'] as String?;
          vid ??= renderer['thumbnailOverlay']
                      ?['musicItemThumbnailOverlayRenderer']?['content']
                  ?['musicPlayButtonRenderer']?['playNavigationEndpoint']
              ?['watchEndpoint']?['videoId'] as String?;
          vid ??= renderer['navigationEndpoint']?['watchPlaylistEndpoint']
              ?['videoId'] as String?;
          vid ??= renderer['onTap']?['watchEndpoint']?['videoId'] as String?;

          if (vid != null && vid.length == 11) {
            final titleRuns = renderer['title']?['runs'] as List<dynamic>?;
            final title = _joinRunsText(titleRuns, 'Unknown Title');

            String artist = 'Unknown Artist';
            int durationMs = 0;

            final subRuns = renderer['subtitle']?['runs'] as List<dynamic>?;
            if (subRuns != null && subRuns.isNotEmpty) {
              artist =
                  YtmMediaHelpers.firstArtistRun(subRuns) ?? 'Unknown Artist';
              final texts = subRuns
                  .map((r) => r['text']?.toString().trim() ?? '')
                  .where((t) => t.isNotEmpty && t != '•' && t != '·')
                  .toList();

              for (final t in texts) {
                final parts = t.split(':').map((e) => int.tryParse(e)).toList();
                if (parts.length == 2 && parts[0] != null && parts[1] != null) {
                  durationMs = (parts[0]! * 60 + parts[1]!) * 1000;
                } else if (parts.length == 3 &&
                    parts[0] != null &&
                    parts[1] != null &&
                    parts[2] != null) {
                  durationMs =
                      (parts[0]! * 3600 + parts[1]! * 60 + parts[2]!) * 1000;
                }
              }
            }

            String? artworkUrl;
            final thumbRenderer = renderer['thumbnailRenderer']
                    ?['musicThumbnailRenderer'] ??
                renderer['thumbnail']?['musicThumbnailRenderer'];
            final thumbs = (thumbRenderer?['thumbnail']?['thumbnails'] ??
                renderer['thumbnail']?['thumbnails']) as List<dynamic>?;
            if (thumbs != null && thumbs.isNotEmpty) {
              artworkUrl = thumbs.last['url'] as String?;
              if (artworkUrl != null) {
                artworkUrl =
                    artworkUrl.replaceAll(RegExp(r'=w\d+-h\d+[^?]*'), '=s1200');
                artworkUrl =
                    artworkUrl.replaceAll(RegExp(r'=s\d+[^?]*'), '=s1200');
              }
            }

            tracks.add(YtmTrack(
              videoId: vid,
              title: title,
              artist: artist,
              duration: Duration(milliseconds: durationMs),
              artworkUrl: artworkUrl,
            ));
            return;
          }
        }
        for (final val in node.values) {
          traverse(val);
        }
      } else if (node is List) {
        for (final item in node) {
          traverse(item);
        }
      }
    }

    traverse(root);
    return tracks;
  }

  YtmTrack? _parseListItemRenderer(Map<String, dynamic> renderer) {
    try {
      final playlistItemData =
          renderer['playlistItemData'] as Map<String, dynamic>?;
      String? videoId = playlistItemData?['videoId'] as String?;

      videoId ??= renderer['navigationEndpoint']?['watchEndpoint']?['videoId']
          as String?;
      videoId ??= renderer['overlay']?['musicItemThumbnailOverlayRenderer']
              ?['content']?['musicPlayButtonRenderer']
          ?['playNavigationEndpoint']?['watchEndpoint']?['videoId'] as String?;
      videoId ??= renderer['doubleTapEndpoint']?['watchEndpoint']?['videoId']
          as String?;

      if (videoId == null || videoId.length != 11) {
        final flexColumns =
            renderer['flexColumns'] as List<dynamic>? ?? const [];
        for (final col in flexColumns) {
          final runs = col['musicResponsiveListItemFlexColumnRenderer']?['text']
              ?['runs'] as List<dynamic>?;
          if (runs != null) {
            for (final r in runs) {
              final nav = r['navigationEndpoint'] as Map<String, dynamic>?;
              final vid = nav?['watchEndpoint']?['videoId'] as String?;
              if (vid != null && vid.length == 11) {
                videoId = vid;
                break;
              }
            }
          }
          if (videoId != null) break;
        }
      }

      // Deep scan the renderer for any 11-char videoId if still null
      if (videoId == null || videoId.length != 11) {
        String? findVideoId(dynamic node) {
          if (node is Map<String, dynamic>) {
            if (node.containsKey('watchEndpoint')) {
              final vid = node['watchEndpoint']?['videoId'] as String?;
              if (vid != null && vid.length == 11) return vid;
            }
            if (node.containsKey('videoId')) {
              final vid = node['videoId'] as String?;
              if (vid != null && vid.length == 11) return vid;
            }
            for (final v in node.values) {
              final res = findVideoId(v);
              if (res != null) return res;
            }
          } else if (node is List) {
            for (final item in node) {
              final res = findVideoId(item);
              if (res != null) return res;
            }
          }
          return null;
        }

        videoId = findVideoId(renderer);
      }

      if (videoId == null || videoId.length != 11) return null;

      String title = L10nHolder.current?.ytmUnknownTitle ?? 'Unknown Title';
      String artist = L10nHolder.current?.unknownArtist ?? 'Unknown Artist';
      int durationMs = 0;

      final flexColumns = renderer['flexColumns'] as List<dynamic>? ?? const [];
      if (flexColumns.isNotEmpty) {
        final col0Runs = flexColumns[0]
            ['musicResponsiveListItemFlexColumnRenderer']?['text']?['runs'];
        if (col0Runs is List && col0Runs.isNotEmpty) {
          final t =
              col0Runs.map((r) => r['text']?.toString() ?? '').join('').trim();
          if (t.isNotEmpty) title = t;
        }
      }
      if (flexColumns.length > 1) {
        final col1Runs = flexColumns[1]
            ['musicResponsiveListItemFlexColumnRenderer']?['text']?['runs'];
        if (col1Runs is List && col1Runs.isNotEmpty) {
          artist =
              YtmMediaHelpers.firstArtistRun(col1Runs) ?? 'Unknown Artist';
        }
      }

      final fixedCols = renderer['fixedColumns'] as List<dynamic>? ?? const [];
      if (fixedCols.isNotEmpty) {
        final durRuns = fixedCols[0]
            ['musicResponsiveListItemFixedColumnRenderer']?['text']?['runs'];
        final durText = (durRuns is List && durRuns.isNotEmpty)
            ? durRuns[0]['text'] as String?
            : null;
        if (durText != null) {
          final parts =
              durText.split(':').map((e) => int.tryParse(e) ?? 0).toList();
          if (parts.length == 2) {
            durationMs = (parts[0] * 60 + parts[1]) * 1000;
          } else if (parts.length == 3) {
            durationMs = (parts[0] * 3600 + parts[1] * 60 + parts[2]) * 1000;
          }
        }
      }

      String? artworkUrl;
      final thumbnails = renderer['thumbnail']?['musicThumbnailRenderer']
          ?['thumbnail']?['thumbnails'] as List<dynamic>?;
      if (thumbnails != null && thumbnails.isNotEmpty) {
        artworkUrl = thumbnails.last['url'] as String?;
        if (artworkUrl != null) {
          artworkUrl =
              artworkUrl.replaceAll(RegExp(r'=w\d+-h\d+[^?]*'), '=s1200');
          artworkUrl = artworkUrl.replaceAll(RegExp(r'=s\d+[^?]*'), '=s1200');
        }
      }

      return YtmTrack(
        videoId: videoId,
        title: title,
        artist: artist,
        duration: Duration(milliseconds: durationMs),
        artworkUrl: artworkUrl,
      );
    } catch (_) {
      return null;
    }
  }

  List<YtmAccountPlaylist> _parseInnertubeAccountPlaylists(
    Map<String, dynamic> root,
  ) {
    final results = <YtmAccountPlaylist>[];
    final seenIds = <String>{};

    void traverse(dynamic node) {
      if (node is Map<String, dynamic>) {
        if (node.containsKey('musicTwoRowItemRenderer')) {
          final renderer =
              node['musicTwoRowItemRenderer'] as Map<String, dynamic>;
          final nav = renderer['navigationEndpoint'] as Map<String, dynamic>?;
          final browseId = nav?['browseEndpoint']?['browseId'] as String?;

          if (browseId != null &&
              (browseId.startsWith('VLPL') ||
                  browseId.startsWith('VL') ||
                  browseId.startsWith('PL') ||
                  browseId.startsWith('RDCLAK5uy_'))) {
            final cleanId =
                browseId.startsWith('VL') ? browseId.substring(2) : browseId;
            if (cleanId != 'LM' &&
                cleanId != 'SE' &&
                !seenIds.contains(cleanId)) {
              seenIds.add(cleanId);

              final titleRuns = renderer['title']?['runs'] as List<dynamic>?;
              final title =
                  titleRuns?.map((r) => r['text']?.toString() ?? '').join() ??
                      'Playlist';

              final subRuns = renderer['subtitle']?['runs'] as List<dynamic>?;
              final subtitle =
                  subRuns?.map((r) => r['text']?.toString() ?? '').join() ??
                      'YouTube Music';

              String? artwork;
              final thumbRenderer =
                  renderer['thumbnailRenderer']?['musicThumbnailRenderer'];
              final thumbs =
                  thumbRenderer?['thumbnail']?['thumbnails'] as List<dynamic>?;
              if (thumbs != null && thumbs.isNotEmpty) {
                artwork = thumbs.last['url'] as String?;
              }

              results.add(YtmAccountPlaylist(
                playlistId: cleanId,
                title: title.isNotEmpty
                    ? title
                    : (L10nHolder.current?.ytmFallbackPlaylistTitle ??
                        'Playlist'),
                subtitle: subtitle,
                artworkUrl: artwork,
              ));
            }
          }
        }

        if (node.containsKey('musicResponsiveListItemRenderer')) {
          final renderer =
              node['musicResponsiveListItemRenderer'] as Map<String, dynamic>;
          final nav = renderer['navigationEndpoint'] as Map<String, dynamic>?;
          final browseId = nav?['browseEndpoint']?['browseId'] as String?;
          if (browseId != null &&
              (browseId.startsWith('VLPL') ||
                  browseId.startsWith('VL') ||
                  browseId.startsWith('PL'))) {
            final cleanId =
                browseId.startsWith('VL') ? browseId.substring(2) : browseId;
            if (cleanId != 'LM' &&
                cleanId != 'SE' &&
                !seenIds.contains(cleanId)) {
              seenIds.add(cleanId);

              String title = L10nHolder.current?.ytmFallbackPlaylistTitle ??
                  'Playlist';
              final flexCols = renderer['flexColumns'] as List<dynamic>?;
              if (flexCols != null && flexCols.isNotEmpty) {
                final r = flexCols[0]
                        ['musicResponsiveListItemFlexColumnRenderer']?['text']
                    ?['runs'] as List<dynamic>?;
                if (r != null && r.isNotEmpty) {
                  title = r.map((e) => e['text']?.toString() ?? '').join();
                }
              }

              String subtitle =
                  L10nHolder.current?.browseYouTubeMusic ?? 'YouTube Music';
              if (flexCols != null && flexCols.length > 1) {
                final r = flexCols[1]
                        ['musicResponsiveListItemFlexColumnRenderer']?['text']
                    ?['runs'] as List<dynamic>?;
                if (r != null && r.isNotEmpty) {
                  subtitle = r.map((e) => e['text']?.toString() ?? '').join();
                }
              }

              String? artwork;
              final thumbs = renderer['thumbnail']?['musicThumbnailRenderer']
                  ?['thumbnail']?['thumbnails'] as List<dynamic>?;
              if (thumbs != null && thumbs.isNotEmpty) {
                artwork = thumbs.last['url'] as String?;
              }

              results.add(YtmAccountPlaylist(
                playlistId: cleanId,
                title: title,
                subtitle: subtitle,
                artworkUrl: artwork,
              ));
            }
          }
        }

        for (final val in node.values) {
          traverse(val);
        }
      } else if (node is List) {
        for (final item in node) {
          traverse(item);
        }
      }
    }

    traverse(root);
    return results;
  }
}
