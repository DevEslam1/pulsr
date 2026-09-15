import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pulsr/core/services/sponsorblock_service.dart';

void main() {
  group('SponsorBlockService', () {
    test('parses skip segments successfully', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.host, 'sponsor.ajay.app');
        expect(request.url.path, '/api/skipSegments');
        expect(request.url.queryParameters['videoID'], 'abc12345');

        final responseJson = jsonEncode([
          {
            'category': 'sponsor',
            'actionType': 'skip',
            'segment': [10.5, 25.0],
            'UUID': 'uuid-1',
          },
          {
            'category': 'intro',
            'actionType': 'skip',
            'segment': [0.0, 5.2],
            'UUID': 'uuid-2',
          },
        ]);
        return http.Response(responseJson, 200);
      });

      final service = SponsorBlockService(mockClient);
      final segments = await service.getSegments('abc12345');

      expect(segments.length, 2);
      // Verify sorting by start duration
      expect(segments[0].uuid, 'uuid-2');
      expect(segments[0].start, Duration.zero);
      expect(segments[0].end, const Duration(milliseconds: 5200));

      expect(segments[1].uuid, 'uuid-1');
      expect(segments[1].start, const Duration(milliseconds: 10500));
      expect(segments[1].end, const Duration(milliseconds: 25000));
    });

    test('caches segments for subsequent calls', () async {
      var callCount = 0;
      final mockClient = MockClient((request) async {
        callCount++;
        return http.Response(
          jsonEncode([
            {
              'category': 'sponsor',
              'segment': [30.0, 45.0],
              'UUID': 'uuid-cached',
            }
          ]),
          200,
        );
      });

      final service = SponsorBlockService(mockClient);
      final first = await service.getSegments('test_id');
      final second = await service.getSegments('test_id');

      expect(callCount, 1);
      expect(first.length, 1);
      expect(second.length, 1);
      expect(first.first.uuid, 'uuid-cached');
    });

    test('findSegmentToSkip correctly identifies active skip segment', () {
      final service = SponsorBlockService();
      final segments = [
        const SponsorBlockSegment(
          category: 'intro',
          start: Duration(seconds: 0),
          end: Duration(seconds: 5),
          uuid: 'intro-1',
        ),
        const SponsorBlockSegment(
          category: 'music_offtopic',
          start: Duration(seconds: 50),
          end: Duration(seconds: 80),
          uuid: 'offtopic-1',
        ),
      ];

      // At second 2 (in intro)
      final introMatch =
          service.findSegmentToSkip(segments, const Duration(seconds: 2));
      expect(introMatch, isNotNull);
      expect(introMatch?.uuid, 'intro-1');

      // At second 10 (normal playback)
      final normalMatch =
          service.findSegmentToSkip(segments, const Duration(seconds: 10));
      expect(normalMatch, isNull);

      // At second 65 (in music_offtopic)
      final offtopicMatch =
          service.findSegmentToSkip(segments, const Duration(seconds: 65));
      expect(offtopicMatch, isNotNull);
      expect(offtopicMatch?.uuid, 'offtopic-1');
    });

    test('merges overlapping and adjacent skip segments into unified intervals', () async {
      final mockClient = MockClient((request) async {
        final responseJson = jsonEncode([
          {
            'category': 'sponsor',
            'actionType': 'skip',
            'segment': [10.0, 20.0],
            'UUID': 'seg-1',
          },
          {
            'category': 'sponsor',
            'actionType': 'skip',
            'segment': [18.0, 30.0], // overlaps seg-1
            'UUID': 'seg-2',
          },
          {
            'category': 'sponsor',
            'actionType': 'skip',
            'segment': [30.0, 35.0], // contiguous with seg-2
            'UUID': 'seg-3',
          },
          {
            'category': 'outro',
            'actionType': 'skip',
            'segment': [100.0, 110.0], // disjoint
            'UUID': 'seg-4',
          },
        ]);
        return http.Response(responseJson, 200);
      });

      final service = SponsorBlockService(mockClient);
      final merged = await service.getSegments('overlap_test');

      // seg-1, seg-2, and seg-3 should be merged into a single segment [10.0, 35.0]
      expect(merged.length, 2);
      expect(merged[0].start, const Duration(seconds: 10));
      expect(merged[0].end, const Duration(seconds: 35));
      expect(merged[0].category, 'sponsor');

      expect(merged[1].start, const Duration(seconds: 100));
      expect(merged[1].end, const Duration(seconds: 110));
      expect(merged[1].category, 'outro');
    });
  });
}
