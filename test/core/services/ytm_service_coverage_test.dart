// test/core/services/ytm_service_coverage_test.dart
//
// Remaining-branch coverage for YtmService: the search hedge/fallback, the
// Dart InnerTube search parser, the account/native stream-tier arbitration,
// the pure-Dart player fallback quality selection, coalescing and the failure
// ledger edge cases. Channels and the Dart HTTP client are fully stubbed.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/di/injection.dart';
import 'package:pulsr/core/services/ytm_account_service.dart';
import 'package:pulsr/core/services/ytm_browse_service.dart';
import 'package:pulsr/core/services/ytm_client_version_resolver.dart';
import 'package:pulsr/core/services/ytm_service.dart';
import 'package:pulsr/core/services/ytm_url_cache.dart';
import 'package:pulsr/core/telemetry/clock.dart';
import 'package:pulsr/core/utils/ytm_rate_limiter.dart';
import 'package:pulsr/domain/models/ytm_track.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockYtmAccountService extends Mock implements YtmAccountService {}

class MockYtmClientVersionResolver extends Mock
    implements YtmClientVersionResolver {}

class MockYtmBrowseService extends Mock implements YtmBrowseService {}

const _channel = MethodChannel(YtmService.channelName);

late List<YtmService> services;
late Future<Object?> Function(MethodCall call) channelHandler;
late List<MethodCall> channelCalls;

void _mockChannel(Future<Object?> Function(MethodCall call)? handler) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, handler);
}

YtmService _newService() {
  final service = YtmService();
  services.add(service);
  return service;
}

Map<String, Object?> _resultRow({String videoId = 'dQw4w9WgXcQ'}) => {
      'videoId': videoId,
      'title': 'Title',
      'artist': 'Artist',
      'durationMs': 1000,
    };

Map<String, Object?> _streamRow({String videoId = 'dQw4w9WgXcQ'}) => {
      'videoId': videoId,
      'url': 'https://example.com/stream.m4a',
      'mimeType': 'audio/mp4',
      'container': 'm4a',
      'bitrateKbps': 128,
      'durationMs': 1000,
      'title': 'T',
      'artist': 'A',
    };

Map<String, dynamic> _playerBody({
  String status = 'OK',
  List<Map<String, Object?>> adaptive = const [],
  List<Map<String, Object?>> formats = const [],
  bool includeStreaming = true,
}) =>
    {
      'playabilityStatus': {'status': status},
      if (includeStreaming)
        'streamingData': {
          'adaptiveFormats': adaptive,
          'formats': formats,
        },
      'videoDetails': {'title': 'Title', 'author': 'Artist'},
    };

Map<String, Object?> _audioFormat({
  String mimeType = 'audio/mp4',
  int bitrate = 128000,
}) =>
    {
      'mimeType': mimeType,
      'bitrate': bitrate,
      'approxDurationMs': '1000',
      'url': 'https://x/$bitrate.m4a',
    };

