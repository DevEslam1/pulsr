// URL safety coverage for RadioStation: IPv4-mapped IPv6 forms, unspecified
// and CGNAT addresses, and case-insensitive scheme handling.
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/domain/models/radio_station.dart';

void main() {
  group('RadioStation.isHttpUrl unsafe hosts', () {
    test('rejects IPv4-mapped private IPv6 hosts', () {
      expect(RadioStation.isHttpUrl('http://[::ffff:192.168.1.1]/stream'),
          isFalse);
      expect(RadioStation.isHttpUrl('http://[::ffff:127.0.0.1]/'), isFalse);
      expect(RadioStation.isHttpUrl('http://[::ffff:7f00:1]/'), isFalse);
      expect(
          RadioStation.isHttpUrl('http://[0:0:0:0:0:ffff:7f00:1]/'), isFalse);
      expect(RadioStation.isHttpUrl('http://[::ffff:0.0.0.0]/'), isFalse);
    });

    test('rejects unspecified, CGNAT and existing private ranges', () {
      expect(RadioStation.isHttpUrl('http://0.0.0.0/stream'), isFalse);
      expect(RadioStation.isHttpUrl('http://100.64.0.1/'), isFalse);
      expect(RadioStation.isHttpUrl('http://10.0.0.5/'), isFalse);
      expect(RadioStation.isHttpUrl('http://172.16.0.1/'), isFalse);
      expect(RadioStation.isHttpUrl('http://192.168.1.1/'), isFalse);
      expect(RadioStation.isHttpUrl('http://169.254.1.1/'), isFalse);
      expect(RadioStation.isHttpUrl('http://[::1]/'), isFalse);
      expect(RadioStation.isHttpUrl('http://[fc00::1]/'), isFalse);
      expect(RadioStation.isHttpUrl('http://[fe80::1]/'), isFalse);
      expect(RadioStation.isHttpUrl('http://localhost/'), isFalse);
    });

    test('accepts public hosts and normalizes the scheme case', () {
      expect(RadioStation.isHttpUrl('https://stream.example.com/live'), isTrue);
      expect(RadioStation.isHttpUrl('HTTPS://stream.example.com/live'), isTrue);
      expect(RadioStation.isHttpUrl('http://8.8.8.8/stream'), isTrue);
      expect(RadioStation.isHttpUrl('http://[2606:4700::1111]/'), isTrue);
      expect(RadioStation.isHttpUrl('file:///etc/passwd'), isFalse);
    });
  });
}
