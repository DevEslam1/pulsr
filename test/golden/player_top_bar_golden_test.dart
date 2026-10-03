// test/golden/player_top_bar_golden_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/player/presentation/themes/player_theme.dart';
import 'package:pulsr/features/player/presentation/themes/player_theme_chrome.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

class _MockPlayerCubit extends Fake implements PlayerCubit {}

void main() {
  testWidgets('PlayerTopBar golden', (tester) async {
    final props = PlayerThemeProps(
      state: const PlayerState(),
      cubit: _MockPlayerCubit(),
      activeColor: const Color(0xFF00E5FF),
      bgColor: const Color(0xFF0B0B0F),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AuraTheme.darkTheme,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: RepaintBoundary(
            child: SizedBox(
              width: 390,
              child: PlayerTopBar(props: props, isTablet: false),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(PlayerTopBar),
      matchesGoldenFile('goldens/player_top_bar.png'),
    );
  });
}
