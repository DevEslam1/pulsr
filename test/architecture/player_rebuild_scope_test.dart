// Player rebuild-scope guard.
//
// The Now Playing screen and the mini player sit on top of a deliberately
// narrow state diff: `PlayerState.differsFromBeyondPosition` reacts to
// transport/track/queue/lyrics changes and to DSP *active-status* toggles, but
// ignores per-second `position` ticks and DSP *parameter* churn (sliders drive
// their own selectors). The screens then re-add position ticks only for the
// skeuomorphic themes that paint progress into their artwork.
//
// Both halves are load-bearing for frame pacing and are invisible to ordinary
// widget tests, so this file pins them down in two ways:
//   1. unit tests on the diff contract itself;
//   2. source-scan guards on the `buildWhen` gates, following the same idiom as
//      test/architecture/settings_wiring_test.dart.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/domain/models/lyrics_line.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';

void main() {
  const songA = SongsTableData(
    id: 1,
    title: 'Scoped Track',
    artist: 'Gate Artist',
    album: 'Rebuild Budget',
    durationMs: 180000,
    path: '/music/scoped-a.flac',
    source: SongSource.local,
    playCount: 0,
    dateAdded: 0,
    isFavorite: false,
    isMissing: false,
    lastPositionMs: 0,
    isDownloaded: false,
  );

  const songB = SongsTableData(
    id: 2,
    title: 'Next Track',
    artist: 'Gate Artist',
    album: 'Rebuild Budget',
    durationMs: 240000,
    path: '/music/scoped-b.flac',
    source: SongSource.local,
    playCount: 0,
    dateAdded: 0,
    isFavorite: false,
    isMissing: false,
    lastPositionMs: 0,
    isDownloaded: false,
  );

  // Baseline: mid-playback, so a position-only tick is a realistic delta.
  const base = PlayerState(
    playback: PlaybackSlice(
      currentSong: songA,
      isPlaying: true,
      position: Duration(seconds: 30),
      duration: Duration(minutes: 3),
    ),
  );

  group('PlayerState diff contract', () {
    test('position-only change is invisible to both diff helpers', () {
      const next = PlayerState(
        playback: PlaybackSlice(
          currentSong: songA,
          isPlaying: true,
          position: Duration(seconds: 31),
          duration: Duration(minutes: 3),
        ),
      );

      expect(base.playback.differsBeyondPosition(next.playback), isFalse);
      expect(next.playback.differsBeyondPosition(base.playback), isFalse);
      expect(base.differsFromBeyondPosition(next), isFalse);
      expect(next.differsFromBeyondPosition(base), isFalse);
    });

    test('isPlaying change is beyond position', () {
      const next = PlayerState(
        playback: PlaybackSlice(
          currentSong: songA,
          isPlaying: false,
          position: Duration(seconds: 30),
          duration: Duration(minutes: 3),
        ),
      );

      expect(base.playback.differsBeyondPosition(next.playback), isTrue);
      expect(base.differsFromBeyondPosition(next), isTrue);
    });

    test('currentSong change is beyond position', () {
      const next = PlayerState(
        playback: PlaybackSlice(
          currentSong: songB,
          isPlaying: true,
          position: Duration(seconds: 30),
          duration: Duration(minutes: 3),
        ),
      );

      expect(base.playback.differsBeyondPosition(next.playback), isTrue);
      expect(base.differsFromBeyondPosition(next), isTrue);
    });

    test('duration change is beyond position', () {
      const next = PlayerState(
        playback: PlaybackSlice(
          currentSong: songA,
          isPlaying: true,
          position: Duration(seconds: 30),
          duration: Duration(minutes: 4),
        ),
      );

      expect(base.playback.differsBeyondPosition(next.playback), isTrue);
      expect(base.differsFromBeyondPosition(next), isTrue);
    });

    test('queue change is beyond position', () {
      final next = base.copyWith(
        queueSlice: const QueueSlice(queue: [songA, songB]),
      );

      expect(base.queueSlice.differs(next.queueSlice), isTrue);
      expect(base.differsFromBeyondPosition(next), isTrue);
    });

    test('lyrics change is beyond position', () {
      final next = base.copyWith(
        lyricsSlice: const LyricsSlice(
          lyrics: [LyricsLine(timestamp: Duration.zero, text: 'first line')],
        ),
      );

      expect(base.lyricsSlice == next.lyricsSlice, isFalse);
      expect(base.differsFromBeyondPosition(next), isTrue);
    });

    test('isEqEnabled change is beyond position', () {
      final next = base.copyWith(dsp: base.dsp.copyWith(isEqEnabled: true));

      expect(base.isEqEnabled, isFalse);
      expect(base.differsFromBeyondPosition(next), isTrue);
    });

    test('isQuranModeEnabled change is beyond position', () {
      final next = base.copyWith(
        dsp: base.dsp.copyWith(isQuranModeEnabled: true),
      );

      expect(base.differsFromBeyondPosition(next), isTrue);
    });
  });

  group('DSP churn stays out of the theme rebuild gate', () {
    test('DSP parameter drags are ignored', () {
      expect(
        base.isDspActive,
        isFalse,
        reason: 'baseline must have no active DSP stage',
      );

      // Every entry is a pure parameter of an effect that is either off or
      // volume-neutral, so none of them may flip `isDspActive`. If one does,
      // the parameter belongs on the isDspActive list instead of here.
      final churned = <String, DspSlice>{
        'virtualizerStrength': base.dsp.copyWith(virtualizerStrength: 0.75),
        'reverbWetDry': base.dsp.copyWith(reverbWetDry: 0.60),
        'preampDb': base.dsp.copyWith(preampDb: -6.0),
        'limiterThresholdDb': base.dsp.copyWith(limiterThresholdDb: -3.0),
        'compressorRatio': base.dsp.copyWith(compressorRatio: 4.0),
        'saturationDrive': base.dsp.copyWith(saturationDrive: 0.90),
        'stereoWidthLow': base.dsp.copyWith(stereoWidthLow: 0.40),
        'crossfeedDelayUs': base.dsp.copyWith(crossfeedDelayUs: 700.0),
        'subCrossoverCornerHz': base.dsp.copyWith(subCrossoverCornerHz: 105.0),
        'dynamicBassStrength': base.dsp.copyWith(dynamicBassStrength: 0.85),
      };

      for (final entry in churned.entries) {
        final next = base.copyWith(dsp: entry.value);
        expect(
          next.isDspActive,
          isFalse,
          reason: '${entry.key} must not activate the DSP chain',
        );
        expect(
          base.differsFromBeyondPosition(next),
          isFalse,
          reason: '${entry.key} must not rebuild the Now Playing theme',
        );
        expect(
          next.differsFromBeyondPosition(base),
          isFalse,
          reason: '${entry.key} must not rebuild in the reverse direction',
        );
      }
    });

    test('isDspActive flipping does rebuild, even mid-drag', () {
      final active = base.copyWith(
        dsp: base.dsp.copyWith(isLimiterEnabled: true),
      );
      expect(active.isDspActive, isTrue);
      expect(base.differsFromBeyondPosition(active), isTrue);
      expect(active.differsFromBeyondPosition(base), isTrue);

      final reverbOn = base.copyWith(
        dsp: base.dsp.copyWith(isReverbEnabled: true, reverbWetDry: 0.5),
      );
      expect(reverbOn.isDspActive, isTrue);
      expect(base.differsFromBeyondPosition(reverbOn), isTrue);

      // With a stage already active, further parameter churn stays ignored:
      // the gate keys on active-status, not on the parameter values.
      final stillActive = active.copyWith(
        dsp: active.dsp.copyWith(limiterThresholdDb: -1.5),
      );
      expect(active.differsFromBeyondPosition(stillActive), isFalse);
    });
  });

  group('Source guards: player buildWhen gates stay scoped', () {
    // Same source-scan idiom as test/architecture/settings_wiring_test.dart:
    // the gate is a widget-level contract that no unit test can observe.
    String read(String path) {
      final file = File(path);
      expect(file.existsSync(), isTrue, reason: '$path must exist');
      return file.readAsStringSync();
    }

    test(
      'now_playing_screen gates on the scoped diff plus theme-only ticks',
      () {
        final src = read(
          'lib/features/player/presentation/now_playing_screen.dart',
        );

        final gateAt = src.indexOf('buildWhen:');
        expect(
          gateAt,
          isNot(-1),
          reason: 'Now Playing must keep an explicit buildWhen gate',
        );
        final gate = src.substring(gateAt, (gateAt + 600).clamp(0, src.length));

        expect(
          gate.contains('differsFromBeyondPosition(curr)'),
          isTrue,
          reason: 'the gate must call the shared scoped diff',
        );
        expect(
          gate.contains('position.inSeconds'),
          isTrue,
          reason: 'skeuomorphic themes need per-second ticks',
        );
        expect(
          gate.contains('needsPositionTick &&'),
          isTrue,
          reason: 'per-second ticks must be behind the theme switch',
        );
        // A gate that rebuilds on everything is the exact regression this file
        // exists to catch; a comment mentioning the helper must not satisfy it.
        expect(
          RegExp(r'buildWhen:\s*\(\s*\w+\s*,\s*\w+\s*\)\s*=>\s*true')
              .hasMatch(src),
          isFalse,
        );
      },
    );

    test('position ticks are conditional on skeuomorphic themes only', () {
      final src = read(
        'lib/features/player/presentation/now_playing_screen.dart',
      );

      // Declared as a switch over the player theme, not hard-wired true: the
      // non-skeuomorphic themes read position from PlayerSeekBar's selector.
      final decl = RegExp(
        r'needsPositionTick\s*=\s*switch\s*\([^)]*\)\s*\{([\s\S]*?)\n\s*\};',
      ).firstMatch(src);
      expect(
        decl,
        isNotNull,
        reason: 'needsPositionTick must be derived from playerThemeMode',
      );
      final arms = decl!.group(1)!;

      for (final theme in const [
        'PlayerThemeMode.circle',
        'PlayerThemeMode.vinyl',
        'PlayerThemeMode.cassette',
        'PlayerThemeMode.cd',
      ]) {
        expect(
          arms.contains(theme),
          isTrue,
          reason: '$theme paints position into artwork',
        );
      }
      expect(
        arms.contains('_ => false'),
        isTrue,
        reason: 'all other themes must not tick every second',
      );
      expect(RegExp(r'needsPositionTick\s*=\s*true').hasMatch(src), isFalse);
    });

    test(
      'mini_player gates its builders instead of rebuilding on any state',
      () {
        final src = read('lib/features/player/presentation/mini_player.dart');
        final stateSrc = read('lib/features/player/cubit/player_state.dart');

        final gates = RegExp(r'buildWhen:([\s\S]*?)builder:').allMatches(src);
        expect(
          gates.length,
          greaterThanOrEqualTo(2),
          reason: 'both mini player builders must be gated',
        );

        for (final gate in gates) {
          final condition = gate.group(1)!;
          expect(
            condition.contains('differsForMiniPlayer'),
            isTrue,
            reason: 'mini player gates must delegate to the named diff '
                'methods on PlayerState instead of hand-enumerating fields, '
                'so a new state field cannot silently leave the mini player '
                'stale',
          );
        }

        // The named gates live on PlayerState and must stay position-free: a
        // per-tick rebuild of the mini player is a battery regression, and the
        // progress bar scopes position to its own inner widget.
        for (final name in const [
          'differsForMiniPlayer',
          'differsForMiniPlayerHorizontal',
        ]) {
          final start = stateSrc.indexOf('bool $name(');
          expect(
            start,
            greaterThan(-1),
            reason: '$name must exist on PlayerState',
          );
          final rest = stateSrc.substring(start);
          final end = rest.indexOf('\n  }');
          final method = end == -1 ? rest : rest.substring(0, end);
          expect(
            method.contains('position'),
            isFalse,
            reason: '$name must ignore position ticks',
          );
        }

        expect(
          RegExp(r'buildWhen:\s*\(\s*\w+\s*,\s*\w+\s*\)\s*=>\s*true')
              .hasMatch(src),
          isFalse,
        );
      },
    );
  });
}
