// test/features/player/widgets/conversion_quality_card_test.dart
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pulsr/core/constants/channels.dart';
import 'package:pulsr/core/constants/prefs_keys.dart';
import 'package:pulsr/features/player/presentation/widgets/equalizer_sheet.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'player_sheet_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final l10n = lookupAppLocalizations(const Locale('en'));
  const effectsChannel = MethodChannel(PulsrChannels.audioEffects);
  final androidVariant = TargetPlatformVariant.only(TargetPlatform.android);

  late List<int> invokedQualities;
  late bool refuseTapSrc;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    invokedQualities = <int>[];
    refuseTapSrc = false;

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(effectsChannel, (call) async {
      if (call.method == 'setTapSrcQuality') {
        final quality = (call.arguments as Map)['quality'] as int;
        invokedQualities.add(quality);
        if (refuseTapSrc) {
          throw PlatformException(
            code: 'REFUSED',
            message: 'tap SRC quality refused',
          );
        }
        return true;
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(effectsChannel, null);
  });

  Widget buildCard(ConversionQualityCard card) => sheetHost(
        playerCubit: stubPlayerCubit(),
        child: card,
      );

  SegmentedButton<int> readSegmentedButton(WidgetTester tester) =>
      tester.widget<SegmentedButton<int>>(find.byType(SegmentedButton<int>));

  testWidgets(
      'defaults to 256 taps (index 2), reconciles native, and disables when blocked or unavailable',
      variant: androidVariant,
      (tester) async {
    await tester.pumpWidget(
      buildCard(const ConversionQualityCard()),
    );
    await tester.pumpAndSettle();

    expect(readSegmentedButton(tester).selected, {2});
    expect(readSegmentedButton(tester).onSelectionChanged, isNotNull);
    expect(invokedQualities, [2]);
    expect(find.text(l10n.conversionTaps64), findsOneWidget);
    expect(find.text(l10n.conversionTaps128), findsOneWidget);
    expect(find.text(l10n.conversionTaps256), findsOneWidget);
    expect(find.text(l10n.conversionTaps512), findsOneWidget);

    await tester.pumpWidget(
      buildCard(const ConversionQualityCard(blockedReason: 'Bit-perfect active')),
    );
    await tester.pumpAndSettle();
    expect(readSegmentedButton(tester).onSelectionChanged, isNull);
    expect(find.text(l10n.blockedByBitPerfectShort), findsOneWidget);

    await tester.pumpWidget(
      buildCard(const ConversionQualityCard(nativeAvailable: false)),
    );
    await tester.pumpAndSettle();
    expect(readSegmentedButton(tester).onSelectionChanged, isNull);
    expect(find.text(l10n.nativeDspUnavailable), findsOneWidget);
  });

  testWidgets('selecting a kernel persists across rebuilds and restores on init',
      variant: androidVariant,
      (tester) async {
    await tester.pumpWidget(
      buildCard(const ConversionQualityCard()),
    );
    await tester.pumpAndSettle();

    expect(readSegmentedButton(tester).selected, {2});

    await tester.tap(find.text(l10n.conversionTaps512));
    await tester.pumpAndSettle();

    expect(readSegmentedButton(tester).selected, {3});
    expect(invokedQualities, [2, 3]);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt(PrefsKeys.tapSrcQuality), 3);

    // Re-mounting a fresh card restores index 3 and reconciles native on boot.
    invokedQualities.clear();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      buildCard(const ConversionQualityCard()),
    );
    await tester.pumpAndSettle();

    expect(readSegmentedButton(tester).selected, {3});
    expect(invokedQualities, [3]);
  });

  testWidgets(
      'native refusal reverts selection to previous value and does not persist',
      variant: androidVariant,
      (tester) async {
    SharedPreferences.setMockInitialValues({PrefsKeys.tapSrcQuality: 1});

    await tester.pumpWidget(
      buildCard(const ConversionQualityCard()),
    );
    await tester.pumpAndSettle();

    expect(readSegmentedButton(tester).selected, {1});
    expect(invokedQualities, [1]);

    // Refuse subsequent native tap-SRC quality updates.
    refuseTapSrc = true;
    await tester.tap(find.text(l10n.conversionTaps64));
    await tester.pumpAndSettle();

    // Must revert to 1 and keep 1 in SharedPreferences.
    expect(readSegmentedButton(tester).selected, {1});
    expect(invokedQualities, [1, 0]);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt(PrefsKeys.tapSrcQuality), 1);
  });
}
