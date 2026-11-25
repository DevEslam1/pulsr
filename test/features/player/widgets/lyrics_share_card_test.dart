import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/domain/models/lyrics_line.dart';
import 'package:pulsr/features/player/presentation/widgets/lyrics_share_card.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

import 'package:pulsr/l10n/app_localizations_delegates.dart';

void main() {
  Widget host(Widget child) {
    return MaterialApp(
      theme: AuraTheme.darkTheme,
      localizationsDelegates: appLocalizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    );
  }

  group('LyricsShareSheet P2-12', () {
    testWidgets('mounts empty state gracefully when lyrics list is empty',
        (tester) async {
      await tester.pumpWidget(
        host(
          const LyricsShareSheet(
            lyrics: <LyricsLine>[],
            song: null,
            activeColor: Colors.tealAccent,
            initialLineIndex: 0,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No lyrics found for this track'), findsOneWidget);
      expect(find.byType(CheckboxListTile), findsNothing);
    });

    testWidgets('renderCard disposes native ui.Picture and ui.Image handles',
        (tester) async {
      ui.Picture? capturedPicture;
      ui.Image? capturedImage;

      final bytes = await tester.runAsync(
        () => LyricsShareCardRenderer.renderCard(
          song: null,
          selectedLines: const [
            LyricsLine(timestamp: Duration(seconds: 5), text: 'Hello world'),
          ],
          accentColor: Colors.tealAccent,
          debugOnDisposed: (picture, image) {
            capturedPicture = picture;
            capturedImage = image;
          },
        ),
      );

      expect(bytes, isNotNull);
      expect(bytes!.take(4).toList(), [0x89, 0x50, 0x4E, 0x47]); // PNG magic
      expect(capturedPicture, isNotNull);
      expect(capturedImage, isNotNull);
      expect(capturedPicture!.debugDisposed, isTrue);
      expect(capturedImage!.debugDisposed, isTrue);
    });
  });
}
