import 'dart:ui' show Tristate;

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/shell/presentation/bottom_nav_bar.dart';
import 'package:pulsr/features/shell/presentation/nav_destinations.dart';
import 'package:pulsr/features/shell/presentation/widgets/landscape_sidebar.dart';
import 'package:pulsr/l10n/app_localizations_delegates.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

class _MockPlayerCubit extends Mock implements PlayerCubit {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MockPlayerCubit playerCubit;

  setUp(() {
    debugClearNavDestinationsCache();
    playerCubit = _MockPlayerCubit();
    when(() => playerCubit.state).thenReturn(const PlayerState());
    when(() => playerCubit.stream)
        .thenAnswer((_) => const Stream<PlayerState>.empty());
  });

  tearDown(debugClearNavDestinationsCache);

  Widget wrapApp(Widget child, {Size size = const Size(390, 844)}) {
    return BlocProvider<PlayerCubit>.value(
      value: playerCubit,
      child: MaterialApp(
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData.dark().copyWith(extensions: [AuraTheme.defaultDark]),
        home: MediaQuery(
          data: MediaQueryData(size: size, disableAnimations: true),
          child: Scaffold(body: child),
        ),
      ),
    );
  }

  testWidgets('phone dock has 4 primary tabs without duplicate Settings',
      (tester) async {
    late List<PulsrDestination> phoneItems;
    late List<PulsrDestination> railItems;

    await tester.pumpWidget(
      wrapApp(
        Builder(
          builder: (context) {
            phoneItems = pulsrDestinations(context);
            railItems = pulsrRailDestinations(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(phoneItems.map((d) => d.index).toList(), [0, 1, 2, 3]);
    expect(
      phoneItems.map((d) => d.label).toList(),
      ['Home', 'Library', 'Search', 'Playlists'],
    );
    expect(
      phoneItems.any((d) => d.index == settingsDestinationIndex),
      isFalse,
    );

    expect(railItems.map((d) => d.index).toList(), [0, 1, 2, 3, 4]);
    expect(railItems.last.index, settingsDestinationIndex);
    expect(railItems.last.label, 'Settings');
  });

  testWidgets(
      'PulsrBottomNavBar renders 4 tabs with >= 48dp hit targets and preserves branch indices when on /settings',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final tapped = <int>[];
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      wrapApp(
        Align(
          alignment: Alignment.bottomCenter,
          child: PulsrBottomNavBar(
            // Simulate user currently visiting /settings (branch 4) via header/palette.
            currentIndex: settingsDestinationIndex,
            onTap: tapped.add,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Library'), findsOneWidget);
    expect(find.text('Search'), findsOneWidget);
    expect(find.text('Playlists'), findsOneWidget);
    expect(find.text('Settings'), findsNothing);

    // Every dock tab must meet the 48dp minimum touch target and expose button semantics.
    for (final label in ['Home', 'Library', 'Search', 'Playlists']) {
      final tabSemantics = tester.getSemantics(
        find.ancestor(
          of: find.text(label),
          matching: find.byWidgetPredicate(
            (w) => w is Semantics && w.properties.label == label,
          ),
        ).first,
      );
      expect(tabSemantics.flagsCollection.isButton, isTrue, reason: label);
      expect(tabSemantics.flagsCollection.isSelected, Tristate.isFalse,
          reason: label);

      final inkWell = find.ancestor(
        of: find.text(label),
        matching: find.byType(InkWell),
      );
      final size = tester.getSize(inkWell.first);
      expect(size.width, greaterThanOrEqualTo(48.0), reason: label);
      expect(size.height, greaterThanOrEqualTo(48.0), reason: label);
    }

    await tester.tap(find.text('Playlists'));
    await tester.pump();
    expect(tapped, [3]);

    semantics.dispose();
  });

  testWidgets(
      'LandscapeSidebar keeps Settings accessible at branch 4 with >= 48dp targets',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final selected = <int>[];
    await tester.pumpWidget(
      wrapApp(
        LandscapeSidebar(
          currentIndex: 0,
          onDestinationSelected: selected.add,
          isExtended: true,
          onToggleExtended: () {},
        ),
        size: const Size(1280, 900),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Library'), findsOneWidget);
    expect(find.text('Search'), findsOneWidget);
    expect(find.text('Playlists'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);

    final settingsInk = find.ancestor(
      of: find.text('Settings'),
      matching: find.byType(InkWell),
    );
    expect(tester.getSize(settingsInk.first).height, greaterThanOrEqualTo(48.0));

    await tester.tap(find.text('Settings'));
    await tester.pump();
    expect(selected, [settingsDestinationIndex]);
  });
}
