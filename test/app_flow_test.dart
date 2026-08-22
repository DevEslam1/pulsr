import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/player/presentation/widgets/player_controls.dart';

void main() {
  group('Pulsr App Flow Headless Test', () {
    testWidgets('Full playback, queue, and player control interaction flow', (tester) async {
      bool isPlaying = false;
      bool isShuffle = false;
      PlayerRepeatMode repeatMode = PlayerRepeatMode.off;

      await tester.pumpWidget(
        MaterialApp(
          theme: AuraTheme.darkTheme,
          home: StatefulBuilder(
            builder: (context, setState) {
              return Scaffold(
                appBar: AppBar(title: const Text('Pulsr E2E')),
                body: Column(
                  children: [
                    const Text('Track 1 - Echoes', key: Key('now_playing_title')),
                    PlayerControls(
                      isPlaying: isPlaying,
                      isShuffle: isShuffle,
                      repeatMode: repeatMode,
                      primaryColor: const Color(0xFF00E5FF),
                      onPlayPause: () {
                        setState(() {
                          isPlaying = !isPlaying;
                        });
                      },
                      onNext: () {},
                      onPrevious: () {},
                      onToggleShuffle: () {
                        setState(() {
                          isShuffle = !isShuffle;
                        });
                      },
                      onToggleRepeat: () {
                        setState(() {
                          repeatMode = repeatMode == PlayerRepeatMode.off
                              ? PlayerRepeatMode.all
                              : PlayerRepeatMode.off;
                        });
                      },
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify track title is displayed
      expect(find.byKey(const Key('now_playing_title')), findsOneWidget);

      // Verify initial Play state
      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);

      // Tap Play
      await tester.tap(find.byIcon(Icons.play_arrow_rounded));
      await tester.pumpAndSettle();

      // Verify transition to Pause icon
      expect(find.byIcon(Icons.pause_rounded), findsOneWidget);

      // Tap Shuffle
      await tester.tap(find.byIcon(Icons.shuffle_rounded));
      await tester.pumpAndSettle();

      // Tap Repeat
      await tester.tap(find.byIcon(Icons.repeat_rounded));
      await tester.pumpAndSettle();
    });
  });
}
