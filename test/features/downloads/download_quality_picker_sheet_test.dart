// test/features/downloads/download_quality_picker_sheet_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/domain/models/ytm_audio_quality.dart';
import 'package:pulsr/features/downloads/presentation/widgets/download_quality_picker_sheet.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

import '../../helpers/test_song_factory.dart';

void main() {
  group('DownloadQualityPickerSheet Tests', () {
    final testSong = createTestSong(
      id: 999,
      title: 'Comfortably Numb',
      artist: 'Pink Floyd',
      durationMs: 382000,
    );

    test('estimateBytes computes correct byte estimates for bitrates', () {
      // 382 seconds * 256 kbps * 1000 / 8 = 12,224,000 bytes (~11.6 MB)
      final highBytes = DownloadQualityPickerSheet.estimateBytes(382000, 256);
      expect(highBytes, equals(12224000));

      final lowBytes = DownloadQualityPickerSheet.estimateBytes(382000, 64);
      expect(lowBytes, equals(3056000));

      expect(DownloadQualityPickerSheet.estimateBytes(0, 256), equals(0));
      expect(DownloadQualityPickerSheet.estimateBytes(382000, 0), equals(0));
    });

    testWidgets('renders all quality options and confirms selection',
        (tester) async {
      YtmAudioQuality? confirmedQuality;

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: DownloadQualityPickerSheet(
              song: testSong,
              initialQuality: YtmAudioQuality.high,
              onConfirm: (q) {
                confirmedQuality = q;
              },
            ),
          ),
        ),
      );

      expect(find.byType(DownloadQualityPickerSheet), findsOneWidget);
      expect(find.text('256 kbps'), findsOneWidget);
      expect(find.text('128 kbps'), findsOneWidget);
      expect(find.text('64 kbps'), findsOneWidget);
      expect(find.textContaining('Comfortably Numb'), findsOneWidget);

      // Select Medium (128 kbps)
      final mediumOption = find.text('128 kbps');
      await tester.tap(mediumOption);
      await tester.pumpAndSettle();

      // Tap Download
      final downloadBtn = find.byType(FilledButton);
      expect(downloadBtn, findsOneWidget);
      await tester.tap(downloadBtn);
      await tester.pump();

      expect(confirmedQuality, equals(YtmAudioQuality.medium));
    });

    testWidgets('renders properly under RTL directionality', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: DownloadQualityPickerSheet(
                song: testSong,
                onConfirm: (_) {},
              ),
            ),
          ),
        ),
      );

      expect(find.byType(DownloadQualityPickerSheet), findsOneWidget);
    });
  });
}
