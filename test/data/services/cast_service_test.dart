// CastService coverage. Under flutter_test `defaultTargetPlatform` is Android,
// so the Android-gated Play Services session path and the mDNS fallback both
// execute against stubbed `com.pulsr.music/cast*` channels. The service is a
// singleton, so tests are ordered so the connection-state transitions flow
// forward and dispose is never called mid-suite.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/constants/channels.dart';
import 'package:pulsr/data/services/cast_service.dart';

const MethodChannel _method = MethodChannel(PulsrChannels.cast);
const MethodChannel _events = MethodChannel(PulsrChannels.castEvents);
const MethodChannel _session = MethodChannel(PulsrChannels.castSession);
const MethodChannel _sessionEvents =
    MethodChannel(PulsrChannels.castSessionEvents);
const StandardMethodCodec _codec = StandardMethodCodec();

TestDefaultBinaryMessenger get _messenger =>
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

Future<void> _emit(String channel, Object? payload) =>
    _messenger.handlePlatformMessage(
        channel, _codec.encodeSuccessEnvelope(payload), null);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final service = CastService();
  late List<MethodCall> calls;

  setUp(() {
    calls = [];
    _messenger.setMockMethodCallHandler(_method, (call) async {
      calls.add(call);
      if (call.method == 'castTo') {
        return <Object?, Object?>{'success': true, 'message': 'casting'};
      }
      return true;
    });
    _messenger.setMockMethodCallHandler(_session, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'isAvailable':
        case 'connect':
        case 'disconnect':
        case 'startDiscovery':
        case 'stopDiscovery':
          return true;
        case 'setPlaybackState':
          return <Object?, Object?>{'success': true};
        case 'setVolume':
          return <Object?, Object?>{'success': true};
        case 'getVolume':
          return <Object?, Object?>{'success': true, 'volume': 0.5};
        case 'castLocalFile':
        case 'castUrl':
        case 'castQueue':
          return <Object?, Object?>{
            'success': true,
            'message': 'casting'
          };
        default:
          return null;
      }
    });
    _messenger.setMockMethodCallHandler(_events, (call) async => null);
    _messenger.setMockMethodCallHandler(_sessionEvents, (call) async => null);
  });

  tearDown(() {
    _messenger.setMockMethodCallHandler(_method, null);
    _messenger.setMockMethodCallHandler(_events, null);
    _messenger.setMockMethodCallHandler(_session, null);
    _messenger.setMockMethodCallHandler(_sessionEvents, null);
  });

  group('models', () {
    test('CastDevice.fromMap parses and defaults', () {
      final device = CastDevice.fromMap({
        'id': 'abc',
        'name': 'Living Room',
        'port': 8009,
      });
      expect(device!.id, 'abc');
      expect(device.name, 'Living Room');
      expect(device.port, 8009);
      expect(CastDevice.fromMap(const {}), isNull);
    });

    test('CastRoute.fromMap parses booleans', () {
      final route = CastRoute.fromMap({
        'id': 'r1',
        'name': 'TV',
        'connected': true,
        'selected': true,
      });
      expect(route!.connected, isTrue);
      expect(route.selected, isTrue);
      expect(CastRoute.fromMap(const {}), isNull);
    });

    test('CastSessionStatus.fromMap is always available', () {
      final status = CastSessionStatus.fromMap({
        'connected': true,
        'deviceName': 'TV',
        'playing': true,
        'positionMs': 1500,
        'error': 'warn',
      });
      expect(status.available, isTrue);
      expect(status.deviceName, 'TV');
      expect(status.positionMs, 1500);
      expect(status.error, 'warn');
      expect(CastSessionStatus.unavailable.available, isFalse);
    });
  });

  group('mDNS fallback', () {
    test('isSupported reflects the native boolean', () async {
      expect(await service.isSupported(), isTrue);
    });

    test('startDiscovery and stopDiscovery forward', () async {
      await service.startDiscovery();
      await service.stopDiscovery();
      expect(calls.where((c) => c.method == 'startDiscovery'), hasLength(1));
      expect(calls.where((c) => c.method == 'stopDiscovery'), hasLength(1));
    });

    test('castTo parses the native result', () async {
      final result = await service.castTo('device-1');
      expect(result.success, isTrue);
      expect(result.message, 'casting');
    });

    test('castTo reports a channel error', () async {
      _messenger.setMockMethodCallHandler(_method, (call) async {
        throw PlatformException(code: 'x');
      });
      final result = await service.castTo('device-1');
      expect(result.success, isFalse);
      expect(result.error, 'channel_error');
    });

    test('the devices stream parses discovered devices', () async {
      await service.startDiscovery(); // attaches the listener
      final received = <List<CastDevice>>[];
      final sub = service.devicesStream.listen(received.add);
      addTearDown(sub.cancel);
      await Future<void>.delayed(Duration.zero);

      await _emit(PulsrChannels.castEvents, {
        'type': 'devices',
        'devices': [
          {'id': 'd1', 'name': 'Kitchen Speaker'},
          null,
          {'id': 'd2'},
        ],
      });
      await Future<void>.delayed(Duration.zero);

      expect(received, isNotEmpty);
      expect(received.last.map((d) => d.id).toList(), ['d1', 'd2']);
      expect(service.devices.map((d) => d.id), ['d1', 'd2']);
    });
  });

  group('Play Services session', () {
    test('isSessionAvailable returns the channel flag', () async {
      expect(await service.isSessionAvailable(), isTrue);
      expect(service.sessionAvailable, isTrue);
    });

    test('connect, disconnect and stopCasting forward', () async {
      expect(await service.connect('route-1'), isTrue);
      expect(await service.disconnect(), isTrue);
      expect(await service.stopCasting(), isTrue);
    });

    test('castLocalFile/castUrl/castQueue parse the result map', () async {
      final local = await service.castLocalFile(path: '/x.mp3', title: 'T');
      final url = await service.castUrl(url: 'https://x/y.mp3');
      final queue = await service.castQueue(queueItems: [
        {'url': 'https://x/y.mp3'}
      ]);
      expect(local.success, isTrue);
      expect(url.success, isTrue);
      expect(queue.success, isTrue);
    });

    test('castLocalFile reports a channel error', () async {
      _messenger.setMockMethodCallHandler(_session, (call) async {
        if (call.method == 'castLocalFile') throw PlatformException(code: 'x');
        return null;
      });
      final result = await service.castLocalFile(path: '/x.mp3');
      expect(result.error, 'channel_error');
    });

    test('setPlaybackState reads the success flag', () async {
      expect(await service.setPlaybackState('play', positionMs: 10), isTrue);
    });

    test('setVolume/getVolume are null/false before a connected session',
        () async {
      // Runs before the session event below flips the singleton to connected.
      expect(await service.setVolume(0.5), isFalse);
      expect(await service.getVolume(), isNull);
    });

    test('the session stream updates routes and connection state', () async {
      await service.startSessionDiscovery(); // attaches the session listener
      final routes = <List<CastRoute>>[];
      final statuses = <CastSessionStatus>[];
      final routeSub = service.routesStream.listen(routes.add);
      final statusSub = service.sessionStream.listen(statuses.add);
      addTearDown(routeSub.cancel);
      addTearDown(statusSub.cancel);
      await Future<void>.delayed(Duration.zero);

      await _emit(PulsrChannels.castSessionEvents, {
        'type': 'routes',
        'routes': [
          {'id': 'r1', 'name': 'TV', 'connected': false},
          {'nope': true},
        ],
      });
      await _emit(PulsrChannels.castSessionEvents, {
        'type': 'session',
        'connected': true,
        'deviceName': 'TV',
        'playing': true,
        'positionMs': 1234,
      });
      await _emit(PulsrChannels.castSessionEvents, {
        'type': 'error',
        'error': 'boom',
      });
      await Future<void>.delayed(Duration.zero);

      expect(routes.last.map((r) => r.id).toList(), ['r1']);
      expect(statuses, isNotEmpty);
      expect(statuses.last.connected, isTrue);
      expect(service.sessionStatus.deviceName, 'TV');
    });

    test('setVolume/getVolume work once a session is connected', () async {
      expect(service.sessionStatus.connected, isTrue);
      expect(await service.setVolume(1.5), isTrue); // clamped internally
      expect(await service.getVolume(), 0.5);
    });

    test('_parseResult reports unknown_response for a null reply', () async {
      _messenger.setMockMethodCallHandler(_session, (call) async => null);
      final result = await service.castUrl(url: 'https://x/y.mp3');
      expect(result.success, isFalse);
      expect(result.error, 'unknown_response');
    });
  });
}
