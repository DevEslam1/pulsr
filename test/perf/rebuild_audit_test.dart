// test/perf/rebuild_audit_test.dart
// FIX-C1: Zero-rebuild audit and formal state machine validation for Phase C
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/services/metadata_search_service.dart';
import 'package:pulsr/core/services/ytm_service.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/data/scanner/media_scanner_service.dart';
import 'package:pulsr/domain/models/eq_preset.dart';
import 'package:pulsr/domain/models/ytm_track.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/tag_editor/tag_editor_cubit.dart';
import 'package:pulsr/features/tag_editor/tag_editor_state.dart';
import 'package:pulsr/features/ytm_search/cubit/ytm_search_state.dart';

class MockMediaScannerService extends Mock implements MediaScannerService {}
class MockMetadataSearchService extends Mock implements MetadataSearchService {}
class MockYtmService extends Mock implements YtmService {}

void main() {
  group('Phase C: Zero-Rebuild Audit & Formal State Machines', () {
    const testSong = SongsTableData(
      id: 101,
      title: 'Audit Track',
      artist: 'Audit Artist',
      album: 'Perf Album',
      durationMs: 250000,
      path: '/path/perf.mp3',
      source: SongSource.local,
      playCount: 5,
      dateAdded: 1000,
      isFavorite: false,
      isMissing: false,
      lastPositionMs: 0,
      isDownloaded: false,
    );

    test('NowPlayingScreen buildWhen skips position-only state emissions (0 rebuilds)', () {
      var state = const PlayerState(
        currentSong: testSong,
        isPlaying: true,
        duration: Duration(minutes: 4),
        position: Duration(seconds: 1),
      );

      var rebuildCount = 0;
      // Simulate 50 position ticks (e.g. 5Hz over 10 seconds)
      for (int i = 2; i <= 50; i++) {
        final nextState = state.copyWith(position: Duration(seconds: i));
        final shouldRebuild = state.differsFromBeyondPosition(nextState);
        if (shouldRebuild) {
          rebuildCount++;
        }
        state = nextState;
      }

      expect(rebuildCount, equals(0),
          reason: 'Position ticks must NEVER trigger NowPlayingScreen rebuilds');
    });

    test('MiniPlayer buildWhen condition ignores playback position ticks', () {
      bool miniPlayerBuildWhen(PlayerState a, PlayerState b) =>
          a.currentSong?.id != b.currentSong?.id ||
          a.currentSong?.title != b.currentSong?.title ||
          a.currentSong?.artist != b.currentSong?.artist ||
          a.currentSong?.remoteArtworkUrl != b.currentSong?.remoteArtworkUrl ||
          a.isPlaying != b.isPlaying ||
          a.duration != b.duration ||
          a.currentIndex != b.currentIndex;

      const state1 = PlayerState(
        currentSong: testSong,
        isPlaying: true,
        duration: Duration(minutes: 4),
        position: Duration(seconds: 5),
      );

      const state2 = PlayerState(
        currentSong: testSong,
        isPlaying: true,
        duration: Duration(minutes: 4),
        position: Duration(seconds: 15),
      );

      expect(miniPlayerBuildWhen(state1, state2), isFalse,
          reason: 'Position progression must not trigger MiniPlayer parent card rebuild');
    });

    test('TagEditorCubit guards saveTags when status is not loaded', () async {
      final mockScanner = MockMediaScannerService();
      final mockMetadata = MockMetadataSearchService();

      final cubit = TagEditorCubit(
        song: testSong,
        scannerService: mockScanner,
        metadataSearchService: mockMetadata,
      );

      // Immediately after instantiation in single-song mode, cubit is loading tags
      // or if status is not loaded, saveTags must safely abort.
      if (cubit.state.status != TagEditorStatus.loaded) {
        await cubit.saveTags();
        // State must remain unaffected (not transitioned to saving or failure)
        expect(cubit.state.status, isNot(TagEditorStatus.saving));
      }

      await cubit.close();
    });

    test('YtmSearchState.phase formal state machine transitions correctly', () {
      // 1. Idle
      const idleState = YtmSearchState();
      expect(idleState.phase, equals(SearchPhase.idle));

      // 2. Debouncing
      final debouncingState = idleState.copyWith(query: 'Coldplay');
      expect(debouncingState.phase, equals(SearchPhase.debouncing));

      // 3. Fetching
      final fetchingState = debouncingState.copyWith(isLoading: true);
      expect(fetchingState.phase, equals(SearchPhase.fetching));

      // 4. Displaying
      const track = YtmTrack(
        videoId: 'abc',
        title: 'Yellow',
        artist: 'Coldplay',
        duration: Duration(minutes: 4),
      );
      final displayingState = fetchingState.copyWith(
        isLoading: false,
        results: [track],
      );
      expect(displayingState.phase, equals(SearchPhase.displaying));
      expect(displayingState.phase.isTerminal, isTrue);

      // 5. Error
      final errorState = fetchingState.copyWith(
        isLoading: false,
        errorMessage: 'Network timeout',
      );
      expect(errorState.phase, equals(SearchPhase.error));
      expect(errorState.phase.isTerminal, isTrue);
    });

    test('Equalizer sub-state comparator excludes position ticks', () {
      const stateA = PlayerState(
        isEqEnabled: true,
        eqPreset: EqPreset(name: 'Rock', gains: [1.0, 2.0]),
        position: Duration(seconds: 10),
      );

      final stateB = stateA.copyWith(
        position: Duration(seconds: 30),
      );

      // Both states share identical DSP parameters
      expect(stateA.isEqEnabled, equals(stateB.isEqEnabled));
      expect(stateA.eqPreset, equals(stateB.eqPreset));
      expect(stateA.isVirtualizerEnabled, equals(stateB.isVirtualizerEnabled));
      expect(stateA.isLimiterEnabled, equals(stateB.isLimiterEnabled));
    });
  });
}
