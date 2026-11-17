import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/errors/ytm_error_classifier.dart';
import 'package:pulsr/core/services/ytm_media_helpers.dart';

void main() {
  test('firstArtistRun skips separators, badges, years and durations', () {
    expect(
      YtmMediaHelpers.firstArtistRun([
        {'text': '•'},
        {'text': 'Song'},
        {'text': 'Real Artist'},
        {'text': '•'},
        {'text': 'Real Album'},
      ]),
      'Real Artist',
    );
    expect(
      YtmMediaHelpers.firstArtistRun([
        {'text': '2024'},
        {'text': '3:45'},
        {'text': '1.2M views'},
      ]),
      isNull,
    );
    expect(YtmMediaHelpers.firstArtistRun(null), isNull);
  });

  test('firstArtistRun accepts names that merely contain badge words', () {
    expect(
      YtmMediaHelpers.firstArtistRun([
        {'text': 'Album Rock Band'},
      ]),
      'Album Rock Band',
    );
    expect(
      YtmMediaHelpers.firstArtistRun([
        {'text': 'The Song Writers'},
      ]),
      'The Song Writers',
    );
  });

  test('extractThumbnailUrl picks the largest thumbnail', () {
    expect(
      YtmMediaHelpers.extractThumbnailUrl({
        'thumbnails': [
          {'url': 'small.jpg', 'width': 60, 'height': 60},
          {'url': 'large.jpg', 'width': 640, 'height': 640},
          {'url': 'medium.jpg', 'width': 120, 'height': 120},
        ],
      }),
      'large.jpg',
    );
    expect(YtmMediaHelpers.extractThumbnailUrl(null), isNull);
  });

  test('a SABR-only answer does not start a substitute search', () {
    // Deliberate: SABR means YouTube is already restricting this client/route,
    // so a multi-query substitute search multiplies requests exactly where the
    // bot-challenge risk is highest. The failure is surfaced honestly instead.
    expect(
      YtmMediaHelpers.isPlayabilityOrRestrictedError(
        const YtmException('SABR_ENFORCED', 'forcing sabr'),
      ),
      isFalse,
    );
  });
}
