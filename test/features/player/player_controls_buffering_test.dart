// Full-player transport controls swap the main button for a buffering spinner.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/player/presentation/widgets/player_controls.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

Widget host({
  required bool isPlaying,
  required bool isBuffering,
  VoidCallback? onPlayPause,
}) {
  return MaterialApp(
    theme: AuraTheme.darkTheme,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: PlayerControls(
        isPlaying: isPlaying,
        isBuffering: isBuffering,
        isShuffle: false,
        repeatMode: PlayerRepeatMode.off,
        primaryColor: Colors.deepPurple,
        onPlayPause: onPlayPause ?? () {},
        onNext: () {},
        onPrevious: () {},
        onToggleShuffle: () {},
        onToggleRepeat: () {},
      ),
    ),
  );
}

void main() {
  testWidgets('buffering renders a spinner instead of the play/pause icon',
      (tester) async {
    await tester.pumpWidget(host(isPlaying: true, isBuffering: true));
    await tester.pump(const Duration(milliseconds: 20));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byIcon(Icons.pause_rounded), findsNothing);
    expect(find.byIcon(Icons.play_arrow_rounded), findsNothing);
  });

  testWidgets('a settled player keeps the pause icon', (tester) async {
    await tester.pumpWidget(host(isPlaying: true, isBuffering: false));
    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
  });

  testWidgets('the spinner still toggles playback when tapped', (tester) async {
    var toggled = 0;
    await tester.pumpWidget(host(
      isPlaying: true,
      isBuffering: true,
      onPlayPause: () => toggled++,
    ));
    await tester.pump(const Duration(milliseconds: 20));

    await tester.tap(
      find
          .ancestor(
            of: find.byType(CircularProgressIndicator),
            matching: find.byType(GestureDetector),
          )
          .first,
    );
    await tester.pump(const Duration(milliseconds: 20));

    expect(toggled, 1);
  });
}
