// Phone + tablet layout matrix for the two densest surfaces.
//
// The existing responsive suites cover 320..1280 at the default text scale.
// This matrix adds the tablet sizes the app actually ships to
// (768x1024 / 1024x1366 / 1366x1024) and re-runs every size at 200% text —
// the configuration most likely to overflow a fixed-height row.
//
// The real Manrope font is loaded: with Flutter's default Ahem metrics every
// glyph is a square, which inflates text and produces overflows that never
// happen on a device.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/constants/channels.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/data/scanner/media_scanner_service.dart';
import 'package:pulsr/features/auth/cubit/auth_cubit.dart';
import 'package:pulsr/features/auth/cubit/auth_state.dart';
import 'package:pulsr/features/library/cubit/library_cubit.dart';
import 'package:pulsr/features/library/cubit/library_state.dart';
import 'package:pulsr/features/library/presentation/library_screen.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/settings/cubit/settings_cubit.dart';
import 'package:pulsr/features/settings/presentation/settings_screen.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../features/library/library_test_harness.dart' as lib;

class MockScanner extends Mock implements MediaScannerService {}

class MockAuthCubit extends Mock implements AuthCubit {}

const _sizes = <String, Size>{
  'phone-small 320x568': Size(320, 568),
  'phone 390x844': Size(390, 844),
  'tablet-portrait 768x1024': Size(768, 1024),
  'tablet-portrait-large 1024x1366': Size(1024, 1366),
  'tablet-landscape 1366x1024': Size(1366, 1024),
};

Widget _app(Widget child, Size size, double textScale) => MediaQuery(
      data: MediaQueryData(
        size: size,
        textScaler: TextScaler.linear(textScale),
        disableAnimations: true,
      ),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AuraTheme.darkTheme,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: child,
      ),
    );

void main() {
  setUpAll(() async {
    lib.registerLibraryFallbacks();
    await (FontLoader('Manrope')
          ..addFont(
              rootBundle.load('assets/fonts/Manrope-VariableFont_wght.ttf')))
        .load();
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
    for (final c in [
      PulsrChannels.hiresDac,
      PulsrChannels.audioEffects,
      PulsrChannels.hiresDacEvents,
    ]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannel(c), (call) async => null);
    }
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'settings_last_selected_category': 'all',
    });
    SettingsScreenController.resetSessionCategory();
  });

  for (final entry in _sizes.entries) {
    for (final scale in const [1.0, 2.0]) {
      testWidgets('settings fits ${entry.key} @ ${scale}x', (tester) async {
        tester.view.physicalSize = entry.value;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final auth = MockAuthCubit();
        when(() => auth.state).thenReturn(const AuthState());
        when(() => auth.stream).thenAnswer((_) => const Stream.empty());
        final settings = SettingsCubit(scannerService: MockScanner());

        await tester.pumpWidget(MultiBlocProvider(
          providers: [
            BlocProvider<SettingsCubit>.value(value: settings),
            BlocProvider<PlayerCubit>.value(value: lib.stubPlayerCubit()),
            BlocProvider<AuthCubit>.value(value: auth),
          ],
          child: _app(const SettingsScreen(), entry.value, scale),
        ));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        expect(tester.takeException(), isNull,
            reason: 'settings overflowed at ${entry.key} @ ${scale}x');
        await tester.pumpWidget(const SizedBox.shrink());
        await settings.close();
      });

      testWidgets('library fits ${entry.key} @ ${scale}x', (tester) async {
        tester.view.physicalSize = entry.value;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final songs = <SongsTableData>[
          for (var i = 0; i < 8; i++)
            lib.testSong(
              id: i + 1,
              title: 'Track number $i with a deliberately long title',
              artist: 'Artist $i',
              album: 'Album $i',
              isFavorite: i.isEven,
              path: '/music/album$i/track$i.flac',
            ),
        ];
        final cubit = lib.stubLibraryCubit(LibraryState(
          songs: songs,
          favorites: songs.where((s) => s.isFavorite).toList(),
        ));

        await tester.pumpWidget(MultiBlocProvider(
          providers: [
            BlocProvider<LibraryCubit>.value(value: cubit),
            BlocProvider<PlayerCubit>.value(value: lib.stubPlayerCubit()),
            BlocProvider<SettingsCubit>.value(value: lib.stubSettingsCubit()),
          ],
          child: _app(const LibraryScreen(), entry.value, scale),
        ));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        expect(tester.takeException(), isNull,
            reason: 'library overflowed at ${entry.key} @ ${scale}x');
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
}
