// test/features/usb_tools/usb_ergonomics_service_test.dart
//
// Service tests: the profile is pushed to the native channel when a DAC
// attaches and again when it is edited, redundant pushes are suppressed, and a
// failing (or absent) platform channel never escapes as an exception.
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/services/usb_exclusive_service.dart';
import 'package:pulsr/features/usb_tools/usb_ergonomics_service.dart';
import 'package:pulsr/features/usb_tools/usb_quirk_profile.dart';
import 'package:pulsr/features/usb_tools/usb_quirk_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Records every channel call and answers with a configurable payload.
class _FakeChannel {
  final List<MethodCall> calls = <MethodCall>[];

  /// Reply per method name; null means "no payload". The apply method answers
  /// with the same `{ok: true}` map the native plugin returns.
  Map<String, Object?> replies = <String, Object?>{
    UsbErgonomicsService.applyMethod: <String, Object?>{'ok': true},
  };

  /// When set, every call throws this instead of replying.
  Object? throwOnCall;

  Future<Object?> invoke(MethodCall call) async {
    calls.add(call);
    final error = throwOnCall;
    if (error != null) throw error;
    return replies[call.method];
  }

  List<MethodCall> named(String method) =>
      calls.where((c) => c.method == method).toList();

  List<String> get methodNames => calls.map((c) => c.method).toList();
}

Future<UsbQuirkStore> _storeWith([UsbQuirkProfile? profile]) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();
  final store = UsbQuirkStore(prefs: prefs);
  if (profile != null) await store.put(profile);
  return store;
}

