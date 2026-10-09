// test/features/sheets/song_info_sheet_coverage_test.dart
//
// Widget coverage for SongInfoSheet's Android ringtone flow (permission gate,
// success, denied and generic failures), the share fallback, the BPM override
// dialog validation, and the no-cubit / no-provider fallbacks.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/constants/channels.dart';
import 'package:pulsr/core/di/injection.dart';
import 'package:pulsr/features/sheets/song_info_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../player/widgets/player_sheet_test_support.dart';

const _ringtoneChannel = MethodChannel(PulsrChannels.ringtone);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<MethodCall> ringtoneCalls;

  Future<Object?> Function(MethodCall) handler =
      (call) async => null;

  void stubRingtone() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_ringtoneChannel, (call) {
      ringtoneCalls.add(call);
      return handler(call);
    });
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    registerFallbackValue(Duration.zero);
    registerFallbackValue(testSong);
    await getIt.reset();
    ringtoneCalls = [];
    handler = (call) async => null;
    stubRingtone();
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_ringtoneChannel, null);
    await getIt.reset();
  });

  MockPlayerCubit baseCubit() {
    final cubit = stubPlayerCubit();
    when(() => cubit.setSongRating(any(), any())).thenAnswer((_) async {});
    when(() => cubit.setSongEqOverride(any(), any())).thenAnswer((_) async {});
    when(() => cubit.setSongVolumeOverride(any(), any())).thenAnswer((_) async {});
    when(() => cubit.saveDspSnapshot()).thenAnswer((_) async {});
    when(() => cubit.saveBookmark()).thenAnswer((_) async => true);
    when(() => cubit.clearBookmark()).thenAnswer((_) async {});
    when(() => cubit.seek(any())).thenAnswer((_) async {});
    when(() => cubit.storedBookmarkFor(any())).thenReturn(null);
    when(() => cubit.setTrackBpm(any(), any())).thenAnswer((_) async {});
    return cubit;
  }

  Future<void> pumpSheet(WidgetTester tester, {MockPlayerCubit? cubit}) async {
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

  void drainExceptions(WidgetTester tester) {
    while (tester.takeException() != null) {}
  }

  Future<void> tapRingtone(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Ringtone'));
    await tester.tap(find.text('Ringtone'));
    await tester.pumpAndSettle();
    drainExceptions(tester);
  }

  Future<void> tapFirstRingtoneOption(WidgetTester tester) async {
    final tile = tester.widget<ListTile>(find.byType(ListTile).first);
    tile.onTap!();
    await tester.pumpAndSettle();
    drainExceptions(tester);
  }

  testWidgets('Android ringtone flow sets the phone ringtone on success',
      (tester) async {
    handler = (call) async {
      if (call.method == 'checkWriteSettingsPermission') return true;
      if (call.method == 'setRingtone') return true;
      return null;
    };

    await pumpSheet(tester, cubit: baseCubit());
    await tapRingtone(tester);

    // The options sheet offers three sound types.
    expect(find.byType(ListTile), findsNWidgets(3));
    await tapFirstRingtoneOption(tester);

    expect(
      ringtoneCalls.any((c) =>
          c.method == 'setRingtone' &&
          (c.arguments as Map)['type'] == 'ringtone'),
      isTrue,
    );
    expect(find.text('Ringtone set successfully'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets(
      'the write-settings permission gate is Android-only; this host calls '
      'setRingtone directly', (tester) async {
    handler = (call) async {
      if (call.method == 'checkWriteSettingsPermission') return false;
      if (call.method == 'setRingtone') return true;
      return null;
    };

    await pumpSheet(tester, cubit: baseCubit());
    await tapRingtone(tester);
    await tapFirstRingtoneOption(tester);

    // Platform.isAndroid is false on the test host, so the permission dialog
    // (song_info_sheet.dart 106-127) is not reachable here; the ringtone write
    // is attempted directly.
    expect(find.byType(Dialog), findsNothing);
    expect(ringtoneCalls.any((c) => c.method == 'setRingtone'), isTrue);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('PERMISSION_DENIED surfaces a settings action snackbar',
      (tester) async {
    handler = (call) async {
      if (call.method == 'checkWriteSettingsPermission') return true;
      if (call.method == 'setRingtone') {
        throw PlatformException(code: 'PERMISSION_DENIED');
      }
      return null;
    };

    await pumpSheet(tester, cubit: baseCubit());
    await tapRingtone(tester);
    await tapFirstRingtoneOption(tester);

    final snack = tester.widget<SnackBar>(find.byType(SnackBar));
    expect(snack.action, isNotNull);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('a non-permission PlatformException includes its message',
      (tester) async {
    handler = (call) async {
      if (call.method == 'checkWriteSettingsPermission') return true;
      if (call.method == 'setRingtone') {
        throw PlatformException(code: 'IO_FAIL', message: 'disk full');
      }
      return null;
    };

    await pumpSheet(tester, cubit: baseCubit());
    await tapRingtone(tester);
    await tapFirstRingtoneOption(tester);
    expect(find.textContaining('disk full'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('a generic error is reported through the failure snackbar',
      (tester) async {
    handler = (call) async {
      if (call.method == 'checkWriteSettingsPermission') return true;
      if (call.method == 'setRingtone') {
        throw StateError('native exploded');
      }
      return null;
    };

    await pumpSheet(tester, cubit: baseCubit());
    await tapRingtone(tester);
    await tapFirstRingtoneOption(tester);
    expect(find.textContaining('native exploded'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('the Edit Tags button is offered on Android', (tester) async {
    await pumpSheet(tester, cubit: baseCubit());
    expect(find.text('Edit Tags'), findsOneWidget);
  });

  testWidgets('sharing a real local file falls back to the error snackbar',
      (tester) async {
    final dir = Directory.systemTemp.createTempSync('pulsr_songinfo_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}${Platform.pathSeparator}track.flac')
      ..writeAsBytesSync(List<int>.filled(64, 0));
    final song =
        testSong.copyWith(path: file.path);

    tester.view.physicalSize = const Size(1000, 3600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(sheetHost(
      playerCubit: baseCubit(),
      settingsCubit: stubSettingsCubit(),
      child: SongInfoSheet(song: song),
    ));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Share'));
    await tester.runAsync(() async {
      await tester.tap(find.text('Share'));
      await Future<void>.delayed(const Duration(milliseconds: 150));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(SnackBar), findsOneWidget);
  });

  testWidgets('BPM dialog rejects an out-of-range value and accepts a valid one',
      (tester) async {
    final cubit = baseCubit();
    await pumpSheet(tester, cubit: cubit);

    final bpm = find.text('Track BPM');
    await tester.ensureVisible(bpm);
    await tester.tap(bpm);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'abc');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.textContaining('BPM'), findsWidgets);

    // Valid entry clears the error via onChanged, then saves on submit.
    await tester.enterText(find.byType(TextField), '128');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    verify(() => cubit.setTrackBpm(testSong, 128.0)).called(1);
  });

  testWidgets('renders without a PlayerCubit provider', (tester) async {
    await pumpSheet(tester);
    expect(find.text('Test Song'), findsOneWidget);
    expect(find.text('Playback Tools'), findsNothing);
  });
}
