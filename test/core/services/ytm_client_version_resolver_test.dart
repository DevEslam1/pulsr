// Deterministic coverage for YtmClientVersionResolver: preference hydration,
// refresh parsing/fallbacks (mocked HTTP, no sockets) and native push wiring.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pulsr/core/constants/channels.dart';
import 'package:pulsr/core/services/ytm_client_version_resolver.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _versionKey = 'ytm_cached_client_version';
const _apiKeyKey = 'ytm_cached_api_key';
const _fetchTsKey = 'ytm_client_version_fetch_ts';
const _stsKey = 'ytm_cached_sts';

String _fullBody({
  String version = '1.20260101.01.00',
  String apiKey = 'AIzaSyMockKeyForUnitTests000000000',
  String sts = '54321',
}) =>
    '{"INNERTUBE_CONTEXT_CLIENT_VERSION":"$version",'
    '"INNERTUBE_API_KEY":"$apiKey","STS":$sts}';

Future<T> _withClient<T>(
  Future<T> Function() body,
  MockClient client,
) =>
    http.runWithClient(body, () => client);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel(PulsrChannels.ytm),
      null,
    );
  });

  group('static defaults', () {
    test('defaultDynamicVersion mirrors the current UTC date', () {
      final before = DateTime.now().toUtc();
      final value = YtmClientVersionResolver.defaultDynamicVersion;
      final after = DateTime.now().toUtc();

      expect(value, matches(RegExp(r'^1\.\d{8}\.01\.00$')));
      final datePart = value.split('.')[1];
      String stamp(DateTime d) => '${d.year.toString().padLeft(4, '0')}'
          '${d.month.toString().padLeft(2, '0')}'
          '${d.day.toString().padLeft(2, '0')}';
      expect(
        datePart == stamp(before) || datePart == stamp(after),
        isTrue,
        reason: 'version $value should be built from today UTC',
      );
    });

    test('fallback constants are non-empty', () {
      expect(YtmClientVersionResolver.fallbackClientVersion, isNotEmpty);
      expect(YtmClientVersionResolver.fallbackApiKey, isNotEmpty);
    });

    test('clientVersionFor maps every known client type', () {
      final resolver = YtmClientVersionResolver();
      expect(resolver.androidMusicVersion, isNotEmpty);
      expect(resolver.iosMusicVersion, isNotEmpty);
      expect(resolver.androidVrVersion, isNotEmpty);
      expect(resolver.androidVersion, isNotEmpty);
      expect(resolver.androidCreatorVersion, isNotEmpty);

      for (final type in ['WEB_REMIX', 'MWEB', 'WEB_EMBEDDED_PLAYER']) {
        expect(resolver.clientVersionFor(type), resolver.clientVersion,
            reason: type);
      }
      expect(resolver.clientVersionFor('ANDROID_MUSIC'),
          resolver.androidMusicVersion);
      expect(resolver.clientVersionFor('IOS_MUSIC'), resolver.iosMusicVersion);
      expect(
          resolver.clientVersionFor('ANDROID_VR'), resolver.androidVrVersion);
      expect(resolver.clientVersionFor('ANDROID'), resolver.androidVersion);
      expect(resolver.clientVersionFor('ANDROID_CREATOR'),
          resolver.androidCreatorVersion);
      expect(
          resolver.clientVersionFor('TVHTML5_SIMPLY_EMBEDDED_PLAYER'), '2.0');
      expect(resolver.clientVersionFor('ANDROID_TESTSUITE'), '1.9');
      expect(
          resolver.clientVersionFor('SOMETHING_ELSE'), resolver.clientVersion);
    });

    test('fresh resolver exposes fallback values and epoch-day STS', () {
      final resolver = YtmClientVersionResolver();
      expect(resolver.clientVersion,
          YtmClientVersionResolver.fallbackClientVersion);
      expect(resolver.apiKey, YtmClientVersionResolver.fallbackApiKey);
      final expectedDays =
          DateTime.now().toUtc().millisecondsSinceEpoch ~/ 86400000;
      expect((resolver.sts - expectedDays).abs(), lessThanOrEqualTo(1));
    });
  });

  group('init from preferences', () {
    test('fresh cached version/key/STS are applied without a refresh',
        () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      SharedPreferences.setMockInitialValues({
        _versionKey: '1.20251224.01.00',
        _apiKeyKey: 'cached-api-key',
        _fetchTsKey: now,
        _stsKey: 777,
      });
      var clientCalls = 0;
      final client = MockClient((request) async {
        clientCalls++;
        return http.Response(_fullBody(), 200);
      });

      final resolver = YtmClientVersionResolver();
      await _withClient(() async {
        await resolver.init();
        // Allow the fire-and-forget native push to run.
        await Future<void>.delayed(Duration.zero);
      }, client);

      expect(resolver.clientVersion, '1.20251224.01.00');
      expect(resolver.apiKey, 'cached-api-key');
      expect(resolver.sts, 777);
      expect(clientCalls, 0);

      // A second init is a no-op and keeps the already-hydrated values.
      await resolver.init();
      expect(resolver.clientVersion, '1.20251224.01.00');
    });

    test('empty cached version falls back but keeps the cached api key',
        () async {
      SharedPreferences.setMockInitialValues({
        _versionKey: '',
        _apiKeyKey: 'kept-key',
        _fetchTsKey: DateTime.now().millisecondsSinceEpoch,
        _stsKey: 0,
      });

      final resolver = YtmClientVersionResolver();
      await _withClient(() async {
        await resolver.init();
        await Future<void>.delayed(Duration.zero);
      }, MockClient((_) async => http.Response('', 200)));

      expect(resolver.clientVersion,
          YtmClientVersionResolver.fallbackClientVersion);
      expect(resolver.apiKey, 'kept-key');
      // STS 0 is ignored, so the epoch-day default is used.
      final expectedDays =
          DateTime.now().toUtc().millisecondsSinceEpoch ~/ 86400000;
      expect((resolver.sts - expectedDays).abs(), lessThanOrEqualTo(1));
    });

    test('stale cache falls back and refreshes from the network', () async {
      final longAgo = DateTime.now()
          .subtract(const Duration(days: 40))
          .millisecondsSinceEpoch;
      SharedPreferences.setMockInitialValues({
        _versionKey: '1.20200101.01.00',
        _apiKeyKey: 'stale-key',
        _fetchTsKey: longAgo,
        _stsKey: 5,
      });

      final resolver = YtmClientVersionResolver();
      await _withClient(() async {
        await resolver.init();
        // Let the unawaited refresh complete against the mock client.
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }, MockClient((_) async => http.Response(_fullBody(), 200)));

      expect(resolver.clientVersion, '1.20260101.01.00');
      expect(resolver.apiKey, 'AIzaSyMockKeyForUnitTests000000000');
      expect(resolver.sts, 54321);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(_versionKey), '1.20260101.01.00');
      expect(prefs.getString(_apiKeyKey), 'AIzaSyMockKeyForUnitTests000000000');
      expect(prefs.getInt(_stsKey), 54321);
      expect(prefs.getInt(_fetchTsKey), isNotNull);
    });

    test('missing cache refreshes and pushes the version to native', () async {
      SharedPreferences.setMockInitialValues({});
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel(PulsrChannels.ytm),
        (call) async {
          calls.add(call);
          return true;
        },
      );

      final resolver = YtmClientVersionResolver();
      await _withClient(() async {
        await resolver.init();
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }, MockClient((_) async => http.Response(_fullBody(), 200)));

      expect(resolver.clientVersion, '1.20260101.01.00');
      final pushes = calls
          .where((c) => c.method == 'setClientVersion')
          .map((c) => (c.arguments as Map)['clientVersion'])
          .toList();
      expect(pushes, contains('1.20260101.01.00'));
    });
  });

  group('refresh parsing', () {
    test('uses the fallback clientVersion/innertubeApiKey/STS patterns',
        () async {
      SharedPreferences.setMockInitialValues({});
      final body = '{"clientVersion":"2.3.4",'
          '"innertubeApiKey":"fallback-key",'
          '"signatureTimestamp":9876}';

      final resolver = YtmClientVersionResolver();
      await _withClient(
        () => resolver.refresh(),
        MockClient((_) async => http.Response(body, 200)),
      );

      expect(resolver.clientVersion, '2.3.4');
      expect(resolver.apiKey, 'fallback-key');
      expect(resolver.sts, 9876);
    });

    test('supports the INNERTUBE_CLIENT_VERSION tertiary pattern', () async {
      SharedPreferences.setMockInitialValues({});
      const body = '{"INNERTUBE_CLIENT_VERSION":"3.0.1"}';

      final resolver = YtmClientVersionResolver();
      await _withClient(
        () => resolver.refresh(),
        MockClient((_) async => http.Response(body, 200)),
      );

      expect(resolver.clientVersion, '3.0.1');
    });

    test('ignores zero STS and leaves defaults in place', () async {
      SharedPreferences.setMockInitialValues({});
      const beforeApiKey = 'AIzaSyC9XL3ZjWddXya6X74dJoCTL-WEYFDNX30';
      const body = '{"STS":0}';

      final resolver = YtmClientVersionResolver();
      await _withClient(
        () => resolver.refresh(),
        MockClient((_) async => http.Response(body, 200)),
      );

      expect(resolver.apiKey, beforeApiKey);
      final expectedDays =
          DateTime.now().toUtc().millisecondsSinceEpoch ~/ 86400000;
      expect((resolver.sts - expectedDays).abs(), lessThanOrEqualTo(1));
    });

    test('non-200 responses are ignored', () async {
      SharedPreferences.setMockInitialValues({});
      final resolver = YtmClientVersionResolver();
      await _withClient(
        () => resolver.refresh(),
        MockClient((_) async => http.Response('server error', 503)),
      );
      expect(resolver.clientVersion,
          YtmClientVersionResolver.fallbackClientVersion);
      expect(resolver.apiKey, YtmClientVersionResolver.fallbackApiKey);
    });

    test('falls back to youtube.com when music.youtube.com fails', () async {
      SharedPreferences.setMockInitialValues({});
      final hosts = <String>[];
      final client = MockClient((request) async {
        hosts.add(request.url.host);
        if (request.url.host == 'music.youtube.com') {
          throw http.ClientException('offline');
        }
        return http.Response(_fullBody(), 200);
      });

      final resolver = YtmClientVersionResolver();
      await _withClient(() => resolver.refresh(), client);

      expect(hosts, ['music.youtube.com', 'www.youtube.com']);
      expect(resolver.clientVersion, '1.20260101.01.00');
    });

    test('survives both endpoints failing', () async {
      SharedPreferences.setMockInitialValues({});
      var attempts = 0;
      final client = MockClient((request) async {
        attempts++;
        throw const SocketException('no route to host');
      });

      final resolver = YtmClientVersionResolver();
      await _withClient(() => resolver.refresh(), client);

      expect(attempts, 2);
      expect(resolver.clientVersion,
          YtmClientVersionResolver.fallbackClientVersion);
    });

    test('a body with no recognizable fields still records the fetch time',
        () async {
      SharedPreferences.setMockInitialValues({});
      final resolver = YtmClientVersionResolver();
      await _withClient(
        () => resolver.refresh(),
        MockClient((_) async => http.Response('<html>music</html>', 200)),
      );

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt(_fetchTsKey), isNotNull);
      expect(prefs.getString(_versionKey), isNull);
    });
  });
}

class SocketException implements Exception {
  const SocketException(this.message);
  final String message;
  @override
  String toString() => 'SocketException: $message';
}
