// test/core/services/yt_download_service_test.dart
//
// The pure, side-effect-free parts of the download path: the size/lifetime
// estimates that decide whether a URL is replaced before the first byte, the
// container sniffer that overrides the URL's guess, and the filename cap.
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/services/yt_download_service.dart';
import 'package:pulsr/domain/models/ytm_track.dart';

YtmStream _stream({
  int bitrateKbps = 128,
  Duration duration = const Duration(minutes: 4),
}) =>
    YtmStream(
      videoId: 'dQw4w9WgXcQ',
      url: 'https://rr1---sn-x.googlevideo.com/videoplayback?expire=1800000000',
      mimeType: 'audio/mp4',
      container: 'm4a',
      bitrateKbps: bitrateKbps,
      duration: duration,
      title: 'T',
      artist: 'A',
    );

void main() {
  group('estimateBytes', () {
    test('is duration × bitrate', () {
      // 240 s at 128 kbps = 3 840 000 bytes.
      expect(YtDownloadService.estimateBytes(_stream()), 3840000);
    });

    test('falls back to 160kbps / 4 minutes when the stream says neither', () {
      final unknown = _stream(bitrateKbps: 0, duration: Duration.zero);
      expect(YtDownloadService.estimateBytes(unknown), 240 * 160 * 1000 ~/ 8);
    });
  });

  group('requiredLifetime', () {
    test('a long track needs far more life than playback\'s 5-minute default',
        () {
      // The bar a download has to clear is "will this URL survive the whole
      // transfer", not "is it about to die". A 40-minute mix at the pessimistic
      // 48 KB/s takes a quarter of an hour, so the 5-minute playback default
      // would happily start it on a URL that dies at 403 halfway through.
      final life = YtDownloadService.requiredLifetime(
          _stream(duration: const Duration(minutes: 40)));
      expect(life, greaterThan(const Duration(minutes: 5)));
      expect(life, const Duration(seconds: 902)); // 38.4 MB / 48 KB/s + 2 min
    });

    test('grows with the track and is clamped at 30 minutes + slack', () {
      final short = YtDownloadService.requiredLifetime(
          _stream(duration: const Duration(minutes: 3)));
      final long = YtDownloadService.requiredLifetime(
          _stream(duration: const Duration(minutes: 40)));
      expect(long, greaterThan(short));

      // Three hours of 320 kbps audio would ask for two and a half hours of
      // life; nothing YouTube mints lasts that long, so the requirement stops
      // at half an hour rather than making every re-resolve pointless.
      final huge = YtDownloadService.requiredLifetime(
          _stream(duration: const Duration(hours: 3), bitrateKbps: 320));
      expect(huge, const Duration(minutes: 32));
    });

    test('never drops below a minute even for a few seconds of audio', () {
      final tiny = YtDownloadService.requiredLifetime(
          _stream(duration: const Duration(seconds: 2), bitrateKbps: 48));
      expect(tiny, const Duration(minutes: 3));
    });
  });

  group('sniffContainerBytes', () {
    test('reads an ISO-BMFF ftyp box as m4a regardless of the URL', () {
      final header = <int>[
        0x00, 0x00, 0x00, 0x20, // box length
        0x66, 0x74, 0x79, 0x70, // 'ftyp'
        0x4D, 0x34, 0x41, 0x20, // 'M4A '
      ];
      final sniffed = YtDownloadService.sniffContainerBytes(header);
      expect(sniffed?.ext, 'm4a');
      expect(sniffed?.mime, 'audio/mp4');
    });

    test('reads an EBML header as webm', () {
      final sniffed = YtDownloadService.sniffContainerBytes(
          const [0x1A, 0x45, 0xDF, 0xA3, 0x01, 0x00, 0x00, 0x00]);
      expect(sniffed?.ext, 'webm');
      expect(sniffed?.mime, 'audio/webm');
    });

    test('reads OggS, fLaC, ID3 and a bare MPEG frame sync', () {
      expect(YtDownloadService.sniffContainerBytes(const [0x4F, 0x67, 0x67, 0x53])?.ext, 'ogg');
      expect(YtDownloadService.sniffContainerBytes(const [0x66, 0x4C, 0x61, 0x43])?.ext, 'flac');
      expect(YtDownloadService.sniffContainerBytes(const [0x49, 0x44, 0x33, 0x03])?.ext, 'mp3');
      expect(YtDownloadService.sniffContainerBytes(const [0xFF, 0xFB, 0x90, 0x00])?.mime,
          'audio/mpeg');
    });

    test('declines an unrecognisable or truncated header', () {
      expect(YtDownloadService.sniffContainerBytes(const [0x00, 0x01]), isNull);
      expect(YtDownloadService.sniffContainerBytes(const []), isNull);
      // 'ftyp' at the wrong offset is not an ISO-BMFF file.
      expect(
          YtDownloadService.sniffContainerBytes(
              const [0x66, 0x74, 0x79, 0x70, 0x00, 0x00, 0x00, 0x00]),
          isNull);
    });
  });

  group('sanitizeFilename', () {
    test('caps the name at 180 UTF-8 bytes, not 180 characters', () {
      // Every one of these is 3 bytes encoded, so a character-based cap would
      // sail past the filesystem's byte limit and MediaStore would refuse the
      // insert with an opaque failure.
      final name = YtDownloadService.sanitizeFilename('　' * 200, '　' * 200, 'm4a');
      final bytes = name.length; // ASCII suffix only after the check below
      expect(bytes, greaterThan(0));
      expect(name.endsWith('.m4a'), isTrue);
      final base = name.substring(0, name.length - 4);
      expect(base.runes.length * 3, lessThanOrEqualTo(180));
    });

    test('replaces reserved characters and keeps the extension', () {
      final name = YtDownloadService.sanitizeFilename(
          'AC/DC', 'Back: In "Black"?', 'm4a');
      expect(name, 'AC_DC - Back_ In _Black__.m4a');
    });

    test('escapes Windows device names and empty input', () {
      expect(YtDownloadService.sanitizeFilename('', '', 'm4a'),
          'Unknown Artist - Unknown Title.m4a');
      expect(YtDownloadService.sanitizeFilename('CON', '', 'm4a'),
          contains('CON - Unknown Title'));
    });
  });
}
