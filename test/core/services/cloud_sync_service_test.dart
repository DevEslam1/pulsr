// test/core/services/cloud_sync_service_test.dart
import 'package:drift/native.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/services/auth_service.dart';
import 'package:pulsr/core/services/cloud_sync_service.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/domain/repositories/music_repository_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockAuthService extends Mock implements AuthService {}

class MockUser extends Mock implements User {}

class MockMusicRepository extends Mock implements IMusicRepository {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockAuthService auth;
  late MockMusicRepository repository;
  late AppDatabase db;
  late CloudSyncService service;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    auth = MockAuthService();
    repository = MockMusicRepository();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    service = CloudSyncService(auth, repository, db);
  });

  tearDown(() async {
    await db.close();
  });

  group('preferences and device id', () {
    test('generates and persists a stable 16-char device id', () async {
      final first = await service.getDeviceId();
      expect(first.length, 16);

      final second = await service.getDeviceId();
      expect(second, first);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('cloud_sync_device_id'), first);
    });

    test('lastSyncTime is null before any sync', () async {
      expect(service.lastSyncTime, isNull);
      await service.getDeviceId();
      expect(service.lastSyncTime, isNull);
    });

    test('favorites sync toggle defaults true and persists changes', () async {
      expect(await service.isFavoritesSyncEnabled, isTrue);
      await service.setFavoritesSyncEnabled(false);
      expect(await service.isFavoritesSyncEnabled, isFalse);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('cloud_sync_favorites_enabled'), isFalse);
    });

    test('playlists sync toggle defaults true and persists changes', () async {
      expect(await service.isPlaylistsSyncEnabled, isTrue);
      await service.setPlaylistsSyncEnabled(false);
      expect(await service.isPlaylistsSyncEnabled, isFalse);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('cloud_sync_playlists_enabled'), isFalse);
    });
  });

  group('syncAll gating', () {
    test('returns false when no user is signed in', () async {
      when(() => auth.currentUser).thenReturn(null);
      expect(await service.syncAll(), isFalse);
    });

    test('returns false in Offline-only mode even with a user', () async {
      SharedPreferences.setMockInitialValues({
        'setting_offline_only_mode': true,
      });
      final user = MockUser();
      when(() => user.uid).thenReturn('uid-1');
      when(() => auth.currentUser).thenReturn(user);

      expect(await service.syncAll(), isFalse);
    });

    test('short-circuits to true when every scope is disabled', () async {
      final user = MockUser();
      when(() => user.uid).thenReturn('uid-1');
      when(() => auth.currentUser).thenReturn(user);

      final result = await service.syncAll(
        syncFavorites: false,
        syncPlaylists: false,
      );
      expect(result, isTrue);
    });

    test('falls back to persisted toggles to disable both scopes', () async {
      await service.setFavoritesSyncEnabled(false);
      await service.setPlaylistsSyncEnabled(false);
      final user = MockUser();
      when(() => user.uid).thenReturn('uid-1');
      when(() => auth.currentUser).thenReturn(user);

      expect(await service.syncAll(), isTrue);
    });
  });
}
