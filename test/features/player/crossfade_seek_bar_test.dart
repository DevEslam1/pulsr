// test/features/player/crossfade_seek_bar_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/features/player/presentation/widgets/waveform_seek_bar.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

void main() {
  group('Crossfade Seek Bar Tests', () {
    testWidgets('WaveformSeekBar renders crossfade region without error',
        (tester) async {
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
                width: 360,
                height: 100,
                child: WaveformSeekBar(
                  position: const Duration(seconds: 45),
                  duration: const Duration(seconds: 120),
                  onSeek: (_) {},
                  samples: List.generate(100, (i) => (i % 10) / 10.0),
                  crossfadeDuration: const Duration(seconds: 10),
                  activeColor: Colors.deepOrange,
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.byType(WaveformSeekBar), findsOneWidget);
      expect(find.byType(CustomPaint), findsWidgets);
    });
  });
}
