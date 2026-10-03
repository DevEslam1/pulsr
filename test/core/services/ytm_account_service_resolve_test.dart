// test/core/services/ytm_account_service_resolve_test.dart
//
// resolvePlayerStream(): the multi-client Dart player chain, quality
// selection, SABR demotion, the guest-pass demotion when no account-bound
// poToken can be minted, and the IP/bot short-circuit. The Innertube client
// is a scripted MockClient; every YtmService collaborator is a mock.
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
late List<http.Request> requests;

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

String _clientName(http.Request request) {
  final body = jsonDecode(request.body) as Map<String, dynamic>;
  final context = body['context'] as Map<String, dynamic>;
  return (context['client'] as Map<String, dynamic>)['clientName'] as String;
}

Map<String, dynamic> _format({
  required String url,
  String mimeType = 'audio/mp4',
  int bitrate = 128000,
  String approxDurationMs = '200000',
  bool cipher = false,
}) =>
    {
      'mimeType': mimeType,
      'bitrate': bitrate,
      'itag': 140,
      'approxDurationMs': approxDurationMs,
      if (cipher) 'signatureCipher': 's=xyz&url=$url' else 'url': url,
    };

http.Response _playerOk({
  required List<Map<String, dynamic>> formats,
  String title = 'Track',
  String artist = 'Artist',
}) =>
    _json(200, {
      'playabilityStatus': {'status': 'OK'},
      'streamingData': {'adaptiveFormats': formats},
      'videoDetails': {'title': title, 'author': artist},
    });

http.Response _playability(String status, {String reason = 'no reason'}) =>
    _json(200, {
      'playabilityStatus': {'status': status, 'reason': reason},
    });

