// test/core/services/yt_download_transfer_math_test.dart
//
// Body-size estimation, pre-flight disk budget, URL lifetime and resume
// stamps, exercised directly against the collaborator extracted from
// YtDownloadService.
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/services/yt_download_transfer_math.dart';
import 'package:pulsr/domain/models/ytm_track.dart';

const _url1 = 'https://rr1---sn-x.googlevideo.com/videoplayback?id=abc';

YtmStream _stream({
  int bitrateKbps = 256,
  Duration duration = const Duration(minutes: 40),
}) =>
    YtmStream(
      videoId: 'dQw4w9WgXcQ',
      url: _url1,
      mimeType: 'audio/mp4',
      container: 'm4a',
      bitrateKbps: bitrateKbps,
      duration: duration,
      title: 'T',
      artist: 'A',
    );

void main() {
  group('estimateBytes', () {
    test('uses bitrate times duration when both are known', () {
      // 2400 s at 256 kbps = 76 800 000 bytes.
      expect(YtDownloadTransferMath.estimateBytes(_stream()), 76800000);
    });

    test('falls back to 160kbps and 240s when metadata is missing', () {
      final unknown =
          _stream(bitrateKbps: 0, duration: const Duration(seconds: 0));
      expect(
          YtDownloadTransferMath.estimateBytes(unknown), 240 * 160 * 1000 ~/ 8);
    });
  });

  group('requiredPreflightBytes (F3)', () {
    test('is two body copies plus 10MB, not the old five', () {
      final stream = _stream();
      final body = YtDownloadTransferMath.estimateBytes(stream);
      final required = YtDownloadTransferMath.requiredPreflightBytes(stream);
      expect(required, body * 2 + 10 * 1024 * 1024);
      expect(required, lessThan(body * 5));
    });

    test('a tiny stream still asks for the 10MB floor', () {
      final stream =
          _stream(bitrateKbps: 64, duration: const Duration(seconds: 30));
      expect(YtDownloadTransferMath.requiredPreflightBytes(stream),
          greaterThanOrEqualTo(10 * 1024 * 1024));
    });
  });

  group('requiredLifetime', () {
    test('clamps to 60..1800 seconds plus the 2-minute tail', () {
      final tiny =
          _stream(bitrateKbps: 64, duration: const Duration(seconds: 1));
      expect(YtDownloadTransferMath.requiredLifetime(tiny),
          const Duration(seconds: 60) + const Duration(minutes: 2));

      final huge =
          _stream(bitrateKbps: 320, duration: const Duration(hours: 4));
      expect(YtDownloadTransferMath.requiredLifetime(huge),
          const Duration(seconds: 1800) + const Duration(minutes: 2));
    });
  });

  group('resume stamps (F6)', () {
    test('identity is container + expected body size, not the URL', () {
      final stamp = YtDownloadTransferMath.resumeStampFor(
          container: 'm4a', expectedBytes: 1000);
      expect(
          stamp,
          YtDownloadTransferMath.resumeStampFor(
              container: ' M4A ', expectedBytes: 1000));
      expect(
          stamp,
          isNot(YtDownloadTransferMath.resumeStampFor(
              container: 'webm', expectedBytes: 1000)));
      expect(
          stamp,
          isNot(YtDownloadTransferMath.resumeStampFor(
              container: 'm4a', expectedBytes: 1001)));
    });

    test('same container and size for different videos never resumes', () {
      final first = YtDownloadTransferMath.resumeStampFor(
          container: 'm4a', expectedBytes: 1000, videoId: 'video-one');
      final second = YtDownloadTransferMath.resumeStampFor(
          container: 'm4a', expectedBytes: 1000, videoId: 'video-two');

      expect(first, isNot(second));
      expect(YtDownloadTransferMath.resumeStampMatches(second, first), isFalse);
      expect(YtDownloadTransferMath.resumeStampMatches('  $first \n', first),
          isTrue);
    });

    test('an unknown size still yields a stable container-scoped stamp', () {
      expect(YtDownloadTransferMath.resumeStampFor(container: 'm4a'),
          YtDownloadTransferMath.resumeStampFor(container: 'm4a'));
      expect(YtDownloadTransferMath.resumeStampFor(container: 'm4a'),
          isNot(YtDownloadTransferMath.resumeStampFor(container: 'webm')));
    });

    test('requires an exact trimmed match', () {
      expect(YtDownloadTransferMath.resumeStampMatches('123', '123'), isTrue);
      expect(YtDownloadTransferMath.resumeStampMatches(' 123 ', '123'), isTrue);
      expect(YtDownloadTransferMath.resumeStampMatches(null, '123'), isFalse);
      expect(YtDownloadTransferMath.resumeStampMatches('124', '123'), isFalse);
      expect(YtDownloadTransferMath.resumeStampMatches('', '123'), isFalse);
      expect(YtDownloadTransferMath.resumeStampMatches('   ', '123'), isFalse);
    });
  });
}
