// SongInfoSheet Android ringtone coverage: the "Set Audio As" chooser and the
// native setRingtone success / failure / permission-denied outcomes, plus the
// file-size row and the no-PlayerCubit fallback. Reachable on a host test by
// enabling the Android capability flag while dart:io Platform.isAndroid stays
// false (so the write-settings permission gate is bypassed — noted unreachable
// for direct coverage).
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/constants/channels.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/sheets/song_info_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../player/widgets/player_sheet_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(PulsrChannels.ringtone);
  dynamic lastSetArgs;
  int openSettingsCalls = 0;

  setUpAll(() {
    registerFallbackValue(testSong);
    registerFallbackValue(Duration.zero);
    registerFallbackValue(0);
    registerFallbackValue('');
    registerFallbackValue(0.0);
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    lastSetArgs = null;
    openSettingsCalls = 0;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'checkWriteSettingsPermission':
          return true;
        case 'setRingtone':
          lastSetArgs = call.arguments;
          return true;
        case 'openWriteSettings':
          openSettingsCalls++;
          return null;
      }
      return null;
    });
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  // The ringtone chooser renders bare ListTiles inside the frosted sheet
  // container, which trips a debug-only ink-splash assertion. It is a layout
  // warning, not behavioural, so it is filtered out. Installed inside the test
  // body because the binding resets FlutterError.onError per test.
  void ignoreInkSplashAssertion() {
    final originalOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details
          .exceptionAsString()
          .contains('ListTile background color or ink splashes')) {
        return;
      }
      originalOnError?.call(details);
    };
    addTearDown(() => FlutterError.onError = originalOnError);
  }

  MockPlayerCubit baseCubit({PlayerState? state}) {
    final cubit = stubPlayerCubit(state: state ?? const PlayerState());
    when(() => cubit.storedBookmarkFor(any())).thenReturn(null);
    when(() => cubit.setSongRating(any(), any())).thenAnswer((_) async {});
    when(() => cubit.setSongEqOverride(any(), any())).thenAnswer((_) async {});
    when(() => cubit.setSongVolumeOverride(any(), any()))
        .thenAnswer((_) async {});
    when(() => cubit.saveDspSnapshot()).thenAnswer((_) async {});
    return cubit;
  }

  Future<void> pumpSheet(WidgetTester tester, {PlayerCubit? cubit}) async {
    tester.view.physicalSize = const Size(1000, 3600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(sheetHost(
      playerCubit: cubit,
      settingsCubit: stubSettingsCubit(),
      child: const SongInfoSheet(song: testSong),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> openRingtoneChooser(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Ringtone'));
    await tester.tap(find.text('Ringtone'));
    await tester.pumpAndSettle();
    expect(find.text('Set Audio As'), findsOneWidget);
  }

  testWidgets('phone ringtone / notification / alarm set the right type',
      (tester) async {
    ignoreInkSplashAssertion();
    await pumpSheet(tester, cubit: baseCubit());
    // A file-size row exists for a track that reports its size.
    await tester.ensureVisible(find.text('File Size'));
    expect(find.text('File Size'), findsOneWidget);

    await openRingtoneChooser(tester);
    await tester.tap(find.text('Phone Ringtone'));
    await tester.pumpAndSettle();
    expect((lastSetArgs as Map)['type'], 'ringtone');
    expect((lastSetArgs as Map)['filePath'], testSong.path);
    expect(find.text('Ringtone set successfully'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));

    await openRingtoneChooser(tester);
    await tester.tap(find.text('Notification Sound'));
    await tester.pumpAndSettle();
    expect((lastSetArgs as Map)['type'], 'notification');
    await tester.pump(const Duration(seconds: 5));

    await openRingtoneChooser(tester);
    await tester.tap(find.text('Alarm Sound'));
    await tester.pumpAndSettle();
    expect((lastSetArgs as Map)['type'], 'alarm');
    await tester.pump(const Duration(seconds: 5));
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('setRingtone returning false shows no success snackbar',
      (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'setRingtone') return false;
      return null;
    });
    ignoreInkSplashAssertion();
    await pumpSheet(tester, cubit: baseCubit());
    await openRingtoneChooser(tester);
    await tester.tap(find.text('Phone Ringtone'));
    await tester.pumpAndSettle();
    expect(find.text('Ringtone set successfully'), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('permission-denied failure offers a Settings retry action',
      (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'setRingtone') {
        throw PlatformException(code: 'PERMISSION_DENIED');
      }
      if (call.method == 'openWriteSettings') openSettingsCalls++;
      return null;
    });
    ignoreInkSplashAssertion();
    await pumpSheet(tester, cubit: baseCubit());
    await openRingtoneChooser(tester);
    await tester.tap(find.text('Phone Ringtone'));
    await tester.pumpAndSettle();

    expect(find.text('Failed to set ringtone.'), findsOneWidget);
    await tester.tap(find.text('Settings'));
    await tester.pump();
    expect(openSettingsCalls, greaterThanOrEqualTo(1));
    await tester.pump(const Duration(seconds: 5));
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('a generic platform failure includes the error message',
      (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'setRingtone') {
        throw PlatformException(code: 'OTHER', message: 'boom');
      }
      return null;
    });
    ignoreInkSplashAssertion();
    await pumpSheet(tester, cubit: baseCubit());
    await openRingtoneChooser(tester);
    await tester.tap(find.text('Phone Ringtone'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Failed to set ringtone. boom'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('without a PlayerCubit the playback tools section is omitted',
      (tester) async {
    await pumpSheet(tester);
    expect(find.text('Playback Tools'), findsNothing);
    expect(find.text('Track Rating'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });
}
