import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/constants/prefs_keys.dart';
import 'package:pulsr/core/services/settings_cache.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/core/widgets/pulsr_dialog.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/player/presentation/responsive_player_layout.dart';
import 'package:pulsr/features/player/presentation/themes/classic_player_theme.dart';
import 'package:pulsr/features/player/presentation/themes/player_theme.dart';
import 'package:pulsr/features/settings/cubit/settings_cubit.dart';
import 'package:pulsr/features/settings/cubit/settings_state.dart';
import 'package:pulsr/features/shell/presentation/widgets/tablet_side_inspector.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/screen_harness.dart';
import '../helpers/test_song_factory.dart';

class _MockSettings extends Mock implements SettingsCubit {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MockSettings settings;
  late PlayerCubit player;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SettingsCache().init();
    settings = _MockSettings();
    when(() => settings.state).thenReturn(const SettingsState());
    when(() => settings.stream)
        .thenAnswer((_) => const Stream<SettingsState>.empty());

    player = stubPlayerCubit(
      PlayerState(
        playback: PlaybackSlice(
          currentSong: createTestSong(
            id: 7,
            title: 'A Very Long Track Title That Wraps Or Ellipsizes Cleanly',
            artist: 'An Equally Long Artist Name For Matrix Testing',
          ),
          isPlaying: true,
          position: const Duration(seconds: 42),
          duration: const Duration(minutes: 3, seconds: 30),
        ),
        queueSlice: QueueSlice(
          queue: [createTestSong(id: 7), createTestSong(id: 8)],
          currentIndex: 0,
        ),
      ),
    );
  });

  Widget buildPlayerHarness({
    required Size size,
    required double textScale,
    Locale locale = const Locale('en'),
    List<DisplayFeature> displayFeatures = const [],
    Widget? body,
  }) {
    final activeColor = AuraTheme.darkTheme.colorScheme.primary;
    final bgColor = AuraTheme.darkTheme.scaffoldBackgroundColor;
    final props = PlayerThemeProps(
      state: player.state,
      cubit: player,
      activeColor: activeColor,
      bgColor: bgColor,
    );

    return MediaQuery(
      data: MediaQueryData(
        size: size,
        textScaler: TextScaler.linear(textScale),
        disableAnimations: true,
        displayFeatures: displayFeatures,
      ),
      child: MaterialApp(
        locale: locale,
        theme: AuraTheme.darkTheme,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: MultiBlocProvider(
          providers: <BlocProvider>[
            BlocProvider<PlayerCubit>.value(value: player),
            BlocProvider<SettingsCubit>.value(value: settings),
          ],
          child: Scaffold(
            body: body ??
                ResponsivePlayerLayout(
                  state: player.state,
                  cubit: player,
                  themeWidget: ClassicPlayerTheme(props: props),
                  activeColor: activeColor,
                  bgColor: bgColor,
                ),
          ),
        ),
      ),
    );
  }

  final matrix = <({String name, Size size, Locale locale})>[
    (name: '360x800 phone', size: const Size(360, 800), locale: const Locale('en')),
    (name: '390x844 phone', size: const Size(390, 844), locale: const Locale('en')),
    (name: '390x844 phone ar RTL', size: const Size(390, 844), locale: const Locale('ar')),
    (name: '600x960 small tablet portrait', size: const Size(600, 960), locale: const Locale('en')),
    (name: '840x1280 tablet portrait', size: const Size(840, 1280), locale: const Locale('en')),
    (name: '1280x800 tablet landscape', size: const Size(1280, 800), locale: const Locale('en')),
    (name: '1280x800 tablet landscape ar RTL', size: const Size(1280, 800), locale: const Locale('ar')),
  ];

  for (final entry in matrix) {
    for (final scale in const [1.0, 1.3, 2.0]) {
      testWidgets('${entry.name} @ ${scale}x text scale renders without overflow',
          (tester) async {
        tester.view.physicalSize = entry.size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final errors = <FlutterErrorDetails>[];
        final prevOnError = FlutterError.onError;
        FlutterError.onError = (details) => errors.add(details);
        addTearDown(() => FlutterError.onError = prevOnError);

        await tester.pumpWidget(
          buildPlayerHarness(
            size: entry.size,
            textScale: scale,
            locale: entry.locale,
          ),
        );
        await tester.pumpAndSettle();

        final overflowErrors = errors
            .where((e) => e.toString().contains('RenderFlex overflowed'))
            .toList();
        expect(overflowErrors, isEmpty,
            reason: 'Overflow on ${entry.name} @ ${scale}x: $overflowErrors');
      });
    }
  }

  testWidgets('Foldable horizontal hinge tabletop renders without overflow',
      (tester) async {
    const size = Size(800, 800);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final errors = <FlutterErrorDetails>[];
    final prevOnError = FlutterError.onError;
    FlutterError.onError = (details) => errors.add(details);
    addTearDown(() => FlutterError.onError = prevOnError);

    await tester.pumpWidget(
      buildPlayerHarness(
        size: size,
        textScale: 1.0,
        displayFeatures: const [
          DisplayFeature(
            bounds: Rect.fromLTWH(0, 390, 800, 20),
            type: DisplayFeatureType.hinge,
            state: DisplayFeatureState.postureHalfOpened,
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    final overflowErrors = errors
        .where((e) => e.toString().contains('RenderFlex overflowed'))
        .toList();
    expect(overflowErrors, isEmpty);
  });

  testWidgets('TabletSideInspector drag handle is 48dp hit & double-tap resets persisted width',
      (tester) async {
    const size = Size(1280, 800);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final key = PrefsKeys.tabletInspectorWidthKey('desktop');
    await SettingsCache().setDouble(key, 420.0);

    await tester.pumpWidget(
      buildPlayerHarness(
        size: size,
        textScale: 1.0,
        body: Row(
          children: [
            const Expanded(child: SizedBox()),
            TabletSideInspector(onClose: () {}),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    final state = tester.state<TabletSideInspectorState>(
      find.byType(TabletSideInspector),
    );
    expect(state.customWidth, 420.0);

    // Find the 48px-wide handle PositionedDirectional
    final handleFinder = find.byWidgetPredicate(
      (w) => w is PositionedDirectional && w.width == 48.0,
    );
    expect(handleFinder, findsOneWidget);

    final handleCenter = tester.getCenter(handleFinder);
    await tester.tapAt(handleCenter);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(handleCenter);
    await tester.pumpAndSettle();

    expect(state.customWidth, isNull);
    expect(SettingsCache().containsKey(key), isFalse);
  });

  testWidgets('PulsrDialog handles Widget, IconData, and String without dynamic',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AuraTheme.darkTheme,
        home: const Scaffold(
          body: PulsrDialog(
            icon: Icons.info_outline_rounded,
            title: 'Typed Title',
            content: Text('Body'),
          ),
        ),
      ),
    );
    expect(find.text('Typed Title'), findsOneWidget);
    expect(find.byIcon(Icons.info_outline_rounded), findsOneWidget);
  });
}
