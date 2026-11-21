// test/features/player/widgets/remaster_control_card_test.dart
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pulsr/core/constants/prefs_keys.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/features/player/presentation/widgets/equalizer_sheet.dart';
import 'package:pulsr/l10n/app_localizations_delegates.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final List<MethodCall> channelCalls = [];

  setUp(() {
    channelCalls.clear();
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.pulsr.music/audio_effects'),
      (MethodCall call) async {
        channelCalls.add(call);
        switch (call.method) {
          case 'setOversampleMultiplier':
          case 'setOversampleKernel':
          case 'setPcmToDsdEnabled':
          case 'setPcmToDsdRate':
          case 'setPcmToDsdOrder':
            return true;
          case 'getOversampleMultiplier':
            return 1;
          case 'getActiveOversampleMultiplier':
            return 2;
          case 'getOversampleKernel':
            return 0;
          case 'isPcmToDsdEnabled':
            return false;
          case 'getPcmToDsdRate':
            return 64;
          case 'getPcmToDsdOrder':
            return 5;
          default:
            return true;
        }
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.pulsr.music/audio_effects'),
      null,
    );
  });

  Widget buildCard({
    String? blockedReason,
    bool nativeAvailable = true,
  }) {
    return MaterialApp(
      localizationsDelegates: appLocalizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: AuraTheme.darkTheme,
      home: Scaffold(
        body: SingleChildScrollView(
          child: RemasterControlCard(
            blockedReason: blockedReason,
            nativeAvailable: nativeAvailable,
          ),
        ),
      ),
    );
  }

  testWidgets('RemasterControlCard renders default passthrough state',
      (tester) async {
    await tester.pumpWidget(buildCard());
    await tester.pumpAndSettle();

    expect(find.text('Remaster Suite'), findsOneWidget);
    expect(find.text('PCM Output Oversampling'), findsOneWidget);
    expect(find.text('Reconstruction Filter Kernel'), findsOneWidget);
    expect(find.text('PCM → DSD Modulator'), findsOneWidget);
    expect(find.text('Bit-Perfect compatible (passthrough)'), findsOneWidget);
  });

  testWidgets('Selecting oversampling updates state, bridge, and degrades bit-perfect',
      (tester) async {
    await tester.pumpWidget(buildCard());
    await tester.pumpAndSettle();

    // Tap 2x
    await tester.tap(find.text('2x'));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt(PrefsKeys.remasterOversampleMultiplier), 2);
    expect(
      find.text('Oversampling 2x requested · Not Bit-Perfect (reconstruction DSP in path)'),
      findsOneWidget,
    );
  });

  testWidgets('Selecting reconstruction filter kernel updates state and bridge',
      (tester) async {
    await tester.pumpWidget(buildCard());
    await tester.pumpAndSettle();

    // Tap Slow Roll-off
    await tester.tap(find.text('Slow Roll-off'));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt(PrefsKeys.remasterFilterKernel), 1);
  });

  testWidgets('Toggling PCM->DSD on reveals DSD controls and shows not bit-perfect',
      (tester) async {
    await tester.pumpWidget(buildCard());
    await tester.pumpAndSettle();

    // Find and toggle switch
    final switchFinder = find.byType(Switch);
    expect(switchFinder, findsOneWidget);
    await tester.tap(switchFinder);
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(PrefsKeys.remasterPcmToDsdEnabled), true);
    expect(find.text('DSD Rate'), findsOneWidget);
    expect(find.text('SDM Order (1-5)'), findsOneWidget);
    expect(
      find.text('PCM → DSD requested · offline engine only, not on the playback route'),
      findsOneWidget,
    );
  });

  testWidgets('Shows blocked by bit-perfect message when blockedReason is provided',
      (tester) async {
    await tester.pumpWidget(buildCard(blockedReason: 'Strict bit-perfect active'));
    await tester.pumpAndSettle();

    expect(find.text('Blocked by Bit-Perfect'), findsOneWidget);
  });

  testWidgets('Shows native DSP unavailable when nativeAvailable is false',
      (tester) async {
    await tester.pumpWidget(buildCard(nativeAvailable: false));
    await tester.pumpAndSettle();

    expect(find.text('Native DSP unavailable on this device'), findsOneWidget);
  });

  testWidgets(
      'RemasterControlCard does not call native setters when blockedReason != null',
      (tester) async {
    channelCalls.clear();
    await tester.pumpWidget(buildCard(blockedReason: 'Bit-perfect locked'));
    await tester.pumpAndSettle();

    final setterCalls = channelCalls.where((c) =>
        c.method.startsWith('setOversample') ||
        c.method.startsWith('setPcmToDsd'));
    expect(setterCalls, isEmpty);
  });
}
