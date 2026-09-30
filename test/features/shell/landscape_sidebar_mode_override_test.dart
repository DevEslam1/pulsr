import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/shell/presentation/widgets/landscape_sidebar.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

class MockPlayerCubit extends Mock implements PlayerCubit {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockPlayerCubit mockPlayerCubit;

  setUp(() {
    mockPlayerCubit = MockPlayerCubit();
    when(() => mockPlayerCubit.state).thenReturn(const PlayerState());
    when(() => mockPlayerCubit.stream).thenAnswer((_) => const Stream.empty());
  });

  group('[M-14] LandscapeSidebar.resolveMode modeOverride', () {
    testWidgets('resolveMode strictly respects modeOverride = hidden even when isExtended and isPeeking are true', (tester) async {
      late BuildContext capturedContext;

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: MediaQuery(
            data: const MediaQueryData(size: Size(1200, 800)),
            child: Builder(
              builder: (context) {
                capturedContext = context;
                return const SizedBox();
              },
            ),
          ),
        ),
      );

      // Without override on large screen -> expanded
      final defaultMode = LandscapeSidebar.resolveMode(
        context: capturedContext,
        isExtended: true,
      );
      expect(defaultMode, equals(SidebarRailMode.expanded));

      // With modeOverride: hidden -> MUST return hidden even if isExtended = true and isPeeking = true
      final hiddenMode = LandscapeSidebar.resolveMode(
        context: capturedContext,
        modeOverride: SidebarRailMode.hidden,
        isExtended: true,
        isPeeking: true,
      );
      expect(hiddenMode, equals(SidebarRailMode.hidden));

      // With modeOverride: compact on large screen -> compact
      final compactMode = LandscapeSidebar.resolveMode(
        context: capturedContext,
        modeOverride: SidebarRailMode.compact,
        isExtended: true,
      );
      expect(compactMode, equals(SidebarRailMode.compact));
    });

    testWidgets('LandscapeSidebar renders SizedBox.shrink when modeOverride is hidden on large screen', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      Widget buildSidebar({SidebarRailMode? modeOverride}) {
        return BlocProvider<PlayerCubit>.value(
          value: mockPlayerCubit,
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: LandscapeSidebar(
                currentIndex: 0,
                onDestinationSelected: (_) {},
                isExtended: true,
                onToggleExtended: () {},
                modeOverride: modeOverride,
              ),
            ),
          ),
        );
      }

      // 1. With modeOverride: hidden, the sidebar should not render any destinations
      await tester.pumpWidget(buildSidebar(modeOverride: SidebarRailMode.hidden));
      await tester.pumpAndSettle();

      expect(find.byType(NavigationRailDestination), findsNothing);
      expect(find.text('PULSR'), findsNothing);

      // 2. With modeOverride: null, the large screen displays the expanded sidebar
      await tester.pumpWidget(buildSidebar(modeOverride: null));
      await tester.pumpAndSettle();

      expect(find.text('PULSR'), findsOneWidget);
    });
  });
}
