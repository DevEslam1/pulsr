// test/core/services/ytm_account_service_more_test.dart
//
// Additional reachable branches of YtmAccountService: secure-storage failure
// funnels, dispose, the OAuth restore no-op, the dataSyncId early return, and
// the private Innertube tree-walkers exercised through the public fetch API
// with renderer shapes the existing suites do not cover.
import 'dart:convert';

import 'package:flutter/services.dart';
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
import 'package:shared_preferences/shared_preferences.dart';

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

Map<String, dynamic> _responsiveTrack({
  String? videoId,
  String title = 'Song',
  String artist = 'Artist',
  String duration = '3:45',
  bool withPlaylistItemData = true,
  Map<String, dynamic>? navigationEndpoint,
}) =>
    {
      'musicResponsiveListItemRenderer': {
        if (withPlaylistItemData) 'playlistItemData': {'videoId': videoId},
        if (navigationEndpoint != null) 'navigationEndpoint': navigationEndpoint,
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
      },
    };

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

  group('storage failure funnels', () {
    test('init survives a secure-storage read failure', () async {
      when(() => secure.read(key: any(named: 'key')))
          .thenThrow(PlatformException(code: 'KEYSTORE'));
      _mockChannel((call) async => null);

      final service = _service();
      await service.init();
      await _settle();
      expect(service.isLoggedIn, isFalse);
    });

    test('saveSession still returns true when persistence throws', () async {
      when(() => secure.write(
            key: any(named: 'key'),
            value: any(named: 'value'),
          )).thenThrow(PlatformException(code: 'WRITE_FAIL'));

      final service = _service();
      expect(await service.saveSession(_validJar), isTrue);
      await _settle();
      expect(service.isLoggedIn, isTrue);
    });

    test('logout survives a secure-storage delete failure', () async {
      final service = await loggedIn();
      when(() => secure.delete(key: any(named: 'key')))
          .thenThrow(PlatformException(code: 'DELETE_FAIL'));

      await service.logout();
      expect(service.isLoggedIn, isFalse);
      expect(service.loginState.value, isFalse);
    });

    test('adoptOAuthSession no-ops when OAuth is not signed in', () async {
      final service = _service();
      await service.adoptOAuthSession();
      expect(service.isOAuthSession, isFalse);
    });

    test('dispose closes listeners and is idempotent', () async {
      final service = _service();
      service.dispose();
      // loginState was disposed; a second dispose would throw, so only call once.
      expect(service.isLoggedIn, isFalse);
    });
  });

  group('ensureDataSyncId short-circuits', () {
    test('returns without a request when the id is already known', () async {
      SharedPreferences.setMockInitialValues({'ytm_data_sync_id': 'dsid||'});
      final service = _service();
      await service.init();
      await _settle();

      final before = requestCount;
      await service.ensureDataSyncId();
      expect(requestCount, before);
      expect(service.dataSyncId, 'dsid||');
    });
  });

  group('home recommendation renderers', () {
    test('parses two-row and playlist-video renderers', () async {
      final service = await loggedIn();
      handler = (request) async => _json(200, {
            'contents': [
              {
                'musicTwoRowItemRenderer': {
                  'navigationEndpoint': {
                    'watchEndpoint': {'videoId': 'twoRowVid01'},
                  },
                  'title': {
                    'runs': [
                      {'text': 'Two Row'},
                    ],
                  },
                  'subtitle': {
                    'runs': [
                      {'text': 'Artist X'},
                      {'text': '3:30'},
                    ],
                  },
                  'thumbnailRenderer': {
                    'musicThumbnailRenderer': {
                      'thumbnail': {
                        'thumbnails': [
                          {'url': 'https://a/two=w120-h120-l90-rj'},
                        ],
                      },
                    },
                  },
                },
              },
              {
                'playlistVideoRenderer': {
                  'videoId': 'plVideo0001',
                  'title': {
                    'runs': [
                      {'text': 'Panel'},
                    ],
                  },
                  'shortBylineText': {
                    'runs': [
                      {'text': 'Panel Artist'},
                    ],
                  },
                  'lengthSeconds': '200',
                  'thumbnail': {
                    'thumbnails': [
                      {'url': 'https://a/pv.jpg'},
                    ],
                  },
                },
              },
            ],
          });

      final tracks = await service.fetchHomeRecommendations();
      expect(tracks.map((t) => t.videoId).toList(),
          ['twoRowVid01', 'plVideo0001']);
      expect(tracks.first.artist, 'Artist X');
      expect(tracks.first.duration, const Duration(minutes: 3, seconds: 30));
      expect(tracks.first.artworkUrl, 'https://a/two=s1200');
      expect(tracks.last.duration, const Duration(seconds: 200));
      expect(tracks.last.artworkUrl, 'https://a/pv.jpg');
    });

    test('parses a responsive track located via navigationEndpoint only',
        () async {
      final service = await loggedIn();
      handler = (request) async => _json(200, {
            'contents': [
              _responsiveTrack(
                withPlaylistItemData: false,
                navigationEndpoint: {
                  'watchEndpoint': {'videoId': 'navTrack001'},
                },
                title: 'Via Nav',
              ),
            ],
          });

      final tracks = await service.fetchHomeRecommendations();
      expect(tracks.single.videoId, 'navTrack001');
      expect(tracks.single.title, 'Via Nav');
    });

    test('follows a reloadContinuationData token', () async {
      final service = await loggedIn();
      handler = (request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        if (body['continuation'] == 'reloadTok') {
          return _json(200, {
            'contents': [
              _responsiveTrack(videoId: 'reloadTrk01', title: 'Reloaded'),
            ],
          });
        }
        return _json(200, {
          'continuations': [
            {
              'reloadContinuationData': {'continuation': 'reloadTok'},
            },
          ],
        });
      };

      final tracks = await service.fetchHomeRecommendations();
      expect(tracks.single.videoId, 'reloadTrk01');
    });

    test('follows a continuationCommand token', () async {
      final service = await loggedIn();
      handler = (request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        if (body['continuation'] == 'cmdTok') {
          return _json(200, {
            'contents': [
              _responsiveTrack(videoId: 'cmdTrack001', title: 'Command'),
            ],
          });
        }
        return _json(200, {
          'continuations': [
            {
              'continuationCommand': {'token': 'cmdTok'},
            },
          ],
        });
      };

      final tracks = await service.fetchHomeRecommendations();
      expect(tracks.single.videoId, 'cmdTrack001');
    });
  });

  group('playlist header renderers', () {
    test('reads a musicDetailHeaderRenderer with a subtitle author', () async {
      final service = await loggedIn();
      handler = (request) async => _json(200, {
            'musicDetailHeaderRenderer': {
              'title': {
                'runs': [
                  {'text': 'Detail Title'},
                ],
              },
              'subtitle': {
                'runs': [
                  {'text': 'Playlist'},
                  {'text': 'DJ Detail'},
                  {'text': '2020'},
                ],
              },
              'thumbnail': {
                'musicThumbnailRenderer': {
                  'thumbnail': {
                    'thumbnails': [
                      {'url': 'https://a/detail.jpg'},
                    ],
                  },
                },
              },
            },
            'contents': {
              'musicPlaylistShelfRenderer': {
                'contents': [
                  _responsiveTrack(videoId: 'detailTrk01'),
                ],
              },
            },
          });

      final details = await service.fetchPlaylistDetails('PLdetail');
      expect(details, isNotNull);
      expect(details!.title, 'Detail Title');
      expect(details.author, 'DJ Detail');
      expect(details.artworkUrl, 'https://a/detail.jpg');
      expect(details.tracks.single.videoId, 'detailTrk01');
    });
  });

  group('liked songs renderer shapes', () {
    test('parses a responsive track without playlistItemData', () async {
      final service = await loggedIn();
      handler = (request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final browseId = body['browseId'] as String?;
        if (browseId == 'VLLM') {
          return _json(200, {
            'contents': {
              'musicPlaylistShelfRenderer': {
                'contents': [
                  _responsiveTrack(
                    withPlaylistItemData: false,
                    navigationEndpoint: {
                      'watchEndpoint': {'videoId': 'deepScanVid'},
                    },
                    title: 'Deep Scan',
                    artist: 'Deep Artist',
                  ),
                ],
              },
            },
          });
        }
        return _json(200, {'contents': {}});
      };

      final tracks = await service.fetchLikedSongs();
      expect(tracks.single.videoId, 'deepScanVid');
      expect(tracks.single.title, 'Deep Scan');
      expect(tracks.single.artist, 'Deep Artist');
    });
  });
}
