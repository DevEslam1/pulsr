// test/core/services/cloud_sync_service_test.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:drift/native.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/services/auth_service.dart';
import 'package:pulsr/core/services/cloud_sync_service.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/domain/repositories/music_repository_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockAuthService extends Mock implements AuthService {}

class MockUser extends Mock implements User {}

class MockMusicRepository extends Mock implements IMusicRepository {}

class _MockFirestore extends Mock implements FirebaseFirestore {}

// ignore: subtype_of_sealed_class
class _MockDocRef extends Mock
    implements DocumentReference<Map<String, dynamic>> {}

// ignore: subtype_of_sealed_class
class _MockCollRef extends Mock
    implements CollectionReference<Map<String, dynamic>> {}

class _MockWriteBatch extends Mock implements WriteBatch {}

// ignore: subtype_of_sealed_class
class _FakeDocRef extends Fake
    implements DocumentReference<Map<String, dynamic>> {}

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

    test('resetSessionState clears persisted baselines and hashes', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          'cloud_sync_local_modified_favorites', '{"song_1": 12345}');
      await prefs.setString(
          'cloud_sync_hashes_cache', '{"users/u1/favorites/1": "hash1"}');
      await prefs.setStringList(
          'cloud_sync_uploaded_favorite_ids', ['fav_1', 'fav_2']);
      await prefs.setStringList(
          'cloud_sync_uploaded_playlist_ids', ['pl_1', 'pl_2']);
      await prefs.setString(
          'cloud_sync_uploaded_playlist_songs', '{"pl_1": ["s1", "s2"]}');

      await service.resetSessionState();

      expect(prefs.getString('cloud_sync_local_modified_favorites'), isNull);
      expect(prefs.getString('cloud_sync_hashes_cache'), isNull);
      expect(prefs.getStringList('cloud_sync_uploaded_favorite_ids'), isNull);
      expect(prefs.getStringList('cloud_sync_uploaded_playlist_ids'), isNull);
      expect(prefs.getString('cloud_sync_uploaded_playlist_songs'), isNull);
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

    test('permanent batch commit failure early-aborts remaining upload batches',
        () async {
      registerFallbackValue(_FakeDocRef());
      registerFallbackValue(SetOptions(merge: true));

      final firestore = _MockFirestore();
      final userDoc = _MockDocRef();
      final favColl = _MockCollRef();
      final batch = _MockWriteBatch();

      when(() => firestore.batch()).thenReturn(batch);
      when(() => userDoc.collection('favorites')).thenReturn(favColl);
      when(() => favColl.doc(any())).thenReturn(_FakeDocRef());
      when(() => batch.set(any(), any(), any())).thenReturn(null);
      when(() => batch.commit()).thenThrow(
        FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'),
      );

      final favorites = List<SongsTableData>.generate(
        250,
        (i) => SongsTableData(
          id: i + 1,
          title: 'Song $i',
          artist: 'Artist $i',
          album: 'Album',
          durationMs: 180000,
          path: '/music/song_$i.mp3',
          source: SongSource.local,
          isFavorite: true,
          isMissing: false,
          isDownloaded: false,
          playCount: 0,
          lastPositionMs: 0,
        ),
      );
      when(() => repository.getFavorites())
          .thenAnswer((_) async => Right(favorites));

      final ok = await service.uploadLocalDataForTesting(
        userDoc,
        syncFavorites: true,
        syncPlaylists: false,
        firestoreOverride: firestore,
      );

      expect(ok, isFalse);
      verify(() => batch.commit()).called(1);
    });
  });
}
