// Behavior-preservation tests for symbols extracted during fat-file
// decomposition (gaps 01-4, 20-3). These lock the exact semantics of the
// moved code so a future refactor cannot silently change validation rules.
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/audio/eq_frequency_validation.dart';
import 'package:pulsr/features/settings/cubit/proxy_endpoint_validator.dart';

void main() {
  group('isValidCustomFrequencyList', () {
    test('accepts a correctly sized strictly-positive finite table', () {
      expect(isValidCustomFrequencyList([31, 62, 125], 3), isTrue);
    });

    test('rejects wrong length', () {
      expect(isValidCustomFrequencyList([31, 62], 3), isFalse);
      expect(isValidCustomFrequencyList([31, 62, 125, 250], 3), isFalse);
    });

    test('rejects non-positive, NaN and infinite entries', () {
      expect(isValidCustomFrequencyList([31, 0, 125], 3), isFalse);
      expect(isValidCustomFrequencyList([31, -20, 125], 3), isFalse);
      expect(isValidCustomFrequencyList([31, double.nan, 125], 3), isFalse);
      expect(isValidCustomFrequencyList([31, double.infinity, 125], 3), isFalse);
    });
  });

  group('validateProxyHostAndPort', () {
    test('accepts IPv4, hostname and localhost with a valid port', () {
      expect(validateProxyHostAndPort(host: '192.168.1.10', port: 8080), isNull);
      expect(validateProxyHostAndPort(host: 'proxy.example.com', port: 3128),
          isNull);
      expect(validateProxyHostAndPort(host: 'localhost', port: 9050), isNull);
      expect(validateProxyHostAndPort(host: '127.0.0.1', port: 1), isNull);
    });

    test('rejects an empty or malformed host', () {
      expect(validateProxyHostAndPort(host: '', port: 1080), isNotNull);
      expect(validateProxyHostAndPort(host: 'not a host', port: 1080),
          isNotNull);
    });

    test('rejects out-of-range ports', () {
      expect(validateProxyHostAndPort(host: 'proxy.example.com', port: 0),
          isNotNull);
      expect(validateProxyHostAndPort(host: 'proxy.example.com', port: 65536),
          isNotNull);
    });
  });
}
