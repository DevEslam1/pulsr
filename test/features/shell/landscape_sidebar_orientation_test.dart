import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/shell/presentation/widgets/landscape_sidebar.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

import 'package:pulsr/l10n/app_localizations_delegates.dart';
class MockPlayerCubit extends Mock implements PlayerCubit {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockPlayerCubit mockPlayerCubit;

  setUp(() {
    mockPlayerCubit = MockPlayerCubit();
    when(() => mockPlayerCubit.state).thenReturn(const PlayerState());
    when(() => mockPlayerCubit.stream).thenAnswer((_) => const Stream.empty());
  });

  Widget buildWidget({required Size screenSize, bool isExtended = false}) {
    return BlocProvider<PlayerCubit>.value(
      value: mockPlayerCubit,
      child: MaterialApp(
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MediaQuery(
          data: MediaQueryData(
            size: screenSize,
          ),
          child: Scaffold(
            body: LandscapeSidebar(
              currentIndex: 0,
              onDestinationSelected: (_) {},
              isExtended: isExtended,
              onToggleExtended: () {},
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('H-07: peeking state resets when orientation changes',
      (tester) async {
    // 1. Start in landscape mode
    await tester.binding.setSurfaceSize(const Size(1000, 600));
    await tester.pumpWidget(buildWidget(screenSize: const Size(1000, 600)));
    await tester.pumpAndSettle();

    final state =
        tester.state<LandscapeSidebarState>(find.byType(LandscapeSidebar));
    expect(state.isPeeking, isFalse);

    // 2. Trigger peek
    state.triggerPeek();
    await tester.pump();
    expect(state.isPeeking, isTrue);

    // 3. Rotate to portrait mode
    await tester.binding.setSurfaceSize(const Size(600, 1000));
    await tester.pumpWidget(buildWidget(screenSize: const Size(600, 1000)));
    await tester.pump();

    // 4. Peeking must be cancelled immediately upon orientation change
    expect(state.isPeeking, isFalse);

    // Cleanup surface size
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('H-50 uses right display cutout inset as start padding in RTL',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      BlocProvider<PlayerCubit>.value(
        value: mockPlayerCubit,
        child: MaterialApp(
          locale: const Locale('ar'),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(1200, 700),
              padding: EdgeInsets.only(left: 6, right: 44),
            ),
            child: Scaffold(
              body: LandscapeSidebar(
                currentIndex: 0,
                onDestinationSelected: (_) {},
                isExtended: false,
                onToggleExtended: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Desktop expanded rail width (240) + RTL start cutout inset (44) = 284.
    expect(tester.getSize(find.byType(LandscapeSidebar)).width, closeTo(284.0, 0.5));
  });
}
