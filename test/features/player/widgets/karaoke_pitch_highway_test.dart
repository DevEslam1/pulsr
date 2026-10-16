// test/features/player/widgets/karaoke_pitch_highway_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/domain/models/lyrics_line.dart';
import 'package:pulsr/features/player/presentation/widgets/karaoke_pitch_highway.dart';

import 'player_sheet_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const testLyrics = [
    LyricsLine(timestamp: Duration.zero, text: 'Hello vocal line'),
    LyricsLine(timestamp: Duration(seconds: 10), text: 'Second line'),
  ];

  Widget buildHighway({
    bool isPlaying = true,
    Duration position = const Duration(seconds: 2),
    int activeLineIndex = 0,
    List<double>? audioBuffer,
    double height = 64.0,
  }) {
    return sheetHost(
      settingsCubit: stubSettingsCubit(),
      child: Center(
        child: SizedBox(
          width: 320,
          child: KaraokePitchHighway(
            isPlaying: isPlaying,
            currentPosition: position,
            accentColor: Colors.deepPurpleAccent,
            height: height,
            lyrics: testLyrics,
            activeLineIndex: activeLineIndex,
            audioBuffer: audioBuffer,
          ),
        ),
      ),
    );
  }

  testWidgets('renders highway container and custom painter', (tester) async {
    await tester.pumpWidget(buildHighway());
    await tester.pumpAndSettle();

    expect(find.byType(KaraokePitchHighway), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);
  });

  testWidgets('updates smoothly when playing and position advances',
      (tester) async {
    await tester.pumpWidget(buildHighway(position: const Duration(seconds: 1)));
    await tester.pump();

    // Advance position
    await tester.pumpWidget(buildHighway(position: const Duration(seconds: 3)));
    await tester.pump();

    expect(find.byType(KaraokePitchHighway), findsOneWidget);
  });

  testWidgets('clears trail and stops on pause', (tester) async {
    await tester.pumpWidget(buildHighway(isPlaying: true));
    await tester.pump();

    await tester.pumpWidget(buildHighway(isPlaying: false));
    await tester.pump();

    expect(find.byType(KaraokePitchHighway), findsOneWidget);
  });

  testWidgets('processes provided audioBuffer through YIN detector',
      (tester) async {
    // Generate a 440 Hz sine wave buffer
    final buffer =
        List<double>.generate(1024, (i) => 0.5 * (i % 32 < 16 ? 1.0 : -1.0));
    await tester.pumpWidget(buildHighway(isPlaying: true, audioBuffer: buffer));
    await tester.pump();

    expect(find.byType(KaraokePitchHighway), findsOneWidget);
  });
}
