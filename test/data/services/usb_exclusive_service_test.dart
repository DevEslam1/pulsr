// UsbExclusiveService coverage. Under flutter_test `defaultTargetPlatform` is
// Android, so the otherwise Android-gated method-channel paths run here. Each
// test stubs the `com.pulsr.music/usb_exclusive` channel and drives the public
// API; the pure enum/model logic is also exercised (defensively, so this file
// stands alone).
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/constants/channels.dart';
import 'package:pulsr/data/services/usb_exclusive_service.dart';

const MethodChannel _method = MethodChannel(PulsrChannels.usbExclusive);
const MethodChannel _events = MethodChannel(PulsrChannels.usbExclusiveEvents);

TestDefaultBinaryMessenger get _messenger =>
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

Map<String, Object?> _statusMap({
  bool attached = true,
  bool permitted = true,
  bool streamingSupported = true,
  bool exclusiveSupported = true,
  bool streaming = false,
  int sampleRate = 48000,
  int bitDepth = 16,
  int channels = 2,
  double? minDb = -60.0,
  double? maxDb = 6.0,
  List<int> rates = const [48000, 44100],
  String deviceName = 'Test DAC',
}) =>
    <String, Object?>{
      'attached': attached,
      'permitted': permitted,
      'deviceName': deviceName,
      'vendorId': 1234,
      'productId': 5678,
      'uacVersion': 2,
      'uacLabel': 'UAC2',
      'hasVolumeControl': true,
      'exclusiveSupported': exclusiveSupported,
      'hardwareVolumeDb': 0.0,
      'minVolumeDb': minDb,
      'maxVolumeDb': maxDb,
      'interfaceNumber': 3,
      'streamingSupported': streamingSupported,
      'streamingActive': streaming,
      // Only the endpoint's actually opened format can confirm a start; the
      // device identity is known as soon as the DAC is attached.
      'deviceId': 7,
      'streamingSampleRate': streaming ? sampleRate : 0,
      'streamingBitDepth': streaming ? bitDepth : 0,
      'streamingChannels': streaming ? channels : 0,
      'hardwareVolumeApplied': false,
      'supportedRates': rates,
      'lastError': 0,
      'resultCode': 7,
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final service = UsbExclusiveService();
  // Mirrors the native side: a start is only trusted once the endpoint reports
  // the format it actually opened on this device.
  var streamingConfirmed = false;

  setUp(() {
    streamingConfirmed = false;
    _messenger.setMockMethodCallHandler(_method, (call) async {
      switch (call.method) {
        case 'getStatus':
          return _statusMap(streaming: streamingConfirmed);
        case 'requestPermission':
          return true;
        case 'setExclusive':
          return <Object?, Object?>{'error': null};
        case 'setHardwareVolume':
          return true;
        case 'startStreaming':
          streamingConfirmed = true;
          return <Object?, Object?>{'success': true};
        case 'stopStreaming':
          streamingConfirmed = false;
          return <Object?, Object?>{'success': true};
        case 'querySupportedRates':
          return <Object?>[96000, 44100, 48000];
        case 'getBufferedMs':
          return 12;
        case 'getDiagnostics':
          return <Object?, Object?>{'underruns': 2};
        default:
          return null;
      }
    });
    _messenger.setMockMethodCallHandler(_events, (call) async => null);
  });

  tearDown(() {
    _messenger.setMockMethodCallHandler(_method, null);
    _messenger.setMockMethodCallHandler(_events, null);
  });

  group('UsbStreamResult', () {
    test('isOk and user messages cover every code', () {
      expect(UsbStreamResult.ok.isOk, isTrue);
      expect(UsbStreamResult.claimFailed.isOk, isFalse);

      expect(UsbStreamResult.ok.toUserMessage(), 'Streaming active');
      expect(UsbStreamResult.claimFailed.toUserMessage(), contains('busy'));
      expect(UsbStreamResult.altSettingFailed.toUserMessage(),
          contains('alternate setting'));
      expect(UsbStreamResult.rateUnsupported.toUserMessage(),
          contains('sample rate'));
      expect(UsbStreamResult.submitFailed.toUserMessage(), contains('URBs'));
      expect(UsbStreamResult.invalidArgs.toUserMessage(), contains('Invalid'));
      expect(UsbStreamResult.unknown.toUserMessage(), contains('bit-perfect'));
    });
  });

  group('UsbExclusiveStatus.fromMap', () {
    test('parses a full status payload', () {
      final status = UsbExclusiveStatus.fromMap(_statusMap());
      expect(status.attached, isTrue);
      expect(status.deviceName, 'Test DAC');
      expect(status.vendorId, 1234);
      expect(status.uacVersion, 2);
      expect(status.uacLabel, 'UAC2');
      expect(status.supportedRates, [48000, 44100]);
      expect(status.lastStreamErrorCode, 7);
      expect(status.minVolumeDb, -60.0);
    });

    test('falls back to defaults for an empty map', () {
      final status = UsbExclusiveStatus.fromMap(const {});
      expect(status.attached, isFalse);
      expect(status.uacVersion, 0);
      expect(status.uacLabel, 'none');
      expect(status.supportedRates, isEmpty);
    });
  });

  group('getStatus', () {
    test('parses the native response and caches it', () async {
      final status = await service.getStatus();
      expect(status.attached, isTrue);
      expect(service.lastStatus.deviceName, 'Test DAC');
    });

    test('invalidates the cached status when native returns null', () async {
      await service.getStatus();
      _messenger.setMockMethodCallHandler(_method, (call) async => null);
      final status = await service.getStatus();
      expect(status.attached, isFalse);
    });
  });

  group('requestPermission', () {
    test('returns the granted flag and refreshes status', () async {
      expect(await service.requestPermission(), isTrue);
    });

    test('returns false when the native call throws', () async {
      _messenger.setMockMethodCallHandler(_method, (call) async {
        if (call.method == 'requestPermission') {
          throw PlatformException(code: 'error');
        }
        return _statusMap();
      });
      expect(await service.requestPermission(), isFalse);
    });
  });

  group('setExclusive', () {
    test('returns false when the device is not attached/permitted', () async {
      _messenger.setMockMethodCallHandler(
          _method,
          (call) async => call.method == 'getStatus'
              ? _statusMap(attached: false, permitted: false)
              : null);
      expect(await service.setExclusive(true), isFalse);
    });

    test('returns true on a map response with no error', () async {
      expect(await service.setExclusive(true), isTrue);
    });

    test('returns false when the native call throws', () async {
      _messenger.setMockMethodCallHandler(_method, (call) async {
        if (call.method == 'setExclusive') {
          throw PlatformException(code: 'error');
        }
        return _statusMap();
      });
      expect(await service.setExclusive(true), isFalse);
    });
  });

  group('setHardwareVolume', () {
    test('clamps and succeeds', () async {
      Map<dynamic, dynamic>? args;
      _messenger.setMockMethodCallHandler(_method, (call) async {
        if (call.method == 'setHardwareVolume') {
          args = call.arguments as Map<dynamic, dynamic>;
          return true;
        }
        return _statusMap();
      });
      await service.getStatus();
      expect(await service.setHardwareVolume(100), isTrue);
      expect(args!['db'], 6.0); // clamped to maxVolumeDb
    });

    test('returns false when the native reply carries an error', () async {
      _messenger.setMockMethodCallHandler(_method, (call) async {
        if (call.method == 'setHardwareVolume') {
          return <Object?, Object?>{'error': 'nope'};
        }
        return _statusMap();
      });
      await service.getStatus();
      expect(await service.setHardwareVolume(0), isFalse);
    });
  });

  group('startStreaming', () {
    test('rejects an unsupported sample rate', () async {
      expect(await service.startStreaming(sampleRate: 12345),
          UsbStreamResult.rateUnsupported);
    });

    test('rejects an out-of-range channel count', () async {
      expect(await service.startStreaming(channels: 0),
          UsbStreamResult.invalidArgs);
      expect(await service.startStreaming(channels: 9),
          UsbStreamResult.invalidArgs);
    });

    test('returns claimFailed when the device is not permitted', () async {
      _messenger.setMockMethodCallHandler(
          _method,
          (call) async =>
              call.method == 'getStatus' ? _statusMap(permitted: false) : null);
      await service.getStatus();
      expect(await service.startStreaming(), UsbStreamResult.claimFailed);
    });

    test('returns invalidArgs when streaming is not supported', () async {
      _messenger.setMockMethodCallHandler(
          _method,
          (call) async => call.method == 'getStatus'
              ? _statusMap(permitted: true, streamingSupported: false)
              : null);
      await service.getStatus();
      expect(await service.startStreaming(), UsbStreamResult.invalidArgs);
    });

    test('maps native error strings to result codes', () async {
      Future<UsbStreamResult> withError(String code) async {
        _messenger.setMockMethodCallHandler(_method, (call) async {
          if (call.method == 'startStreaming') {
            return <Object?, Object?>{'success': false, 'error': code};
          }
          return _statusMap();
        });
        await service.getStatus();
        return service.startStreaming();
      }

      expect(await withError('claim_failed'), UsbStreamResult.claimFailed);
      expect(await withError('alt_setting_failed'),
          UsbStreamResult.altSettingFailed);
      expect(
          await withError('rate_unsupported'), UsbStreamResult.rateUnsupported);
      expect(await withError('submit_failed'), UsbStreamResult.submitFailed);
      expect(await withError('invalid_args'), UsbStreamResult.invalidArgs);
      expect(await withError('mystery'), UsbStreamResult.unknown);
    });

    test('returns ok on success', () async {
      await service.getStatus();
      expect(await service.startStreaming(), UsbStreamResult.ok);
    });
  });

  test('stop requires fresh confirmation that the stream is inactive', () async {
    await service.getStatus(); // cached inactive status must not prove teardown
    _messenger.setMockMethodCallHandler(_method, (call) async {
      if (call.method == 'stopStreaming') return {'success': true};
      return null;
    });
    expect(await service.stopStreaming(), isFalse);
    _messenger.setMockMethodCallHandler(_method, (call) async {
      if (call.method == 'stopStreaming') return {'success': true};
      return {..._statusMap(), 'streamingActive': true};
    });
    expect(await service.stopStreaming(), isFalse);
  });

  test('start does not trust cached permission or an unconfirmed success', () async {
    await service.getStatus();
    _messenger.setMockMethodCallHandler(_method, (call) async {
      if (call.method == 'startStreaming') return {'success': true};
      return null;
    });
    expect(await service.startStreaming(), isNot(UsbStreamResult.ok));
  });

  group('misc channel calls', () {
    test('querySupportedRates sorts the native list', () async {
      expect(await service.querySupportedRates(), [44100, 48000, 96000]);
    });

    test('stopStreaming reports success', () async {
      expect(await service.stopStreaming(), isTrue);
    });

    test('getBufferedMs returns the numeric value', () async {
      expect(await service.getBufferedMs(), 12.0);
    });

    test('getDiagnostics returns the map', () async {
      expect(await service.getDiagnostics(), {'underruns': 2});
    });
  });

  test('the event stream forwards parsed status maps', () async {
    await service.getStatus(); // attaches the event listener
    final received = <UsbExclusiveStatus>[];
    final sub = service.statusStream.listen(received.add);
    addTearDown(sub.cancel);

    await Future<void>.delayed(Duration.zero);

    const codec = StandardMethodCodec();
    await _messenger.handlePlatformMessage(
      PulsrChannels.usbExclusiveEvents,
      codec.encodeSuccessEnvelope(_statusMap(deviceName: 'Live DAC')),
      null,
    );
    await Future<void>.delayed(Duration.zero);

    expect(received, isNotEmpty);
    expect(received.last.deviceName, 'Live DAC');
  });

  test('dispose is idempotent and tears the stream down', () {
    service.dispose();
    service.dispose();
  });
}
