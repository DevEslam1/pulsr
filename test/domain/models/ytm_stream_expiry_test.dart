// test/domain/models/ytm_stream_expiry_test.dart
//
// Every playable googlevideo URL carries an `expire` stamp, but not every
// producer of a YtmStream copies it into `expiresAt`: the NewPipe fallback and
// the remote backend both omit it, and the backend's own stamp is not reliably
// in millis. With `expiresAt` null both `isExpired` and `isExpiringSoon` answer
// false forever, so a dead URL is served as fresh; read as millis when it is
// really seconds, every stream is born expired instead.
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/domain/models/ytm_track.dart';

YtmStream _stream({String? url, int? expiresAt}) => YtmStream(
      videoId: 'dQw4w9WgXcQ',
      url: url ?? 'https://rr1---sn-x.googlevideo.com/videoplayback?id=1',
      mimeType: 'audio/mp4',
      container: 'm4a',
      bitrateKbps: 128,
      duration: const Duration(minutes: 4),
      title: 'T',
      artist: 'A',
      expiresAt: expiresAt,
    );

void main() {
  group('expiryFromUrl', () {
    test('reads the query form', () {
      final stamp = YtmStream.expiryFromUrl(
          'https://rr1---sn-x.googlevideo.com/videoplayback?expire=1800000000&id=1');
      expect(stamp, 1800000000 * 1000);
    });

    test('reads the path segment form', () {
      // The `/expire/<epoch>/` form is what a URL rewritten by the media CDN
      // looks like; reading only the query form left these with no expiry at
      // all, and the proactive re-resolve never fired for them.
      final stamp = YtmStream.expiryFromUrl(
          'https://rr1---sn-x.googlevideo.com/videoplayback/expire/1800000000/id/1/itag/140');
      expect(stamp, 1800000000 * 1000);
    });

    test('returns null for a URL with no stamp', () {
      expect(
          YtmStream.expiryFromUrl('https://example.com/audio.m4a'), isNull);
    });
  });

  group('withResolvedExpiry', () {
    test('fills a missing stamp from the URL', () {
      final resolved = _stream(
        url:
            'https://rr1---sn-x.googlevideo.com/videoplayback?expire=1800000000',
      ).withResolvedExpiry();
      expect(resolved.expiresAt, 1800000000 * 1000);
      expect(resolved.isExpired, isFalse);
    });

    test('scales a seconds-valued stamp up instead of believing it', () {
      // 1 800 000 000 read as millis is January 1971: `isExpired` would answer
      // true for every stream the backend ever returned, and the URL cache
      // refuses to store an already-expired entry.
      final resolved = _stream(expiresAt: 1800000000).withResolvedExpiry();
      expect(resolved.expiresAt, 1800000000 * 1000);
      expect(resolved.isExpired, isFalse);
    });

    test('leaves a millis stamp alone and returns the same instance', () {
      final original = _stream(expiresAt: 1800000000 * 1000);
      final resolved = original.withResolvedExpiry();
      expect(resolved.expiresAt, 1800000000 * 1000);
      expect(identical(resolved, original), isTrue);
    });

    test('keeps every other field', () {
      final resolved = _stream(
        url:
            'https://rr1---sn-x.googlevideo.com/videoplayback?expire=1800000000',
      ).withResolvedExpiry();
      expect(resolved.videoId, 'dQw4w9WgXcQ');
      expect(resolved.container, 'm4a');
      expect(resolved.mimeType, 'audio/mp4');
      expect(resolved.bitrateKbps, 128);
      expect(resolved.duration, const Duration(minutes: 4));
      expect(resolved.isTaggable, isTrue);
    });

    test('a stampless URL stays stampless rather than guessing', () {
      final resolved =
          _stream(url: 'https://example.com/audio.m4a').withResolvedExpiry();
      expect(resolved.expiresAt, isNull);
    });

    test('an expired stamp is reported as expired', () {
      final past = DateTime.now()
              .subtract(const Duration(hours: 1))
              .millisecondsSinceEpoch ~/
          1000;
      final resolved = _stream(expiresAt: past).withResolvedExpiry();
      expect(resolved.isExpired, isTrue);
      expect(resolved.isExpiringSoon(), isTrue);
    });
  });
}
