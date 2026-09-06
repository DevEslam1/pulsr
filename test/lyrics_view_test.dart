// test/lyrics_view_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/domain/models/lyrics_line.dart';
import 'package:pulsr/features/player/presentation/widgets/lyrics_view.dart';

void main() {
  testWidgets('LyricsView renders empty state when lyrics list is empty',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: LyricsView(lyrics: []),
        ),
      ),
    );

    expect(find.byIcon(Icons.lyrics_outlined), findsOneWidget);
    expect(find.text('Search Lyrics'), findsOneWidget);
  });

  testWidgets('LyricsView renders CircularProgressIndicator when isLoading is true',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: LyricsView(
            lyrics: [],
            isLoading: true,
          ),
        ),
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('LyricsView renders plain-text lyrics when timestamps are zero',
      (tester) async {
    final plainLines = [
      LyricsLine(timestamp: Duration.zero, text: 'First plain line'),
      LyricsLine(timestamp: Duration.zero, text: 'Second plain line'),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            height: 400,
            child: LyricsView(
              lyrics: plainLines,
              currentPosition: Duration.zero,
            ),
          ),
        ),
      ),
    );

    expect(find.text('First plain line'), findsOneWidget);
    expect(find.text('Second plain line'), findsOneWidget);
  });

  testWidgets('LyricsView renders synced lyrics using flutter_lyric engine',
      (tester) async {
    final syncedLines = [
      LyricsLine(timestamp: const Duration(seconds: 2), text: 'Line one'),
      LyricsLine(timestamp: const Duration(seconds: 5), text: 'Line two'),
      LyricsLine(timestamp: const Duration(seconds: 10), text: 'Line three'),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 350,
            height: 500,
            child: LyricsView(
              lyrics: syncedLines,
              currentPosition: const Duration(seconds: 3),
              source: LyricsSource.lrclib,
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Source badge should be present
    expect(find.text('LRCLIB Synced'), findsOneWidget);
  });
}
