import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mutex/mutex.dart';
import 'package:pulsr/core/constants/prefs_keys.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/features/player/cubit/controllers/player_controllers.dart';
import 'package:pulsr/features/player/cubit/managers/player_lyrics_manager.dart';
import 'package:pulsr/features/player/cubit/managers/player_sponsorblock_manager.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../player_test_support.dart';

class _MockLyricsManager extends Mock implements PlayerLyricsManager {}

class _MockSponsorBlockManager extends Mock
    implements PlayerSponsorBlockManager {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('P2-17 SongAutoplayExtension Expando source of truth', () {
    test(
        'marking an instance isAutoplay = true does not leak to a fresh SongsTableData with the same id',
        () {
      final autoplaySong = buildSong(777, title: 'Autoplay Hit')
        ..isAutoplay = true;
      expect(autoplaySong.isAutoplay, isTrue);
      expect(autoplaySong.hasExplicitAutoplayFlag, isTrue);

      final freshLibraryRow = buildSong(777, title: 'Autoplay Hit');
      expect(identical(autoplaySong, freshLibraryRow), isFalse);
      expect(freshLibraryRow.isAutoplay, isFalse);
      expect(freshLibraryRow.hasExplicitAutoplayFlag, isFalse);
    });

    test(
        'restoreQueueSlots retains QueueTier.autoplay and sets isAutoplay/hasExplicitAutoplayFlag on restored songs',
        () async {
      final restoredRow = buildSong(888, title: 'Restored Autoplay');
      final slotsDoc = {
        'schemaVersion': 1,
        'activeSlot': 0,
        '0': {
          'songIds': [888],
          'currentIndex': 0,
          'positionMs': 0,
          'speed': 1.0,
          'trackTiers': {'888': 'autoplay'},
        },
      };
      SharedPreferences.setMockInitialValues({
        PrefsKeys.queueSlots: jsonEncode(slotsDoc),
      });

      final repo = MockMusicRepository();
      when(() => repo.getSongsByIds([888]))
          .thenAnswer((_) async => right([restoredRow]));

      var state = const PlayerState();
      final controller = PlayerQueueController(
        audioHandler: RecordingAudioHandler(),
        repository: repo,
        getState: () => state,
        emit: (s) => state = s,
        isClosed: () => false,
        queueMutex: Mutex(),
        slotLookupCache: <int, SongsTableData>{},
        queueSlots: <int, QueueSlotData>{},
        updateWidgetThrottled: ({bool force = false}) {},
        loadLyrics: (_) {},
        debouncedPersistQueueSlots: () {},
        bumpQueueVersion: () {},
        isSameTrack: (a, b) => a?.id == b?.id,
        invalidateQueueSyncResolution: () {},
      );

      await controller.restoreQueueSlots();

      expect(state.trackTiers[888], QueueTier.autoplay);
      expect(state.currentSong, isNotNull);
      expect(state.currentSong!.isAutoplay, isTrue);
      expect(state.currentSong!.hasExplicitAutoplayFlag, isTrue);
    });

    test(
        'enrichAudioQuality preserveAutoplay propagates isAutoplay to the enriched SongsTableData',
        () async {
      final initialSong = buildSong(999, title: 'Stream')..isAutoplay = true;
      final enrichedSong = buildSong(999, title: 'Stream (Hi-Res)');

      final repo = MockMusicRepository();
      when(() => repo.getSongById(999))
          .thenAnswer((_) async => right(enrichedSong));

      var state = PlayerState(
        playback: PlaybackSlice(currentSong: initialSong),
        queueSlice: QueueSlice(
          queue: [initialSong],
          currentIndex: 0,
          trackTiers: const {999: QueueTier.autoplay},
        ),
      );

      final metadata = PlayerMetadataController(
        lyricsManager: _MockLyricsManager(),
        sponsorBlockManager: _MockSponsorBlockManager(),
        repository: repo,
        getState: () => state,
        emit: (s) => state = s,
        isClosed: () => false,
        isSameTrack: (a, b) => a?.id == b?.id,
      );

      await metadata.enrichAudioQuality(initialSong);

      expect(state.currentSong?.title, 'Stream (Hi-Res)');
      expect(state.currentSong?.isAutoplay, isTrue);
      expect(state.currentSong?.hasExplicitAutoplayFlag, isTrue);
      expect(state.queue.single.isAutoplay, isTrue);
    });
  });
}
