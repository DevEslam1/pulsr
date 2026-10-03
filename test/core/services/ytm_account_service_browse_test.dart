// test/core/services/ytm_account_service_browse_test.dart
//
// The Innertube parsing/fallback surface of YtmAccountService: library
// playlists, liked songs (with continuation and the /next + account +
// native fallback chain), home recommendations and native lyrics. All of it
// is driven through the public API with a scripted MockClient, so the private
// tree-walkers are covered without a network or plugin.
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/constants/channels.dart';
import 'package:pulsr/core/di/injection.dart';
import 'package:pulsr/core/services/ytm_account_service.dart';
import 'package:pulsr/core/services/ytm_circuit_breaker.dart';
import 'package:pulsr/core/services/ytm_client_version_resolver.dart';
import 'package:pulsr/core/services/ytm_service.dart';
import 'package:pulsr/core/utils/ytm_rate_limiter.dart';
import 'package:pulsr/domain/models/lyrics_line.dart';
import 'package:pulsr/domain/models/ytm_track.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';

class MockYtmService extends Mock implements YtmService {}

class MockSecureStorage extends Mock implements FlutterSecureStorage {}

const String _validJar = 'SAPISID=sapisid; __Secure-3PSID=psid';
const _ytmChannel = MethodChannel(PulsrChannels.ytm);

late MockYtmService ytm;
late MockSecureStorage secure;
late Future<http.Response> Function(http.Request request) handler;
late int requestCount;

void _mockChannel(Future<Object?> Function(MethodCall call) channelHandler) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_ytmChannel, channelHandler);
}

http.Response _json(int status, Object body) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

http.Response _authHome() => _json(200, {
      'responseContext': {
        'mainAppWebResponseContext': {'datasyncId': 'dsid||'},
      },
      'contents': {
        'singleColumnBrowseResultsRenderer': {},
      },
    });

http.Response _loggedOut() => _json(200, {
      'responseContext': {
        'mainAppWebResponseContext': {'loggedOut': true},
      },
    });

YtmAccountService _service() {
  return YtmAccountService(YtmClientVersionResolver())
    ..debugInnertubeClient = MockClient((request) {
      requestCount++;
      return handler(request);
    });
}

Future<void> _settle() => pumpEventQueue(times: 30);

void _stubYtmService() {
  when(() => ytm.breaker).thenReturn(YtmCircuitBreaker());
  when(() => ytm.syncCookies(any())).thenAnswer((_) async {});
  when(() => ytm.setDataSyncId(any())).thenAnswer((_) async {});
  when(() => ytm.invalidatePoToken()).thenAnswer((_) async {});
  when(() => ytm.ensurePoTokenReady()).thenAnswer((_) async => true);
  when(() => ytm.clearNativeSession()).thenAnswer((_) async {});
  when(() => ytm.notifyAuthExpired()).thenReturn(null);
  when(() => ytm.getPlaylistTracks(any(), limit: any(named: 'limit')))
      .thenAnswer((_) async => const []);
}

Map<String, dynamic> _twoRowPlaylist({
  required String browseId,
  String title = 'Mix',
  String subtitle = '20 songs',
  String? artwork,
}) =>
    {
      'musicTwoRowItemRenderer': {
        'navigationEndpoint': {
          'browseEndpoint': {'browseId': browseId},
        },
        'title': {
          'runs': [
            {'text': title},
          ],
        },
        'subtitle': {
          'runs': [
            {'text': subtitle},
          ],
        },
        if (artwork != null)
          'thumbnailRenderer': {
            'musicThumbnailRenderer': {
              'thumbnail': {
                'thumbnails': [
                  {'url': artwork, 'width': 120, 'height': 120},
                ],
              },
            },
          },
      },
    };

Map<String, dynamic> _responsivePlaylist({
  required String browseId,
  required String title,
  String subtitle = 'YouTube Music',
}) =>
    {
      'musicResponsiveListItemRenderer': {
        'navigationEndpoint': {
          'browseEndpoint': {'browseId': browseId},
        },
        'flexColumns': [
          {
            'musicResponsiveListItemFlexColumnRenderer': {
              'text': {
                'runs': [
                  {'text': title},
                ],
              },
            },
          },
          {
            'musicResponsiveListItemFlexColumnRenderer': {
              'text': {
                'runs': [
                  {'text': subtitle},
                ],
              },
            },
          },
        ],
        'thumbnail': {
          'musicThumbnailRenderer': {
            'thumbnail': {
              'thumbnails': [
                {'url': 'https://art/$browseId.jpg', 'width': 60, 'height': 60},
              ],
            },
          },
        },
      },
    };

