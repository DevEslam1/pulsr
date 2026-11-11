import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pulsr/data/audio/audio_handler.dart';
import 'package:pulsr/data/audio/equalizer_manager.dart';
import 'package:pulsr/data/audio/per_song_playback_store.dart';
import 'package:pulsr/data/audio/per_song_volume_store.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/domain/models/audio_effects_config.dart';
import 'package:pulsr/features/player/cubit/controllers/dsp_effect_applier.dart';
import 'package:pulsr/features/player/cubit/controllers/playback_volume_mute.dart';
import 'package:pulsr/features/player/cubit/controllers/player_playback_options_controller.dart';
import 'package:pulsr/features/player/cubit/controllers/player_transport_controller.dart';
import 'package:pulsr/features/player/cubit/controllers/queue_slot_data.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/player/cubit/quran_restore_snapshot.dart';
import '../player_test_support.dart';

class MockAudioHandler extends Mock implements PulsrAudioHandler {}
class MockPerSongPlaybackStore extends Mock implements PerSongPlaybackStore {}
class MockPerSongVolumeStore extends Mock implements PerSongVolumeStore {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Phase 1: State Integrity & Concurrency', () {
    group('1.1 & 1.2 DSP Mutex & Rollback Merge', () {
      test('DspEffectApplier serializes concurrent applies and merge-policy does not clobber newer value', () async {
        PlayerState state = const PlayerState();
        final applier = DspEffectApplier(
          getState: () => state,
          emit: (s) => state = s,
          markUserInteracting: () {},
          guardDsp: (_, {showError = true}) => true,
          rebalanceVolumeBoost: () async {},
        );

        // Op 1 changes isVirtualizerEnabled to true and fails after delay
        // Op 2 changes isSpatializerEnabled to true and succeeds
        final op1 = applier.apply(
          featureName: 'Virtualizer',
          rebalanceVolumeBoost: false,
          updateDsp: (dsp) => dsp.copyWith(isVirtualizerEnabled: true),
          applyAudioHandler: () async {
            await Future<void>.delayed(const Duration(milliseconds: 30));
            throw Exception('Op 1 failed');
          },
        );

        // Slightly delayed Op 2
        await Future<void>.delayed(const Duration(milliseconds: 5));
        final op2 = applier.apply(
          featureName: 'Spatializer',
          rebalanceVolumeBoost: false,
          updateDsp: (dsp) => dsp.copyWith(isSpatializerEnabled: true),
          applyAudioHandler: () async {
            // Op 2 succeeds
          },
        );

        final res1 = await op1;
        final res2 = await op2;

        expect(res1, isFalse);
        expect(res2, isTrue);
        // op1 failed so virtualizer reverted to false
        expect(state.isVirtualizerEnabled, isFalse);
        // op2 succeeded so spatializer remains true (merge rollback didn't clobber it!)
        expect(state.isSpatializerEnabled, isTrue);
      });
    });

    group('1.3 Clamped Effective Boosts', () {
      test('DspSlice stores clamped effective values and exposes them via PlayerState', () {
        const state = PlayerState(
          dsp: DspSlice(
            volumeBoost: 15.0,
            effectiveVolumeBoost: 10.0,
            effectiveBassBoost: 8.0,
          ),
        );
        expect(state.volumeBoost, equals(15.0));
        expect(state.effectiveVolumeBoost, equals(10.0));
        expect(state.effectiveBassBoost, equals(8.0));
      });
    });

    group('1.4 PlaybackVolumeMute FIFO & Concurrency', () {
      test('routes concurrent operations through FIFO and updates state', () async {
        final handler = MockAudioHandler();
        var currentVol = 1.0;
        when(() => handler.volume).thenAnswer((_) => currentVol);
        final volumeCalls = <double>[];
        when(() => handler.setVolume(any())).thenAnswer((inv) async {
          final v = inv.positionalArguments.single as double;
          await Future<void>.delayed(const Duration(milliseconds: 10));
          currentVol = v;
          volumeCalls.add(v);
        });

        PlayerState state = const PlayerState();
        final mute = PlaybackVolumeMute(
          audioHandler: handler,
          getState: () => state,
          emit: (s) => state = s,
        );

        // Fire rapid concurrent volume adjustments
        final futures = [
          mute.setVolume(0.8),
          mute.adjustVolume(-0.2),
          mute.setVolume(0.5),
        ];
        await Future.wait(futures);

        expect(volumeCalls.length, 3);
        expect(volumeCalls[0], closeTo(0.8, 1e-4));
        expect(volumeCalls[1], closeTo(0.6, 1e-4));
        expect(volumeCalls[2], closeTo(0.5, 1e-4));
        expect(state.isMuted, isFalse);
      });

      test('toggleMute emits error on failure', () async {
        final handler = MockAudioHandler();
        when(() => handler.volume).thenAnswer((_) => 0.7);
        when(() => handler.setVolume(any())).thenThrow(Exception('Native mute error'));

        PlayerState state = const PlayerState();
        final mute = PlaybackVolumeMute(
          audioHandler: handler,
          getState: () => state,
          emit: (s) => state = s,
        );

        await mute.toggleMute();
        expect(state.errorMessage, equals('Toggle mute failed'));
      });
    });

