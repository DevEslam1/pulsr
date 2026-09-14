// test/core/services/yt_download_preflight_test.dart
//
// F3 / F6 / F11 regression, all against the pure helpers the download path now
// routes through.
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/services/yt_download_service.dart';
import 'package:pulsr/domain/models/ytm_track.dart';

const _url1 = 'https://rr1---sn-x.googlevideo.com/videoplayback?id=abc';
const _url2 =
    'https://rr2---sn-y.googlevideo.com/videoplayback?id=zzz&mime=audio%2Fwebm';

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
  group('download pre-flight space requirement (F3)', () {
    test('is two body copies plus slack, not the old five', () {
      final stream = _stream();
      final body = YtDownloadService.estimateBytes(stream);
      final required = YtDownloadService.requiredPreflightBytes(stream);
      expect(required, equals(body * 2 + 10 * 1024 * 1024));
      expect(required, lessThan(body * 5),
          reason: 'the 5x rule was the false-negative this fixes');
    });

    test('a 40-minute 256kbps track no longer demands ~5x its size', () {
      final stream = _stream(); // 2400s * 256kbps = 76.8 MB
      expect(YtDownloadService.estimateBytes(stream), equals(76800000));
      expect(YtDownloadService.requiredPreflightBytes(stream),
          equals(164085760));
      // Fits the "300MB free" case the old rule refused.
      expect(YtDownloadService.requiredPreflightBytes(stream),
          lessThan(300 * 1024 * 1024));
    });

    test('a tiny stream still asks for the 10MB floor', () {
      final stream = _stream(bitrateKbps: 64, duration: const Duration(seconds: 30));
      expect(YtDownloadService.requiredPreflightBytes(stream),
          greaterThanOrEqualTo(10 * 1024 * 1024));
    });
  });

  group('sequential resume stamp (F6)', () {
    test('a part written for the same url is resumable', () {
      final stamp = YtDownloadService.resumeStampFor(Uri.parse(_url1));
      expect(YtDownloadService.resumeStampMatches(stamp, stamp), isTrue);
      expect(YtDownloadService.resumeStampMatches('  $stamp\n', stamp), isTrue);
    });

    test('a part written for a different url is NOT resumable', () {
      final stamp = YtDownloadService.resumeStampFor(Uri.parse(_url1));
      final other = YtDownloadService.resumeStampFor(Uri.parse(_url2));
      expect(other, isNot(equals(stamp)));
      expect(YtDownloadService.resumeStampMatches(other, stamp), isFalse);
    });

    test('a missing or empty stamp is not resumable', () {
      expect(YtDownloadService.resumeStampMatches(null, '123'), isFalse);
      expect(YtDownloadService.resumeStampMatches('', '123'), isFalse);
      expect(YtDownloadService.resumeStampMatches('   ', '123'), isFalse);
    });
  });

  group('container extension allow-list (F11)', () {
    test('accepts known containers, case-insensitively', () {
      expect(YtDownloadService.safeExtension('m4a'), equals('m4a'));
      expect(YtDownloadService.safeExtension('WEBM'), equals('webm'));
      expect(YtDownloadService.safeExtension(' mp3 '), equals('mp3'));
    });

    test('falls back for anything that is not a bare container extension', () {
      expect(YtDownloadService.safeExtension(null), equals('m4a'));
      expect(YtDownloadService.safeExtension(''), equals('m4a'));
      expect(YtDownloadService.safeExtension('../../etc/passwd'), equals('m4a'));
      expect(YtDownloadService.safeExtension('m4a/..'), equals('m4a'));
      expect(YtDownloadService.safeExtension('exe'), equals('m4a'));
    });

    test('sanitizeFilename cannot end a name with a traversal tail', () {
      final name = YtDownloadService.sanitizeFilename('Artist', '..', 'm4a');
      expect(name.endsWith('...m4a'), isFalse);
      expect(name.endsWith('.m4a'), isTrue);
    });
  });
}