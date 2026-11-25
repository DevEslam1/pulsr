import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/player/presentation/widgets/player_controls.dart';
import 'package:pulsr/features/player/presentation/widgets/quran_mode_badge.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

import 'package:pulsr/l10n/app_localizations_delegates.dart';

Widget _harness(Widget child, {double textScale = 1.0}) {
  return MaterialApp(
    theme: ThemeData.dark().copyWith(extensions: [AuraTheme.defaultDark]),
    localizationsDelegates: appLocalizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: Center(
        child: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: child,
        ),
      ),
    ),
  );
}

PlayerControls _controls({
  bool showAbControls = false,
  double mainButtonSize = 46.0,
  double? sideButtonSize = 36.0,
}) {
  return PlayerControls(
    isPlaying: false,
    isShuffle: false,
    repeatMode: PlayerRepeatMode.off,
    onPlayPause: () {},
    onNext: () {},
    onPrevious: () {},
    onToggleShuffle: () {},
    onToggleRepeat: () {},
    primaryColor: Colors.tealAccent,
    mainButtonSize: mainButtonSize,
    sideButtonSize: sideButtonSize,
    showAbControls: showAbControls,
    abPointA: showAbControls ? Duration.zero : null,
    onSetAbPointA: () {},
    onSetAbPointB: () {},
    onToggleAbLoop: () {},
    onClearAbLoop: () {},
  );
}

Size _tapTargetSize(WidgetTester tester, Finder icon) {
  final inks = find.ancestor(of: icon, matching: find.byType(InkWell));
  if (inks.evaluate().isNotEmpty) return tester.getSize(inks.first);
  final gestures =
      find.ancestor(of: icon, matching: find.byType(GestureDetector));
  return tester.getSize(gestures.first);
}

void main() {
  testWidgets('transport controls keep 48dp hit targets at 360dp',
      (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // Deliberately sub-48 inputs: the widget must expand the hit areas.
    await tester.pumpWidget(_harness(_controls()));
    await tester.pumpAndSettle();

    const icons = <IconData>[
      Icons.shuffle_rounded,
      Icons.skip_previous_rounded,
      Icons.play_arrow_rounded,
      Icons.skip_next_rounded,
      Icons.repeat_rounded,
    ];
    for (final icon in icons) {
      final finder = find.byIcon(icon);
      expect(finder, findsOneWidget, reason: 'missing $icon');
      final size = _tapTargetSize(tester, finder);
      expect(size.width, greaterThanOrEqualTo(48.0),
          reason: '$icon hit width ${size.width}');
      expect(size.height, greaterThanOrEqualTo(48.0),
          reason: '$icon hit height ${size.height}');
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('AB loop controls meet 48dp targets without overflow',
      (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_harness(_controls(showAbControls: true)));
    await tester.pumpAndSettle();

    for (final label in const ['A', 'B']) {
      final text = find.text(label);
      expect(text, findsOneWidget);
      final ink = find.ancestor(of: text, matching: find.byType(InkWell));
      expect(ink, findsWidgets);
      final size = tester.getSize(ink.first);
      expect(size.width, greaterThanOrEqualTo(48.0),
          reason: '$label hit width ${size.width}');
      expect(size.height, greaterThanOrEqualTo(48.0),
          reason: '$label hit height ${size.height}');
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('Quran badge exposes button semantics and a 48dp target',
      (tester) async {
    final handle = tester.ensureSemantics();
    var tapped = false;

    await tester
        .pumpWidget(_harness(QuranModeBadge(onTap: () => tapped = true)));
    await tester.pumpAndSettle();

    final badge = find.byType(QuranModeBadge);
    final ink = find.descendant(of: badge, matching: find.byType(InkWell));
    expect(ink, findsOneWidget);
    final size = tester.getSize(ink);
    expect(size.width, greaterThanOrEqualTo(48.0));
    expect(size.height, greaterThanOrEqualTo(48.0));

    final node = tester.getSemantics(badge);
    final l10n = lookupAppLocalizations(const Locale('en'));
    expect(node.label, contains(l10n.quranMode));
    expect(node.flagsCollection.isButton, isTrue);

    await tester.tap(ink);
    expect(tapped, isTrue);
    handle.dispose();
  });

  testWidgets('controls and badge survive 2.0x text scaling without overflow',
      (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _harness(
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            QuranModeBadge(onTap: () {}),
            _controls(
                showAbControls: true, mainButtonSize: 64, sideButtonSize: null),
          ],
        ),
        textScale: 2.0,
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
