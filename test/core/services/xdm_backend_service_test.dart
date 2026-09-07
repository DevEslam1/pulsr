// test/core/services/xdm_backend_service_test.dart
// Remote backend decommissioned: all entry points are hard-disabled and
// perform no network I/O.
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/services/xdm_backend_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockHttpClient extends Mock implements http.Client {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockHttpClient mockClient;
  late XdmBackendService service;

  setUpAll(() {
    registerFallbackValue(Uri());
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    mockClient = MockHttpClient();
    service = XdmBackendService.withClient(mockClient);
  });

  group('XdmBackendService (disabled)', () {
    test('isEnabled always returns false', () async {
      expect(await service.isEnabled(), isFalse);
      expect(XdmBackendService.hardDisabled, isTrue);
    });

    test('isCookieSyncAllowed always returns false', () async {
      expect(await service.isCookieSyncAllowed(), isFalse);
    });

    test('checkHealth reports disabled without network I/O', () async {
      final health = await service.checkHealth(force: true);
      expect(health.ok, isFalse);
      expect(health.message, contains('disabled'));
      verifyNever(() => mockClient.get(any()));
    });

    test('resolveStream returns null without network I/O', () async {
      final result = await service.resolveStream('dQw4w9WgXcQ');
      expect(result, isNull);
      verifyNever(() => mockClient.get(any(), headers: any(named: 'headers')));
    });

    test('getPlaylist returns empty without network I/O', () async {
      final tracks = await service
          .getPlaylist('https://www.youtube.com/playlist?list=PL123');
      expect(tracks, isEmpty);
      verifyNever(() => mockClient.get(any(), headers: any(named: 'headers')));
    });

    test('search returns empty without network I/O', () async {
      final tracks = await service.search('test query');
      expect(tracks, isEmpty);
      verifyNever(() => mockClient.get(any(), headers: any(named: 'headers')));
    });
  });
}