Map<String, dynamic> _responsiveTrack({
  required String videoId,
  String title = 'Song',
  String artist = 'Artist',
  String duration = '3:45',
  String? artwork,
}) =>
    {
      'musicResponsiveListItemRenderer': {
        'playlistItemData': {'videoId': videoId},
        'flexColumns': [
          {
            'musicResponsiveListItemFlexColumnRenderer': {
              'text': {
                'runs': [
                  {'text': title},
                ],
              },
            },
          },
          {
            'musicResponsiveListItemFlexColumnRenderer': {
              'text': {
                'runs': [
                  {'text': artist},
                  {'text': ' • '},
                  {'text': 'Song'},
                ],
              },
            },
          },
        ],
        'fixedColumns': [
          {
            'musicResponsiveListItemFixedColumnRenderer': {
              'text': {
                'runs': [
                  {'text': duration},
                ],
              },
            },
          },
        ],
        if (artwork != null)
          'thumbnail': {
            'musicThumbnailRenderer': {
              'thumbnail': {
                'thumbnails': [
                  {'url': artwork, 'width': 120, 'height': 120},
                ],
              },
            },
          },
      },
    };

Map<String, dynamic> _panelTrack({
  required String videoId,
  String title = 'Panel Song',
  String artist = 'Panel Artist',
  String? length = '4:33',
}) =>
    {
      'playlistPanelVideoRenderer': {
        'videoId': videoId,
        'title': {
          'runs': [
            {'text': title},
          ],
        },
        'shortBylineText': {
          'runs': [
            {'text': artist},
          ],
        },
        if (length != null)
          'lengthText': {
            'runs': [
              {'text': length},
            ],
          },
        'thumbnail': {
          'thumbnails': [
            {'url': 'https://art/panel.jpg'},
          ],
        },
      },
    };

Map<String, dynamic> _shelf(
  List<Map<String, dynamic>> tracks, {
  List<Map<String, dynamic>>? continuations,
}) =>
    {
      'contents': {
        'musicPlaylistShelfRenderer': {
          'contents': tracks,
          if (continuations != null) 'continuations': continuations,
        },
      },
    };

Map<String, dynamic> _continuationResponse(
  List<Map<String, dynamic>> tracks, {
  List<Map<String, dynamic>>? continuations,
}) =>
    {
      'continuationContents': {
        'musicPlaylistShelfContinuation': {
          'contents': tracks,
          if (continuations != null) 'continuations': continuations,
        },
      },
    };

