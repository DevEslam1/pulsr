// test/features/player/widgets/quran_mushaf_view_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/quran/quran_uthmani_text.dart';
import 'package:pulsr/domain/models/quran_metadata.dart';
import 'package:pulsr/features/player/presentation/widgets/quran_mushaf_view.dart';

void main() {
  Widget testHost(Widget child, {double textScale = 1}) {
    return MaterialApp(
      theme: ThemeData.dark(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
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
    testWidgets('fits a narrow phone with large text', (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(testHost(
          const QuranMushafView(
            metadata: sampleMetadata,
            currentPosition: Duration.zero,
          ),
          textScale: 2));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('scrolls accurately to a late verse in a long surah',
        (tester) async {
      await tester.pumpWidget(testHost(const QuranMushafView(
        metadata: QuranMetadata(
            surahNumber: 2,
            surahName: 'Al-Baqarah',
            ayahStart: 1,
            ayahEnd: 286,
            reciter: 'Reciter',
            ayahTimings: [
              QuranAyahTiming(
                  ayahNumber: 200,
                  start: Duration.zero,
                  end: Duration(seconds: 10)),
            ]),
        currentPosition: Duration(seconds: 5),
      )));
      await tester.pumpAndSettle();
      final verse = find.textContaining(quranUthmaniText[2]![199]);
      final rect = tester.getRect(verse);
      final viewport = tester.getRect(find.byType(SingleChildScrollView).last);
      expect(rect.top, greaterThanOrEqualTo(viewport.top));
      expect(rect.top, lessThan(viewport.bottom));
    });

    testWidgets('blind recall hides translation and scripture from semantics',
        (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(testHost(const QuranMushafView(
        metadata: sampleMetadata,
        currentPosition: Duration.zero,
      )));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Hifz Blind Recall Mode'));
      await tester.pumpAndSettle();
      expect(
          find.text(
              'In the name of Allah, the Entirely Merciful, the Especially Merciful.'),
          findsNothing);
      expect(
          find.bySemanticsLabel(
              RegExp(RegExp.escape(quranUthmaniText[1]!.first))),
          findsNothing);
      semantics.dispose();
    });

    testWidgets('keeps preceding ayah active inside a timing gap',
        (tester) async {
      await tester.pumpWidget(testHost(QuranMushafView(
        metadata: sampleMetadata.copyWith(ayahTimings: const [
          QuranAyahTiming(
              ayahNumber: 1, start: Duration.zero, end: Duration(seconds: 4)),
          QuranAyahTiming(
              ayahNumber: 2,
              start: Duration(seconds: 4),
              end: Duration(seconds: 8)),
          QuranAyahTiming(
              ayahNumber: 3,
              start: Duration(seconds: 10),
              end: Duration(seconds: 14)),
        ]),
        currentPosition: const Duration(seconds: 9),
      )));
      await tester.pumpAndSettle();
      expect(find.text('Ayah 2 / 7'), findsOneWidget);
    });

    testWidgets('does not invent playback synchronization without timings',
        (tester) async {
      await tester.pumpWidget(testHost(QuranMushafView(
        metadata: sampleMetadata.copyWith(ayahStart: 3, ayahTimings: []),
        currentPosition: Duration.zero,
      )));
      await tester.pumpAndSettle();
      expect(find.text('Ayah 1 / 7'), findsNothing);
    });

    testWidgets('does not repeat the basmalah above Al-Fatihah',
        (tester) async {
      await tester.pumpWidget(testHost(const QuranMushafView(
        metadata: sampleMetadata,
        currentPosition: Duration.zero,
      )));
      await tester.pumpAndSettle();
      expect(find.text(quranUthmaniText[1]!.first), findsNothing);
      expect(find.textContaining(quranUthmaniText[1]!.first), findsOneWidget);
    });

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
      expect(find.textContaining(quranUthmaniText[1]!.first), findsWidgets);
      expect(find.textContaining(quranUthmaniText[1]![1]), findsOneWidget);
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
      final ayah2Finder = find.textContaining(quranUthmaniText[1]![1]);
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
