// test/data/usecases/backup_restore_live_stores_test.dart
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/di/injection.dart';
import 'package:pulsr/data/audio/per_song_eq_store.dart';
import 'package:pulsr/data/audio/per_song_volume_store.dart';
import 'package:pulsr/data/audio/song_rating_store.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/data/repositories/music_repository.dart';
import 'package:pulsr/data/usecases/backup_usecases.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late MusicRepository repository;
  late ImportBackupUseCase importUseCase;
  late SongRatingStore ratingStore;
  late PerSongEqStore eqStore;
  late PerSongVolumeStore volumeStore;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await getIt.reset();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repository = MusicRepository(db);
    importUseCase = ImportBackupUseCase(repository, db);

    ratingStore = SongRatingStore();
    eqStore = PerSongEqStore();
    volumeStore = PerSongVolumeStore();
    getIt.registerSingleton<SongRatingStore>(ratingStore);
    getIt.registerSingleton<PerSongEqStore>(eqStore);
    getIt.registerSingleton<PerSongVolumeStore>(volumeStore);
    await Future.wait<void>(
        [ratingStore.ready, eqStore.ready, volumeStore.ready]);
  });

  tearDown(() async {
    await db.close();
    await getIt.reset();
  });

  test('import refreshes the registered live stores without a restart',
      () async {
    await db.into(db.songsTable).insert(
          SongsTableCompanion.insert(
            id: const Value(10),
            title: 'Track A',
            path: '/storage/music/track_a.mp3',
          ),
        );

    final backup = jsonEncode({
      'version': 4,
      'ratings': {'path:/storage/music/track_a.mp3': 4},
      'perSongEq': {'path:/storage/music/track_a.mp3': 'Bass Boost'},
      'perSongVolume': {'path:/storage/music/track_a.mp3': -3.5},
    });

    await importUseCase.execute(backup);

    expect(ratingStore.getRating('10'), 4,
        reason: 'restored ratings must be visible without a restart');
    expect(eqStore.getPresetForTrack('10'), 'Bass Boost');
    expect(volumeStore.getGainDbForTrack('10'), -3.5);
  });

  test('store reload is idempotent and clears when the key is removed',
      () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(SongRatingStore.prefsKey, jsonEncode({'10': 5}));

    await ratingStore.reload();
    await ratingStore.reload();
    expect(ratingStore.getRating('10'), 5);

    await prefs.remove(SongRatingStore.prefsKey);
    await ratingStore.reload();
    expect(ratingStore.getRating('10'), 0);
  });
}