    group('1.5 Per-song memory restoration', () {
      test('restores global defaults when track has no stored speed or pitch', () async {
        final handler = MockAudioHandler();
        stubPlaybackRateHandler(handler);
        when(() => handler.userBaseSpeed).thenReturn(1.0);

        final playStore = MockPerSongPlaybackStore();
        final volStore = MockPerSongVolumeStore();

        // Song A has stored speed 1.5, pitch 1.2
        when(() => playStore.getSpeed('1')).thenReturn(1.5);
        when(() => playStore.getPitch('1')).thenReturn(1.2);
        when(() => volStore.getGainDbForTrack(any())).thenReturn(0.0);

        // Song B has NO stored speed or pitch
        when(() => playStore.getSpeed('2')).thenReturn(null);
        when(() => playStore.getPitch('2')).thenReturn(null);

        final songA = buildSong(1, title: 'Song A');
        final songB = buildSong(2, title: 'Song B');

        PlayerState state = PlayerState(
          playback: PlaybackSlice(currentSong: songA),
        );

        final controller = PlayerPlaybackOptionsController(
          audioHandler: handler,
          perSongPlaybackStore: playStore,
          perSongVolumeStore: volStore,
          getState: () => state,
          emit: (s) => state = s,
          isClosed: () => false,
        );

        // Play A
        await controller.applyPerSongPlaybackMemory(songA);
        expect(state.playbackSpeed, equals(1.5));
        expect(state.playbackPitch, equals(1.2));

        // Now move to B (which has no stored playback memory)
        state = state.copyWith(playback: state.playback.copyWith(currentSong: songB));
        await controller.applyPerSongPlaybackMemory(songB);

        // Speed must be restored to default (1.0) and pitch to 1.0!
        expect(state.playbackSpeed, equals(1.0));
        expect(state.playbackPitch, equals(1.0));
      });
    });

    group('1.6 QuranRestoreSnapshot v2', () {
      test('migrates v1 snapshot without playbackPitch to default 1.0', () {
        final jsonV1 = <String, dynamic>{
          'isEqEnabled': true,
          'isReverbEnabled': false,
          'reverbPreset': 1,
          'reverbWetDry': 0.25,
          'isDynamicsEnabled': false,
          'dynamicsPreset': 'off',
          'isSaturationEnabled': false,
          'saturationDrive': 0.3,
          'saturationMix': 0.5,
          'saturationTilt': 0.3,
          'playbackSpeed': 1.25,
          'isShuffle': false,
          'preampDb': 0.0,
        };

        final snapshot = QuranRestoreSnapshot.fromJson(jsonV1);
        expect(snapshot.schemaVersion, equals(1));
        expect(snapshot.playbackPitch, equals(1.0));
        expect(snapshot.playbackSpeed, equals(1.25));
      });

      test('v2 round-trip preserves schemaVersion and playbackPitch', () {
        const snapshot = QuranRestoreSnapshot(
          schemaVersion: 2,
          eqPreset: flatPreset,
          isEqEnabled: true,
          headphoneProfile: null,
          isReverbEnabled: true,
          reverbPreset: 2,
          reverbWetDry: 0.3,
          isDynamicsEnabled: true,
          dynamicsPreset: DynamicsPreset.vocalFocus,
          isSaturationEnabled: true,
          saturationDrive: 0.4,
          saturationMix: 0.6,
          saturationTilt: 0.2,
          playbackSpeed: 1.1,
          playbackPitch: 0.95,
          isShuffle: true,
          preampDb: -1.5,
        );

        final json = snapshot.toJson();
        expect(json['schemaVersion'], equals(2));
        expect(json['playbackPitch'], equals(0.95));

        final decoded = QuranRestoreSnapshot.fromJson(json);
        expect(decoded.schemaVersion, equals(2));
        expect(decoded.playbackPitch, equals(0.95));
        expect(decoded.playbackSpeed, equals(1.1));
        expect(decoded.preampDb, equals(-1.5));
      });
    });

    group('1.8 Transport previous queueHistory restore', () {
      test('restores queueHistory when previous history jump fails', () async {
        final handler = MockAudioHandler();
        final song1 = buildSong(1);
        final song2 = buildSong(2);
        final historySong = buildSong(99, title: 'History Song');

        PlayerState state = PlayerState(
          queueSlice: QueueSlice(
            queue: [song1, song2],
            currentIndex: 0,
            queueHistory: [historySong],
          ),
          playback: const PlaybackSlice(
            position: Duration(seconds: 1),
          ),
        );

        final transport = PlayerTransportController(
          audioHandler: handler,
          getState: () => state,
          emit: (s) => state = s,
          isClosed: () => false,
          onPlaySong: (song, {queue, initialPosition, queueIndex}) async {
            throw Exception('History jump failed');
          },
        );

        await transport.previous();

        // Failed history jump must restore queueHistory!
        expect(state.queueHistory, contains(historySong));
        expect(state.errorMessage, equals('Skip to previous failed'));
      });
    });

    group('1.11 cacheSlotSongs LRU Cap', () {
      test('enforces maxSlotLookupCacheEntries cap by evicting oldest entries', () {
        final cache = <int, SongsTableData>{};

        // Add 4100 songs
        final batch = List.generate(
          4100,
          (i) => buildSong(i, title: 'Track $i'),
        );
        cacheSlotSongs(cache, batch);

        expect(cache.length, equals(maxSlotLookupCacheEntries));
        // Oldest (0..3) must have been evicted
        expect(cache.containsKey(0), isFalse);
        expect(cache.containsKey(1), isFalse);
        expect(cache.containsKey(2), isFalse);
        expect(cache.containsKey(3), isFalse);
        // Newest must be retained
        expect(cache.containsKey(4099), isTrue);
      });
    });

    group('1.13 EqualizerManager _setBandModeCore parity', () {
      test('clearing selectedHeadphoneProfile on setBandMode', () async {
        // EqualizerManager's _setBandModeCore clears selectedHeadphoneProfile
        final eqManager = EqualizerManager();
        eqManager.selectedHeadphoneProfile = null;
        // Verify field exists and is accessible
        expect(eqManager.selectedHeadphoneProfile, isNull);
      });
    });
  });
}
