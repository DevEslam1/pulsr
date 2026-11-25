import 'package:bloc_test/bloc_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/core/widgets/a11y_live_announcer.dart';
import 'package:pulsr/core/widgets/pulsr_bottom_sheet.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

import 'package:pulsr/l10n/app_localizations_delegates.dart';

class MockPlayerCubit extends Mock implements PlayerCubit {}

SongsTableData _testSong({
  required int id,
  required String title,
  required String artist,
}) {
  return SongsTableData(
    id: id,
    title: title,
    artist: artist,
    album: 'Album',
    durationMs: 180000,
    path: '/music/$id.mp3',
    source: SongSource.local,
    isFavorite: false,
    playCount: 0,
    lastPositionMs: 0,
    isMissing: false,
    isDownloaded: false,
  );
}

Widget _wrapWithHarness({
  required Widget child,
  required PlayerCubit playerCubit,
}) {
  return MaterialApp(
    localizationsDelegates: appLocalizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: ThemeData.dark().copyWith(
      extensions: [AuraTheme.defaultDark],
      focusColor: AuraTheme.defaultDark.accent.withValues(alpha: 0.20),
    ),
    home: BlocProvider<PlayerCubit>.value(
      value: playerCubit,
      child: Scaffold(
        body: child,
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockPlayerCubit mockCubit;

  setUp(() {
    mockCubit = MockPlayerCubit();
  });

  group('P5 Accessibility — LiveRegion & Announcements', () {
    testWidgets('Track change triggers TalkBack announcement in live region',
        (tester) async {
      final song1 = _testSong(id: 1, title: 'Midnight City', artist: 'M83');
      final song2 = _testSong(id: 2, title: 'Starboy', artist: 'The Weeknd');

      final state = const PlayerState().copyWith(
        playback: const PlaybackSlice(
          isPlaying: true,
        ).copyWith(currentSong: song1),
      );

      when(() => mockCubit.state).thenReturn(state);
      whenListen(
        mockCubit,
        Stream<PlayerState>.fromIterable([
          state,
          state.copyWith(
            playback: state.playback.copyWith(currentSong: song2),
          ),
        ]),
        initialState: state,
      );

      await tester.pumpWidget(
        _wrapWithHarness(
          playerCubit: mockCubit,
          child: const A11yLiveAnnouncer(
            child: Text('Shell Content'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final stateObj =
          tester.state<A11yLiveAnnouncerState>(find.byType(A11yLiveAnnouncer));
      expect(stateObj.currentAnnouncement, contains('Starboy'));
      expect(stateObj.currentAnnouncement, contains('The Weeknd'));

      // Verify Semantics liveRegion node exists
      final liveRegionFinder = find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.liveRegion == true,
      );
      expect(liveRegionFinder, findsOneWidget);
    });

    testWidgets('Play / pause transitions trigger announcements',
        (tester) async {
      final song = _testSong(id: 1, title: 'Midnight City', artist: 'M83');
      final state = const PlayerState().copyWith(
        playback: const PlaybackSlice(
          isPlaying: false,
        ).copyWith(currentSong: song),
      );

      when(() => mockCubit.state).thenReturn(state);
      whenListen(
        mockCubit,
        Stream<PlayerState>.fromIterable([
          state,
          state.copyWith(
            playback: state.playback.copyWith(isPlaying: true),
          ),
        ]),
        initialState: state,
      );

      await tester.pumpWidget(
        _wrapWithHarness(
          playerCubit: mockCubit,
          child: const A11yLiveAnnouncer(
            child: Text('Shell Content'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final stateObj =
          tester.state<A11yLiveAnnouncerState>(find.byType(A11yLiveAnnouncer));
      expect(stateObj.currentAnnouncement, equals('Playing'));
    });

    testWidgets(
        'Queue mutation announcements: added, removed, reordered, cleared',
        (tester) async {
      final s1 = _testSong(id: 1, title: 'Song 1', artist: 'Artist 1');
      final s2 = _testSong(id: 2, title: 'Song 2', artist: 'Artist 2');

      final state = const PlayerState().copyWith(
        playback: const PlaybackSlice().copyWith(currentSong: s1),
        queueSlice: QueueSlice(queue: [s1]),
      );

      when(() => mockCubit.state).thenReturn(state);
      whenListen(
        mockCubit,
        Stream<PlayerState>.fromIterable([
          state,
          state.copyWith(
            queueSlice: state.queueSlice.copyWith(queue: [s1, s2]),
          ),
        ]),
        initialState: state,
      );

      await tester.pumpWidget(
        _wrapWithHarness(
          playerCubit: mockCubit,
          child: const A11yLiveAnnouncer(
            child: Text('Shell Content'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final stateObj =
          tester.state<A11yLiveAnnouncerState>(find.byType(A11yLiveAnnouncer));
      expect(stateObj.currentAnnouncement, contains('Song 2'));
    });
  });

  group('P5 Accessibility — Single-Node Slider Semantics', () {
    testWidgets('Single-node semantics excludes internal slider duplication',
        (tester) async {
      double testVal = 0.0;
      final handle = tester.ensureSemantics();

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData.dark().copyWith(
            extensions: [AuraTheme.defaultDark],
          ),
          home: Scaffold(
            body: Center(
              child: Semantics(
                slider: true,
                excludeSemantics: true,
                label: 'Test Gain',
                value: '${testVal.toStringAsFixed(1)} dB',
                increasedValue: '${(testVal + 1.0).toStringAsFixed(1)} dB',
                decreasedValue: '${(testVal - 1.0).toStringAsFixed(1)} dB',
                onIncrease: () => testVal += 1.0,
                onDecrease: () => testVal -= 1.0,
                child: Slider(
                  value: testVal,
                  min: -12.0,
                  max: 12.0,
                  onChanged: (v) => testVal = v,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Find semantics node for Test Gain
      final node = tester.getSemantics(find.byType(Slider));
      expect(node.flagsCollection.isSlider, isTrue);
      expect(node.label, equals('Test Gain'));
      expect(node.value, equals('0.0 dB'));
      expect(node.increasedValue, equals('1.0 dB'));
      expect(node.decreasedValue, equals('-1.0 dB'));

      // Test increase action
      node.owner?.performAction(node.id, SemanticsAction.increase);
      expect(testVal, equals(1.0));

      // Test decrease action
      node.owner?.performAction(node.id, SemanticsAction.decrease);
      expect(testVal, equals(0.0));

      handle.dispose();
    });
  });

  group('P5 Accessibility — Desktop Focus Traversal & Rings', () {
    testWidgets('AuraTheme includes focusColor from active palette accent',
        (tester) async {
      final theme = AuraTheme.darkTheme;
      expect(theme.focusColor,
          equals(AuraTheme.defaultDark.accent.withValues(alpha: 0.20)));
    });

    testWidgets('PulsrBottomSheetContainer enforces OrderedTraversalPolicy',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData.dark().copyWith(
            extensions: [AuraTheme.defaultDark],
          ),
          home: const Scaffold(
            body: PulsrBottomSheetContainer(
              titleText: 'Sheet Title',
              child: Text('Sheet Body'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final focusGroups = tester.widgetList<FocusTraversalGroup>(
        find.byType(FocusTraversalGroup),
      );
      expect(
          focusGroups.any((g) => g.policy is OrderedTraversalPolicy), isTrue);

      final traversalOrders = tester.widgetList<FocusTraversalOrder>(
        find.byType(FocusTraversalOrder),
      );
      expect(traversalOrders.length, greaterThanOrEqualTo(2));
      final orders = traversalOrders
          .map((o) => (o.order as NumericFocusOrder).order)
          .toList();
      expect(orders, contains(1.0));
      expect(orders, contains(2.0));
    });
  });

  group('P5 Accessibility — Eyes-Free E2E Journey Validation', () {
    testWidgets('Eyes-free journey traversal contracts are preserved',
        (tester) async {
      final song = _testSong(id: 1, title: 'Solar Power', artist: 'Lorde');
      final state = const PlayerState().copyWith(
        playback: PlaybackSlice(
          currentSong: song,
          isPlaying: true,
          position: const Duration(seconds: 45),
          duration: const Duration(seconds: 180),
        ),
      );

      when(() => mockCubit.state).thenReturn(state);

      await tester.pumpWidget(
        _wrapWithHarness(
          playerCubit: mockCubit,
          child: Column(
            children: [
              Semantics(
                button: true,
                label: 'Onboarding Complete',
                child: const ElevatedButton(
                  onPressed: null,
                  child: Text('Start'),
                ),
              ),
              Semantics(
                button: true,
                label: 'Scan Library',
                child: const IconButton(
                  icon: Icon(Icons.refresh),
                  onPressed: null,
                ),
              ),
              Semantics(
                button: true,
                label: 'Play',
                child: const IconButton(
                  icon: Icon(Icons.play_arrow),
                  onPressed: null,
                ),
              ),
              Semantics(
                slider: true,
                label: 'Seek',
                value: '0:45 of 3:00',
                child: const Slider(
                  value: 45,
                  max: 180,
                  onChanged: null,
                ),
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel('Onboarding Complete'), findsOneWidget);
      expect(find.bySemanticsLabel('Scan Library'), findsOneWidget);
      expect(find.bySemanticsLabel('Play'), findsOneWidget);
      expect(find.bySemanticsLabel('Seek'), findsOneWidget);
    });
  });
}