http.Response _json(Map<String, dynamic> body, [int status = 200]) =>
    http.Response(jsonEncode(body), status,
        headers: {'content-type': 'application/json'});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await getIt.reset();
    YtmRateLimiter.debugReset();
    services = [];
    channelCalls = [];
    channelHandler = (call) async => null;
    _mockChannel((call) {
      channelCalls.add(call);
      return channelHandler(call);
    });
  });

  tearDown(() async {
    for (final service in services) {
      try {
        service.dispose();
      } catch (_) {}
    }
    _mockChannel(null);
    await getIt.reset();
  });

  group('failure ledger edge cases', () {
    test('a bot failure with no video id still trips the global cooldown', () {
      final service = _newService();
      service.recordFailure('', const YtmException('BOT_CHALLENGE'));
      expect(service.isBotCoolingDown, isTrue);
    });

    test('debugClearBotCooldown(null) clears every ledger', () {
      final service = _newService();
      service.recordFailure('vid1', const YtmException('BOT_CHALLENGE'));
      service.recordFailure('vid2', const YtmException('YTM_FAILED'));
      service.debugClearBotCooldown();
      expect(service.isBotCoolingDown, isFalse);
      expect(service.isVideoCoolingDown('vid1'), isFalse);
    });

    test('notifyAuthExpired after dispose is a no-op', () {
      final service = _newService();
      service.dispose();
      service.notifyAuthExpired();
    });

    test('dispose swallows a client close failure', () {
      final service = _newService();
      service.debugHttpClient = _ThrowingCloseClient();
      service.dispose();
    });
  });

  group('searchWithFallback', () {
    test('a non-empty native answer wins without starting the fallback',
        () async {
      channelHandler = (call) async =>
          call.method == 'search' ? [_resultRow()] : null;
      final service = _newService();
      var httpCalls = 0;
      service.debugHttpClient = MockClient((_) async {
        httpCalls++;
        return _json(_playerBody());
      });
      final results = await service.searchWithFallback('query');
      expect(results.single.videoId, 'dQw4w9WgXcQ');
      expect(httpCalls, 0);
    });

    test('an empty native answer promotes the Dart fallback', () async {
      channelHandler = (call) async => call.method == 'search' ? const [] : null;
      final service = _newService();
      service.debugHttpClient = MockClient((_) async => _json({
            'contents': {
              'a': {
                'musicResponsiveListItemRenderer': {
                  'playlistItemData': {'videoId': 'ABCDEFGHIJK'},
                  'flexColumns': [
                    {
                      'musicResponsiveListItemFlexColumnRenderer': {
                        'text': {
                          'runs': [
                            {'text': 'Fallback Title'}
                          ]
                        }
                      }
                    },
                    {
                      'musicResponsiveListItemFlexColumnRenderer': {
                        'text': {
                          'runs': [
                            {'text': 'Fallback Artist'}
                          ]
                        }
                      }
                    },
                  ],
                  'thumbnail': {
                    'musicThumbnailRenderer': {
                      'thumbnail': {
                        'thumbnails': [
                          {'url': 'small.jpg', 'width': 10, 'height': 10},
                          {'url': 'big.jpg', 'width': 480, 'height': 360},
                        ]
                      }
                    }
                  },
                }
              }
            }
          }));
      final results = await service.searchWithFallback('query');
      expect(results.single.videoId, 'ABCDEFGHIJK');
      expect(results.single.title, 'Fallback Title');
      expect(results.single.artist, 'Fallback Artist');
      expect(results.single.artworkUrl, 'big.jpg');
    });

    test('a native throw also promotes the fallback', () async {
      channelHandler = (call) async {
        if (call.method == 'search') throw PlatformException(code: 'YTM_FAILED');
        return null;
      };
      final service = _newService();
      service.debugHttpClient = MockClient((_) async => _json(_playerBody()));
      final results = await service.searchWithFallback('query');
      expect(results, isEmpty);
    });
  });

  group('Dart InnerTube search parser', () {
    Future<List<dynamic>> fallbackSearch(
        Map<String, dynamic> Function(String body) build) async {
      channelHandler = (call) async => call.method == 'search' ? const [] : null;
      final service = _newService();
      service.debugHttpClient = MockClient((_) async => _json(build('')));
      return service.searchWithFallback('query');
    }

    test('reads a two-row renderer and filters subtitle separators', () async {
      final results = await fallbackSearch((_) => {
            'contents': {
              'x': {
                'musicTwoRowItemRenderer': {
                  'navigationEndpoint': {
                    'watchEndpoint': {'videoId': 'ABCDEFGHIJK'}
                  },
                  'title': {
                    'runs': [
                      {'text': 'Row Title'}
                    ]
                  },
                  'subtitle': {
                    'runs': [
                      {'text': '•'},
                      {'text': 'Song'},
                      {'text': 'Real Artist'},
                    ]
                  },
                  'thumbnailRenderer': {
                    'musicThumbnailRenderer': {
                      'thumbnail': {
                        'thumbnails': [
                          {'url': 'row.jpg', 'width': 5, 'height': 5}
                        ]
                      }
                    }
                  },
                }
              }
            }
          });
      expect(results.single.videoId, 'ABCDEFGHIJK');
      expect(results.single.title, 'Row Title');
      expect(results.single.artist, 'Real Artist');
    });

    test('falls back to the watch endpoint in the title run', () async {
      final results = await fallbackSearch((_) => {
            'contents': {
              'x': {
                'musicResponsiveListItemRenderer': {
                  'flexColumns': [
                    {
                      'musicResponsiveListItemFlexColumnRenderer': {
                        'text': {
                          'runs': [
                            {
                              'text': 'Only Title',
                              'navigationEndpoint': {
                                'watchEndpoint': {'videoId': 'ABCDEFGHIJK'}
                              },
                            }
                          ]
                        }
                      }
                    },
                  ],
                }
              }
            }
          });
      expect(results.single.videoId, 'ABCDEFGHIJK');
      expect(results.single.artist, 'Unknown Artist');
    });

    test('a 429 response feeds the shared rate limiter', () async {
      channelHandler = (call) async => call.method == 'search' ? const [] : null;
      final service = _newService();
      service.debugHttpClient = MockClient((_) async =>
          http.Response('', 429, headers: {'retry-after': '7'}));
      await service.searchWithFallback('query');
      expect(YtmRateLimiter.shared.isCoolingDown, isTrue);
    });

    test('malformed JSON is swallowed and yields no fallback results',
        () async {
      channelHandler = (call) async => call.method == 'search' ? const [] : null;
      final service = _newService();
      service.debugHttpClient =
          MockClient((_) async => http.Response('not json', 200));
      expect(await service.searchWithFallback('query'), isEmpty);
    });
  });

  group('getPlaylistTracks', () {
    test('an account failure falls through to the native alias', () async {
      final account = MockYtmAccountService();
      when(() => account.fetchPlaylistTracks(any(),
              maxTracks: any(named: 'maxTracks')))
          .thenThrow(const YtmException('YTM_FAILED'));
      getIt.registerSingleton<YtmAccountService>(account);
      channelHandler = (call) async => call.method == 'getPlaylist'
          ? {
              'tracks': [_streamRow()]
            }
          : null;

      final tracks = await _newService().getPlaylistTracks('LM');
      expect(tracks.single.videoId, 'dQw4w9WgXcQ');
      expect(channelCalls.last.arguments, {'url': 'LL', 'limit': 100});
    });

    test('a native failure degrades to an empty list', () async {
      channelHandler = (call) async => throw PlatformException(code: 'x');
      expect(await _newService().getPlaylistTracks('PLabc'), isEmpty);
    });
  });

  group('resolveStream arbitration', () {
    test('coalesces concurrent identical resolves into one native chain',
        () async {
      final gate = Completer<Object?>();
      channelHandler = (call) async {
        if (call.method == 'resolveStream') return gate.future;
        return null;
      };
      final service = _newService();
      final first = service.resolveStream('coalesce001');
      final second = service.resolveStream('coalesce001');
      gate.complete(_streamRow(videoId: 'coalesce001'));
      final results = await Future.wait([first, second]);
      expect(results.every((s) => s.url == 'https://example.com/stream.m4a'),
          isTrue);
      expect(
        channelCalls.where((c) => c.method == 'resolveStream').length,
        1,
      );
    });

    test('forceRefresh bypasses the cache and coalescing', () async {
      final cache = YtmUrlCache.withClock(FakeClock(DateTime(2026)));
      getIt.registerSingleton<YtmUrlCache>(cache);
      cache.putStream(
        YtmStream(
          videoId: 'forceRefresh',
          url: 'https://stale.example/a.m4a',
          mimeType: 'audio/mp4',
          container: 'm4a',
          bitrateKbps: 128,
          duration: const Duration(minutes: 3),
          title: 't',
          artist: 'a',
          expiresAt: DateTime.now()
              .add(const Duration(hours: 2))
              .millisecondsSinceEpoch,
        ),
        quality: 'high',
      );
      channelHandler = (call) async =>
          call.method == 'resolveStream' ? _streamRow() : null;
      final stream = await _newService()
          .resolveStream('forceRefresh', forceRefresh: true);
      expect(stream.url, 'https://example.com/stream.m4a');
      expect(cache.get('forceRefresh'), isNull);
    });

    test('coalesce:false performs an independent resolve', () async {
      channelHandler = (call) async =>
          call.method == 'resolveStream' ? _streamRow() : null;
      final service = _newService();
      final a = service.resolveStream('indep000001', coalesce: false);
      final b = service.resolveStream('indep000001', coalesce: false);
      await Future.wait([a, b]);
      expect(
        channelCalls.where((c) => c.method == 'resolveStream').length,
        2,
      );
    });
  });

  group('account tier', () {
    test('a logged-in account serves the stream (guest pass bootstrap)',
        () async {
      final account = MockYtmAccountService();
      when(() => account.isLoggedIn).thenReturn(true);
      when(() => account.dataSyncId).thenReturn(null);
      when(() => account.ensureDataSyncId()).thenAnswer((_) async {});
      when(() => account.resolvePlayerStream(any(),
              quality: any(named: 'quality')))
          .thenAnswer((_) async => YtmStream(
                videoId: 'account0001',
                url: 'https://account.example/a.m4a',
                mimeType: 'audio/mp4',
                container: 'm4a',
                bitrateKbps: 256,
                duration: const Duration(minutes: 3),
                title: 't',
                artist: 'a',
              ));
      getIt.registerSingleton<YtmAccountService>(account);

      final stream = await _newService().resolveStream('account0001');
      expect(stream.url, 'https://account.example/a.m4a');
      verify(() => account.ensureDataSyncId()).called(1);
    });

    test('an auth failure in the account tier falls back to native', () async {
      final account = MockYtmAccountService();
      when(() => account.isLoggedIn).thenReturn(true);
      when(() => account.dataSyncId).thenReturn('dsid||');
      when(() => account.resolvePlayerStream(any(),
              quality: any(named: 'quality')))
          .thenThrow(const YtmException('YTM_AUTH'));
      getIt.registerSingleton<YtmAccountService>(account);
      channelHandler = (call) async =>
          call.method == 'resolveStream' ? _streamRow() : null;

      final stream = await _newService().resolveStream('authfail001');
      expect(stream.url, 'https://example.com/stream.m4a');
    });
  });

  group('pure-Dart player fallback', () {
    test('quality low picks the smallest bitrate', () async {
      channelHandler = (_) async => null;
      final service = _newService();
      service.debugHttpClient = MockClient((_) async => _json(_playerBody(
            adaptive: [
              _audioFormat(bitrate: 64000),
              _audioFormat(bitrate: 128000),
              _audioFormat(bitrate: 320000),
            ],
          )));
      final stream = await service.resolveStream('lowquality1', quality: 'low');
      expect(stream.bitrateKbps, 64);
    });

    test('quality medium picks the bitrate nearest 128k', () async {
      channelHandler = (_) async => null;
      final service = _newService();
      service.debugHttpClient = MockClient((_) async => _json(_playerBody(
            adaptive: [
              _audioFormat(bitrate: 64000),
              _audioFormat(bitrate: 96000),
              _audioFormat(bitrate: 320000),
            ],
          )));
      final stream =
          await service.resolveStream('medquality1', quality: 'medium');
      expect(stream.bitrateKbps, 96);
    });

    test('an embed client is used when the first clients fail', () async {
      channelHandler = (_) async => null;
      final service = _newService();
      service.debugHttpClient = MockClient((request) async {
        final ua = request.headers['User-Agent'] ?? '';
        if (ua.contains('PlayStation')) {
          return _json(_playerBody(adaptive: [_audioFormat(bitrate: 192000)]));
        }
        return http.Response('nope', 500);
      });
      final stream = await service.resolveStream('embedclient');
      expect(stream.bitrateKbps, 192);
    });

    test('an unexpected payload shape collapses to YTM_FAILED', () async {
      channelHandler = (_) async => null;
      final service = _newService();
      service.debugHttpClient =
          MockClient((_) async => _json(_playerBody(includeStreaming: false)));
      await expectLater(
        service.resolveStream('nostream001'),
        throwsA(
            isA<YtmException>().having((e) => e.code, 'code', 'YTM_FAILED')),
      );
    });

    test('a payload with no audio formats collapses to YTM_FAILED', () async {
      channelHandler = (_) async => null;
      final service = _newService();
      service.debugHttpClient = MockClient((_) async => _json(_playerBody()));
      await expectLater(
        service.resolveStream('noformats01'),
        throwsA(isA<YtmException>()),
      );
    });

    test('a registered version resolver feeds the Dart client headers',
        () async {
      final resolver = MockYtmClientVersionResolver();
      when(() => resolver.apiKey).thenReturn('key-1');
      when(() => resolver.clientVersion).thenReturn('1.2.3');
      when(() => resolver.androidVersion).thenReturn('19.0');
      when(() => resolver.androidVrVersion).thenReturn('1.60');
      getIt.registerSingleton<YtmClientVersionResolver>(resolver);
      channelHandler = (_) async => null;

      final service = _newService();
      service.debugHttpClient = MockClient((request) async {
        expect(request.headers['X-Goog-Api-Key'], 'key-1');
        return _json(_playerBody(adaptive: [_audioFormat(bitrate: 128000)]));
      });
      final stream = await service.resolveStream('resolver001');
      expect(stream.bitrateKbps, 128);
    });

    test('the InnerTube search path reads account visitor data and cookies',
        () async {
      final account = MockYtmAccountService();
      when(() => account.sessionVisitorData).thenReturn('visitor-1');
      when(() => account.isLoggedIn).thenReturn(true);
      when(() => account.cookies).thenReturn('SAPISID=abc; SID=def');
      getIt.registerSingleton<YtmAccountService>(account);
      channelHandler = (call) async => call.method == 'search' ? const [] : null;

      final service = _newService();
      service.debugHttpClient = MockClient((request) async {
        expect(request.headers['X-Goog-Visitor-Id'], 'visitor-1');
        expect(request.headers['Cookie'], contains('SAPISID'));
        return _json(_playerBody());
      });
      await service.searchWithFallback('query');
    });
  });

  group('_guard retry', () {
    test('a transient platform error is retried once before succeeding',
        () async {
      var attempts = 0;
      channelHandler = (call) async {
        if (call.method == 'search') {
          attempts++;
          if (attempts == 1) throw PlatformException(code: 'TRANSIENT');
          return [_resultRow()];
        }
        return null;
      };
      final tracks = await _newService().search('query');
      expect(tracks.single.videoId, 'dQw4w9WgXcQ');
      expect(attempts, 2);
    });
  });
}

class _ThrowingCloseClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    throw StateError('unused');
  }

  @override
  void close() => throw StateError('close failed');
}
