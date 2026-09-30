// test/features/player/player_theme_scaffold_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/player/presentation/themes/player_theme.dart';
import 'package:pulsr/features/player/presentation/themes/player_theme_scaffold.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

class _MockPlayerCubit extends Fake implements PlayerCubit {}

void main() {
  group('PlayerThemeScaffold Tests', () {
    final mockCubit = _MockPlayerCubit();
    final dummyProps = PlayerThemeProps(
      state: const PlayerState(),
      cubit: mockCubit,
      activeColor: const Color(0xFF6750A4),
      bgColor: const Color(0xFF1C1B1F),
    );

    testWidgets('renders PlayerThemeScaffold with header and custom body', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: PlayerThemeScaffold(
              props: dummyProps,
              viewSwitcher: (context, metrics) => const SizedBox(key: ValueKey('test_switcher')),
              seekBar: (context, metrics) => const SizedBox(key: ValueKey('test_seek')),
              controls: (context, metrics) => const SizedBox(key: ValueKey('test_controls')),
              bottomDock: (context, metrics) => const SizedBox(key: ValueKey('test_dock')),
              body: (context, metrics) => const SizedBox(
                key: ValueKey('test_body'),
                child: Center(child: Text('Custom Visuals')),
              ),
            ),
          ),
        ),
      );

      expect(find.byType(PlayerThemeScaffold), findsOneWidget);
      expect(find.byType(PlayerHeaderBar), findsOneWidget);
      expect(find.byKey(const ValueKey('test_body')), findsOneWidget);
      expect(find.byKey(const ValueKey('test_switcher')), findsOneWidget);
      expect(find.byKey(const ValueKey('test_seek')), findsOneWidget);
      expect(find.byKey(const ValueKey('test_controls')), findsOneWidget);
      expect(find.byKey(const ValueKey('test_dock')), findsOneWidget);
    });

    testWidgets('calculates landscape metrics and layout when constraints are wide', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 720,
                height: 400,
                child: PlayerThemeScaffold(
                  props: dummyProps,
                  viewSwitcher: (context, metrics) => const SizedBox(),
                  seekBar: (context, metrics) => const SizedBox(),
                  controls: (context, metrics) => const SizedBox(),
                  bottomDock: (context, metrics) => const SizedBox(),
                  body: (context, metrics) {
                    expect(metrics.isLandscape, isTrue);
                    return const SizedBox.shrink();
                  },
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.byType(PlayerThemeScaffold), findsOneWidget);
    });

    testWidgets('clips center view with rounded corners (AppRadii.r24) in landscape mode', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 800,
                height: 400,
                child: PlayerThemeScaffold(
                  props: dummyProps,
                  viewSwitcher: (context, metrics) => const SizedBox(),
                  seekBar: (context, metrics) => const SizedBox(),
                  controls: (context, metrics) => const SizedBox(),
                  bottomDock: (context, metrics) => const SizedBox(),
                  body: (context, metrics) => const SizedBox.shrink(),
                ),
              ),
            ),
          ),
        ),
      );

      final clipRRectFinder = find.byType(ClipRRect);
      expect(clipRRectFinder, findsWidgets);

      bool foundRoundedClip = false;
      for (final element in clipRRectFinder.evaluate()) {
        final clip = element.widget as ClipRRect;
        if (clip.borderRadius == BorderRadius.circular(AppRadii.r24)) {
          foundRoundedClip = true;
          break;
        }
      }
      expect(foundRoundedClip, isTrue,
          reason: 'Landscape center view should be clipped with rounded corners of AppRadii.r24');
    });
  });
}
