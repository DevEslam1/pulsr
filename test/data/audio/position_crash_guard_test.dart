import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:pulsr/data/audio/position_crash_guard.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this.path);
  final String path;

  @override
  Future<String?> getTemporaryPath() async => path;

  @override
  Future<String?> getApplicationSupportPath() async => path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('crash_guard_test_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    SharedPreferences.setMockInitialValues({});
    await PositionCrashGuard.clearSnapshot();
  });

  tearDown(() async {
    await PositionCrashGuard.clearSnapshot();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('PositionCrashGuard', () {
    test(
        'timestamp comparison prefers crash guard when snapshot is newer than DB timestamp',
        () async {
      await PositionCrashGuard.writeSnapshot(
        songId: 10,
        queueIndex: 0,
        positionMs: 45000,
        queueIds: [10, 11, 12],
      );

      final snapshot = await PositionCrashGuard.readSnapshot();
      expect(snapshot, isNotNull);
      final snapshotTs = snapshot!.timestamp;

      // 1. Snapshot newer than older DB timestamp -> prefer crash guard
      final preferWhenOlderDb =
          await PositionCrashGuard.shouldPreferCrashGuard(snapshotTs - 5000);
      expect(preferWhenOlderDb, isTrue);

      // 2. DB timestamp newer than snapshot -> prefer DB (do NOT prefer crash guard)
      final preferWhenNewerDb =
          await PositionCrashGuard.shouldPreferCrashGuard(snapshotTs + 5000);
      expect(preferWhenNewerDb, isFalse);

      // 3. DB timestamp equal to snapshot -> prefer DB
      final preferWhenEqualDb =
          await PositionCrashGuard.shouldPreferCrashGuard(snapshotTs);
      expect(preferWhenEqualDb, isFalse);
    });

    test(
        'timestamp comparison falls back to clean shutdown timestamp when dbTimestampMs is null',
        () async {
      await PositionCrashGuard.writeSnapshot(
        songId: 20,
        queueIndex: 1,
        positionMs: 30000,
        queueIds: [20],
      );

      final snapshot = await PositionCrashGuard.readSnapshot();
      expect(snapshot, isNotNull);
      final snapshotTs = snapshot!.timestamp;

      // Clean shutdown timestamp older than snapshot -> prefer crash guard
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
          PositionCrashGuard.keyLastCleanShutdownTs, snapshotTs - 10000);
      expect(await PositionCrashGuard.shouldPreferCrashGuard(), isTrue);

      // Clean shutdown timestamp newer than snapshot -> prefer clean state
      await prefs.setInt(
          PositionCrashGuard.keyLastCleanShutdownTs, snapshotTs + 10000);
      expect(await PositionCrashGuard.shouldPreferCrashGuard(), isFalse);
    });

    test('returns false when no snapshot exists', () async {
      await PositionCrashGuard.clearSnapshot();
      expect(await PositionCrashGuard.shouldPreferCrashGuard(1000), isFalse);
      expect(await PositionCrashGuard.shouldPreferCrashGuard(), isFalse);
    });
  });
}
