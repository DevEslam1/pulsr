// test/features/settings/settings_dirty_reconciliation_test.dart
//
// Covers FIX-H07 dirty-field reconciliation for the audio setters that were
// previously omitted, plus the secure-storage write-failure path in
// SettingsProxyActions.
import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/constants/prefs_keys.dart';
import 'package:pulsr/core/network/proxy_config.dart';
import 'package:pulsr/data/scanner/media_scanner_service.dart';
import 'package:pulsr/features/settings/cubit/settings_cubit.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockMediaScannerService extends Mock implements MediaScannerService {}

class MockSecureStorage extends Mock implements FlutterSecureStorage {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('SettingsCubit dirty-field reconciliation (FIX-H07)', () {
    test(
        'audio fields changed while the initial load is in flight are not reverted',
        () async {
      SharedPreferences.setMockInitialValues({});

      final storage = MockSecureStorage();
      final gate = Completer<String?>();
      var gateServed = false;
      when(() => storage.read(key: any(named: 'key'))).thenAnswer((_) {
        if (!gateServed) {
          gateServed = true;
          return gate.future;
        }
        return Future<String?>.value(null);
      });
      when(() => storage.delete(key: any(named: 'key')))
          .thenAnswer((_) async {});
      when(() => storage.write(
            key: any(named: 'key'),
            value: any(named: 'value'),
          )).thenAnswer((_) async {});

      final cubit = SettingsCubit(
        scannerService: MockMediaScannerService(),
        secureStorage: storage,
      );
      addTearDown(cubit.close);

      // User toggles while the async load is still blocked on secure storage.
      await cubit.setFloatOutputEnabled(false);
      await cubit.setAaudioTargetBufferMs(500);
      await cubit.setDuckingMode('pause');
      await cubit.setAdaptiveQualityEnabled(false);
      await cubit.setAaudioPreferExclusive(false);

      // The on-disk snapshot the load will read is now stale (old values).
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(PrefsKeys.floatOutputEnabled, true);
      await prefs.setInt(PrefsKeys.aaudioTargetBufferMs, 150);
      await prefs.setString(PrefsKeys.duckingMode, 'duck');
      await prefs.setBool(PrefsKeys.adaptiveQualityEnabled, true);
      await prefs.setBool(PrefsKeys.aaudioPreferExclusive, true);

      // Let the in-flight load finish applying the stale snapshot.
      gate.complete(null);
      await cubit.preferencesReady;

      expect(cubit.state.floatOutputEnabled, isFalse);
      expect(cubit.state.aaudioTargetBufferMs, 500);
      expect(cubit.state.duckingMode, 'pause');
      expect(cubit.state.adaptiveQualityEnabled, isFalse);
      expect(cubit.state.aaudioPreferExclusive, isFalse);
    });
  });

  group('SettingsProxyActions secure storage failure', () {
    test(
        'a failed secure-storage write surfaces an error and reverts hasProxyPassword',
        () async {
      SharedPreferences.setMockInitialValues({});

      final storage = MockSecureStorage();
      when(() => storage.read(key: any(named: 'key')))
          .thenAnswer((_) async => null);
      when(() => storage.delete(key: any(named: 'key')))
          .thenAnswer((_) async {});
      when(() => storage.write(
            key: any(named: 'key'),
            value: any(named: 'value'),
          )).thenAnswer((_) async {
        throw Exception('keystore unavailable');
      });

      final cubit = SettingsCubit(
        scannerService: MockMediaScannerService(),
        secureStorage: storage,
      );
      await cubit.preferencesReady;
      addTearDown(cubit.close);

      expect(cubit.state.hasProxyPassword, isFalse);

      await cubit.setProxySettings(
        enabled: true,
        type: AppProxyType.http,
        host: '127.0.0.1',
        port: 8080,
        username: 'user',
        password: 'secret',
      );

      expect(cubit.state.hasProxyPassword, isFalse,
          reason: 'state must not claim a password was stored');
      expect(cubit.state.errorMessage, isNotNull);
    });
  });
}
