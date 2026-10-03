// Edge-case coverage for ProxyConfig/ProxyEntry: boundary validation, wildcard
// bypass rules, IPv6 formatting, parser delimiter/URI branches and map codecs.
// Existing happy-path coverage lives in test/proxy_config_test.dart.
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/network/proxy_config.dart';

void main() {
  group('AppProxyType', () {
    test('displayName covers both variants', () {
      expect(AppProxyType.http.displayName, 'HTTP / HTTPS');
      expect(AppProxyType.socks5.displayName, 'SOCKS5');
    });
  });

  group('ProxyConfig validation and formatting', () {
    test('isValid checks for a non-blank host and a valid port range', () {
      expect(const ProxyConfig(host: '   ', port: 8080).isValid, isFalse);
      expect(const ProxyConfig(host: 'p', port: 0).isValid, isFalse);
      expect(const ProxyConfig(host: 'p', port: -1).isValid, isFalse);
      expect(const ProxyConfig(host: 'p', port: 65535).isValid, isTrue);
      expect(const ProxyConfig(host: 'p', port: 65536).isValid, isFalse);
    });

    test('hasAuth ignores whitespace-only usernames', () {
      expect(const ProxyConfig(username: '   ').hasAuth, isFalse);
      expect(const ProxyConfig(username: 'u').hasAuth, isTrue);
    });

    test('bypassList trims, lowercases and drops empty entries', () {
      const config = ProxyConfig(
        bypassHosts: ' LocalHost , EXAMPLE.com ,, *.Internal.NET ',
      );
      expect(config.bypassList, ['localhost', 'example.com', '*.internal.net']);
    });

    test('default bypass list covers localhost and loopback', () {
      const config = ProxyConfig();
      expect(config.bypassList, ['localhost', '127.0.0.1']);
      expect(config.isBypassed(Uri.parse('http://localhost/x')), isTrue);
      expect(config.isBypassed(Uri.parse('http://127.0.0.1/x')), isTrue);
      expect(config.isBypassed(Uri.parse('http://[::1]:8080/x')), isTrue);
      expect(config.isBypassed(Uri.parse('http://example.com/x')), isFalse);
    });

    test('wildcards require a dot boundary', () {
      const config = ProxyConfig(bypassHosts: '*.example.com');
      expect(config.isBypassed(Uri.parse('http://example.com')), isTrue);
      expect(config.isBypassed(Uri.parse('http://a.example.com')), isTrue);
      expect(config.isBypassed(Uri.parse('http://fakeexample.com')), isFalse);
      expect(
        config.isBypassed(Uri.parse('http://notexample.com.cn')),
        isFalse,
      );
    });

    test('toFindProxyString returns DIRECT for disabled/invalid/bypassed', () {
      final uri = Uri.parse('https://music.youtube.com');
      expect(const ProxyConfig().toFindProxyString(uri), 'DIRECT');
      expect(
        const ProxyConfig(enabled: true, host: '', port: 8080)
            .toFindProxyString(uri),
        'DIRECT',
      );
      expect(
        const ProxyConfig(
          enabled: true,
          host: 'proxy.local',
          port: 8080,
          bypassHosts: 'music.youtube.com',
        ).toFindProxyString(uri),
        'DIRECT',
      );
    });

    test('IPv6 hosts are bracketed exactly once', () {
      const raw = ProxyConfig(
        enabled: true,
        host: '::1',
        port: 8080,
      );
      expect(
        raw.toFindProxyString(Uri.parse('https://example.com')),
        'PROXY [::1]:8080; DIRECT',
      );

      const bracketed = ProxyConfig(
        enabled: true,
        host: '[::1]',
        port: 8080,
      );
      expect(
        bracketed.toFindProxyString(Uri.parse('https://example.com')),
        'PROXY [::1]:8080; DIRECT',
      );
    });

    test('isSupportedOnDart is true unless a valid SOCKS proxy is enabled', () {
      expect(const ProxyConfig().isSupportedOnDart, isTrue);
      expect(
        const ProxyConfig(enabled: true, type: AppProxyType.socks5, host: '')
            .isSupportedOnDart,
        isTrue,
      );
      expect(
        const ProxyConfig(
          enabled: true,
          type: AppProxyType.socks5,
          host: 'proxy.local',
          port: 1080,
        ).isSupportedOnDart,
        isFalse,
      );
      expect(
        const ProxyConfig(
          enabled: true,
          type: AppProxyType.http,
          host: 'proxy.local',
          port: 3128,
        ).isSupportedOnDart,
        isTrue,
      );
    });

    test('toMap trims host and username but keeps the password verbatim', () {
      const config = ProxyConfig(
        enabled: true,
        type: AppProxyType.socks5,
        host: '  proxy.local  ',
        port: 1080,
        username: '  user  ',
        password: '  p@ss  ',
        bypassHosts: '',
      );
      final map = config.toMap();
      expect(map['host'], 'proxy.local');
      expect(map['username'], 'user');
      expect(map['password'], '  p@ss  ');
      expect(map['type'], 'socks5');
      expect(map['enabled'], isTrue);
    });

    test('fromMap applies defaults for missing and mistyped fields', () {
      final config = ProxyConfig.fromMap(const {});
      expect(config.enabled, isFalse);
      expect(config.type, AppProxyType.http);
      expect(config.host, '');
      expect(config.port, 8080);
      expect(config.username, '');
      expect(config.password, '');
      expect(config.bypassHosts, 'localhost, 127.0.0.1');

      final coerced = ProxyConfig.fromMap(const {
        'type': 'socks5',
        'port': 1080.0,
        'enabled': true,
        'host': 'h',
      });
      expect(coerced.type, AppProxyType.socks5);
      expect(coerced.port, 1080);
      expect(coerced.enabled, isTrue);

      final unknown = ProxyConfig.fromMap(const {'type': 'ftp'});
      expect(unknown.type, AppProxyType.http);
    });

    test('copyWith overrides only supplied fields', () {
      const base = ProxyConfig(
        enabled: true,
        type: AppProxyType.http,
        host: 'h',
        port: 8080,
        username: 'u',
        password: 'p',
        bypassHosts: 'a',
      );
      final copy = base.copyWith(
        enabled: false,
        type: AppProxyType.socks5,
        host: 'h2',
        port: 1080,
        username: 'u2',
        password: 'p2',
        bypassHosts: 'b',
      );
      expect(copy.enabled, isFalse);
      expect(copy.type, AppProxyType.socks5);
      expect(copy.host, 'h2');
      expect(copy.port, 1080);
      expect(copy.username, 'u2');
      expect(copy.password, 'p2');
      expect(copy.bypassHosts, 'b');

      final untouched = base.copyWith();
      expect(untouched.host, 'h');
      expect(untouched.port, 8080);
    });
  });

  group('ProxyEntry basics', () {
    test('isValid/hasAuth/display helpers', () {
      const entry = ProxyEntry(
        id: '1',
        host: '  proxy.local  ',
        port: 1080,
        username: '  ',
      );
      expect(entry.isValid, isTrue);
      expect(entry.hasAuth, isFalse);
      expect(entry.displayAddress, '  proxy.local  :1080');
      expect(entry.displayTitle, '  proxy.local  :1080');

      const labelled = ProxyEntry(
        id: '2',
        host: 'p',
        port: 1,
        label: '  Fast US  ',
      );
      expect(labelled.displayTitle, 'Fast US');

      const invalid = ProxyEntry(id: '3', host: ' ', port: 0);
      expect(invalid.isValid, isFalse);
    });

    test('toProxyConfig trims host/username and honours flags', () {
      const entry = ProxyEntry(
        id: '1',
        host: '  proxy.local ',
        port: 1080,
        username: ' user ',
        password: 'pw',
        type: AppProxyType.socks5,
      );
      final config = entry.toProxyConfig(enabled: false, bypassHosts: 'x');
      expect(config.enabled, isFalse);
      expect(config.type, AppProxyType.socks5);
      expect(config.host, 'proxy.local');
      expect(config.port, 1080);
      expect(config.username, 'user');
      expect(config.password, 'pw');
      expect(config.bypassHosts, 'x');
    });

    test('toMap/fromMap round trip with null optional fields', () {
      const entry = ProxyEntry(id: 'id1', host: 'h', port: 80);
      final map = entry.toMap();
      expect(map['latencyMs'], isNull);
      expect(map['isWorking'], isNull);
      expect(map['lastError'], isNull);

      final restored = ProxyEntry.fromMap(const {});
      expect(restored.id, 'null:null');
      expect(restored.host, '');
      expect(restored.port, 8080);
      expect(restored.type, AppProxyType.http);
      expect(restored.latencyMs, isNull);
      expect(restored.isWorking, isNull);
      expect(restored.lastError, isNull);

      final coerced = ProxyEntry.fromMap(const {
        'id': 'x',
        'type': 'nope',
        'port': 443.0,
        'latencyMs': 12.0,
        'isWorking': true,
        'label': 'L',
      });
      expect(coerced.type, AppProxyType.http);
      expect(coerced.port, 443);
      expect(coerced.latencyMs, 12);
      expect(coerced.isWorking, isTrue);
      expect(coerced.label, 'L');
    });

    test('copyWith clears lastError explicitly and preserves the rest', () {
      const entry = ProxyEntry(
        id: '1',
        host: 'h',
        port: 80,
        label: 'L',
        latencyMs: 10,
        isWorking: false,
        lastError: 'boom',
      );
      final cleared = entry.copyWith(clearLastError: true, isTesting: true);
      expect(cleared.lastError, isNull);
      expect(cleared.isTesting, isTrue);
      expect(cleared.label, 'L');
      expect(cleared.latencyMs, 10);
      expect(cleared.isWorking, isFalse);

      final replaced = entry.copyWith(
        id: '2',
        host: 'h2',
        port: 81,
        username: 'u',
        password: 'p',
        type: AppProxyType.socks5,
        label: 'L2',
        latencyMs: 20,
        isWorking: true,
        lastError: 'other',
      );
      expect(replaced.id, '2');
      expect(replaced.host, 'h2');
      expect(replaced.port, 81);
      expect(replaced.username, 'u');
      expect(replaced.password, 'p');
      expect(replaced.type, AppProxyType.socks5);
      expect(replaced.label, 'L2');
      expect(replaced.latencyMs, 20);
      expect(replaced.isWorking, isTrue);
      expect(replaced.lastError, 'other');
      expect(replaced.isTesting, isFalse);
    });
  });

  group('ProxyEntry.parse', () {
    test('rejects blank lines and comments', () {
      expect(ProxyEntry.parse(''), isNull);
      expect(ProxyEntry.parse('   '), isNull);
      expect(ProxyEntry.parse('# comment'), isNull);
      expect(ProxyEntry.parse('// comment'), isNull);
    });

    test('parses URI schemes and detects SOCKS5', () {
      final httpEntry = ProxyEntry.parse('http://user:pass@host.example:3128');
      expect(httpEntry, isNotNull);
      expect(httpEntry!.host, 'host.example');
      expect(httpEntry.port, 3128);
      expect(httpEntry.username, 'user');
      expect(httpEntry.password, 'pass');
      expect(httpEntry.type, AppProxyType.http);

      final socksEntry = ProxyEntry.parse('socks://host.example:1080');
      expect(socksEntry!.type, AppProxyType.socks5);
      expect(socksEntry.port, 1080);

      final uppercase = ProxyEntry.parse('SOCKS5://u:p@[::1]:1080');
      expect(uppercase!.type, AppProxyType.socks5);
      expect(uppercase.host, '::1');
      expect(uppercase.port, 1080);
      expect(uppercase.username, 'u');
      expect(uppercase.password, 'p');
    });

    test('decodes percent-encoded user info and uses the scheme default port',
        () {
      final entry = ProxyEntry.parse('http://us%40er:p%3Ass@host.example');
      expect(entry!.username, 'us@er');
      expect(entry.password, 'p:ss');
      // A scheme with no default port (socks) falls back to 8080.
      expect(entry.port, 80);

      final socks = ProxyEntry.parse('socks5://user@host.example');
      expect(socks!.port, 8080);
    });

    test('parses user:pass@host:port and bracketed IPv6 forms', () {
      final plain = ProxyEntry.parse('user:pass@host.example:8080');
      expect(plain!.host, 'host.example');
      expect(plain.port, 8080);
      expect(plain.username, 'user');
      expect(plain.password, 'pass');

      final noPassword = ProxyEntry.parse('user@host.example');
      expect(noPassword!.username, 'user');
      expect(noPassword.password, '');
      expect(noPassword.port, 8080);

      final ipv6 = ProxyEntry.parse('user:pass@[::1]:1080');
      expect(ipv6!.host, '::1');
      expect(ipv6.port, 1080);
      expect(ipv6.username, 'user');
      expect(ipv6.password, 'pass');

      final ipv6NoPort = ProxyEntry.parse('user@[::1]');
      expect(ipv6NoPort!.host, '::1');
      expect(ipv6NoPort.port, 8080);
    });

    test('parses colon, comma, tab and whitespace delimiters', () {
      final colon = ProxyEntry.parse('host.example:8080:user:pa:ss');
      expect(colon!.host, 'host.example');
      expect(colon.port, 8080);
      expect(colon.username, 'user');
      expect(colon.password, 'pa:ss');

      final comma = ProxyEntry.parse('host.example,1080,user,pass');
      expect(comma!.host, 'host.example');
      expect(comma.port, 1080);
      expect(comma.username, 'user');
      expect(comma.password, 'pass');

      final tab = ProxyEntry.parse('host.example\t1080\tuser\tpass');
      expect(tab!.host, 'host.example');
      expect(tab.port, 1080);
      expect(tab.username, 'user');

      final spaces = ProxyEntry.parse('host.example 1080 user pass');
      expect(spaces!.host, 'host.example');
      expect(spaces.port, 1080);
      expect(spaces.password, 'pass');
    });

    test('non-numeric ports default to 8080', () {
      expect(ProxyEntry.parse('host.example:not-a-port')!.port, 8080);
      expect(ProxyEntry.parse('host.example,abc')!.port, 8080);
    });

    test('supports bracketed IPv6 with credentials via the delimiter path', () {
      final entry = ProxyEntry.parse('[::1]:1080:user:pass');
      expect(entry!.host, '::1');
      expect(entry.port, 1080);
      expect(entry.username, 'user');
      expect(entry.password, 'pass');
    });

    test('bare IPv6 handling follows the delimiter heuristic', () {
      // A numeric bare IPv6 is kept whole with the default port.
      final loopback = ProxyEntry.parse('::1');
      expect(loopback!.host, '::1');
      expect(loopback.port, 8080);

      // A leading alphabetic group is not recognized as IPv6 and is split.
      final linkLocal = ProxyEntry.parse('fe80::1');
      expect(linkLocal!.host, 'fe80');
      expect(linkLocal.port, 1);
    });

    test('malformed bracketed entries are rejected', () {
      expect(ProxyEntry.parse('[::1'), isNull);
    });

    test('a URI that fails to parse falls back to scheme stripping', () {
      // Uri.tryParse returns null for the malformed bracket, then the scheme
      // is stripped and the leading '[' is rejected.
      expect(ProxyEntry.parse('http://[::1'), isNull);
      expect(ProxyEntry.parse('socks5://[::1'), isNull);
    });

    test('a lone host defaults the port and empty auth fields', () {
      final entry = ProxyEntry.parse('proxy.example');
      expect(entry!.host, 'proxy.example');
      expect(entry.port, 8080);
      expect(entry.username, '');
      expect(entry.password, '');
      expect(entry.type, AppProxyType.http);
    });

    test('parseList dedupes on host/port/user and re-ids entries', () {
      final list = ProxyEntry.parseList('''
host.example:1080:user:one
host.example:1080:user:two
host.example:1080:other:three
host.example:1081:user:four

# comment
''');
      expect(list, hasLength(3));
      expect(list[0].password, 'one');
      expect(list[0].id, startsWith('proxy_1_'));
      expect(list[2].port, 1081);
    });

    test('parseList caps the number of parsed entries at 5000', () {
      final buffer = StringBuffer();
      for (int i = 0; i < 5010; i++) {
        buffer.writeln('10.0.$i.1:1080');
      }
      final list = ProxyEntry.parseList(buffer.toString());
      expect(list, hasLength(5000));
    });

    test('parseList ignores entries whose port range is invalid', () {
      final list = ProxyEntry.parseList('host.example:0\nhost.example:70000');
      expect(list, isEmpty);
    });

    test('parseList truncates pathological input at 10 MB', () {
      final buffer = StringBuffer('10.0.0.1:1080\n')
        ..write(' ' * (10 * 1024 * 1024 + 16));
      final list = ProxyEntry.parseList(buffer.toString());
      expect(list, hasLength(1));
      expect(list.single.host, '10.0.0.1');
      expect(list.single.port, 1080);
    });
  });
}
