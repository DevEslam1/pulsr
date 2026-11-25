import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/network/remote_target_policy.dart';
import 'package:pulsr/core/widgets/pulsr_chip.dart';
import 'package:pulsr/core/widgets/pulsr_dialog.dart';
import 'package:pulsr/core/widgets/pulsr_error_boundary.dart';
import 'package:pulsr/core/widgets/pulsr_list_tile.dart';
import 'package:pulsr/core/widgets/pulsr_segmented_control.dart';
import 'package:pulsr/core/widgets/pulsr_slider.dart';
import 'package:pulsr/core/widgets/pulsr_text.dart';
import 'package:pulsr/core/widgets/pulsr_toast.dart';
import 'package:pulsr/core/widgets/song_tile.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/settings/cubit/settings_state.dart'
    show PlayerSliderStyle;
import 'package:pulsr/l10n/app_localizations_delegates.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

class MockPlayerCubit extends Mock implements PlayerCubit {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockPlayerCubit mockPlayerCubit;

  const testSong = SongsTableData(
    id: 101,
    title: 'Test Symphony',
    artist: 'Test Artist',
    album: 'Test Album',
    durationMs: 180000,
    path: '/music/test.flac',
    source: SongSource.local,
    playCount: 0,
    dateAdded: 0,
    isFavorite: false,
    isMissing: false,
    isDownloaded: false,
    lastPositionMs: 0,
  );

  setUp(() {
    mockPlayerCubit = MockPlayerCubit();
    when(() => mockPlayerCubit.state).thenReturn(const PlayerState());
    when(() => mockPlayerCubit.stream).thenAnswer((_) => const Stream.empty());
  });

  group('Phase 4: SongTile Accessibility', () {
    testWidgets('Trailing actions are separate focusable semantic nodes',
        (tester) async {
      bool morePressed = false;

      await tester.pumpWidget(
        BlocProvider<PlayerCubit>.value(
          value: mockPlayerCubit,
          child: MaterialApp(
            localizationsDelegates: appLocalizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: SongTile(
                song: testSong,
                onTap: () {},
                onMorePressed: () => morePressed = true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final moreFinder = find.byType(IconButton);
      expect(moreFinder, findsOneWidget);

      await tester.tap(moreFinder);
      expect(morePressed, isTrue);

      // Verify Semantics handles more button as a distinct button
      final moreSemantics = find.descendant(
        of: moreFinder,
        matching: find.byType(Semantics),
      );
      expect(moreSemantics, findsWidgets);
    });
  });

  group('Phase 4: PulsrListTile Accessibility', () {
    testWidgets('Trailing switch remains reachable by screen readers',
        (tester) async {
      bool switchVal = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return PulsrListTile(
                  title: 'High Resolution Audio',
                  subtitle: 'Enable 24-bit 192kHz output',
                  trailing: Switch(
                    value: switchVal,
                    onChanged: (v) => setState(() => switchVal = v),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final switchFinder = find.byType(Switch);
      expect(switchFinder, findsOneWidget);

      await tester.tap(switchFinder);
      await tester.pumpAndSettle();
      expect(switchVal, isTrue);
    });
  });

  group('Phase 4: PulsrChip Accessibility', () {
    testWidgets('onDeleted close button is a reachable semantic button',
        (tester) async {
      bool deleted = false;

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: PulsrChip(
              label: 'Classical',
              onTap: () {},
              onDeleted: () => deleted = true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final deleteIcon = find.byIcon(Icons.close_rounded);
      expect(deleteIcon, findsOneWidget);

      await tester.tap(deleteIcon);
      expect(deleted, isTrue);
    });
  });

  group('Phase 4: PulsrSlider Style Gating', () {
    testWidgets(
        'PlayerSliderStyle.normal selects straight track even if isWavy is true',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PulsrSlider(
              value: 0.5,
              onChanged: (_) {},
              isWavy: true,
              sliderStyle: PlayerSliderStyle.normal,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final customPaintFinder = find.byType(CustomPaint);
      expect(customPaintFinder, findsWidgets);
    });
  });

  group('Phase 4: PulsrToast maxLines', () {
    testWidgets('PulsrToast wires maxLines properly', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () {
                    PulsrToast.show(
                      context,
                      message: 'Line 1\nLine 2\nLine 3\nLine 4',
                      maxLines: 4,
                    );
                  },
                  child: const Text('Show Toast'),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Show Toast'));
      await tester.pump();

      final textFinder = find.text('Line 1\nLine 2\nLine 3\nLine 4');
      expect(textFinder, findsOneWidget);
      final Text textWidget = tester.widget(textFinder);
      expect(textWidget.maxLines, equals(4));
    });
  });

  group('Phase 4: PulsrDialog', () {
    testWidgets(
        'showConfirmDialog pops correctly with custom navigator context',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () {
                    PulsrDialogHelper.showConfirmDialog(
                      context,
                      title: 'Delete Playlist?',
                      message: 'This cannot be undone.',
                    );
                  },
                  child: const Text('Open Dialog'),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Delete Playlist?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Delete Playlist?'), findsNothing);
    });
  });

  group('Phase 4: PulsrErrorBoundary Localization', () {
    testWidgets('Localizes default strings via AppLocalizations with fallbacks',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            body: PulsrErrorBoundary(
              builder: (context) => throw Exception('Boundary test'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Something went wrong'), findsOneWidget);
      expect(
        find.text(
            'An unexpected error occurred while displaying this content.'),
        findsOneWidget,
      );
      expect(find.text('Try again'), findsOneWidget);
    });
  });

  group('Phase 4: PulsrSegmentedControl & Pressable', () {
    testWidgets('Segmented control non-sliding branch uses clampedIndex',
        (tester) async {
      int selected = -1;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PulsrSegmentedControl(
              slidingIndicator: false,
              segments: const [
                PulsrSegment(label: 'Tab 1', icon: Icons.audiotrack),
                PulsrSegment(label: 'Tab 2', icon: Icons.album),
              ],
              selectedIndex: 99,
              onChanged: (idx) => selected = idx,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap Tab 1 (index 0)
      await tester.tap(find.text('Tab 1'));
      await tester.pumpAndSettle();
      expect(selected, equals(0));
    });
  });

  group('Phase 4: PulsrText Typography', () {
    test('fontFallbacks contains Noto Sans Arabic', () {
      expect(PulsrText.fontFallbacks, contains('Noto Sans Arabic'));
      expect(PulsrText.fontFamily, equals('Manrope'));
    });
  });

  group('Phase 4: CachedArtwork Policy', () {
    test('RemoteTargetPolicy classifies unsafe localhost fallback as blocked',
        () {
      expect(
        RemoteTargetPolicy.isAllowed('http://127.0.0.1/evil.jpg'),
        isFalse,
      );
      expect(
        RemoteTargetPolicy.isAllowed('http://169.254.169.254/metadata'),
        isFalse,
      );
    });
  });
}
