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
  test('raw integer source depth parses, copies and expires with transport', () {
    final active = UsbExclusiveStatus.fromMap({
      'streamingActive': true, 'rawPcmBitDepth': 32,
    });
    expect(active.rawPcmBitDepth, 32);
    expect(active.copyWith(streamingBitDepth: 32).rawPcmBitDepth, 32);
    expect(active.copyWith(rawPcmBitDepth: 0).rawPcmBitDepth, 0);
    expect(UsbExclusiveStatus.fromMap({'rawPcmBitDepth': 32}).rawPcmBitDepth, 0);
    expect(UsbExclusiveStatus.none.rawPcmBitDepth, 0);
  });
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

    test('accepts the 44.1-family high-rate endpoints', () async {
      var openedRate = 0;
      _messenger.setMockMethodCallHandler(_method, (call) async {
        if (call.method == 'startStreaming') {
          openedRate =
              (call.arguments as Map<dynamic, dynamic>)['sampleRate'] as int;
          return <Object?, Object?>{'success': true};
        }
        return _statusMap(
          streaming: openedRate > 0,
          sampleRate: openedRate == 0 ? 48000 : openedRate,
        );
      });
      await service.getStatus();
      for (final rate in <int>[705600, 768000]) {
        openedRate = 0;
        expect(
          await service.startStreaming(sampleRate: rate),
          UsbStreamResult.ok,
          reason: 'a DAC that advertised $rate must not be refused by the client',
        );
      }
    });

    test('maps a clock selector restore failure to its own code', () async {
      _messenger.setMockMethodCallHandler(_method, (call) async {
        if (call.method == 'startStreaming') {
          return <Object?, Object?>{
            'success': false,
            'error': 'clock_selector_restore_failed',
          };
        }
        return _statusMap();
      });
      await service.getStatus();
      expect(await service.startStreaming(),
          UsbStreamResult.clockSelectorRestoreFailed);
      expect(UsbStreamResult.clockSelectorRestoreFailed.toUserMessage(),
          contains('selector'));
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

    test('accepts a wider wire bit depth in non-strict mode and requires exact in strict', () async {
      _messenger.setMockMethodCallHandler(_method, (call) async {
        if (call.method == 'startStreaming') return {'success': true};
        return _statusMap(streaming: true, bitDepth: 24);
      });
      await service.getStatus();
      expect(
        await service.startStreaming(sampleRate: 48000, bitDepth: 16, strict: false),
        UsbStreamResult.ok,
      );
      expect(
        await service.startStreaming(sampleRate: 48000, bitDepth: 16, strict: true),
        UsbStreamResult.unknown,
      );
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

  group('clock domain', () {
    test('parses the stable wire names and fails closed', () {
      expect(UsbClockDomain.fromWire('bitPerfectLocked'),
          UsbClockDomain.bitPerfectLocked);
      expect(UsbClockDomain.fromWire('asrc'), UsbClockDomain.asrc);
      expect(UsbClockDomain.fromWire('bestEffort'), UsbClockDomain.bestEffort);
      expect(UsbClockDomain.fromWire('bitPerfect'), UsbClockDomain.unknown);
      expect(UsbClockDomain.fromWire(null), UsbClockDomain.unknown);
      expect(UsbClockDomain.bitPerfectLocked.isBitPerfect, isTrue);
      expect(UsbClockDomain.asrc.isResampled, isTrue);
      expect(UsbClockDomain.bestEffort.isBitPerfect, isFalse);
      expect(UsbClockDomain.unknown.toShortLabel(), 'Unknown');
    });

    test('parses status fields and keeps them through copyWith', () {
      final status = UsbExclusiveStatus.fromMap(<String, Object?>{
        ..._statusMap(streaming: true),
        'clockDomain': 'bitPerfectLocked',
        'clockDriftPpm': -37,
        'ringFillMs': 2400,
        'feedbackPresent': true,
        'drainPending': true,
        'sessionState': 'STREAMING',
        'quirkApplied': <String>['force16Bit'],
        'quirkRejected': <String, String>{'bufferMs': 'range'},
        'quirkBitPerfectAffected': true,
        'quirkBitPerfectReason': 'quirk_force_16bit',
      });
      expect(status.clockDomain, UsbClockDomain.bitPerfectLocked);
      expect(status.clockDriftPpm, -37);
      expect(status.ringFillMs, 2400);
      expect(status.feedbackPresent, isTrue);
      expect(status.drainPending, isTrue);
      expect(status.sessionState, 'STREAMING');
      expect(status.quirkApplied, <String>['force16Bit']);
      expect(status.quirkRejected, <String, String>{'bufferMs': 'range'});
      expect(status.quirkBitPerfectAffected, isTrue);
      expect(status.quirkBitPerfectReason, 'quirk_force_16bit');
      final copy = status.copyWith(clockDomain: UsbClockDomain.asrc);
      expect(copy.clockDomain, UsbClockDomain.asrc);
      expect(copy.ringFillMs, 2400);
      expect(UsbExclusiveStatus.none.clockDomain, UsbClockDomain.unknown);
    });
  });

  test('startStreaming forwards the requested render mode', () async {
    Map<dynamic, dynamic>? startArgs;
    _messenger.setMockMethodCallHandler(_method, (call) async {
      if (call.method == 'startStreaming') {
        startArgs = call.arguments as Map<dynamic, dynamic>;
        return <Object?, Object?>{'success': true};
      }
      return _statusMap(streaming: true);
    });
    await service.getStatus();
    expect(
      await service.startStreaming(renderMode: UsbRenderMode.bitPerfectPull),
      UsbStreamResult.ok,
    );
    expect(startArgs?['renderMode'], 1);

    expect(
      await service.startStreaming(renderMode: UsbRenderMode.clockSyncAsrc),
      UsbStreamResult.ok,
    );
    expect(startArgs?['renderMode'], 2);

    expect(await service.startStreaming(), UsbStreamResult.ok);
    expect(startArgs?['renderMode'], 0);
  });

  test('getUsbEvents returns structured maps and tolerates no handler',
      () async {
    _messenger.setMockMethodCallHandler(_method, (call) async {
      if (call.method == 'getUsbEvents') {
        return <Object?>[
          <Object?, Object?>{'clockDomain': 'bestEffort', 'rate': 48000},
        ];
      }
      return _statusMap();
    });
    expect(await service.getUsbEvents(), [
      <String, dynamic>{'clockDomain': 'bestEffort', 'rate': 48000},
    ]);

    _messenger.setMockMethodCallHandler(_method, (call) async {
      if (call.method == 'getUsbEvents') {
        throw MissingPluginException();
      }
      return _statusMap();
    });
    expect(await service.getUsbEvents(), isEmpty);
  });

  test('applyQuirkProfile reports native acceptance', () async {
    Map<dynamic, dynamic>? args;
    _messenger.setMockMethodCallHandler(_method, (call) async {
      if (call.method == 'setQuirkProfile') {
        args = call.arguments as Map<dynamic, dynamic>;
        return <Object?, Object?>{'ok': true};
      }
      return _statusMap();
    });
    expect(
      await service.applyQuirkProfile(<String, Object?>{'force16Bit': true}),
      isTrue,
    );
    expect(args?['force16Bit'], isTrue);
  });

  test('PCM source wrappers forward the path and report the native answer',
      () async {
    final calls = <MethodCall>[];
    _messenger.setMockMethodCallHandler(_method, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'startPcmFile':
          return true;
        case 'stopPcmFile':
          return true;
        case 'hasPcmFileSource':
          return true;
        default:
          return _statusMap();
      }
    });
    expect(await service.startPcmFile('/tmp/reference.wav'), isTrue);
    expect(
      (calls.firstWhere((c) => c.method == 'startPcmFile').arguments
          as Map<dynamic, dynamic>)['path'],
      '/tmp/reference.wav',
    );
    expect(await service.stopPcmFile(), isTrue);
    expect(await service.hasPcmFileSource(), isTrue);
  });

  test('PCM source wrappers fail closed when native throws', () async {
    _messenger.setMockMethodCallHandler(_method, (call) async {
      if (call.method.startsWith('startPcmFile') ||
          call.method.startsWith('stopPcmFile') ||
          call.method == 'hasPcmFileSource') {
        throw PlatformException(code: 'no_native');
      }
      return _statusMap();
    });
    expect(await service.startPcmFile('/x.wav'), isFalse);
    expect(await service.stopPcmFile(), isFalse);
    expect(await service.hasPcmFileSource(), isFalse);
  });

  test('dispose is idempotent and tears the stream down', () {
    service.dispose();
    service.dispose();
  });
}
