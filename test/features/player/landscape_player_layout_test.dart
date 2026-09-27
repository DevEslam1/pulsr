// test/features/player/landscape_player_layout_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/responsive/pulsr_layout_metrics.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/player/presentation/responsive_player_layout.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

class MockPlayerCubit extends Mock implements PlayerCubit {}

void main() {
  late MockPlayerCubit mockPlayerCubit;

  setUp(() {
    mockPlayerCubit = MockPlayerCubit();
    when(() => mockPlayerCubit.state).thenReturn(const PlayerState());
    when(() => mockPlayerCubit.stream).thenAnswer((_) => const Stream.empty());
  });

  Widget buildSubject({
    required Size size,
    required Widget child,
  }) {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: MediaQuery(
        data: MediaQueryData(size: size),
        child: Scaffold(
          body: BlocProvider<PlayerCubit>.value(
            value: mockPlayerCubit,
            child: SizedBox(
              width: size.width,
              height: size.height,
              child: child,
            ),
          ),
        ),
      ),
    );
  }

  group('Landscape Player Layout Tests', () {
    testWidgets(
      'Phone in landscape (844x390) renders full-screen theme without tablet TabBar double-split',
      (tester) async {
        const phoneLandscape = Size(844, 390);

        await tester.pumpWidget(
          buildSubject(
            size: phoneLandscape,
            child: ResponsivePlayerLayout(
              state: const PlayerState(),
              cubit: mockPlayerCubit,
              themeWidget: const Center(
                key: ValueKey('test_theme_widget'),
                child: Text('Immersive Player Theme'),
              ),
              activeColor: Colors.deepPurple,
              bgColor: Colors.black,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Must display the theme widget directly
        expect(find.byKey(const ValueKey('test_theme_widget')), findsOneWidget);

        // Must NOT render the tablet TabBar (Queue/Lyrics/DSP) on a phone in landscape
        expect(find.byType(TabBar), findsNothing);
        expect(find.text('Queue'), findsNothing);
      },
    );

    testWidgets(
      'Tablet in landscape (1024x768) renders tablet 2-pane view with TabBar',
      (tester) async {
        const tabletLandscape = Size(1024, 768);

        await tester.pumpWidget(
          buildSubject(
            size: tabletLandscape,
            child: ResponsivePlayerLayout(
              state: const PlayerState(),
              cubit: mockPlayerCubit,
              themeWidget: const Center(
                key: ValueKey('test_theme_widget'),
                child: Text('Theme in Left Pane'),
              ),
              activeColor: Colors.deepPurple,
              bgColor: Colors.black,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Theme is present in left pane
        expect(find.byKey(const ValueKey('test_theme_widget')), findsOneWidget);

        // Tablet TabBar is present in right pane
        expect(find.byType(TabBar), findsOneWidget);
        expect(find.text('Queue'), findsOneWidget);
        expect(find.text('Lyrics'), findsOneWidget);
        expect(find.text('DSP'), findsOneWidget);
      },
    );

    testWidgets(
      'PulsrLayoutMetrics.isPlayerSplitMode enforces 620dp width floor',
      (tester) async {
        bool? splitNarrow;
        bool? splitWide;

        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: const MediaQueryData(
                size: Size(844, 390),
              ),
              child: Builder(
                builder: (context) {
                  splitNarrow = PulsrLayoutMetrics.isPlayerSplitMode(
                    context,
                    const BoxConstraints(maxWidth: 450, maxHeight: 390),
                  );
                  splitWide = PulsrLayoutMetrics.isPlayerSplitMode(
                    context,
                    const BoxConstraints(maxWidth: 844, maxHeight: 390),
                  );
                  return const SizedBox();
                },
              ),
            ),
          ),
        );

        // Narrow pane (< 620) must NOT split horizontally
        expect(splitNarrow, isFalse);

        // Wide pane (>= 620) in landscape MUST split horizontally
        expect(splitWide, isTrue);
      },
    );
  });
}
