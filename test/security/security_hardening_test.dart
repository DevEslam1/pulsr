import 'dart:convert';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/services/file_intent_handler.dart';
import 'package:pulsr/core/services/playlist_share_service.dart';
import 'package:pulsr/core/services/ytm_account_service.dart';
import 'package:pulsr/core/services/ytm_client_version_resolver.dart';
import 'package:pulsr/features/auth/presentation/ytm_web_login_sheet.dart';
import 'package:pulsr/features/settings/cubit/proxy_endpoint_validator.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockYtmClientVersionResolver extends Mock
    implements YtmClientVersionResolver {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  group('Phase I: Security Hardening Tests', () {
    test(
        '1. SharedPreferences -> FlutterSecureStorage migration protects auth cookies',
        () async {
      // Seed legacy plaintext session cookie into SharedPreferences
      const legacyCookie = 'HSID=xyz123; SSID=abc456; SAPISID=hash789;';
      SharedPreferences.setMockInitialValues({
        'ytm_session_cookies': legacyCookie,
      });

      final mockResolver = MockYtmClientVersionResolver();
      when(() => mockResolver.init()).thenAnswer((_) async {});
      when(() => mockResolver.clientVersion).thenReturn('1.20240101');
      when(() => mockResolver.apiKey).thenReturn('AIzaFakeKey');

      final accountService = YtmAccountService(mockResolver);

      // Perform init / read which triggers the legacy migration
      await accountService.init();

      // Verify cookies are now loaded and stored in FlutterSecureStorage
      const storage = FlutterSecureStorage();
      final secureCookie =
          await storage.read(key: 'ytm_session_cookies_secure');
      expect(secureCookie, equals(legacyCookie));

      // Verify SharedPreferences legacy key was completely purged
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('ytm_session_cookies'), isFalse);
    });

    test('2. Proxy endpoint validator supports IPv6-mapped IPv4 addresses', () {
      // Valid IPv6-mapped IPv4 addresses
      expect(
          validateProxyHostAndPort(host: '::ffff:192.0.2.1', port: 8080), isNull);
      expect(
          validateProxyHostAndPort(host: '[::ffff:127.0.0.1]', port: 1080),
          isNull);
      expect(
          validateProxyHostAndPort(
              host: '0:0:0:0:0:ffff:192.168.1.1', port: 3128),
          isNull);
      expect(validateProxyHostAndPort(host: '127.0.0.1', port: 80), isNull);
      expect(validateProxyHostAndPort(host: '[::1]', port: 443), isNull);

      // Invalid formats / out of range
      expect(
          validateProxyHostAndPort(host: '::ffff:999.999.999.999', port: 8080),
          equals('Invalid proxy host format'));
      expect(validateProxyHostAndPort(host: '::ffff:invalid', port: 8080),
          equals('Invalid proxy host format'));
      expect(validateProxyHostAndPort(host: '::ffff:1.2.3.4', port: 0),
          equals('Proxy port must be between 1 and 65535'));
      expect(validateProxyHostAndPort(host: '::ffff:1.2.3.4', port: 70000),
          equals('Proxy port must be between 1 and 65535'));
    });

    test(
        '3. ReDoS stress test on extractYouTubeVideoId finishes within 50ms on 10k chars',
        () {
      // 10,000-character malicious / pathological input
      final evilInput = 'https://www.youtube.com/watch?${'a' * 10000}';
      final evilSubdomains = '${'sub.' * 2500}youtube.com/watch?v=12345678901';

      final sw = Stopwatch()..start();
      final result1 = FileIntentHandler.extractYouTubeVideoId(evilInput);
      final elapsed1 = sw.elapsedMilliseconds;

      sw.reset();
      sw.start();
      final result2 = FileIntentHandler.extractYouTubeVideoId(evilSubdomains);
      final elapsed2 = sw.elapsedMilliseconds;

      // Assert that both pathological inputs return safely and in under 50ms
      expect(result1, isNull);
      expect(result2, isNull);
      expect(elapsed1, lessThan(50),
          reason: 'Pathological input took ${elapsed1}ms, exceeding 50ms ceiling');
      expect(elapsed2, lessThan(50),
          reason:
              'Pathological subdomains took ${elapsed2}ms, exceeding 50ms ceiling');

      // Valid IDs still parse instantly
      expect(FileIntentHandler.extractYouTubeVideoId('dQw4w9WgXcQ'),
          equals('dQw4w9WgXcQ'));
      expect(
          FileIntentHandler.extractYouTubeVideoId(
              'https://youtu.be/dQw4w9WgXcQ'),
          equals('dQw4w9WgXcQ'));
      expect(
          FileIntentHandler.extractYouTubeVideoId(
              'https://www.youtube.com/watch?v=dQw4w9WgXcQ'),
          equals('dQw4w9WgXcQ'));
    });

    test('4. PlaylistShareService enforces JSON tree depth <= 5 to block attacks',
        () {
      final service = PlaylistShareService();

      // Valid playlist bundle (depth = 3)
      final validJson = jsonEncode({
        'name': 'Rock Classics',
        'exportTimestamp': 1710000000000,
        'tracks': [
          {
            'title': 'Bohemian Rhapsody',
            'artist': 'Queen',
            'album': 'A Night at the Opera',
            'durationMs': 354000,
            'source': 'local',
          }
        ]
      });

      expect(PlaylistShareService.computeDepth(jsonDecode(validJson)),
          lessThanOrEqualTo(5));
      final bundle = service.importPlaylist(validJson);
      expect(bundle, isNotNull);
      expect(bundle!.name, equals('Rock Classics'));
      expect(bundle.tracks.length, equals(1));

      // Pathologically deep JSON tree (depth = 8)
      final deepMap = <String, dynamic>{
        'level1': {
          'level2': {
            'level3': {
              'level4': {
                'level5': {
                  'level6': {
                    'level7': 'payload',
                  }
                }
              }
            }
          }
        }
      };

      final deepJson = jsonEncode(deepMap);
      expect(PlaylistShareService.computeDepth(deepMap), greaterThan(5));

      // Should be rejected safely without stack overflow
      final rejected = service.importPlaylist(deepJson);
      expect(rejected, isNull);
    });

    test('5. YtmWebLoginSheet builds hardened sandbox settings and navigation policy',
        () {
      final settings = YtmWebLoginSheet.buildDefaultSettings();

      // Assert sandbox file access restrictions
      expect(settings.allowFileAccess, isFalse);
      expect(settings.allowContentAccess, isFalse);
      expect(settings.allowFileAccessFromFileURLs, isFalse);
      expect(settings.allowUniversalAccessFromFileURLs, isFalse);
      expect(settings.mixedContentMode,
          equals(MixedContentMode.MIXED_CONTENT_NEVER_ALLOW));
      expect(settings.javaScriptCanOpenWindowsAutomatically, isFalse);
      expect(settings.requestedWithHeaderOriginAllowList, isEmpty);

      // Assert navigation policy cancels dangerous schemes and untrusted origins
      expect(
          YtmWebLoginSheet.evaluateNavigation(
              Uri.parse('javascript:alert("pwned")')),
          equals(NavigationActionPolicy.CANCEL));
      expect(
          YtmWebLoginSheet.evaluateNavigation(
              Uri.parse('file:///data/user/0/com.pulsr.music/databases/pulsr.db')),
          equals(NavigationActionPolicy.CANCEL));
      expect(
          YtmWebLoginSheet.evaluateNavigation(
              Uri.parse('data:text/html;base64,PHNjcmlwdD5hbGVydCgxKTwvc2NyaXB0Pg==')),
          equals(NavigationActionPolicy.CANCEL));
      expect(
          YtmWebLoginSheet.evaluateNavigation(
              Uri.parse('blob:https://evil.attacker.com/uuid')),
          equals(NavigationActionPolicy.CANCEL));
      expect(
          YtmWebLoginSheet.evaluateNavigation(
              Uri.parse('market://details?id=com.google.android.apps.youtube.music')),
          equals(NavigationActionPolicy.CANCEL));
      expect(
          YtmWebLoginSheet.evaluateNavigation(
              Uri.parse('https://evil-phishing-attacker.com/google-login')),
          equals(NavigationActionPolicy.CANCEL));

      // Assert navigation policy allows legitimate Google & YouTube Music auth endpoints
      expect(
          YtmWebLoginSheet.evaluateNavigation(
              Uri.parse('https://accounts.google.com/v3/signin/identifier')),
          equals(NavigationActionPolicy.ALLOW));
      expect(
          YtmWebLoginSheet.evaluateNavigation(
              Uri.parse('https://music.youtube.com/')),
          equals(NavigationActionPolicy.ALLOW));
      expect(
          YtmWebLoginSheet.evaluateNavigation(
              Uri.parse('https://www.youtube.com/watch?v=dQw4w9WgXcQ')),
          equals(NavigationActionPolicy.ALLOW));
    });
  });
}
