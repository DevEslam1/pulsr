// test/services/canvas/canvas_sources_test.dart
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pulsr/services/canvas/apple_music_canvas.dart';
import 'package:pulsr/services/canvas/community_canvas.dart';
import 'package:pulsr/services/canvas/tidal_canvas.dart';

void main() {
  group('CommunityCanvas', () {
    test('fetches manifest and matches track', () async {
      final mockClient = MockClient((request) async {
        if (request.url.toString() == CommunityCanvas.manifestUrl) {
          final manifest = {
            'items': [
              {
                'song': 'Levitating',
                'artist': 'Dua Lipa',
                'album': 'Future Nostalgia',
                'url': 'https://cdn.example.com/levitating.mp4',
              }
            ]
          };
          return http.Response(jsonEncode(manifest), 200);
        }
        return http.Response('Not Found', 404);
      });

      final source = CommunityCanvas(client: mockClient);
      final result = await source.search('Levitating', 'Dua Lipa', 'Future Nostalgia');

      expect(result, isNotNull);
      expect(result!.title, 'Levitating');
      expect(result.artist, 'Dua Lipa');
      expect(result.videoUrl, 'https://cdn.example.com/levitating.mp4');
      expect(result.source, 'community');
    });

    test('returns null when no matching track in manifest', () async {
      final mockClient = MockClient((request) async {
        return http.Response(jsonEncode({'items': []}), 200);
      });

      final source = CommunityCanvas(client: mockClient);
      final result = await source.search('Nonexistent', 'Unknown', null);
      expect(result, isNull);
    });
  });

  group('TidalCanvas', () {
    test('correctly converts 5-part video cover id to CDN URL', () {
      const coverId = '277a83f7-920f-4318-97f6-6d60c490ff4f';
      expect(
        TidalCanvas.coverUrl(coverId),
        'https://resources.tidal.com/videos/277a83f7/920f/4318/97f6/6d60c490ff4f/1280x1280.mp4',
      );
      expect(TidalCanvas.coverUrl('invalid-id'), isNull);
    });

    test('searches Tidal and returns video cover', () async {
      final mockClient = MockClient((request) async {
        final mockResponse = {
          'tracks': {
            'items': [
              {
                'title': 'Starboy',
                'artists': [{'name': 'The Weeknd'}],
                'album': {
                  'title': 'Starboy',
                  'videoCover': '12345678-1234-1234-1234-123456789abc',
                }
              }
            ]
          }
        };
        return http.Response(jsonEncode(mockResponse), 200);
      });

      final source = TidalCanvas(client: mockClient);
      final result = await source.search('Starboy', 'The Weeknd', 'Starboy');

      expect(result, isNotNull);
      expect(result!.title, 'Starboy');
      expect(result.source, 'tidal');
      expect(
        result.videoUrl,
        'https://resources.tidal.com/videos/12345678/1234/1234/1234/123456789abc/1280x1280.mp4',
      );
    });
  });

  group('AppleMusicCanvas', () {
    test('searches catalog and resolves editorialVideo', () async {
      final expSeconds = (DateTime.now().millisecondsSinceEpoch ~/ 1000) + 3600;
      final payload = base64Url.encode(utf8.encode('{"exp":$expSeconds,"iss":"AMPWebPlay"}')).replaceAll('=', '');
      final header = base64Url.encode(utf8.encode('{"kid":"WebPlayKid"}')).replaceAll('=', '');
      final dummyToken = '$header.$payload.signature';

      final mockClient = MockClient((request) async {
        final url = request.url.toString();
        if (url == AppleMusicCanvas.webPlayerUrl) {
          return http.Response(
            '<html><script src="/assets/index-test.js"></script></html>',
            200,
          );
        }
        if (url == 'https://music.apple.com/assets/index-test.js') {
          return http.Response('const t = "$dummyToken";', 200);
        }
        if (url.contains('/search')) {
          final catalogResponse = {
            'results': {
              'songs': {
                'data': [
                  {
                    'attributes': {
                      'name': 'Flowers',
                      'artistName': 'Miley Cyrus',
                      'albumName': 'Endless Summer Vacation',
                      'editorialVideo': {
                        'motionDetailSquare': {
                          'video': 'https://video.itunes.apple.com/apple-assets/flowers.mp4'
                        }
                      }
                    }
                  }
                ]
              }
            }
          };
          return http.Response(jsonEncode(catalogResponse), 200);
        }
        return http.Response('Not Found', 404);
      });

      final source = AppleMusicCanvas(client: mockClient);
      final result = await source.search('Flowers', 'Miley Cyrus', 'Endless Summer Vacation');

      expect(result, isNotNull);
      expect(result!.title, 'Flowers');
      expect(result.source, 'apple_music');
      expect(result.videoUrl, 'https://video.itunes.apple.com/apple-assets/flowers.mp4');
    });
  });
}
