import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/constants/channels.dart';
import 'package:pulsr/core/network/network_change_monitor.dart';

class _MockConnectivity extends Mock implements Connectivity {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('NetworkChangeMonitor emits events after dispose -> start restart',
      () async {
    final connectivity = _MockConnectivity();
    final connectivityController =
        StreamController<List<ConnectivityResult>>.broadcast();
    when(() => connectivity.checkConnectivity())
        .thenAnswer((_) async => [ConnectivityResult.wifi]);
    when(() => connectivity.onConnectivityChanged)
        .thenAnswer((_) => connectivityController.stream);

    final monitor = NetworkChangeMonitor(connectivity: connectivity);

    await monitor.start();
    await monitor.dispose();

    await monitor.start();
    final received = Completer<void>();
    final sub = monitor.onNetworkChanged.listen((_) {
      if (!received.isCompleted) {
        received.complete();
      }
    });

    connectivityController.add([ConnectivityResult.mobile]);
    await received.future.timeout(const Duration(seconds: 3));
    expect(received.isCompleted, isTrue);

    await sub.cancel();
    await monitor.dispose();
    await connectivityController.close();
  });

  test('native onNetworkChanged emits even when transports are unchanged',
      () async {
    final connectivity = _MockConnectivity();
    final connectivityController =
        StreamController<List<ConnectivityResult>>.broadcast();
    when(() => connectivity.checkConnectivity())
        .thenAnswer((_) async => [ConnectivityResult.wifi]);
    when(() => connectivity.onConnectivityChanged)
        .thenAnswer((_) => connectivityController.stream);

    final monitor = NetworkChangeMonitor(connectivity: connectivity);
    await monitor.start();
    final received = Completer<void>();
    final sub = monitor.onNetworkChanged.listen((_) {
      if (!received.isCompleted) {
        received.complete();
      }
    });

    const codec = StandardMethodCodec();
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
      PulsrChannels.proxy,
      codec.encodeMethodCall(
        const MethodCall(
            'onNetworkChanged', <String, dynamic>{'identity': 'wifi-b'}),
      ),
      (_) {},
    );

    await received.future.timeout(const Duration(seconds: 3));
    expect(received.isCompleted, isTrue);

    await sub.cancel();
    await monitor.dispose();
    await connectivityController.close();
  });
}
