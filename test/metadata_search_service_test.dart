import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pulsr/core/services/metadata_search_service.dart';

void main() {
  group('MetadataSearchService Tests', () {
    test('searchMetadata parses iTunes response and upgrades artwork resolution', () async {
      final mockClient = MockClient((request) async {
        if (request.url.host == 'itunes.apple.com') {
          final payload = {
            'resultCount': 1,
            'results': [
              {
                'trackName': 'Comfortably Numb',
                'artistName': 'Pink Floyd',
                'collectionName': 'The Wall',
                'primaryGenreName': 'Progressive Rock',
                'releaseDate': '1979-11-30T08:00:00Z',
                'trackNumber': 19,
                'artworkUrl100': 'https://is1-ssl.mzstatic.com/image/thumb/100x100bb.jpg',
              }
            ]
          };
          return http.Response(jsonEncode(payload), 200);
        }
        return http.Response('Not Found', 404);
      });

      final service = MetadataSearchService(mockClient);
      final results = await service.searchMetadata(title: 'Comfortably Numb', artist: 'Pink Floyd');

      expect(results.length, equals(1));
      final track = results.first;
      expect(track.title, equals('Comfortably Numb'));
      expect(track.artist, equals('Pink Floyd'));
      expect(track.album, equals('The Wall'));
      expect(track.genre, equals('Progressive Rock'));
      expect(track.releaseYear, equals('1979'));
      expect(track.trackNumber, equals('19'));
      expect(track.artworkUrl, contains('1400x1400'));
    });

    test('searchMetadata handles network error gracefully', () async {
      final mockClient = MockClient((request) async {
        throw Exception('Network unreachable');
      });

      final service = MetadataSearchService(mockClient);
      final results = await service.searchMetadata(title: 'Unknown Title');

      expect(results, isEmpty);
    });
  });
}
