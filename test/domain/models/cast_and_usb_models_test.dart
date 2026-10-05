import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/domain/services/cast_service.dart';
import 'package:pulsr/domain/services/usb_exclusive_service.dart';

void main() {
  group('CastDevice.fromMap', () {
    test('maps all fields and tolerates missing optional values', () {
      final d = CastDevice.fromMap({
        'id': 'abc123',
        'name': 'Living Room TV',
        'model': 'Chromecast Ultra',
        'host': '192.168.1.20',
        'port': 8009,
      });
      expect(d, isNotNull);
      expect(d!.id, 'abc123');
      expect(d.name, 'Living Room TV');
      expect(d.model, 'Chromecast Ultra');
      expect(d.port, 8009);
    });

    test('returns null without an id and falls back name to id', () {
      expect(CastDevice.fromMap({'name': 'x'}), isNull);
      final d = CastDevice.fromMap({'id': 'only-id'})!;
      expect(d.name, 'only-id');
      expect(d.model, '');
    });
  });

  group('CastRoute.fromMap', () {
    test('maps route fields', () {
      final r = CastRoute.fromMap({
        'id': 'route-1',
        'name': 'Kitchen Speaker',
        'connected': true,
        'selected': true,
      });
      expect(r, isNotNull);
      expect(r!.id, 'route-1');
      expect(r.name, 'Kitchen Speaker');
      expect(r.connected, isTrue);
      expect(r.selected, isTrue);
    });

    test('returns null without id', () {
      expect(CastRoute.fromMap({'name': 'x'}), isNull);
    });
  });

  group('CastSessionStatus.fromMap', () {
    test('marks the SDK available and parses session state', () {
      final s = CastSessionStatus.fromMap({
        'connected': true,
        'deviceName': 'Living Room',
        'playing': true,
        'positionMs': 1234,
      });
      expect(s.available, isTrue);
      expect(s.connected, isTrue);
      expect(s.deviceName, 'Living Room');
      expect(s.playing, isTrue);
      expect(s.positionMs, 1234);
    });

    test('defaults unavailable', () {
      expect(CastSessionStatus.unavailable.available, isFalse);
      expect(CastSessionStatus.unavailable.connected, isFalse);
    });
  });

  group('UsbExclusiveStatus.fromMap', () {
    test('parses a full UAC2 status', () {
      final s = UsbExclusiveStatus.fromMap({
        'attached': true,
        'permitted': true,
        'deviceName': 'Topping E30',
        'vendorId': 0x152A,
        'productId': 0x8750,
        'uacVersion': 2,
        'uacLabel': 'UAC2',
        'hasVolumeControl': true,
        'exclusiveActive': false,
        'exclusiveSupported': true,
        'hardwareVolumeDb': -12.5,
        'minVolumeDb': -60.0,
        'maxVolumeDb': 0.0,
        'interfaceNumber': 1,
      });
      expect(s.attached, isTrue);
      expect(s.permitted, isTrue);
      expect(s.deviceName, 'Topping E30');
      expect(s.uacVersion, 2);
      expect(s.hasVolumeControl, isTrue);
      expect(s.exclusiveSupported, isTrue);
      expect(s.hardwareVolumeDb, -12.5);
      expect(s.minVolumeDb, -60.0);
      expect(s.interfaceNumber, 1);
    });

    test('parses streaming fields', () {
      final s = UsbExclusiveStatus.fromMap({
        'attached': true,
        'streamingActive': true,
        'streamingSupported': true,
      });
      expect(s.streamingActive, isTrue);
      expect(s.streamingSupported, isTrue);
    });

    test('defaults gracefully when no device is attached', () {
      final s = UsbExclusiveStatus.fromMap(const {});
      expect(s.attached, isFalse);
      expect(s.permitted, isFalse);
      expect(s.uacVersion, 0);
      expect(s.uacLabel, 'none');
      expect(s.hasVolumeControl, isFalse);
      expect(s.hardwareVolumeDb, isNull);
    });
  });
}
