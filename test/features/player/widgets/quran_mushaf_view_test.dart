// test/features/player/widgets/quran_mushaf_view_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/domain/models/quran_metadata.dart';
import 'package:pulsr/features/player/presentation/widgets/quran_mushaf_view.dart';

void main() {
  Widget testHost(Widget child) {
    return MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(
        body: SingleChildScrollView(
          child: child,
        ),
      ),
    );
  }

  const sampleMetadata = QuranMetadata(
    surahNumber: 1,
    surahName: 'Al-Fatihah',
    ayahStart: 1,
    ayahEnd: 7,
    reciter: 'Mishary Alafasy',
    ayahTimings: [
      QuranAyahTiming(
          ayahNumber: 1,
          start: Duration(seconds: 0),
          end: Duration(seconds: 4)),
      QuranAyahTiming(
          ayahNumber: 2,
          start: Duration(seconds: 4),
          end: Duration(seconds: 8)),
      QuranAyahTiming(
          ayahNumber: 3,
          start: Duration(seconds: 8),
          end: Duration(seconds: 12)),
    ],
  );

  group('QuranMushafView Widget Tests', () {
    testWidgets('renders Surah header, Basmalah, and verse list',
        (tester) async {
      await tester.pumpWidget(testHost(
        const QuranMushafView(
          metadata: sampleMetadata,
          currentPosition: Duration(seconds: 2),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('Al-Fatihah'), findsOneWidget);
      expect(find.text('بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ'), findsWidgets);
      expect(find.textContaining('الْحَمْدُ لِلَّهِ رَبِّ الْعَالَمِينَ'),
          findsOneWidget);
    });

    testWidgets('triggers tap-to-seek when an Ayah is tapped', (tester) async {
      Duration? seekTarget;
      await tester.pumpWidget(testHost(
        QuranMushafView(
          metadata: sampleMetadata,
          currentPosition: Duration.zero,
          onSeek: (pos) => seekTarget = pos,
        ),
      ));
      await tester.pumpAndSettle();

      // Tap on Ayah 2
      final ayah2Finder =
          find.textContaining('الْحَمْدُ لِلَّهِ رَبِّ الْعَالَمِينَ');
      expect(ayah2Finder, findsOneWidget);
      await tester.tap(ayah2Finder);
      await tester.pump();

      expect(seekTarget, const Duration(seconds: 4));
    });

    testWidgets('toggles Hifz blind recall mode', (tester) async {
      await tester.pumpWidget(testHost(
        const QuranMushafView(
          metadata: sampleMetadata,
          currentPosition: Duration(seconds: 1),
        ),
      ));
      await tester.pumpAndSettle();

      // Find Hifz blind mode toggle icon
      final hifzToggle = find.byTooltip('Hifz Blind Recall Mode');
      expect(hifzToggle, findsOneWidget);
      await tester.tap(hifzToggle);
      await tester.pumpAndSettle();

      // Now blind recall is on, icon changes to visibility_off
      expect(find.byTooltip('Show Text'), findsOneWidget);
    });
  });
}
