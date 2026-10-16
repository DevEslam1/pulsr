// test/core/services/artist_bio_service_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pulsr/core/services/artist_bio_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _ClosableClient extends http.BaseClient {
  final http.Client _inner;
  bool isClosed = false;
  _ClosableClient(this._inner);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      _inner.send(request);

  @override
  void close() {
    isClosed = true;
    _inner.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(
        {'setting_offline_only_mode': false});
  });

  group('ArtistBioService', () {
    test('does not close injected http.Client on dispose', () {
      final inner = MockClient((request) async {
        return http.Response('{}', 200);
      });
      final client = _ClosableClient(inner);
      final service = ArtistBioService(client);
      service.dispose();
      expect(client.isClosed, isFalse);
    });

    test('does not cache transient network failures (5xx)', () async {
      var callCount = 0;
      final mockClient = MockClient((request) async {
        callCount++;
        return http.Response('Server error', 500);
      });

      final service = ArtistBioService(mockClient);

      // First call fails upstream
      final info1 = await service.getArtistInfo('Radiohead');
      expect(info1, isNull);
      expect(callCount, 2); // 1 Deezer + 1 Wikipedia call

      // Second call must NOT hit cache and must retry network
      final info2 = await service.getArtistInfo('Radiohead');
      expect(info2, isNull);
      expect(callCount, 4); // Called network again!
    });

    test('caches successful response (200 with data)', () async {
      var callCount = 0;
      final mockClient = MockClient((request) async {
        callCount++;
        if (request.url.host.contains('deezer')) {
          return http.Response(
            '{"data":[{"picture_xl":"https://example.com/pic.jpg","nb_fan":5000}]}',
            200,
          );
        } else {
          return http.Response('{"extract":"British rock band."}', 200);
        }
      });

      final service = ArtistBioService(mockClient);

      final info1 = await service.getArtistInfo('Radiohead');
      expect(info1, isNotNull);
      expect(info1!.pictureUrl, 'https://example.com/pic.jpg');
      expect(info1.bio, 'British rock band.');
      expect(callCount, 2);

      // Second call must hit memory cache
      final info2 = await service.getArtistInfo('Radiohead');
      expect(info2, isNotNull);
      expect(info2!.pictureUrl, 'https://example.com/pic.jpg');
      expect(callCount, 2); // No new network calls
    });
  });
}
