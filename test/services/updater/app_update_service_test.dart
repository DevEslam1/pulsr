import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/services/updater/app_update_service.dart';

void main() {
  group('ParsedVersion', () {
    test('parses standard semver and prefixed versions', () {
      final v1 = ParsedVersion.parse('1.0.0');
      expect(v1.parts, [1, 0, 0]);
      expect(v1.isPreRelease, isFalse);

      final v2 = ParsedVersion.parse('v2.14.3');
      expect(v2.parts, [2, 14, 3]);
      expect(v2.isPreRelease, isFalse);

      final v3 = ParsedVersion.parse('1.2.0-beta1');
      expect(v3.parts, [1, 2, 0]);
      expect(v3.isPreRelease, isTrue);
    });

    test('compares versions accurately', () {
      expect(ParsedVersion.isNewer('1.1.0', '1.0.0'), isTrue);
      expect(ParsedVersion.isNewer('1.0.1', '1.0.0'), isTrue);
      expect(ParsedVersion.isNewer('2.0.0', '1.9.9'), isTrue);
      expect(ParsedVersion.isNewer('1.10.0', '1.9.0'), isTrue);

      // Stable release outranks pre-release
      expect(ParsedVersion.isNewer('1.0.0', '1.0.0-beta'), isTrue);

      // Equal or older
      expect(ParsedVersion.isNewer('1.0.0', '1.0.0'), isFalse);
      expect(ParsedVersion.isNewer('1.0.0', '1.1.0'), isFalse);
      expect(ParsedVersion.isNewer('1.0.0-beta', '1.0.0'), isFalse);
    });
  });

  group('UpdateInfo.fromGitHubJson', () {
    test('extracts apk asset URL and release metadata', () {
      final json = {
        'tag_name': 'v1.2.0',
        'html_url': 'https://github.com/pulsr-audio/pulsr/releases/tag/v1.2.0',
        'body': '## What is new\n- Added Discord Rich Presence\n- Added In-App Updater',
        'published_at': '2026-10-12T00:00:00Z',
        'assets': [
          {
            'name': 'source-code.zip',
            'state': 'uploaded',
            'browser_download_url': 'https://github.com/pulsr-audio/pulsr/releases/download/v1.2.0/source.zip',
          },
          {
            'name': 'pulsr-1.2.0.apk',
            'state': 'uploaded',
            'browser_download_url': 'https://github.com/pulsr-audio/pulsr/releases/download/v1.2.0/pulsr-1.2.0.apk',
          },
        ],
      };

      final info = UpdateInfo.fromGitHubJson(json);
      expect(info.version, '1.2.0');
      expect(info.tagName, 'v1.2.0');
      expect(info.releaseUrl, 'https://github.com/pulsr-audio/pulsr/releases/tag/v1.2.0');
      expect(info.apkUrl, 'https://github.com/pulsr-audio/pulsr/releases/download/v1.2.0/pulsr-1.2.0.apk');
      expect(info.notes, contains('Added Discord Rich Presence'));
    });

    test('handles release without apk gracefully', () {
      final json = {
        'tag_name': 'v1.0.5',
        'html_url': 'https://github.com/pulsr-audio/pulsr/releases/tag/v1.0.5',
        'body': 'Draft notes',
        'assets': <dynamic>[],
      };

      final info = UpdateInfo.fromGitHubJson(json);
      expect(info.version, '1.0.5');
      expect(info.apkUrl, isNull);
    });
  });
}
