// test/core/services/yt_download_file_naming_test.dart
//
// Extension allow-list, filename hardening and container sniffing, exercised
// directly against the collaborator extracted from YtDownloadService.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/services/yt_download_file_naming.dart';

void main() {
  group('safeExtension', () {
    test('accepts known containers, case-insensitively', () {
      expect(YtDownloadFileNaming.safeExtension('m4a'), 'm4a');
      expect(YtDownloadFileNaming.safeExtension('WEBM'), 'webm');
      expect(YtDownloadFileNaming.safeExtension(' mp3 '), 'mp3');
      expect(YtDownloadFileNaming.safeExtension('FLAC'), 'flac');
    });

    test('falls back for anything that is not a bare container extension', () {
      expect(YtDownloadFileNaming.safeExtension(null), 'm4a');
      expect(YtDownloadFileNaming.safeExtension(''), 'm4a');
      expect(YtDownloadFileNaming.safeExtension('../../etc/passwd'), 'm4a');
      expect(YtDownloadFileNaming.safeExtension('m4a/..'), 'm4a');
      expect(YtDownloadFileNaming.safeExtension(r'a\b'), 'm4a');
      expect(YtDownloadFileNaming.safeExtension('a.b'), 'm4a');
      expect(YtDownloadFileNaming.safeExtension('exe'), 'm4a');
    });
  });

  group('sanitizeFilename', () {
    test('falls back to Unknown Artist/Title when empty', () {
      expect(YtDownloadFileNaming.sanitizeFilename('', '', 'mp3'),
          'Unknown Artist - Unknown Title.mp3');
    });

    test('cannot end a name with a traversal tail', () {
      final name = YtDownloadFileNaming.sanitizeFilename('Artist', '..', 'm4a');
      expect(name.endsWith('...m4a'), isFalse);
      expect(name.endsWith('.m4a'), isTrue);
    });

    test('never equals a reserved device name, since the base is "a - t"', () {
      expect(YtDownloadFileNaming.sanitizeFilename('CON', '', 'mp3'),
          'CON - Unknown Title.mp3');
      expect(YtDownloadFileNaming.sanitizeFilename('NUL', 'x', 'mp3'),
          'NUL - x.mp3');
    });

    test('caps the base name at 180 UTF-8 bytes, not characters', () {
      final name =
          YtDownloadFileNaming.sanitizeFilename('　' * 200, '　' * 200, 'm4a');
      final base = name.substring(0, name.length - '.m4a'.length);
      expect(base.runes.length * 3, lessThanOrEqualTo(180));
      expect(name.endsWith('.m4a'), isTrue);
    });
  });

  group('sniffContainerBytes', () {
    test('detects ISO-BMFF, WebM, Ogg, FLAC and MP3 magic', () {
      expect(
        YtDownloadFileNaming.sniffContainerBytes(
            const [0, 0, 0, 0, 0x66, 0x74, 0x79, 0x70]),
        (ext: 'm4a', mime: 'audio/mp4'),
      );
      expect(
        YtDownloadFileNaming.sniffContainerBytes(
            const [0x1A, 0x45, 0xDF, 0xA3]),
        (ext: 'webm', mime: 'audio/webm'),
      );
      expect(
        YtDownloadFileNaming.sniffContainerBytes(
            const [0x4F, 0x67, 0x67, 0x53]),
        (ext: 'ogg', mime: 'audio/ogg'),
      );
      expect(
        YtDownloadFileNaming.sniffContainerBytes(
            const [0x66, 0x4C, 0x61, 0x43]),
        (ext: 'flac', mime: 'audio/flac'),
      );
      expect(
        YtDownloadFileNaming.sniffContainerBytes(
            const [0x49, 0x44, 0x33, 0x03]),
        (ext: 'mp3', mime: 'audio/mpeg'),
      );
      expect(
        YtDownloadFileNaming.sniffContainerBytes(
            const [0xFF, 0xFB, 0x90, 0x00]),
        (ext: 'mp3', mime: 'audio/mpeg'),
      );
    });

    test('returns null for unknown or truncated headers', () {
      expect(YtDownloadFileNaming.sniffContainerBytes(const []), isNull);
      expect(
          YtDownloadFileNaming.sniffContainerBytes(const [0x00, 0x01]), isNull);
      expect(
          YtDownloadFileNaming.sniffContainerBytes(
              const [0, 0, 0, 0, 0x66, 0x74]),
          isNull);
    });
  });

  group('sniffContainer', () {
    test('reads the header off disk and sniffs the real container', () async {
      final dir = Directory.systemTemp.createTempSync('pulsr_sniff_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final webm = File('${dir.path}/body.bin');
      await webm.writeAsBytes(const [0x1A, 0x45, 0xDF, 0xA3, 0, 0, 0, 0]);
      expect(
        await YtDownloadFileNaming.sniffContainer(webm),
        (ext: 'webm', mime: 'audio/webm'),
      );
    });

    test('returns null for a missing file', () async {
      expect(
        await YtDownloadFileNaming.sniffContainer(
            File('${Directory.systemTemp.path}/pulsr_missing_file.bin')),
        isNull,
      );
    });
  });
}
