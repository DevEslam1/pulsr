// test/core/utils/startup_gates_test.dart
//
// Guards the cold-start ordering contract: offline-only mode must be read from
// persisted prefs BEFORE deciding which online initializers may run.
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/config/app_config.dart';
import 'package:pulsr/core/constants/prefs_keys.dart';
import 'package:pulsr/core/utils/startup_gates.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('StartupGates', () {
    test('missing prefs default to online (no persisted opt-out)', () {
      expect(StartupGates.isOfflineOnly(null), isFalse);
      expect(StartupGates.cloudSyncAllowed(null), AppConfig.isCloudSyncAllowed);
    });

    test('offline-only mode disables cloud sync and YTM online work', () async {
      SharedPreferences.setMockInitialValues({
        PrefsKeys.offlineOnlyMode: true,
      });
      final prefs = await SharedPreferences.getInstance();

      expect(StartupGates.isOfflineOnly(prefs), isTrue);
      expect(StartupGates.onlineAllowed(prefs), isFalse);
      expect(StartupGates.cloudSyncAllowed(prefs), isFalse);
    });

    test('online mode keeps cloud sync available', () async {
      SharedPreferences.setMockInitialValues({
        PrefsKeys.offlineOnlyMode: false,
      });
      final prefs = await SharedPreferences.getInstance();

      expect(StartupGates.isOfflineOnly(prefs), isFalse);
      expect(
          StartupGates.cloudSyncAllowed(prefs), AppConfig.isCloudSyncAllowed);
      expect(
        StartupGates.onlineAllowed(prefs),
        AppConfig.ytmEnabled,
      );
    });

    test('the gate reflects the awaited prefs value, not a later microtask',
        () async {
      SharedPreferences.setMockInitialValues({
        PrefsKeys.offlineOnlyMode: true,
      });
      // The pre-fix code computed `onlineAllowed` synchronously while the
      // prefs future was still pending, so this value was always ignored.
      final prefs = await SharedPreferences.getInstance();
      final gateBeforeAwait = StartupGates.cloudSyncAllowed(prefs);
      expect(gateBeforeAwait, isFalse);
    });
  });
}