UsbExclusiveStatus _status({
  bool attached = true,
  int? vid = 0x1d6b,
  int? pid = 0x0104,
  int? deviceId = 42,
  String? name = 'Melo DAC',
}) {
  return UsbExclusiveStatus(
    attached: attached,
    permitted: true,
    deviceId: deviceId,
    vendorId: vid,
    productId: pid,
    deviceName: name,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final profile = UsbQuirkProfile(
    vid: 0x1d6b,
    pid: 0x0104,
    label: 'Melo DAC',
    hidEnabled: true,
  );

  late StreamController<UsbExclusiveStatus> controller;
  late _FakeChannel fake;

  setUp(() {
    controller = StreamController<UsbExclusiveStatus>.broadcast();
    fake = _FakeChannel();
  });

  tearDown(() async {
    await controller.close();
  });

  Future<UsbErgonomicsService> build(UsbQuirkStore store) async {
    final service = UsbErgonomicsService(
      store: store,
      statusStream: controller.stream,
      invoker: fake.invoke,
    );
    await service.start();
    return service;
  }

  group('attach', () {
    test('applies the stored profile with every knob', () async {
      final service = await build(await _storeWith(profile));

      controller.add(_status());
      await pumpEventQueue();

      final applied = fake.named(UsbErgonomicsService.applyMethod);
      expect(applied, hasLength(1));
      final args = applied.single.arguments as Map<Object?, Object?>;
      expect(args['vid'], 0x1d6b);
      expect(args['pid'], 0x0104);
      expect(args['hidEnabled'], isTrue);
      // The removed write-only knobs must never be sent again.
      expect(args.containsKey('silenceMs'), isFalse);
      expect(args.containsKey('bufferMs'), isFalse);
      expect(args.containsKey('transferSizeBytes'), isFalse);
      expect(args.containsKey('force16Bit'), isFalse);
      expect(args.containsKey('altResetOnStop'), isFalse);

      expect(service.state.attached, isTrue);
      expect(service.state.deviceLabel, 'Melo DAC');
      expect(service.state.quirk, profile);
      expect(fake.named(UsbErgonomicsService.hidMethod), hasLength(1));
      service.dispose();
    });

    test('applies neutral defaults when no profile is stored', () async {
      final service = await build(await _storeWith());

      controller.add(_status());
      await pumpEventQueue();

      final args = fake
          .named(UsbErgonomicsService.applyMethod)
          .single
          .arguments as Map<Object?, Object?>;
      expect(args['hidEnabled'], isFalse);
      expect(service.state.quirk, isNull);
      service.dispose();
    });

    test('does not re-apply identical status ticks', () async {
      final service = await build(await _storeWith(profile));

      controller.add(_status());
      await pumpEventQueue();
      controller.add(_status());
      await pumpEventQueue();

      expect(fake.named(UsbErgonomicsService.applyMethod), hasLength(1));
      service.dispose();
    });

    test('detach clears the transient values', () async {
      final service = await build(await _storeWith(profile));
      controller.add(_status());
      await pumpEventQueue();

      fake.replies = <String, Object?>{
        UsbErgonomicsService.probeMethod: <String, Object?>{'mbps': 480},
        UsbErgonomicsService.hidMethod: <String, Object?>{
          'claimed': true,
          'consumerControl': true,
        },
      };
      await service.probeBusSpeed();
      expect(service.state.busSpeedMbps, 480);

      controller.add(_status(attached: false));
      await pumpEventQueue();

      expect(service.state.attached, isFalse);
      expect(service.state.busSpeedMbps, isNull);
      expect(service.state.hid.claimed, isFalse);
      service.dispose();
    });
  });

  group('edit', () {
    test('saveQuirk stores and re-applies the new value', () async {
      final store = await _storeWith(profile);
      final service = await build(store);
      controller.add(_status());
      await pumpEventQueue();

      final edited = profile.copyWith(hidEnabled: false);
      expect(await service.saveQuirk(edited), isTrue);
      await pumpEventQueue();

      expect(store.get(profile.vid, profile.pid)?.hidEnabled, isFalse);
      final applied = fake.named(UsbErgonomicsService.applyMethod);
      expect(applied, hasLength(2));
      expect(
        (applied.last.arguments as Map<Object?, Object?>)['hidEnabled'],
        isFalse,
      );
      expect(service.state.quirk, edited);
      service.dispose();
    });

    test('deleteQuirk removes the entry and applies the fallback', () async {
      final store = await _storeWith(profile);
      final fallback = UsbQuirkProfile(vid: 0, pid: 0, label: 'Fallback');
      await store.setGlobalDefaults(fallback);
      final service = await build(store);
      controller.add(_status());
      await pumpEventQueue();

      expect(await service.deleteQuirk(), isTrue);
      await pumpEventQueue();

      expect(store.get(profile.vid, profile.pid), isNull);
      expect(service.state.quirk, fallback);
      expect(
        (fake.named(UsbErgonomicsService.applyMethod).last.arguments
            as Map<Object?, Object?>)['hidEnabled'],
        isFalse,
      );
      service.dispose();
    });

    test('deleteQuirk without device ids reports an error and does not throw',
        () async {
      final store = await _storeWith(profile);
      final service = await build(store);

      expect(await service.deleteQuirk(), isFalse);
      expect(service.state.lastError, isNotNull);
      service.dispose();
    });
  });

  group('diagnostics', () {
    test('probeBusSpeed parses the measured Mbps', () async {
      fake.replies = <String, Object?>{
        UsbErgonomicsService.probeMethod: <String, Object?>{'mbps': 480.0},
      };
      final service = await build(await _storeWith(profile));
      controller.add(_status());
      await pumpEventQueue();

      final mbps = await service.probeBusSpeed();

      expect(mbps, 480.0);
      expect(service.state.busSpeedMbps, 480.0);
      expect(service.state.deviceId, 42);
      final probe = fake.named(UsbErgonomicsService.probeMethod).single;
      expect(
        (probe.arguments as Map<Object?, Object?>)['deviceId'],
        42,
        reason: 'the probe must target the selected physical device',
      );
      service.dispose();
    });

    test('probeBusSpeed surfaces a missing reading without throwing', () async {
      final service = await build(await _storeWith(profile));
      controller.add(_status());
      await pumpEventQueue();

      expect(await service.probeBusSpeed(), isNull);
      expect(service.state.lastError, isNotNull);
      service.dispose();
    });

    test('refreshHidStatus maps the native reply', () async {
      fake.replies = <String, Object?>{
        UsbErgonomicsService.hidMethod: <String, Object?>{
          'claimed': true,
          'consumerControl': false,
          'lastButton': 'play_pause',
        },
      };
      final service = await build(await _storeWith(profile));
      controller.add(_status());
      await pumpEventQueue();

      await service.refreshHidStatus();

      expect(service.state.hid.claimed, isTrue);
      expect(service.state.hid.consumerControl, isFalse);
      expect(service.state.hid.lastButton, 'play_pause');
      expect(service.state.hid.describe(), contains('play_pause'));
      service.dispose();
    });

    test('resetAltSetting reports success and failure', () async {
      fake.replies = <String, Object?>{
        UsbErgonomicsService.resetAltMethod: <String, Object?>{'ok': true},
      };
      final service = await build(await _storeWith(profile));
      controller.add(_status());
      await pumpEventQueue();

      expect(await service.resetAltSetting(), isTrue);

      fake.replies = <String, Object?>{
        UsbErgonomicsService.resetAltMethod: <String, Object?>{
          'ok': false,
          'detail': 'no streaming interface',
        },
      };
      expect(await service.resetAltSetting(), isFalse);
      expect(service.state.lastError, 'no streaming interface');
      service.dispose();
    });
  });

  group('failure handling', () {
    test('a PlatformException is logged into lastError, never thrown', () async {
      final service = await build(await _storeWith(profile));
      fake.throwOnCall = PlatformException(
        code: 'usb_claim_failed',
        message: 'claim failed',
      );

      controller.add(_status());
      await pumpEventQueue();

      expect(service.state.attached, isTrue);
      expect(service.state.lastError, 'claim failed');
      expect(service.hasAppliedProfile, isFalse);
      service.dispose();
    });

    test('a MissingPluginException is absorbed silently', () async {
      final service = await build(await _storeWith(profile));
      fake.throwOnCall = MissingPluginException('no handler');

      controller.add(_status());
      await pumpEventQueue();

      expect(service.state.lastError, isNull);
      expect(service.state.attached, isTrue);
      service.dispose();
    });

    test('a generic exception is absorbed', () async {
      final service = await build(await _storeWith(profile));
      fake.throwOnCall = StateError('boom');

      controller.add(_status());
      await pumpEventQueue();

      expect(service.state.lastError, isNotNull);
      service.dispose();
    });
  });

  group('lifecycle', () {
    test('dispose cancels the status subscription', () async {
      final service = await build(await _storeWith(profile));
      controller.add(_status());
      await pumpEventQueue();
      final before = fake.calls.length;

      service.dispose();
      controller.add(_status());
      await pumpEventQueue();

      expect(fake.calls.length, before);
    });

    test('start is idempotent', () async {
      final service = await build(await _storeWith(profile));
      await service.start();
      controller.add(_status());
      await pumpEventQueue();

      expect(fake.named(UsbErgonomicsService.applyMethod), hasLength(1));
      service.dispose();
    });
  });
}
