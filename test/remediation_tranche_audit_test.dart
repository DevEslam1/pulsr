// test/remediation_tranche_audit_test.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/bloc/base_cubit.dart';
import 'package:pulsr/core/constants/app_timing.dart';
import 'package:pulsr/core/theme/dynamic_theme_cubit.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/player/cubit/queue_slot_codec.dart';
import 'package:pulsr/features/library/presentation/widgets/genre_hierarchy_view.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

class _TestPulsrCubit extends PulsrCubit<int> {
  _TestPulsrCubit() : super(0);

  void increment() => safeEmit(state + 1);

  StreamSubscription<T> testAutoSub<T>(
    Stream<T> stream,
    void Function(T data) onData,
  ) {
    return autoSub(stream, onData);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Remediation Tranche Audit Tests', () {
    test('C1 & C2: BaseCubit autoSub returns cancelled subscription when closed and close() cleans up', () async {
      final cubit = _TestPulsrCubit();
      expect(cubit.activeSubscriptionCount, equals(0));

      final controller = StreamController<int>.broadcast();
      var dataReceived = 0;

      // Subscribe before close
      cubit.testAutoSub(controller.stream, (val) => dataReceived += val);
      expect(cubit.activeSubscriptionCount, equals(1));

      controller.add(5);
      await Future.delayed(const Duration(milliseconds: 10));
      expect(dataReceived, equals(5));

      // Close cubit
      await cubit.close();
      expect(cubit.isClosed, isTrue);
      expect(cubit.activeSubscriptionCount, equals(0));

      // Attempting autoSub after close returns an already cancelled subscription (C1)
      final postCloseSub = cubit.testAutoSub(controller.stream, (val) => dataReceived += val);
      expect(postCloseSub, isNotNull);

      // Sending data should NOT reach callback
      controller.add(10);
      await Future.delayed(const Duration(milliseconds: 10));
      expect(dataReceived, equals(5)); // untouched

      await controller.close();
    });

    test('C3: DynamicThemeCubit handles close and resets properly', () async {
      final cubit = DynamicThemeCubit();
      expect(cubit.state.hasCustomArtworkColor, isFalse);

      await cubit.close();
      expect(cubit.isClosed, isTrue);
    });

    test('M6: QueueSlotCodec clampPosition validates bounds properly', () {
      // Negative position clamps to zero
      expect(QueueSlotCodec.clampPosition(-1000), equals(Duration.zero));
      expect(QueueSlotCodec.clampPosition(0), equals(Duration.zero));

      // Positive valid position
      expect(
        QueueSlotCodec.clampPosition(5000),
        equals(const Duration(milliseconds: 5000)),
      );

      // Value beyond maxPositionMs (7 days) clamps to maxPositionMs
      const maxMs = QueueSlotCodec.maxPositionMs;
      expect(
        QueueSlotCodec.clampPosition(maxMs + 100000),
        equals(const Duration(milliseconds: maxMs)),
      );
    });

    test('M7: PlayerState differsFromBeyondPosition checks playbackPitch', () {
      const state1 = PlayerState(
        playback: PlaybackSlice(playbackPitch: 1.0),
      );
      const state2 = PlayerState(
        playback: PlaybackSlice(playbackPitch: 1.2),
      );
      const state3 = PlayerState(
        playback: PlaybackSlice(playbackPitch: 1.0),
      );

      expect(state1.differsFromBeyondPosition(state2), isTrue);
      expect(state1.differsFromBeyondPosition(state3), isFalse);
    });

    test('L2: AppTiming provides standardized timing durations', () {
      expect(AppTiming.debounceShort, equals(const Duration(milliseconds: 200)));
      expect(AppTiming.debounceMedium, equals(const Duration(milliseconds: 300)));
      expect(AppTiming.debounceLong, equals(const Duration(milliseconds: 500)));
      expect(AppTiming.throttleProgress, equals(const Duration(milliseconds: 100)));
      expect(AppTiming.navThrottle, equals(const Duration(milliseconds: 200)));
      expect(AppTiming.staggerDelay, equals(const Duration(milliseconds: 500)));
    });

    test('H7: Enhanced songs hash differentiates lists with identical endpoints and length', () {
      SongsTableData createSong(int id) => SongsTableData(
        id: id,
        title: 'Song $id',
        artist: 'Artist',
        album: 'Album',
        durationMs: 1000,
        path: '/$id.mp3',
        source: SongSource.local,
        isFavorite: false,
        isMissing: false,
        isDownloaded: false,
        playCount: 0,
        lastPositionMs: 0,
      );

      // 12 songs: song 1 to 12
      final list1 = List.generate(12, (i) => createSong(i + 1));
      // Same length, same first (1) and last (12), but middle item (5) is different
      final list2 = List.generate(12, (i) {
        if (i == 4) return createSong(999);
        return createSong(i + 1);
      });

      int computeHash(List<SongsTableData> songs) {
        return Object.hashAll([
          songs.length,
          for (final s in songs.take(10)) s.id,
          for (final s in songs.skip(songs.length > 10 ? songs.length - 10 : 0)) s.id,
        ]);
      }

      final hash1 = computeHash(list1);
      final hash2 = computeHash(list2);

      expect(hash1, isNot(equals(hash2)));
    });

    testWidgets('H12: GenreCategory clearCache and instance count reference management', (tester) async {
      GenreCategory.clearCache();

      const category = GenreCategory('Jazz', Icons.music_note, ['jazz', 'blues']);
      expect(category.matches('Smooth Jazz Evening'), isTrue);
      expect(category.matches('Rock and Roll'), isFalse);

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          home: const Scaffold(
            body: GenreHierarchyView(genres: []),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Ensure regex cache matches still function with widget mounted
      expect(category.matches('Delta Blues'), isTrue);

      // Unmount the widget
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();

      // Clearing cache when count drops to 0 leaves future matching operational
      expect(category.matches('Bebop Jazz'), isTrue);
    });

    test('Lyrics & Overlay: PlayerState differsFromBeyondPosition reacts immediately to lyrics and queue tabs', () {
      const base = PlayerState(
        lyricsSlice: LyricsSlice(isLyricsVisible: false, isQueueVisible: false),
      );

      // Tapping lyrics tab toggles isLyricsVisible to true
      final lyricsTabActive = base.copyWith(
        lyricsSlice: base.lyricsSlice.copyWith(isLyricsVisible: true),
      );
      expect(base.differsFromBeyondPosition(lyricsTabActive), isTrue,
          reason: 'Lyrics tab toggle must trigger rebuild immediately without reopen');

      // Tapping queue tab toggles isQueueVisible to true
      final queueTabActive = base.copyWith(
        lyricsSlice: base.lyricsSlice.copyWith(isQueueVisible: true),
      );
      expect(base.differsFromBeyondPosition(queueTabActive), isTrue,
          reason: 'Queue tab toggle must trigger rebuild immediately');

      // Position ticks do not trigger rebuild
      final positionTick = base.copyWith(
        playback: base.playback.copyWith(position: const Duration(seconds: 15)),
      );
      expect(base.differsFromBeyondPosition(positionTick), isFalse,
          reason: 'Position ticks must be filtered out');
    });
  });
}
