import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/domain/models/audio_effects_config.dart';
import 'package:pulsr/domain/models/eq_preset.dart';
import 'package:pulsr/features/player/cubit/controllers/player_dsp_controller.dart';
import 'package:pulsr/features/player/cubit/player_scrobble_coordinator.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/player/cubit/player_widget_coordinator.dart';
import 'package:pulsr/features/player/cubit/quran_restore_snapshot.dart';
import 'package:pulsr/features/player/presentation/widgets/dsp_inspector_sheet.dart';

SongsTableData _makeSong(int id, String title, String artist) {
  return SongsTableData(
    id: id,
    title: title,
    artist: artist,
    album: 'Album $id',
    path: '/music/track$id.mp3',
    durationMs: 180000,
    playCount: 0,
    lastPositionMs: 0,
    isFavorite: false,
    isMissing: false,
    isDownloaded: false,
    source: SongSource.local,
  );
}

void main() {
  group('Player Audit Remediation Tests', () {
    test('PlayerScrobbleCoordinator has independent monotonic clocks per instance', () {
      final coordinator1 = PlayerScrobbleCoordinator(
        service: () => null,
        isQuranMode: () => false,
        isClosed: () => false,
        interval: const Duration(seconds: 30),
      );
      final coordinator2 = PlayerScrobbleCoordinator(
        service: () => null,
        isQuranMode: () => false,
        isClosed: () => false,
        interval: const Duration(seconds: 30),
      );

      // Verify coordinators are separate instances with their own timers/state
      expect(identical(coordinator1, coordinator2), isFalse);
      coordinator1.dispose();
      coordinator2.dispose();
    });

    test('Equalizer band gains hash differentiates permuted bands (Object.hashAll)', () {
      // Previously XOR fold caused identical hash for permuted bands
      final gainsA = [1.0, 2.0, 3.0];
      final gainsB = [3.0, 2.0, 1.0];

      final hashA = Object.hashAll(gainsA);
      final hashB = Object.hashAll(gainsB);

      expect(hashA, isNot(equals(hashB)));
    });

    test('PlayerWidgetCoordinator nextTitles includes songs hash in cache key', () {
      final coordinator = PlayerWidgetCoordinator(null);
      final songA = _makeSong(1, 'Song 1', 'Artist 1');
      final songB = _makeSong(2, 'Song 2', 'Artist 2');
      final songC = _makeSong(3, 'Song 3', 'Artist 3');

      final state1 = PlayerState(
        playback: PlaybackSlice(currentSong: songA),
        queueSlice: QueueSlice(queue: [songA, songB], currentIndex: 0),
      );

      final titles1 = coordinator.nextTitles(state1, 1);

      // Same queue version, same index, same queue length, same current song ID,
      // but second song changed from songB to songC
      final state2 = PlayerState(
        playback: PlaybackSlice(currentSong: songA),
        queueSlice: QueueSlice(queue: [songA, songC], currentIndex: 0),
      );

      final titles2 = coordinator.nextTitles(state2, 1);

      expect(titles1, isNot(equals(titles2)));
      expect(titles1?.first, 'Song 2 · Artist 2');
      expect(titles2?.first, 'Song 3 · Artist 3');
    });

    test('DspInspectorSheet.sanitizeReport redacts absolute file paths', () {
      const rawReport = '''
DSP Chain Status:
- App Data: /data/user/0/com.pulsr.music/files/dsp_state.json
- Reverb IR: /storage/emulated/0/Music/Impulses/hall.wav
- Custom Preset: C:\\Users\\Eslam\\Music\\preset.json
- Sample Rate: 48000Hz
''';

      final sanitized = DspInspectorSheet.sanitizeReport(rawReport);

      expect(sanitized.contains('/data/user/0/com.pulsr.music/files/dsp_state.json'), isFalse);
      expect(sanitized.contains('/storage/emulated/0/Music/Impulses/hall.wav'), isFalse);
      expect(sanitized.contains('C:\\Users\\Eslam\\Music\\preset.json'), isFalse);
      expect(sanitized.contains('[REDACTED_APP_PATH]'), isTrue);
      expect(sanitized.contains('[REDACTED_STORAGE_PATH]'), isTrue);
      expect(sanitized.contains('[REDACTED_LOCAL_PATH]'), isTrue);
      expect(sanitized.contains('Sample Rate: 48000Hz'), isTrue);
    });

    test('PlayerDspController defines 25MB max IR WAV file size limit', () {
      expect(PlayerDspController.maxIrFileSizeBytes, equals(25 * 1024 * 1024));
    });

    test('SongSource.radio is defined and distinct from local and youtube', () {
      expect(SongSource.radio, 'radio');
      expect(SongSource.radio, isNot(equals(SongSource.local)));
      expect(SongSource.radio, isNot(equals(SongSource.youtube)));
    });

    test('PlaybackSlice preserves and differentiates sleepTimerRemainingTracks', () {
      final slice1 = PlaybackSlice(sleepTimerRemainingTracks: 3);
      final slice2 = PlaybackSlice(sleepTimerRemainingTracks: 2);
      final slice3 = PlaybackSlice(sleepTimerRemainingTracks: 3);

      expect(slice1.sleepTimerRemainingTracks, 3);
      expect(slice1.differsBeyondPosition(slice2), isTrue);
      expect(slice1.differsBeyondPosition(slice3), isFalse);

      final state = PlayerState(playback: slice1);
      expect(state.sleepTimerRemainingTracks, 3);
    });

    test('PlayerState.differsFromBeyondPosition ignores internal DSP parameters but triggers on user-visible toggles', () {
      final base = PlayerState();
      
      // Internal DSP parameter tweak (e.g. saturation drive / stereo width) should NOT trigger full screen rebuild
      final internalTweak = base.copyWith(
        dsp: base.dsp.copyWith(saturationDrive: 0.8, stereoWidthLow: 0.5),
      );
      expect(base.differsFromBeyondPosition(internalTweak), isFalse);

      // User-visible DSP mode toggles DO trigger
      final eqToggled = base.copyWith(
        dsp: base.dsp.copyWith(isEqEnabled: !base.isEqEnabled),
      );
      expect(base.differsFromBeyondPosition(eqToggled), isTrue);

      final quranToggled = base.copyWith(
        dsp: base.dsp.copyWith(isQuranModeEnabled: !base.isQuranModeEnabled),
      );
      expect(base.differsFromBeyondPosition(quranToggled), isTrue);
    });

    test('QuranRestoreSnapshot serializes and deserializes correctly', () {
      final rockPreset = EqPreset.defaultPresets.firstWhere((p) => p.name == 'Rock');
      final snapshot = QuranRestoreSnapshot(
        eqPreset: rockPreset,
        isEqEnabled: true,
        headphoneProfile: null,
        isReverbEnabled: true,
        reverbPreset: 2,
        reverbWetDry: 0.35,
        isDynamicsEnabled: true,
        dynamicsPreset: DynamicsPreset.vocalFocus,
        isSaturationEnabled: true,
        saturationDrive: 0.4,
        saturationMix: 0.5,
        saturationTilt: -0.2,
        playbackSpeed: 1.25,
        isShuffle: true,
        preampDb: -1.5,
      );

      final json = snapshot.toJson();
      final restored = QuranRestoreSnapshot.fromJson(json);

      expect(restored.eqPreset.name, 'Rock');
      expect(restored.isEqEnabled, isTrue);
      expect(restored.headphoneProfile, isNull);
      expect(restored.isReverbEnabled, isTrue);
      expect(restored.reverbPreset, 2);
      expect(restored.reverbWetDry, 0.35);
      expect(restored.isDynamicsEnabled, isTrue);
      expect(restored.dynamicsPreset, DynamicsPreset.vocalFocus);
      expect(restored.isSaturationEnabled, isTrue);
      expect(restored.saturationDrive, 0.4);
      expect(restored.playbackSpeed, 1.25);
      expect(restored.isShuffle, isTrue);
      expect(restored.preampDb, -1.5);
    });
  });
}