YtmAccountService _service() {
  return YtmAccountService(YtmClientVersionResolver())
    ..debugInnertubeClient = MockClient((request) {
      requests.add(request);
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
  when(() => ytm.getPlayerPoToken(any())).thenAnswer((_) async => 'player-tok');
  when(() => ytm.getPoTokenState()).thenAnswer((_) async => {
        'streamingPoToken': 'guest-stream-tok',
        'visitorData': 'guest-visitor',
      });
  when(() => ytm.getAccountPoToken(any())).thenAnswer((_) async => {
        'poToken': 'account-tok',
        'visitorData': 'account-visitor',
      });
  when(() => ytm.clearNativeSession()).thenAnswer((_) async {});
  when(() => ytm.notifyAuthExpired()).thenReturn(null);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await getIt.reset();
    YtmRateLimiter.debugReset();
    requests = <http.Request>[];
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

  Future<YtmAccountService> loggedIn({String? dataSyncId}) async {
    SharedPreferences.setMockInitialValues(
        dataSyncId == null ? {} : {'ytm_data_sync_id': dataSyncId});
    final service = _service();
    await service.init();
    await _settle();
    return service;
  }

  group('authenticated WEB_REMIX resolve', () {
    test('returns the highest-bitrate m4a with session cookies and expiry',
        () async {
      final service = await loggedIn(dataSyncId: 'dsid||');
      handler = (request) async {
        if (_clientName(request) == 'WEB_REMIX') {
          return _playerOk(
            formats: [
              _format(
                url:
                    'https://rr1---sn-x.googlevideo.com/videoplayback?expire=1800000000&mime=audio%2Fmp4',
                bitrate: 128000,
              ),
              _format(
                url:
                    'https://rr2---sn-y.googlevideo.com/videoplayback?expire=1800000000&mime=audio%2Fmp4',
                bitrate: 256000,
              ),
              _format(
                url:
                    'https://rr3---sn-z.googlevideo.com/videoplayback?expire=1800000000&mime=audio%2Fwebm',
                mimeType: 'audio/webm; codecs=opus',
                bitrate: 160000,
              ),
            ],
            title: 'High Res',
            artist: 'Uploader',
          );
        }
        return _playability('UNPLAYABLE');
      };

      final stream = await service.resolvePlayerStream('dQw4w9WgXcQ');

      expect(stream, isNotNull);
      expect(stream!.videoId, 'dQw4w9WgXcQ');
      expect(stream.bitrateKbps, 256);
      expect(stream.container, 'm4a');
      expect(stream.mimeType, 'audio/mp4');
      expect(stream.title, 'High Res');
      expect(stream.artist, 'Uploader');
      expect(stream.cookies, _validJar);
      expect(stream.userAgent, isNotNull);
      expect(stream.expiresAt, 1800000000000);

      final webRequest = requests.firstWhere((r) =>
          r.url.path.contains('/player') && _clientName(r) == 'WEB_REMIX');
      expect(webRequest.headers['Cookie'], _validJar);
      expect(webRequest.headers['Authorization'], startsWith('SAPISIDHASH '));
      expect(webRequest.headers['x-goog-authuser'], '0');
      final body = jsonDecode(webRequest.body) as Map<String, dynamic>;
      expect(
        (body['serviceIntegrityDimensions'] as Map)['poToken'],
        'account-tok',
      );
      final playback =
          (body['playbackContext'] as Map)['contentPlaybackContext'] as Map;
      expect(playback['poToken'], 'account-tok');
      final client = (body['context'] as Map)['client'] as Map<String, dynamic>;
      expect(client['visitorData'], 'account-visitor');
      verify(() => ytm.getAccountPoToken('dsid||')).called(1);
    });

    test('low quality picks the lowest bitrate m4a', () async {
      final service = await loggedIn(dataSyncId: 'dsid||');
      handler = (request) async => _playerOk(formats: [
            _format(url: 'https://x/1?expire=1800000000', bitrate: 64000),
            _format(url: 'https://x/2?expire=1800000000', bitrate: 128000),
            _format(url: 'https://x/3?expire=1800000000', bitrate: 320000),
          ]);

      final stream =
          await service.resolvePlayerStream('dQw4w9WgXcQ', quality: 'low');
      expect(stream!.bitrateKbps, 64);
    });

    test('medium quality picks the bitrate closest to 128k', () async {
      final service = await loggedIn(dataSyncId: 'dsid||');
      handler = (request) async => _playerOk(formats: [
            _format(url: 'https://x/1?expire=1800000000', bitrate: 64000),
            _format(url: 'https://x/2?expire=1800000000', bitrate: 192000),
            _format(url: 'https://x/3?expire=1800000000', bitrate: 320000),
          ]);

      final stream =
          await service.resolvePlayerStream('dQw4w9WgXcQ', quality: 'medium');
      expect(stream!.bitrateKbps, 192);
    });

    test('ciphered formats are skipped and the client is demoted', () async {
      final service = await loggedIn(dataSyncId: 'dsid||');
      handler = (request) async {
        switch (_clientName(request)) {
          case 'WEB_REMIX':
            return _playerOk(formats: [
              _format(
                url: 'https://x/cipher?expire=1800000000',
                cipher: true,
              ),
            ]);
          case 'ANDROID_VR':
            return _playerOk(formats: [
              _format(url: 'https://x/guest?expire=1800000000'),
            ]);
          default:
            return _playability('UNPLAYABLE');
        }
      };

      final first = await service.resolvePlayerStream('dQw4w9WgXcQ');
      expect(first!.url, 'https://x/guest?expire=1800000000');

      // The demotion puts WEB_REMIX at the tail for the next 10 minutes.
      requests.clear();
      handler = (request) async {
        if (_clientName(request) == 'ANDROID_VR') {
          return _playerOk(formats: [
            _format(url: 'https://x/guest2?expire=1800000000'),
          ]);
        }
        return _playability('UNPLAYABLE');
      };
      final second = await service.resolvePlayerStream('dQw4w9WgXcQ');
      expect(second!.url, 'https://x/guest2?expire=1800000000');
      expect(_clientName(requests.first), 'ANDROID_VR');
      expect(requests.map(_clientName), isNot(contains('WEB_REMIX')),
          reason: 'the demoted client is tried last, after a success wins');
    });
  });

  group('guest pass demotion', () {
    test('a missing dataSyncId drops the session cookies for Tier-1', () async {
      // The home browse used for restore validation deliberately carries no
      // datasyncId, so the service stays signed in but account-unbound.
      handler = (request) async => _json(200, {
            'contents': {
              'singleColumnBrowseResultsRenderer': {},
            },
          });
      final service = _service();
      await service.init();
      await _settle();
      expect(service.isLoggedIn, isTrue);
      expect(service.dataSyncId, isNull);

      requests.clear();
      handler = (request) async {
        if (_clientName(request) == 'ANDROID_VR') {
          return _playerOk(formats: [
            _format(url: 'https://x/guest?expire=1800000000'),
          ]);
        }
        return _playability('UNPLAYABLE');
      };

      final stream = await service.resolvePlayerStream('dQw4w9WgXcQ');

      expect(stream, isNotNull);
      expect(stream!.cookies, isNull);
      verify(() => ytm.getPlayerPoToken('dQw4w9WgXcQ'))
          .called(greaterThanOrEqualTo(1));
      final guestRequest =
          requests.firstWhere((r) => _clientName(r) == 'ANDROID_VR');
      expect(guestRequest.headers.containsKey('Cookie'), isFalse);
      expect(guestRequest.headers['X-Goog-Visitor-Id'], 'guest-visitor');
      final body = jsonDecode(guestRequest.body) as Map<String, dynamic>;
      expect(
        body.containsKey('serviceIntegrityDimensions'),
        isFalse,
        reason: 'only web-shaped clients use serviceIntegrityDimensions',
      );
      final playback =
          (body['playbackContext'] as Map)['contentPlaybackContext'] as Map;
      expect(playback['poToken'], 'guest-stream-tok');
    });

    test('an empty account mint demotes the pass to guest', () async {
      when(() => ytm.getAccountPoToken(any())).thenAnswer((_) async => null);
      final service = await loggedIn(dataSyncId: 'dsid||');
      handler = (request) async {
        if (_clientName(request) == 'ANDROID_VR') {
          return _playerOk(formats: [
            _format(url: 'https://x/guest?expire=1800000000'),
          ]);
        }
        return _playability('UNPLAYABLE');
      };

      final stream = await service.resolvePlayerStream('dQw4w9WgXcQ');
      expect(stream, isNotNull);
      expect(stream!.cookies, isNull);
      verify(() => ytm.getPlayerPoToken(any())).called(greaterThanOrEqualTo(1));
    });

    test('a throwing account mint demotes the pass to guest', () async {
      when(() => ytm.getAccountPoToken(any()))
          .thenThrow(PlatformException(code: 'no_botguard'));
      final service = await loggedIn(dataSyncId: 'dsid||');
      handler = (request) async {
        if (_clientName(request) == 'ANDROID_VR') {
          return _playerOk(formats: [
            _format(url: 'https://x/guest?expire=1800000000'),
          ]);
        }
        return _playability('UNPLAYABLE');
      };

      final stream = await service.resolvePlayerStream('dQw4w9WgXcQ');
      expect(stream, isNotNull);
      expect(stream!.cookies, isNull);
    });
  });

  group('chain fallback and short-circuit', () {
    test('a non-blocking UNPLAYABLE walks the whole authenticated chain',
        () async {
      final service = await loggedIn(dataSyncId: 'dsid||');
      handler = (request) async => _playability('UNPLAYABLE');

      final stream = await service.resolvePlayerStream('dQw4w9WgXcQ');

      expect(stream, isNull);
      final playerRequests =
          requests.where((r) => r.url.path.contains('/player')).toList();
      expect(playerRequests, hasLength(9));
      expect(
        playerRequests.map(_clientName).toList(),
        [
          'WEB_REMIX',
          'ANDROID_VR',
          'ANDROID_MUSIC',
          'IOS_MUSIC',
          'TVHTML5_SIMPLY_EMBEDDED_PLAYER',
          'WEB_EMBEDDED_PLAYER',
          'MWEB',
          'ANDROID_CREATOR',
          'ANDROID_TESTSUITE',
        ],
      );
    });

    test('two guest LOGIN_REQUIRED answers short-circuit the chain', () async {
      final service = await loggedIn(dataSyncId: 'dsid||');
      handler = (request) async => _playability('LOGIN_REQUIRED');

      final stream = await service.resolvePlayerStream('dQw4w9WgXcQ');

      expect(stream, isNull);
      final playerRequests =
          requests.where((r) => r.url.path.contains('/player')).toList();
      expect(playerRequests, hasLength(3),
          reason: 'WEB_REMIX is session-bound and does not count as a guest '
              'block, so ANDROID_VR + ANDROID_MUSIC trip the threshold');
    });

    test('a bot-word reason counts as a block signal', () async {
      final service = await loggedIn(dataSyncId: 'dsid||');
      handler = (request) async => _playability('UNPLAYABLE',
          reason: 'Sign in to confirm you are not a bot');

      final stream = await service.resolvePlayerStream('dQw4w9WgXcQ');

      expect(stream, isNull);
      expect(
          requests.where((r) => r.url.path.contains('/player')), hasLength(2));
    });

    test('HTTP 429 then 403 short-circuits the chain', () async {
      final service = await loggedIn(dataSyncId: 'dsid||');
      var call = 0;
      handler = (request) async {
        call++;
        return _json(call == 1 ? 429 : 403, const {});
      };

      final stream = await service.resolvePlayerStream('dQw4w9WgXcQ');

      expect(stream, isNull);
      expect(
          requests.where((r) => r.url.path.contains('/player')), hasLength(2));
    });

    test('an auth exception from a client propagates instead of falling back',
        () async {
      final service = await loggedIn(dataSyncId: 'dsid||');
      handler = (request) async =>
          throw const YtmException('YTM_AUTH', 'session expired');

      await expectLater(
        service.resolvePlayerStream('dQw4w9WgXcQ'),
        throwsA(isA<YtmException>().having((e) => e.isAuth, 'isAuth', isTrue)),
      );
    });

    test('a logged-out service walks the guest chain and returns null',
        () async {
      // No cookies at init, so this is a pure guest service.
      SharedPreferences.setMockInitialValues({});
      _mockChannel((call) async => null);
      final service = _service();
      await service.init();
      await _settle();

      handler = (request) async => _playability('UNPLAYABLE');

      final stream = await service.resolvePlayerStream('dQw4w9WgXcQ');

      expect(stream, isNull);
      final playerRequests =
          requests.where((r) => r.url.path.contains('/player')).toList();
      expect(playerRequests, hasLength(9));
      expect(
        playerRequests.map(_clientName).toList(),
        [
          'ANDROID_VR',
          'TVHTML5_SIMPLY_EMBEDDED_PLAYER',
          'WEB_REMIX',
          'WEB_EMBEDDED_PLAYER',
          'MWEB',
          'ANDROID_MUSIC',
          'IOS_MUSIC',
          'ANDROID_CREATOR',
          'ANDROID_TESTSUITE',
        ],
      );
      // Embed clients need root-level thirdParty; web clients carry the
      // content-bound token in serviceIntegrityDimensions.
      final embed = playerRequests.firstWhere(
          (r) => _clientName(r) == 'TVHTML5_SIMPLY_EMBEDDED_PLAYER');
      final embedBody = jsonDecode(embed.body) as Map<String, dynamic>;
      expect(embedBody['thirdParty'], isNotNull);
      expect(
        (embedBody['context'] as Map)['thirdParty'],
        isNotNull,
      );
      final web =
          playerRequests.firstWhere((r) => _clientName(r) == 'WEB_REMIX');
      final webBody = jsonDecode(web.body) as Map<String, dynamic>;
      expect(
        (webBody['serviceIntegrityDimensions'] as Map)['poToken'],
        'player-tok',
      );
    });
  });

  group('YtmStream session binding', () {
    test('a stream resolved on the session is taggable m4a with cookies',
        () async {
      final service = await loggedIn(dataSyncId: 'dsid||');
      handler = (request) async => _playerOk(formats: [
            _format(url: 'https://x/a?expire=1800000000'),
          ]);

      final stream = await service.resolvePlayerStream(
        'dQw4w9WgXcQ',
      );
      expect(stream!.isTaggable, isTrue);
      expect(stream.expiresAtDateTime, isNotNull);
    });

    test('a resolved stream without an expire stamp keeps expiresAt null',
        () async {
      final service = await loggedIn(dataSyncId: 'dsid||');
      handler = (request) async => _playerOk(formats: [
            _format(url: 'https://x/no-stamp'),
          ]);

      final stream = await service.resolvePlayerStream('dQw4w9WgXcQ');
      expect(stream!.expiresAt, isNull);
    });
  });
}
