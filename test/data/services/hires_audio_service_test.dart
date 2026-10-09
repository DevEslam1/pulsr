// HiResAudioService channel coverage. Under flutter_test `defaultTargetPlatform`
// is Android, so the Android-gated native paths execute against stubbed
// `com.pulsr.music/hires_dac` responses. Pure decision helpers live in
// output_features_test.dart; this file drives the async service surface.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/constants/channels.dart';
import 'package:pulsr/data/services/hires_audio_service.dart';

const MethodChannel _method = MethodChannel(PulsrChannels.hiresDac);
const MethodChannel _events = MethodChannel(PulsrChannels.hiresDacEvents);
const MethodChannel _permissions =
    MethodChannel('flutter.baseflow.com/permissions/methods');

TestDefaultBinaryMessenger get _messenger =>
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

Map<String, Object?> _output({
  String name = 'Test DAC',
  int sampleRate = 48000,
  int bitDepth = 24,
  List<int> rates = const [44100, 48000, 96000],
}) =>
    <String, Object?>{
      'deviceName': name,
      'isUsbDac': true,
      'sampleRate': sampleRate,
      'bitDepth': bitDepth,
      'isBitPerfectActive': false,
      'supportedSampleRates': rates,
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<MethodCall> calls;
  late Map<String, Object?> Function(MethodCall call) responder;
  late HiResAudioService service;

  setUp(() {
    calls = [];
    responder = (call) => _output();
    _messenger.setMockMethodCallHandler(_method, (call) async {
      calls.add(call);
      return responder(call);
    });
    _messenger.setMockMethodCallHandler(_events, (call) async => null);
    _messenger.setMockMethodCallHandler(_permissions, (call) async {
      if (call.method == 'checkPermissionStatus') return 1; // granted
      return null;
    });
    service = HiResAudioService();
  });

  tearDown(() {
    service.dispose();
    _messenger.setMockMethodCallHandler(_method, null);
    _messenger.setMockMethodCallHandler(_events, null);
    _messenger.setMockMethodCallHandler(_permissions, null);
  });

  test('getAudioOutputInfo parses the native payload', () async {
    final info = await service.getAudioOutputInfo();
    expect(info.deviceName, 'Test DAC');
    expect(info.isUsbDac, isTrue);
    expect(info.supportedSampleRates, [44100, 48000, 96000]);
    expect(service.currentOutputInfo, info);
  });

  test('getAudioOutputInfo falls back when native returns null', () async {
    responder = (call) => <String, Object?>{};
    _messenger.setMockMethodCallHandler(_method, (call) async => null);

    final info = await service.getAudioOutputInfo();
    expect(info.deviceName, 'Default Audio Output');
    expect(info.sampleRate, 0);
  });

  test('getDirectCapabilities parses the format list', () async {
    responder = (call) => <String, Object?>{
          'directFormats': [
            {'encoding': '24', 'sampleRate': 96000, 'supported': true},
            {'encoding': 'float', 'sampleRate': 192000, 'supported': false},
          ],
        };
    final formats = await service.getDirectCapabilities();
    expect(formats, hasLength(2));
    expect(formats.first.encoding, '24');
    expect(formats.last.supported, isFalse);
  });

  test('getDirectCapabilities returns empty on channel error', () async {
    _messenger.setMockMethodCallHandler(_method, (call) async {
      throw PlatformException(code: 'x');
    });
    expect(await service.getDirectCapabilities(), isEmpty);
  });

  test('getUsbDacCapabilities returns the map or null', () async {
    responder = (call) => <String, Object?>{'uacVersion': 2, 'label': 'UAC2'};
    expect(await service.getUsbDacCapabilities(), {'uacVersion': 2, 'label': 'UAC2'});
  });

  test('isBitPerfectSupported reflects the native boolean', () async {
    responder = (call) => <String, Object?>{};
    _messenger.setMockMethodCallHandler(
        _method, (call) async => call.method == 'isBitPerfectSupported');
    expect(await service.isBitPerfectSupported(), isTrue);
  });

  test('setBitPerfectMode succeeds', () async {
    responder = (call) => <String, Object?>{'success': true};
    expect(await service.setBitPerfectMode(true), isTrue);
    expect(service.lastBitPerfectFailureReason, isNull);
  });

  test('setBitPerfectMode failure rolls back and records the reason', () async {
    responder = (call) => <String, Object?>{
          'success': false,
          'reason': 'target_format_unavailable',
        };
    expect(await service.setBitPerfectMode(true), isFalse);
    expect(service.lastBitPerfectFailureReason, 'target_format_unavailable');
    expect(
      calls.where((c) => c.method == 'setBitPerfectMode').length,
      1,
    );
    // The rollback uses the legacy boolean setter.
    expect(calls.any((c) => c.method == 'setBitPerfectMode'), isTrue);
  });

  test('setBitPerfectMode channel error records channel_error', () async {
    _messenger.setMockMethodCallHandler(_method, (call) async {
      if (call.method == 'setBitPerfectModeDetailed') {
        throw PlatformException(code: 'x');
      }
      return _output();
    });
    expect(await service.setBitPerfectMode(true), isFalse);
    expect(service.lastBitPerfectFailureReason, 'channel_error');
  });

  test('selectOutputDevice handles map, bool, unknown and error responses',
      () async {
    responder = (call) => <String, Object?>{
          'success': false,
          'error': 'permission_denied',
          'requiresSystemPicker': true,
        };
    var result = await service.selectOutputDevice(5);
    expect(result.success, isFalse);
    expect(result.requiresSystemPicker, isTrue);
    expect(result.error, 'permission_denied');

    _messenger.setMockMethodCallHandler(
        _method, (call) async => call.method == 'setOutputDevice' ? true : _output());
    result = await service.selectOutputDevice(5);
    expect(result.success, isTrue);

    _messenger.setMockMethodCallHandler(
        _method, (call) async => call.method == 'setOutputDevice' ? null : _output());
    result = await service.selectOutputDevice(5);
    expect(result.error, 'unknown_response');

    _messenger.setMockMethodCallHandler(_method, (call) async {
      if (call.method == 'setOutputDevice') throw PlatformException(code: 'x');
      return _output();
    });
    result = await service.selectOutputDevice(5);
    expect(result.error, 'channel_error');
  });

  test('openOutputSwitcher and clearOutputDevice return native success',
      () async {
    _messenger.setMockMethodCallHandler(
        _method,
        (call) async => call.method == 'openOutputSwitcher' ||
                call.method == 'clearOutputDevice'
            ? true
            : _output());
    expect(await service.openOutputSwitcher(), isTrue);
    expect(await service.clearOutputDevice(), isTrue);
  });

  test('setTargetOutputFormat validates rate and bit depth', () async {
    expect(await service.setTargetOutputFormat(sampleRate: 12345), isFalse);
    expect(await service.setTargetOutputFormat(bitDepth: 20), isFalse);
  });

  test('setTargetOutputFormat rejects a rate the device does not support',
      () async {
    responder = (call) => call.method == 'getAudioOutputInfo'
        ? _output(rates: const [48000])
        : <String, Object?>{'success': true};
    _messenger.setMockMethodCallHandler(_method, (call) async {
      calls.add(call);
      final r = responder(call);
      return r;
    });
    await service.getAudioOutputInfo();
    expect(await service.setTargetOutputFormat(sampleRate: 96000), isFalse);
  });

  test('setTargetOutputFormat succeeds for a supported format', () async {
    _messenger.setMockMethodCallHandler(
        _method,
        (call) async => call.method == 'setTargetOutputFormat' ? true : _output());
    expect(await service.setTargetOutputFormat(sampleRate: 48000, bitDepth: 24),
        isTrue);
  });

  test('Bluetooth helpers forward to the native codec controls', () async {
    _messenger.setMockMethodCallHandler(_method, (call) async {
      switch (call.method) {
        case 'setBluetoothCodec':
        case 'setBluetoothSampleRate':
        case 'setBluetoothBitDepth':
        case 'setBluetoothLdacQuality':
          return true;
        default:
          return _output();
      }
    });

    expect(await service.setBluetoothCodec('LDAC'), isTrue);
    expect(await service.setBluetoothSampleRate(48000), isTrue);
    expect(await service.setBluetoothBitDepth(24), isTrue);
    expect(await service.setBluetoothLdacQuality(3), isTrue);
  });

  test('setBluetoothSampleRate rejects an unsupported rate', () async {
    expect(await service.setBluetoothSampleRate(12345), isFalse);
  });

  test('openBluetoothDevOptions completes', () async {
    await service.openBluetoothDevOptions();
    expect(calls.any((c) => c.method == 'openBluetoothDevOptions'), isTrue);
  });

  test('requestBluetoothPermission returns early when already granted',
      () async {
    await service.requestBluetoothPermission();
    // Granted permission means the native settings fallback is not reached.
    expect(calls.any((c) => c.method == 'requestBluetoothPermission'), isFalse);
  });
}
