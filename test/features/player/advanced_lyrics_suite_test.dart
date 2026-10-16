import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/data/lyrics/lyrics_translation_service.dart';
import 'package:pulsr/domain/models/lyrics_line.dart';
import 'package:pulsr/features/player/presentation/widgets/lyrics/advanced_lyrics_view.dart';
import 'package:pulsr/features/player/presentation/widgets/lyrics_share_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('WordTimestamp and LyricsLine Domain Models', () {
    test('WordTimestamp progressAt interpolates correctly', () {
      const wt = WordTimestamp(word: 'Pulsr', startMs: 1000, endMs: 2000);
      expect(wt.progressAt(500), 0.0);
      expect(wt.progressAt(1000), 0.0);
      expect(wt.progressAt(1500), 0.5);
      expect(wt.progressAt(2000), 1.0);
      expect(wt.progressAt(2500), 1.0);
    });

    test('LyricsLine detects background vocal via isBackground or brackets',
        () {
      const normalLine = LyricsLine(
        timestamp: Duration(seconds: 1),
        text: 'Lead vocal line',
      );
      expect(normalLine.isBackgroundLine, isFalse);

      const flaggedLine = LyricsLine(
        timestamp: Duration(seconds: 1),
        text: 'Backing vocal',
        isBackground: true,
      );
      expect(flaggedLine.isBackgroundLine, isTrue);

      const bracketedLine = LyricsLine(
        timestamp: Duration(seconds: 1),
        text: '(ooh aah backing)',
      );
      expect(bracketedLine.isBackgroundLine, isTrue);

      const squareBracketLine = LyricsLine(
        timestamp: Duration(seconds: 1),
        text: '[echo vocal]',
      );
      expect(squareBracketLine.isBackgroundLine, isTrue);
    });

    test('LyricsLine supports duet alignment and romanization', () {
      const duetLine = LyricsLine(
        timestamp: Duration(seconds: 2),
        text: 'Second singer',
        alignment: LyricAlignment.end,
        romanization: 'Daini no kashu',
      );
      expect(duetLine.alignment, LyricAlignment.end);
      expect(duetLine.romanization, 'Daini no kashu');

      final copied = duetLine.copyWith(alignment: LyricAlignment.start);
      expect(copied.alignment, LyricAlignment.start);
      expect(copied.romanization, 'Daini no kashu');
    });
  });

  group('LyricsTranslationService', () {
    test('translates lyrics and caches results', () async {
      final mockClient = MockClient((request) async {
        if (request.url.toString().contains('translate_a/single')) {
          // Mock Google Translate response with delimiter preserved
          final responseJson = [
            [
              ['Hello world', 'Hola mundo'],
              ['\n\uE0000001\uE001\n', '\n\uE0000001\uE001\n'],
              ['Good night', 'Buenas noches'],
            ],
            null,
            'es',
          ];
          return http.Response.bytes(
            utf8.encode(jsonEncode(responseJson)),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        return http.Response('Not Found', 404);
      });

      final service = LyricsTranslationService(client: mockClient);
      final lines = [
        const LyricsLine(timestamp: Duration(seconds: 1), text: 'Hola mundo'),
        const LyricsLine(
            timestamp: Duration(seconds: 3), text: 'Buenas noches'),
      ];

      final result1 = await service.translateLyrics(
        lines: lines,
        targetLanguage: 'en',
        trackId: 'test_track_1',
      );

      expect(result1.fromCache, isFalse);
      expect(result1.lines.length, 2);
      expect(result1.lines[0].translation, isNotNull);

      // Second call should return from cache
      final result2 = await service.translateLyrics(
        lines: lines,
        targetLanguage: 'en',
        trackId: 'test_track_1',
      );
      expect(result2.fromCache, isTrue);
      expect(result2.lines[0].translation, result1.lines[0].translation);
    });

    test('romanizes non-Latin lyrics', () async {
      final mockClient = MockClient((request) async {
        if (request.url.toString().contains('translate_a/single')) {
          // Romanization response: segment[3] contains romanized text
          final responseJson = [
            [
              [null, null, null, 'Konnichiwa sekai'],
            ],
            null,
            'ja',
          ];
          return http.Response(jsonEncode(responseJson), 200);
        }
        return http.Response('Not Found', 404);
      });

      final service = LyricsTranslationService(client: mockClient);
      final lines = [
        const LyricsLine(timestamp: Duration(seconds: 1), text: 'こんにちは世界'),
      ];

      final result = await service.romanizeLyrics(
        lines: lines,
        trackId: 'test_ja_song',
      );

      expect(result.isRomanized, isTrue);
      expect(result.lines[0].romanization, 'Konnichiwa sekai');
    });
  });

  group('LyricsShareCardRenderer', () {
    test('renders 1080x1920 high resolution card to PNG bytes', () async {
      final lines = [
        const LyricsLine(
            timestamp: Duration(seconds: 10), text: 'Every breath you take'),
        const LyricsLine(
          timestamp: Duration(seconds: 14),
          text: '(Every move you make)',
          isBackground: true,
          translation: '(Cada movimiento que hagas)',
        ),
      ];

      final pngBytes = await LyricsShareCardRenderer.renderCard(
        song: null,
        selectedLines: lines,
        accentColor: Colors.deepPurpleAccent,
        showTranslation: true,
      );

      expect(pngBytes, isNotEmpty);
      // Valid PNG header check
      expect(pngBytes[0], 0x89);
      expect(pngBytes[1], 0x50); // P
      expect(pngBytes[2], 0x4E); // N
      expect(pngBytes[3], 0x47); // G
    });
  });

  group('AdvancedLyricsView Widget', () {
    testWidgets('renders word-level karaoke animations and background vocals',
        (tester) async {
      final lyrics = [
        const LyricsLine(
          timestamp: Duration(seconds: 1),
          text: 'Hello world',
          words: [
            WordTimestamp(word: 'Hello', startMs: 1000, endMs: 2000),
            WordTimestamp(word: 'world', startMs: 2000, endMs: 3000),
          ],
        ),
        const LyricsLine(
          timestamp: Duration(seconds: 4),
          text: '(Echo voice)',
          isBackground: true,
          alignment: LyricAlignment.end,
        ),
      ];

      Duration? tappedDuration;
      int? longPressedIndex;

      await tester.pumpWidget(
        MaterialApp(
          theme: AuraTheme.darkTheme,
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 600,
              child: AdvancedLyricsView(
                lyrics: lyrics,
                currentPosition: const Duration(milliseconds: 1500),
                activeColor: Colors.amber,
                onLineTapped: (d) => tappedDuration = d,
                onLineLongPressed: (i) => longPressedIndex = i,
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Words should be rendered
      expect(find.text('Hello'), findsOneWidget);
      expect(find.text('world'), findsOneWidget);
      expect(find.text('(Echo voice)'), findsOneWidget);

      // Tap on second line seeks to its timestamp
      await tester.tap(find.text('(Echo voice)'));
      await tester.pump();
      expect(tappedDuration, const Duration(seconds: 4));

      // Long press triggers share callback
      await tester.longPress(find.text('Hello'));
      await tester.pump();
      expect(longPressedIndex, 0);
    });
  });
}