Map<String, dynamic> _header({
  String title = 'My Playlist',
  String author = 'Channel Name',
  String artwork = 'https://art/big.jpg',
  bool editable = false,
}) {
  final header = {
    'title': {
      'runs': [
        {'text': title},
      ],
    },
    'straplineTextOne': {
      'runs': [
        {'text': author},
      ],
    },
    'thumbnail': {
      'croppedSquareThumbnailRenderer': {
        'thumbnail': {
          'thumbnails': [
            {'url': artwork},
          ],
        },
      },
    },
  };
  return editable
      ? {
          'musicEditablePlaylistDetailHeaderRenderer': {
            'header': {'musicResponsiveHeaderRenderer': header},
          },
        }
      : {
          'musicResponsiveHeaderRenderer': header,
        };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await getIt.reset();
    YtmRateLimiter.debugReset();
    requestCount = 0;
    handler = (request) async => _authHome();

    ytm = MockYtmService();
    _stubYtmService();
    getIt.registerSingleton<YtmService>(ytm);

    secure = MockSecureStorage();
    when(() => secure.read(key: any(named: 'key')))
        .thenAnswer((_) async => null);
    when(() => secure.write(
          key: any(named: 'key'),
          value: any(named: 'value'),
        )).thenAnswer((_) async {});
    when(() => secure.delete(key: any(named: 'key'))).thenAnswer((_) async {});
    YtmAccountService.setSecureStorageForTesting(secure);

    _mockChannel((call) async {
      if (call.method == 'getCookies') return _validJar;
      return null;
    });
  });

  tearDown(() async {
    _mockChannel((call) async => null);
    await getIt.reset();
  });

  Future<YtmAccountService> loggedIn() async {
    final service = _service();
    await service.init();
    await _settle();
    expect(service.isLoggedIn, isTrue);
    return service;
  }

  group('fetchAccountPlaylists', () {
    test('throws YTM_AUTH when signed out', () async {
      await expectLater(
        _service().fetchAccountPlaylists(),
        throwsA(isA<YtmException>().having((e) => e.isAuth, 'isAuth', isTrue)),
      );
    });

    test('parses two-row and responsive playlist renderers, deduping ids',
        () async {
      final service = await loggedIn();
      handler = (request) async => _json(200, {
            'contents': [
              _twoRowPlaylist(
                browseId: 'VLPLone',
                title: 'One',
                artwork: 'https://art/one.jpg',
              ),
              _twoRowPlaylist(browseId: 'VLPLone', title: 'Duplicate'),
              _twoRowPlaylist(browseId: 'VLLM', title: 'Liked'),
              _twoRowPlaylist(browseId: 'VLSE', title: 'Episodes'),
              _twoRowPlaylist(browseId: 'PLdirect', title: 'Direct'),
              _twoRowPlaylist(browseId: 'RDCLAK5uy_x', title: 'Radio'),
              _responsivePlaylist(
                browseId: 'PLresp',
                title: 'Responsive',
                subtitle: '3 songs',
              ),
            ],
          });

      final playlists = await service.fetchAccountPlaylists();

      expect(playlists.map((p) => p.playlistId).toList(),
          ['PLone', 'PLdirect', 'RDCLAK5uy_x', 'PLresp']);
      expect(playlists.first.title, 'One');
      expect(playlists.first.artworkUrl, 'https://art/one.jpg');
      expect(playlists.last.title, 'Responsive');
      expect(playlists.last.subtitle, '3 songs');
    });

    test('tries the next browse id when one yields no playlists', () async {
      final service = await loggedIn();
      final browsed = <String>[];
      handler = (request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        browsed.add(body['browseId'] as String);
        if (body['browseId'] == 'FEmusic_library_landing') {
          return _json(200, {
            'contents': [
              _twoRowPlaylist(browseId: 'VLPLlate', title: 'Late'),
            ],
          });
        }
        return _json(200, {'contents': {}});
      };

      final playlists = await service.fetchAccountPlaylists();
      expect(playlists.single.playlistId, 'PLlate');
      expect(browsed, [
        'FEmusic_library_playlists',
        'FEmusic_liked_playlists',
        'FEmusic_library_landing',
      ]);
    });

    test('an unauthenticated body plus a dead session logs out and throws',
        () async {
      final service = await loggedIn();
      handler = (request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        if (body['browseId'] == 'FEmusic_home') {
          return _json(401, const {});
        }
        return _loggedOut();
      };

      await expectLater(
        service.fetchAccountPlaylists(),
        throwsA(isA<YtmException>().having((e) => e.code, 'code', 'YTM_AUTH')),
      );
      verify(() => ytm.clearNativeSession()).called(1);
    });

    test('an unauthenticated body with a live session notifies and continues',
        () async {
      final service = await loggedIn();
      handler = (request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        if (body['browseId'] == 'FEmusic_home') return _authHome();
        return _loggedOut();
      };

      expect(await service.fetchAccountPlaylists(), isEmpty);
      verify(() => ytm.notifyAuthExpired()).called(3);
    });

    test('non-auth transport failures are swallowed into an empty list',
        () async {
      final service = await loggedIn();
      handler = (request) async => throw Exception('socket down');

      expect(await service.fetchAccountPlaylists(), isEmpty);
    });

    test('a 403 on a cookie session is retried once before failing', () async {
      final service = await loggedIn();
      var calls = 0;
      handler = (request) async {
        calls++;
        if (calls == 1) {
          return _json(403, {'error': 'blocked'});
        }
        return _json(200, {
          'contents': [
            _twoRowPlaylist(browseId: 'VLPLretried', title: 'Retried'),
          ],
        });
      };

      final playlists = await service.fetchAccountPlaylists();
      expect(playlists.single.playlistId, 'PLretried');
      expect(calls, 2);
    });

    test('a rotated Set-Cookie on a successful browse updates the jar',
        () async {
      final service = await loggedIn();
      handler = (request) async => http.Response(
            jsonEncode({'contents': {}}),
            200,
            headers: {
              'content-type': 'application/json',
              'set-cookie': 'SIDCC=rotated; Path=/',
            },
          );

      await service.fetchAccountPlaylists();
      await _settle();

      expect(service.cookies, contains('SIDCC=rotated'));
      verify(() => ytm.syncCookies(any())).called(greaterThanOrEqualTo(1));
    });
  });

  group('fetchLikedSongs', () {
    test('throws YTM_AUTH when signed out', () async {
      await expectLater(
        _service().fetchLikedSongs(),
        throwsA(isA<YtmException>().having((e) => e.isAuth, 'isAuth', isTrue)),
      );
    });

    test('parses a playlist shelf and follows one continuation page', () async {
      final service = await loggedIn();
      handler = (request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final continuation = body['continuation'] as String?;
        if (continuation == 'page2') {
          return _json(
              200,
              _continuationResponse([
                _responsiveTrack(videoId: 'dQw4w9WgXcQ', title: 'Duplicate'),
                _responsiveTrack(
                  videoId: 'aBcDeFgHiJk',
                  title: 'Second',
                  artist: 'Other',
                  duration: '4:05',
                  artwork: 'https://art/cover=w120-h120-l90-rj',
                ),
              ]));
        }
        return _json(
          200,
          _shelf(
            [
              _responsiveTrack(
                videoId: 'dQw4w9WgXcQ',
                title: 'First',
                artwork: 'https://art/first=s120-c',
              ),
            ],
            continuations: [
              {
                'nextContinuationData': {'continuation': 'page2'},
              },
            ],
          ),
        );
      };

      final tracks = await service.fetchLikedSongs();

      expect(tracks.map((t) => t.videoId).toList(),
          ['dQw4w9WgXcQ', 'aBcDeFgHiJk']);
      expect(tracks.first.title, 'First');
      expect(tracks.first.duration, const Duration(minutes: 3, seconds: 45));
      expect(tracks.first.artworkUrl, 'https://art/first=s1200');
      expect(tracks.last.duration, const Duration(minutes: 4, seconds: 5));
      expect(tracks.last.artworkUrl, 'https://art/cover=s1200');
    });

    test('a header shell with a continuation token still resolves tracks',
        () async {
      final service = await loggedIn();
      handler = (request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        if (body['continuation'] == 'initTok') {
          return _json(
            200,
            _continuationResponse([
              _responsiveTrack(videoId: 'initTracks1', title: 'From Init'),
            ]),
          );
        }
        // A shelf with no contents but a successor token.
        return _json(200, {
          'contents': {
            'musicPlaylistShelfRenderer': {
              'continuations': [
                {
                  'continuationEndpoint': {
                    'continuationCommand': {'token': 'initTok'},
                  },
                },
              ],
            },
          },
        });
      };

      final tracks = await service.fetchLikedSongs();
      expect(tracks.single.videoId, 'initTracks1');
      expect(tracks.single.title, 'From Init');
    });

    test('falls back to the /next endpoint for panel renderers', () async {
      final service = await loggedIn();
      handler = (request) async {
        if (request.url.path.contains('/next')) {
          return _json(200, {
            'contents': [
              _panelTrack(videoId: 'panelOne123', length: '4:33'),
              _panelTrack(
                videoId: 'panelTwo456',
                title: 'Hour Long',
                length: '1:02:03',
              ),
            ],
          });
        }
        return _json(200, {'contents': {}});
      };

      final tracks = await service.fetchLikedSongs();

      expect(tracks.map((t) => t.videoId).toList(),
          ['panelOne123', 'panelTwo456']);
      expect(tracks.first.duration, const Duration(minutes: 4, seconds: 33));
      expect(tracks.last.duration,
          const Duration(hours: 1, minutes: 2, seconds: 3));
      expect(tracks.first.artworkUrl, 'https://art/panel.jpg');
    });

    test('discovers a Liked Music playlist from the account library', () async {
      final service = await loggedIn();
      handler = (request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final browseId = body['browseId'] as String?;
        if (browseId == 'FEmusic_library_playlists') {
          return _json(200, {
            'contents': [
              _twoRowPlaylist(
                browseId: 'VLPLliked',
                title: 'Liked Music',
                subtitle: 'Auto playlist',
              ),
            ],
          });
        }
        if (browseId == 'VLPLliked' || browseId == 'PLliked') {
          return _json(
            200,
            _shelf([
              _responsiveTrack(videoId: 'likedTrack1', title: 'Loved'),
            ]),
          );
        }
        return _json(200, {'contents': {}});
      };

      final tracks = await service.fetchLikedSongs();
      expect(tracks.single.videoId, 'likedTrack1');
    });

    test('falls back to the native Kotlin extractor', () async {
      final service = await loggedIn();
      handler = (request) async => _json(200, {'contents': {}});
      when(() => ytm.getPlaylistTracks(any(), limit: any(named: 'limit')))
          .thenAnswer((_) async => [
                const YtmTrack(
                  videoId: 'nativeTrack1',
                  title: 'Native',
                  artist: 'Kotlin',
                  duration: Duration(minutes: 2),
                ),
              ]);

      final tracks = await service.fetchLikedSongs();
      expect(tracks.single.videoId, 'nativeTrack1');
    });

    test('returns empty when every engine comes up empty', () async {
      final service = await loggedIn();
      handler = (request) async => _json(200, {'contents': {}});

      expect(await service.fetchLikedSongs(), isEmpty);
    });
  });

  group('fetchHomeRecommendations', () {
    test('is empty and request-free when signed out', () async {
      expect(await _service().fetchHomeRecommendations(), isEmpty);
      expect(requestCount, 0);
    });

    test('parses and dedupes recommendation tracks', () async {
      final service = await loggedIn();
      handler = (request) async => _json(200, {
            'contents': [
              _responsiveTrack(videoId: 'homeTrack01', title: 'Home One'),
              _responsiveTrack(videoId: 'homeTrack01', title: 'Duplicate'),
              _responsiveTrack(videoId: 'homeTrack02', title: 'Home Two'),
            ],
          });

      final tracks = await service.fetchHomeRecommendations();
      expect(tracks.map((t) => t.videoId).toList(),
          ['homeTrack01', 'homeTrack02']);
    });

    test('respects maxTracks', () async {
      final service = await loggedIn();
      handler = (request) async => _json(200, {
            'contents': [
              _responsiveTrack(videoId: 'homeTrack01'),
              _responsiveTrack(videoId: 'homeTrack02'),
              _responsiveTrack(videoId: 'homeTrack03'),
            ],
          });

      final tracks = await service.fetchHomeRecommendations(maxTracks: 2);
      expect(tracks, hasLength(2));
    });

    test('an empty first page is continued via its token', () async {
      final service = await loggedIn();
      handler = (request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        if (body['continuation'] == 'homeNext') {
          return _json(200, {
            'contents': [
              _responsiveTrack(videoId: 'homeTrack09', title: 'Continued'),
            ],
          });
        }
        return _json(200, {
          'continuations': [
            {
              'nextContinuationData': {'continuation': 'homeNext'},
            },
          ],
        });
      };

      final tracks = await service.fetchHomeRecommendations();
      expect(tracks.single.videoId, 'homeTrack09');
    });

    test('an unauthenticated response yields no recommendations', () async {
      final service = await loggedIn();
      handler = (request) async => _loggedOut();

      expect(await service.fetchHomeRecommendations(), isEmpty);
    });
  });

  group('fetchYtmLyrics', () {
    test('empty video id is null', () async {
      expect(await _service().fetchYtmLyrics(''), isNull);
    });

    test('a non-200 next response is null', () async {
      final service = _service();
      // 401 is a non-retryable non-200 (a 5xx would back off three times).
      handler = (request) async => _json(401, const {});
      expect(await service.fetchYtmLyrics('dQw4w9WgXcQ'), isNull);
    });

    test('a lyrics tab whose browse id is not MPLYt is null', () async {
      final service = _service();
      handler = (request) async => _json(200, {
            'contents': [
              {
                'tabRenderer': {
                  'title': 'Lyrics',
                  'endpoint': {
                    'browseEndpoint': {'browseId': 'not-mplyt'},
                  },
                },
              },
            ],
          });
      expect(await service.fetchYtmLyrics('dQw4w9WgXcQ'), isNull);
    });

    test('no lyrics tab at all is null', () async {
      final service = _service();
      handler = (request) async => _json(200, {
            'contents': [
              {
                'tabRenderer': {
                  'title': 'Related',
                  'endpoint': {
                    'browseEndpoint': {'browseId': 'MPRelated'},
                  },
                },
              },
            ],
          });
      expect(await service.fetchYtmLyrics('dQw4w9WgXcQ'), isNull);
    });

    test('timed lyrics render both string and run-shaped lines', () async {
      final service = _service();
      handler = (request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        if (body['browseId'] == 'MPLYt123') {
          return _json(200, {
            'musicTimedLyricsRenderer': {
              'timedLyricsData': [
                {
                  'lyricLine': 'Plain line',
                  'cueRange': {'startTimeMilliseconds': '1500'},
                },
                {
                  'lyricLine': {
                    'runs': [
                      {'text': 'Run '},
                      {'text': 'line'},
                    ],
                  },
                  'cueRange': {'startTimeMilliseconds': 4200},
                },
                {'lyricLine': 'No cue range'},
              ],
            },
          });
        }
        return _json(200, {
          'contents': [
            {
              'tabRenderer': {
                'title': 'Lyrics',
                'endpoint': {
                  'browseEndpoint': {'browseId': 'MPLYt123'},
                },
              },
            },
          ],
        });
      };

      final result = await service.fetchYtmLyrics('dQw4w9WgXcQ');
      expect(result, isNotNull);
      expect(result!.source, LyricsSource.ytmusic);
      expect(result.lines.map((l) => l.text).toList(),
          ['Plain line', 'Run line', 'No cue range']);
      expect(result.lines[0].timestamp, const Duration(milliseconds: 1500));
      expect(result.lines[1].timestamp, const Duration(milliseconds: 4200));
      expect(result.lines[2].timestamp, Duration.zero);
    });

    test('a description shelf with runs becomes plain lyric lines', () async {
      final service = _service();
      handler = (request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        if (body['browseId'] == 'MPLYt999') {
          return _json(200, {
            'musicDescriptionShelfRenderer': {
              'description': {
                'runs': [
                  {'text': 'First plain line\n'},
                  {'text': 'Second plain line'},
                ],
              },
            },
          });
        }
        return _json(200, {
          'contents': [
            {
              'tabRenderer': {
                'title': 'Lyrics',
                'endpoint': {
                  'browseEndpoint': {'browseId': 'MPLYt999'},
                },
              },
            },
          ],
        });
      };

      final result = await service.fetchYtmLyrics('dQw4w9WgXcQ');
      expect(result, isNotNull);
      expect(result!.lines.map((l) => l.text).toList(),
          ['First plain line', 'Second plain line']);
    });

    test('a description shelf stored as a string becomes plain lines',
        () async {
      final service = _service();
      handler = (request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        if (body['browseId'] == 'MPLYt777') {
          return _json(200, {
            'musicDescriptionShelfRenderer': {
              'description': 'Only line',
            },
          });
        }
        return _json(200, {
          'contents': [
            {
              'tabRenderer': {
                'title': 'Lyrics',
                'endpoint': {
                  'browseEndpoint': {'browseId': 'MPLYt777'},
                },
              },
            },
          ],
        });
      };

      final result = await service.fetchYtmLyrics('dQw4w9WgXcQ');
      expect(result!.lines.single.text, 'Only line');
    });
  });

  group('fetchPlaylistDetails', () {
    test('blank input is null', () async {
      expect(await _service().fetchPlaylistDetails('   '), isNull);
    });

    test('extracts list= from a URL and parses header plus tracks', () async {
      final service = await loggedIn();
      final seenBrowseIds = <String>[];
      handler = (request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        seenBrowseIds.add(body['browseId']?.toString() ?? '');
        return _json(200, {
          ..._header(
            title: 'Road Trip',
            author: 'DJ',
            artwork: 'https://art/road.jpg',
          ),
          ..._shelf([
            _responsiveTrack(videoId: 'tripTrack01', title: 'Driving'),
          ]),
        });
      };

      final details = await service.fetchPlaylistDetails(
        'https://music.youtube.com/playlist?list=PLxyz',
      );

      expect(details, isNotNull);
      expect(details!.id, 'PLxyz');
      expect(details.title, 'Road Trip');
      expect(details.author, 'DJ');
      expect(details.artworkUrl, 'https://art/road.jpg');
      expect(details.tracks.single.videoId, 'tripTrack01');
      expect(seenBrowseIds.first, 'VLPLxyz');
    });

    test('follows playlist shelf continuations and dedupes', () async {
      final service = await loggedIn();
      handler = (request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        if (body['continuation'] == 'plPage2') {
          return _json(
            200,
            _continuationResponse([
              _responsiveTrack(videoId: 'plTrack0001'),
              _responsiveTrack(videoId: 'plTrack0002', title: 'Second'),
            ]),
          );
        }
        return _json(200, {
          ..._header(title: 'Paged'),
          ..._shelf(
            [_responsiveTrack(videoId: 'plTrack0001', title: 'First')],
            continuations: [
              {
                'continuationCommand': {'token': 'plPage2'},
              },
            ],
          ),
        });
      };

      final details =
          await service.fetchPlaylistDetails('VLPLpaged', maxTracks: 200);
      expect(details!.tracks.map((t) => t.videoId).toList(),
          ['plTrack0001', 'plTrack0002']);
    });

    test('uses the editable header shape and the /next fallback', () async {
      final service = await loggedIn();
      handler = (request) async {
        if (request.url.path.contains('/next')) {
          return _json(200, {
            ..._header(
                title: 'From Next', author: 'Next Author', editable: true),
            'contents': [
              _panelTrack(videoId: 'nextTrack01'),
            ],
          });
        }
        return _json(200, {'contents': {}});
      };

      final details = await service.fetchPlaylistDetails('PLfallback');
      expect(details, isNotNull);
      expect(details!.title, 'From Next');
      expect(details.author, 'Next Author');
      expect(details.tracks.single.videoId, 'nextTrack01');
    });

    test('the next fallback names itself after the raw id when untitled',
        () async {
      final service = await loggedIn();
      handler = (request) async {
        if (request.url.path.contains('/next')) {
          return _json(200, {
            'contents': [
              _panelTrack(videoId: 'nextTrack02'),
            ],
          });
        }
        return _json(200, {'contents': {}});
      };

      final details = await service.fetchPlaylistDetails('PLuntitled');
      expect(details!.title, 'Playlist (PLuntitled)');
    });

    test('an unauthenticated browse is skipped when signed in', () async {
      final service = await loggedIn();
      var calls = 0;
      handler = (request) async {
        calls++;
        if (calls == 1) return _loggedOut();
        return _json(200, {
          ..._header(title: 'Second Try'),
          ..._shelf([
            _responsiveTrack(videoId: 'retryTrack1'),
          ]),
        });
      };

      final details = await service.fetchPlaylistDetails('PLretry');
      expect(details!.title, 'Second Try');
      expect(details.tracks.single.videoId, 'retryTrack1');
    });

    test('returns null when both browse and next find nothing', () async {
      final service = await loggedIn();
      handler = (request) async => _json(200, {'contents': {}});
      expect(await service.fetchPlaylistDetails('PLnothing'), isNull);
    });

    test('liked-songs aliases route through fetchLikedSongs', () async {
      final service = await loggedIn();
      handler = (request) async => _json(
            200,
            _shelf([
              _responsiveTrack(videoId: 'lmTrack0001', title: 'Liked One'),
            ]),
          );

      final details = await service.fetchPlaylistDetails('LM');
      expect(details, isNotNull);
      expect(details!.title, 'Liked Music');
      expect(details.author, 'Auto Playlist');
      expect(details.tracks.single.videoId, 'lmTrack0001');
      expect(details.artworkUrl, isNull);
    });

    test('fetchPlaylistTracks unwraps the details', () async {
      final service = await loggedIn();
      handler = (request) async => _json(
            200,
            _shelf([
              _responsiveTrack(videoId: 'wrapTrack01'),
            ]),
          );

      final tracks = await service.fetchPlaylistTracks('PLwrap');
      expect(tracks.single.videoId, 'wrapTrack01');
      expect(await service.fetchPlaylistTracks(''), isEmpty);
    });
  });
}
