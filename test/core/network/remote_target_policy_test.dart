// test/core/network/remote_target_policy_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/network/remote_target_policy.dart';
import 'package:pulsr/domain/models/radio_station.dart';

void main() {
  group('classify - scheme and host syntax', () {
    test('accepts absolute http(s) URLs', () {
      expect(RemoteTargetPolicy.isAllowed('https://music.example.org/a.mp3'),
          isTrue);
      expect(RemoteTargetPolicy.isAllowed('http://radio.example.net:8000/live'),
          isTrue);
    });

    test('rejects empty, relative and non-HTTP schemes', () {
      for (final url in [
        '',
        '   ',
        '/music/track.flac',
        'ytmusic://abc',
        'file:///storage/emulated/0/a.mp3',
        'ftp://example.org/a.flac',
        'javascript:alert(1)',
      ]) {
        expect(RemoteTargetPolicy.classify(url),
            RemoteTargetVerdict.invalidScheme,
            reason: url);
      }
    });

    test('rejects a missing host', () {
      expect(RemoteTargetPolicy.isAllowed('https:///path'), isFalse);
      expect(RemoteTargetPolicy.isAllowed('http://'), isFalse);
      expect(RemoteTargetPolicy.isAllowed('http://?q=1'), isFalse);
    });

    test('requireHttps refuses cleartext http', () {
      expect(
        RemoteTargetPolicy.classify('http://example.org/a.jpg',
            requireHttps: true),
        RemoteTargetVerdict.invalidScheme,
      );
      expect(
        RemoteTargetPolicy.isAllowed('https://example.org/a.jpg',
            requireHttps: true),
        isTrue,
      );
    });
  });

  group('classify - private network rejection', () {
    test('rejects loopback, RFC1918, link-local and metadata hosts', () {
      const blocked = [
        'http://localhost/a',
        'http://127.0.0.1/a',
        'http://127.1.2.3/a',
        'http://0.0.0.0/a',
        'http://10.1.2.3/a',
        'http://172.16.0.9/a',
        'http://172.31.255.255/a',
        'http://192.168.1.1/a',
        'http://169.254.169.254/latest/meta-data/',
        'http://100.64.0.5/a',
        'http://printer.local/a',
        'http://[::1]/a',
        'http://[fe80::1]/a',
        'http://[fc00::1]/a',
        'http://[::ffff:192.168.0.2]/a',
        'http://[::ffff:7f00:1]/a',
      ];
      for (final url in blocked) {
        expect(RemoteTargetPolicy.classify(url),
            RemoteTargetVerdict.privateNetwork,
            reason: url);
      }
    });

    test('allows public addresses near but outside the private ranges', () {
      expect(RemoteTargetPolicy.isAllowed('http://172.15.0.1/a'), isTrue);
      expect(RemoteTargetPolicy.isAllowed('http://172.32.0.1/a'), isTrue);
      expect(RemoteTargetPolicy.isAllowed('http://192.169.0.1/a'), isTrue);
      expect(RemoteTargetPolicy.isAllowed('http://8.8.8.8/a'), isTrue);
    });
  });

  group('allowlist', () {
    test('matches on a dot boundary only', () {
      const suffixes = {'youtube.com', 'google.com'};
      expect(RemoteTargetPolicy.hostMatchesAnySuffix('youtube.com', suffixes),
          isTrue);
      expect(
          RemoteTargetPolicy.hostMatchesAnySuffix('music.youtube.com', suffixes),
          isTrue);
      expect(RemoteTargetPolicy.hostMatchesAnySuffix('evilyoutube.com', suffixes),
          isFalse);
      expect(
          RemoteTargetPolicy.hostMatchesAnySuffix('youtube.com.evil.tld', suffixes),
          isFalse);
      expect(
          RemoteTargetPolicy.hostMatchesAnySuffix('notgoogle.com', suffixes),
          isFalse);
    });

    test('an allowlisted host may be private (cast/DLNA renderers)', () {
      const suffixes = {'192.168.1.50'};
      expect(
        RemoteTargetPolicy.classify('http://192.168.1.50:1400/avt',
            allowedHostSuffixes: suffixes),
        RemoteTargetVerdict.allowed,
      );
      // Without the explicit allowlist it stays blocked.
      expect(
        RemoteTargetPolicy.classify('http://192.168.1.50:1400/avt'),
        RemoteTargetVerdict.privateNetwork,
      );
    });

    test('the allowlist never permits cleartext when https is required', () {
      expect(
        RemoteTargetPolicy.classify(
          'http://192.168.1.50/a',
          requireHttps: true,
          allowedHostSuffixes: const {'192.168.1.50'},
        ),
        RemoteTargetVerdict.invalidScheme,
      );
    });
  });

  group('isSafeHost (DNS rebinding)', () {
    test('rejects a public name that resolves into private space', () async {
      final safe = await RemoteTargetPolicy.isSafeHost(
        'rebind.example.com',
        lookup: (_) async => ['192.168.1.10'],
      );
      expect(safe, isFalse);
    });

    test('accepts a name that resolves only to public addresses', () async {
      final safe = await RemoteTargetPolicy.isSafeHost(
        'cdn.example.com',
        lookup: (_) async => ['93.184.216.34', '2606:2800:220:1::1'],
      );
      expect(safe, isTrue);
    });

    test('fails closed when the resolver throws', () async {
      final safe = await RemoteTargetPolicy.isSafeHost(
        'broken.example.com',
        lookup: (_) async => throw const SocketExceptionStub(),
      );
      expect(safe, isFalse);
    });

    test('does not resolve when the host is already private', () async {
      var lookups = 0;
      final safe = await RemoteTargetPolicy.isSafeHost(
        '192.168.0.1',
        lookup: (_) async {
          lookups++;
          return const ['192.168.0.1'];
        },
      );
      expect(safe, isFalse);
      expect(lookups, 0);
    });

    test('an IP literal needs no DNS when no lookup is injected', () async {
      expect(await RemoteTargetPolicy.isSafeHost('93.184.216.34'), isTrue);
      expect(await RemoteTargetPolicy.isSafeHost('10.0.0.1'), isFalse);
    });
  });

  group('parity with the radio model', () {
    test('RadioStation.host checks delegate to the shared policy', () {
      const hosts = [
        'localhost',
        '127.0.0.1',
        '10.0.0.5',
        '172.20.1.1',
        '192.168.1.20',
        '169.254.169.254',
        '93.184.216.34',
        '::1',
        'fe80::1',
      ];
      for (final host in hosts) {
        expect(
          RadioStation.isUnsafeIpAddress(host),
          RemoteTargetPolicy.isUnsafeHost(host),
          reason: host,
        );
      }
    });

    test('RadioStation.isHttpUrl keeps rejecting internal targets', () {
      expect(RadioStation.isHttpUrl('http://192.168.1.2:8000/live'), isFalse);
      expect(RadioStation.isHttpUrl('https://stream.example.org/live'), isTrue);
      expect(RadioStation.isHttpUrl('ytmusic://abc'), isFalse);
    });
  });
}

/// Stand-in exception so the test does not depend on dart:io's SocketException
/// constructor signature.
class SocketExceptionStub implements Exception {
  const SocketExceptionStub();
}
