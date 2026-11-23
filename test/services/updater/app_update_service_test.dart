import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pulsr/services/updater/app_update_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

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
        'body':
            '## What is new\n- Added Discord Rich Presence\n- Added In-App Updater',
        'published_at': '2026-10-12T00:00:00Z',
        'assets': [
          {
            'name': 'source-code.zip',
            'state': 'uploaded',
            'browser_download_url':
                'https://github.com/pulsr-audio/pulsr/releases/download/v1.2.0/source.zip',
          },
          {
            'name': 'pulsr-1.2.0.apk',
            'state': 'uploaded',
            'browser_download_url':
                'https://github.com/pulsr-audio/pulsr/releases/download/v1.2.0/pulsr-1.2.0.apk',
          },
        ],
      };

      final info = UpdateInfo.fromGitHubJson(json);
      expect(info.version, '1.2.0');
      expect(info.tagName, 'v1.2.0');
      expect(info.releaseUrl,
          'https://github.com/pulsr-audio/pulsr/releases/tag/v1.2.0');
      expect(info.apkUrl,
          'https://github.com/pulsr-audio/pulsr/releases/download/v1.2.0/pulsr-1.2.0.apk');
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

  group('AppUpdateService security & integrity (BUG-P1-17)', () {
    test('enforces HTTPS and GitHub release host allowlist on apkUrl', () {
      expect(
        AppUpdateService.isAllowedApkUrl(
          'https://github.com/pulsr-audio/pulsr/releases/download/v1.0.0/pulsr.apk',
        ),
        isTrue,
      );
      expect(
        AppUpdateService.isAllowedApkUrl(
          'https://objects.githubusercontent.com/github-production-release-asset/pulsr.apk',
        ),
        isTrue,
      );
      expect(
        AppUpdateService.isAllowedApkUrl(
          'http://github.com/pulsr-audio/pulsr/releases/download/v1.0.0/pulsr.apk',
        ),
        isFalse,
      );
      expect(
        AppUpdateService.isAllowedApkUrl(
          'https://evil.example.com/pulsr.apk',
        ),
        isFalse,
      );
    });

    test('sanitizes version before building APK filename', () {
      expect(
        AppUpdateService.sanitizeVersionForFilename('../../etc/passwd'),
        isNot(contains('..')),
      );
      expect(
        AppUpdateService.sanitizeVersionForFilename('../../etc/passwd'),
        isNot(contains('/')),
      );
      expect(
        AppUpdateService.sanitizeVersionForFilename('1.2.0-beta.1'),
        equals('1.2.0-beta.1'),
      );
    });

    test('verifies SHA-256 checksum and deletes partial APK on mismatch', () async {
      final payload = utf8.encode('fake-apk-binary-payload');
      final validSha = sha256.convert(payload).toString();
      final tempDir = await Directory.systemTemp.createTemp('pulsr_updater_test_');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final client = MockClient.streaming((request, _) async {
        return http.StreamedResponse(
          Stream.fromIterable([payload]),
          200,
          contentLength: payload.length,
        );
      });
      final service = AppUpdateService(client: client);
      addTearDown(() => service.dispose());

      // 1. Valid SHA-256 succeeds
      final goodFile = await service.downloadApk(
        UpdateInfo(
          version: '1.2.0',
          tagName: 'v1.2.0',
          releaseUrl: 'https://github.com/pulsr-audio/pulsr/releases/tag/v1.2.0',
          apkUrl:
              'https://github.com/pulsr-audio/pulsr/releases/download/v1.2.0/pulsr.apk',
          sha256: validSha,
        ),
        cacheDirectoryOverride: tempDir,
      );
      expect(goodFile, isNotNull);
      expect(await goodFile!.exists(), isTrue);

      // 2. Bad SHA-256 throws and deletes the corrupt file
      await expectLater(
        () => service.downloadApk(
          UpdateInfo(
            version: '1.2.1',
            tagName: 'v1.2.1',
            releaseUrl:
                'https://github.com/pulsr-audio/pulsr/releases/tag/v1.2.1',
            apkUrl:
                'https://github.com/pulsr-audio/pulsr/releases/download/v1.2.1/pulsr.apk',
            sha256: '0' * 64,
          ),
          cacheDirectoryOverride: tempDir,
        ),
        throwsStateError,
      );
      final updatesDir = Directory('${tempDir.path}/updates');
      final remaining = updatesDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.apk'))
          .toList();
      expect(remaining, isEmpty);
    });

    test('ParsedVersion ignores +build suffix cleanly during comparison', () {
      expect(ParsedVersion.isNewer('1.2.4+5', '1.2.3+99'), isTrue);
      expect(ParsedVersion.isNewer('1.2.3+5', '1.2.3+1'), isFalse);
      expect(ParsedVersion.parse('2.0.1+42').parts, [2, 0, 1]);
    });

    test('rejects APK download when mandatory sha256 is absent', () async {
      final client = MockClient.streaming((request, _) async {
        return http.StreamedResponse(Stream.fromIterable([utf8.encode('apk')]), 200);
      });
      final service = AppUpdateService(client: client);
      addTearDown(() => service.dispose());
      final tempDir = await Directory.systemTemp.createTemp('pulsr_upd_nosha_');
      addTearDown(() async {
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
      });

      await expectLater(
        () => service.downloadApk(
          const UpdateInfo(
            version: '1.2.2',
            tagName: 'v1.2.2',
            releaseUrl:
                'https://github.com/pulsr-audio/pulsr/releases/tag/v1.2.2',
            apkUrl:
                'https://github.com/pulsr-audio/pulsr/releases/download/v1.2.2/pulsr.apk',
          ),
          cacheDirectoryOverride: tempDir,
        ),
        throwsArgumentError,
      );
    });

    test('blocks APK redirect to non-allowlisted host', () async {
      final client = MockClient.streaming((request, _) async {
        return http.StreamedResponse(
          const Stream<List<int>>.empty(),
          302,
          headers: {'location': 'https://evil.example.com/malicious.apk'},
        );
      });
      final service = AppUpdateService(client: client);
      addTearDown(() => service.dispose());
      final tempDir = await Directory.systemTemp.createTemp('pulsr_upd_redir_');
      addTearDown(() async {
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
      });

      await expectLater(
        () => service.downloadApk(
          UpdateInfo(
            version: '1.2.3',
            tagName: 'v1.2.3',
            releaseUrl:
                'https://github.com/pulsr-audio/pulsr/releases/tag/v1.2.3',
            apkUrl:
                'https://github.com/pulsr-audio/pulsr/releases/download/v1.2.3/pulsr.apk',
            sha256: 'a' * 64,
          ),
          cacheDirectoryOverride: tempDir,
        ),
        throwsStateError,
      );
    });

    test('respects offlineOnlyMode in checkForUpdate', () async {
      SharedPreferences.setMockInitialValues({'setting_offline_only_mode': true});
      var called = false;
      final client = MockClient((request) async {
        called = true;
        return http.Response('{}', 200);
      });
      final service = AppUpdateService(client: client);
      addTearDown(() => service.dispose());

      final info = await service.check();
      expect(info, isNull);
      expect(called, isFalse);
    });
  });
}
