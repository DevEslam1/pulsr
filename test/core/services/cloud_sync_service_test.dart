// test/core/services/cloud_sync_service_test.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/services/auth_service.dart';
import 'package:pulsr/core/services/cloud_sync_service.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/domain/models/ytm_track.dart';
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

// ignore: subtype_of_sealed_class
class _MockQuerySnapshot extends Mock
    implements QuerySnapshot<Map<String, dynamic>> {}

// ignore: subtype_of_sealed_class
class _MockQueryDocSnapshot extends Mock
    implements QueryDocumentSnapshot<Map<String, dynamic>> {}

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
      await prefs
          .setStringList('cloud_sync_uploaded_playlist_ids', ['pl_1', 'pl_2']);
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

  group('C-02 & C-03 upsert and session isolation regressions', () {
    test(
        'download merge upserts existing cloud track without FK cascade wiping playlist entries',
        () async {
      await db.customStatement('PRAGMA foreign_keys = ON;');

      const track = YtmTrack(
        videoId: 'vid_dup_c02',
        title: 'Local Cached Song',
        artist: 'Local Artist',
        duration: Duration(seconds: 200),
      );
      final songData = track.toSongData();

      await db.into(db.songsTable).insert(
            SongsTableCompanion.insert(
              id: Value(songData.id),
              title: songData.title,
              artist: Value(songData.artist),
              album: const Value('Local Album'),
              durationMs: Value(songData.durationMs),
              path: 'ytmusic://other_stale_path',
              source: const Value(SongSource.youtube),
              isFavorite: const Value(false),
            ),
          );
      final playlistId = await db.into(db.playlistsTable).insert(
            PlaylistsTableCompanion.insert(name: 'My Keep Playlist'),
          );
      await db.into(db.playlistEntriesTable).insert(
            PlaylistEntriesTableCompanion.insert(
              playlistId: playlistId,
              songId: songData.id,
              orderIndex: 0,
            ),
          );

      final userDoc = _MockDocRef();
      final favColl = _MockCollRef();
      final querySnap = _MockQuerySnapshot();
      final docSnap = _MockQueryDocSnapshot();
      when(() => userDoc.collection('favorites')).thenReturn(favColl);
      when(() => favColl.get()).thenAnswer((_) async => querySnap);
      when(() => querySnap.docs).thenReturn([docSnap]);
      when(() => docSnap.id).thenReturn('cloud_fav_doc');
      when(() => docSnap.data()).thenReturn({
        'remoteId': 'vid_dup_c02',
        'title': 'Cloud Title',
        'artist': 'Cloud Artist',
        'durationMs': 200000,
        'remoteArtworkUrl': 'https://img.example/cover.jpg',
        'modifiedAt': Timestamp.fromDate(DateTime.now()),
      });

      await service.downloadAndMergeCloudDataForTesting(
        userDoc,
        syncFavorites: true,
        syncPlaylists: false,
      );

      final songs = await db.select(db.songsTable).get();
      expect(songs, hasLength(1));
      expect(songs.single.id, songData.id);
      expect(songs.single.isFavorite, isTrue);

      final entries = await db.select(db.playlistEntriesTable).get();
      expect(entries, hasLength(1));
      expect(entries.single.songId, songData.id);
      expect(entries.single.playlistId, playlistId);
    });

    test(
        'UID change on syncAll resets stale session state and persists new UID',
        () async {
      SharedPreferences.setMockInitialValues({
        'cloud_sync_last_uid': 'uid-previous',
        'cloud_sync_hashes_cache': '{"users/uid-previous/favorites/1":"abc"}',
        'cloud_sync_uploaded_favorite_ids': ['fav-1'],
        'cloud_sync_favorites_enabled': false,
        'cloud_sync_playlists_enabled': false,
      });

      final user = MockUser();
      when(() => user.uid).thenReturn('uid-next');
      when(() => auth.currentUser).thenReturn(user);

      final ok = await service.syncAll();
      expect(ok, isTrue);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('cloud_sync_last_uid'), 'uid-next');
      expect(prefs.getString('cloud_sync_hashes_cache'), isNull);
      expect(prefs.getStringList('cloud_sync_uploaded_favorite_ids'), isNull);
    });

    test(
        'AuthService signOut invokes registered CloudSyncService resetSessionState',
        () async {
      SharedPreferences.setMockInitialValues({
        'cloud_sync_last_uid': 'uid-active',
        'cloud_sync_hashes_cache': '{"k":"v"}',
      });
      final authSvc = AuthService();
      final syncWithHook = CloudSyncService(authSvc, repository, db);
      expect(syncWithHook, isNotNull);

      await authSvc.signOut();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('cloud_sync_last_uid'), isNull);
      expect(prefs.getString('cloud_sync_hashes_cache'), isNull);
    });
  });
}
