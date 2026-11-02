import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/services/ambient_sound_service.dart';
import 'package:pulsr/features/player/presentation/widgets/ambient_sound_panel.dart';
import 'package:pulsr/features/player/presentation/widgets/ambient_sound_sheet.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/fake_audio_player.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: SingleChildScrollView(
        child: child,
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AmbientSoundService.playerFactory = () => FakeAudioPlayer();
  });

  tearDown(() {
    AmbientSoundService.playerFactory = () => FakeAudioPlayer();
    // Turn off all effects between tests
    final service = AmbientSoundService();
    for (final e in List.of(service.activeEffects)) {
      service.toggleEffect(e);
    }
  });

  group('AmbientSoundPanel', () {
    testWidgets('renders title', (tester) async {
      await tester.pumpWidget(_wrap(const AmbientSoundPanel()));
      await tester.pumpAndSettle();

      expect(find.text('Ambient Sounds'), findsOneWidget);
    });

    testWidgets('shows EFFECTS chips with all 9 effect labels', (tester) async {
      await tester.pumpWidget(_wrap(const AmbientSoundPanel()));
      await tester.pumpAndSettle();

      expect(find.text('EFFECTS'), findsOneWidget);
      expect(find.byType(ChoiceChip), findsNWidgets(9));
      for (final effect in AmbientSoundEffect.values) {
        expect(find.text(effect.label), findsOneWidget,
            reason: '${effect.label} chip should be visible');
      }
    });

    testWidgets('tapping an effect chip toggles it on', (tester) async {
      await tester.pumpWidget(_wrap(const AmbientSoundPanel()));
      await tester.pumpAndSettle();

      final service = AmbientSoundService();
      expect(service.isEffectActive(AmbientSoundEffect.rain), isFalse);

      await tester.tap(find.text('Rain'));
      await tester.pumpAndSettle();

      expect(service.isEffectActive(AmbientSoundEffect.rain), isTrue);
    });

    testWidgets('multiple effects can be toggled on at once', (tester) async {
      await tester.pumpWidget(_wrap(const AmbientSoundPanel()));
      await tester.pumpAndSettle();

      final service = AmbientSoundService();

      await tester.tap(find.text('Rain'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Fire'));
      await tester.pumpAndSettle();

      expect(service.isEffectActive(AmbientSoundEffect.rain), isTrue);
      expect(service.isEffectActive(AmbientSoundEffect.fire), isTrue);
      expect(service.activeEffects.length, 2);
    });

    testWidgets('shows VOLUMES section only when effects are active',
        (tester) async {
      await tester.pumpWidget(_wrap(const AmbientSoundPanel()));
      await tester.pumpAndSettle();

      // Initially no VOLUMES section
      expect(find.text('VOLUMES'), findsNothing);

      // Enable an effect
      final service = AmbientSoundService();
      await service.toggleEffect(AmbientSoundEffect.rain);
      await tester.pumpAndSettle();

      expect(find.text('VOLUMES'), findsOneWidget);
      expect(find.byType(Slider), findsOneWidget);
    });

    testWidgets('shows paused badge when player is not playing', (tester) async {
      final service = AmbientSoundService();
      await service.toggleEffect(AmbientSoundEffect.rain);
      service.onPlayerPlaybackStateChanged(false);

      await tester.pumpWidget(_wrap(const AmbientSoundPanel()));
      await tester.pumpAndSettle();

      expect(find.text('Paused'), findsOneWidget);
      expect(find.text('Paused with player'), findsOneWidget);
    });

    testWidgets('shows "1 ON" badge when one effect is active', (tester) async {
      final service = AmbientSoundService();
      await service.toggleEffect(AmbientSoundEffect.ocean);

      await tester.pumpWidget(_wrap(const AmbientSoundPanel()));
      await tester.pumpAndSettle();

      expect(find.text('1 ON'), findsOneWidget);
    });
  });

  group('AmbientSoundSheet', () {
    testWidgets('renders within bottom sheet container', (tester) async {
      await tester.pumpWidget(_wrap(const AmbientSoundSheet()));
      await tester.pumpAndSettle();

      expect(find.text('Ambient Sounds'), findsAtLeastNWidgets(1));
      expect(find.byType(AmbientSoundPanel), findsOneWidget);
    });
  });
}
