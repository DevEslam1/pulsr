import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/services/scrobbler_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockHttpClient extends Mock implements http.Client {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockHttpClient mockClient;
  late ScrobblerService scrobblerService;

  setUp(() {
    mockClient = MockHttpClient();
    scrobblerService = ScrobblerService(mockClient);
    registerFallbackValue(Uri.parse('https://example.com'));
  });

  group('Scrobbler Persistence & Session Recovery Tests', () {
    test('checkPendingScrobble ignores session if played <50% and <240s',
        () async {
      SharedPreferences.setMockInitialValues({
        'scrobbler_last_song': 101,
        'scrobbler_last_time': DateTime.now().millisecondsSinceEpoch - 60000,
        'scrobbler_last_position': 30000, // 30s
        'scrobbler_last_duration': 200000, // 200s -> 15%
        'scrobbler_last_artist': 'Artist A',
        'scrobbler_last_track': 'Track A',
      });

      await scrobblerService.checkPendingScrobble();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('scrobbler_last_song'), isNull);
    });

    test(
        'checkPendingScrobble triggers scrobble if played >50% before termination',
        () async {
      final nowMillis = DateTime.now().millisecondsSinceEpoch - 60000;
      SharedPreferences.setMockInitialValues({
        'scrobbler_last_song': 202,
        'scrobbler_last_time': nowMillis,
        'scrobbler_last_position': 120000, // 120s
        'scrobbler_last_duration': 200000, // 200s -> 60%
        'scrobbler_last_artist': 'Pink Floyd',
        'scrobbler_last_track': 'Time',
        'scrobbler_last_album': 'The Dark Side of the Moon',
        'setting_custom_scrobbler_enabled': true,
        'setting_custom_scrobbler_url': 'https://webhook.site/scrobble',
      });

      when(() => mockClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          )).thenAnswer((_) async => http.Response('{"status":"ok"}', 200));

      await scrobblerService.checkPendingScrobble();

      verify(() => mockClient.post(
            Uri.parse('https://webhook.site/scrobble'),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          )).called(1);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('scrobbler_last_song'), isNull);
    });
  });
}
