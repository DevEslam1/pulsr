// test/core/network/app_http_overrides_test.dart
//
// testConnection()'s response classification: proxy auth rejections must fail
// before the YouTube 4xx-reachability rule, or wrong proxy credentials report
// "working".
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/network/app_http_overrides.dart';

void main() {
  final youtubeUri = Uri.parse('https://music.youtube.com/');
  final googleVideoUri = Uri.parse('https://rr1---sn-abc.googlevideo.com/');
  final otherUri = Uri.parse('https://example.com/');

  group('AppHttpOverrides.evaluateResponse', () {
    test('2xx/3xx are reachable', () {
      expect(AppHttpOverrides.evaluateResponse(200, 'OK', youtubeUri).success,
          isTrue);
      expect(
          AppHttpOverrides.evaluateResponse(204, 'No Content', youtubeUri)
              .success,
          isTrue);
      expect(AppHttpOverrides.evaluateResponse(302, 'Found', otherUri).success,
          isTrue);
    });

    test('407 proxy authentication fails even on a YouTube host', () {
      final result = AppHttpOverrides.evaluateResponse(
          407, 'Proxy Authentication Required', youtubeUri);

      expect(result.success, isFalse);
      expect(result.error, contains('407'));
    });

    test('401 authentication fails before the 4xx reachability rule', () {
      final result =
          AppHttpOverrides.evaluateResponse(401, 'Unauthorized', youtubeUri);

      expect(result.success, isFalse);
      expect(result.error, contains('401'));
    });

    test('403/404 from YouTube still count as proxy-reachable', () {
      expect(
          AppHttpOverrides.evaluateResponse(403, 'Forbidden', youtubeUri)
              .success,
          isTrue);
      expect(
          AppHttpOverrides.evaluateResponse(404, 'Not Found', youtubeUri)
              .success,
          isTrue);
      expect(
          AppHttpOverrides.evaluateResponse(404, 'Not Found', googleVideoUri)
              .success,
          isTrue);
    });

    test('4xx from a non-YouTube host fails', () {
      final result =
          AppHttpOverrides.evaluateResponse(403, 'Forbidden', otherUri);

      expect(result.success, isFalse);
      expect(result.error, contains('403'));
    });

    test('5xx fails on every host', () {
      expect(
          AppHttpOverrides.evaluateResponse(500, 'Server Error', youtubeUri)
              .success,
          isFalse);
      expect(
          AppHttpOverrides.evaluateResponse(503, 'Unavailable', otherUri)
              .success,
          isFalse);
    });

    test('an empty reason phrase still yields a usable error', () {
      final result = AppHttpOverrides.evaluateResponse(407, '', youtubeUri);

      expect(result.success, isFalse);
      expect(result.error, isNotEmpty);
    });
  });
}
