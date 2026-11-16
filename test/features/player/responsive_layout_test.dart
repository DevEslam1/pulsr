import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/core/utils/adaptive.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/player/presentation/responsive_player_layout.dart';
import 'package:pulsr/features/player/presentation/themes/player_theme.dart';
import 'package:pulsr/features/player/presentation/themes/player_theme_scaffold.dart';
import 'package:pulsr/features/player/presentation/themes/theme_registry.dart';
import 'package:pulsr/features/settings/cubit/settings_cubit.dart';
import 'package:pulsr/features/settings/cubit/settings_state.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

import '../../helpers/test_song_factory.dart';

import 'package:pulsr/l10n/app_localizations_delegates.dart';
class MockPlayerCubit extends Mock implements PlayerCubit {}

class MockSettingsCubit extends Mock implements SettingsCubit {}

void main() {
  group('Adaptive responsive metrics across screen sizes', () {
    testWidgets(
        'Validates scale factors across small, standard, large, and tablet screens',
        (tester) async {
      const testSizes = [
        Size(320, 568), // Small phone (iPhone SE 1st gen)
        Size(360, 640), // Compact Android
        Size(390, 844), // Standard phone baseline
        Size(412, 915), // Pixel 7
        Size(430, 932), // iPhone 14/15 Pro Max
        Size(768, 1024), // Tablet portrait
        Size(1024, 768), // Tablet landscape
        Size(1440, 900), // Desktop / large window
      ];

      for (final size in testSizes) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) {
                // Verify scale factors are strictly bounded
                expect(context.scaleFactorW, inInclusiveRange(0.80, 1.35));
                expect(context.scaleFactorH, inInclusiveRange(0.70, 1.30));
                expect(context.scaleFactorR, inInclusiveRange(0.70, 1.35));
                expect(context.fontScale, inInclusiveRange(0.80, 1.35));

                // Verify responsive dimension scaling helpers
                expect(context.rw(100), greaterThan(0));
                expect(context.rh(100), greaterThan(0));
                expect(context.rsp(16), greaterThan(0));
                expect(context.rr(12), greaterThan(0));

                // Verify page padding adapts properly
                expect(
                    context.pagePadding,
                    anyOf(equals(12.0), equals(16.0), equals(24.0),
                        equals(32.0)));

                // Verify PlayerThemeMetrics calculations
                final metrics = PlayerThemeMetrics.calculate(
                  context,
                  BoxConstraints(maxWidth: size.width, maxHeight: size.height),
                );
                expect(metrics.heightRatio, inInclusiveRange(0.55, 1.25));
                expect(metrics.pillBarWidth, greaterThan(0));
                expect(metrics.pillBarWidth, lessThanOrEqualTo(size.width));
                expect(metrics.pillBarHeight, inInclusiveRange(30.0, 60.0));

                // Verify safe artwork sizing never overflows available height/width
                final safeArtSmall = PlayerThemeMetrics.safeArtworkSize(
                  availableWidth: 150,
                  availableHeight: 120,
                  isTablet: context.isTablet,
                );
                expect(safeArtSmall, lessThanOrEqualTo(120));
                expect(safeArtSmall, greaterThanOrEqualTo(0));

                final safeArtLarge = PlayerThemeMetrics.safeArtworkSize(
                  availableWidth: 600,
                  availableHeight: 500,
                  isTablet: context.isTablet,
                );
                expect(safeArtLarge, lessThanOrEqualTo(500));

                return const Scaffold(
                  body: Center(child: Text('Responsive test passed')),
                );
              },
            ),
          ),
        );

        await tester.pumpAndSettle();
        expect(find.text('Responsive test passed'), findsOneWidget);
      }
    });

    testWidgets(
        'Safe artwork size handles zero and negative constraints gracefully',
        (tester) async {
      final safeArtZero = PlayerThemeMetrics.safeArtworkSize(
        availableWidth: 0,
        availableHeight: 0,
        isTablet: false,
      );
      expect(safeArtZero, equals(0.0));

      final safeArtNegative = PlayerThemeMetrics.safeArtworkSize(
        availableWidth: -10,
        availableHeight: 200,
        isTablet: false,
      );
      expect(safeArtNegative, equals(0.0));
    });
  });

  group('ResponsivePlayerLayout split-view overlay flags', () {
    late MockPlayerCubit cubit;

    setUp(() {
      cubit = MockPlayerCubit();
      when(() => cubit.state).thenReturn(const PlayerState(
        lyricsSlice: LyricsSlice(isLyricsVisible: true),
      ));
      when(() => cubit.stream).thenAnswer((_) => const Stream.empty());
      when(() => cubit.resetOverlayViews()).thenAnswer((_) {});
    });

    Widget host(Size size) => MaterialApp(
          theme: AuraTheme.darkTheme,
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: MediaQuery(
            data: MediaQueryData(size: size),
            child: Scaffold(
              body: SizedBox(
                width: size.width,
                height: size.height,
                child: BlocProvider<PlayerCubit>.value(
                  value: cubit,
                  child: ResponsivePlayerLayout(
                    state: cubit.state,
                    cubit: cubit,
                    themeWidget: const Center(child: Text('THEME')),
                    activeColor: Colors.deepPurple,
                    bgColor: Colors.black,
                  ),
                ),
              ),
            ),
          ),
        );

    testWidgets('selecting the DSP tab clears the stale overlay flags',
        (tester) async {
      await tester.pumpWidget(host(const Size(1024, 768)));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.tune_rounded), findsOneWidget);

      await tester.tap(find.byIcon(Icons.tune_rounded));
      await tester.pumpAndSettle();

      verify(() => cubit.resetOverlayViews()).called(greaterThanOrEqualTo(1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('leaving the split layout clears the stale overlay flags',
        (tester) async {
      await tester.pumpWidget(host(const Size(1024, 768)));
      await tester.pumpAndSettle();
      verifyNever(() => cubit.resetOverlayViews());

      await tester.pumpWidget(host(const Size(390, 844)));
      await tester.pump();
      await tester.pump();

      verify(() => cubit.resetOverlayViews()).called(1);
      expect(find.text('THEME'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('short landscape phones stay single-pane without overflowing',
        (tester) async {
      await tester.pumpWidget(host(const Size(844, 390)));
      await tester.pumpAndSettle();

      expect(find.text('THEME'), findsOneWidget);
      // No floating split dock: the short landscape keeps the single column.
      expect(find.byIcon(Icons.tune_rounded), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('short landscape single-pane fits a real player theme',
        (tester) async {
      final state = PlayerState(
        playback: PlaybackSlice(
          currentSong: createTestSong(path: ''),
          isPlaying: false,
          position: const Duration(seconds: 30),
          duration: const Duration(minutes: 3),
        ),
      );
      final themeCubit = MockPlayerCubit();
      when(() => themeCubit.state).thenReturn(state);
      when(() => themeCubit.stream)
          .thenAnswer((_) => const Stream<PlayerState>.empty());
      when(() => themeCubit.resetOverlayViews()).thenAnswer((_) {});
      final settings = MockSettingsCubit();
      when(() => settings.state).thenReturn(const SettingsState());
      when(() => settings.stream)
          .thenAnswer((_) => const Stream<SettingsState>.empty());

      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<PlayerCubit>.value(value: themeCubit),
            BlocProvider<SettingsCubit>.value(value: settings),
          ],
          child: MaterialApp(
            theme: AuraTheme.darkTheme,
            localizationsDelegates: appLocalizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: MediaQuery(
              data: const MediaQueryData(size: Size(844, 390)),
              child: Scaffold(
                body: SizedBox(
                  width: 844,
                  height: 390,
                  child: ResponsivePlayerLayout(
                    state: state,
                    cubit: themeCubit,
                    themeWidget: ThemeRegistry.build(
                      PlayerThemeMode.classic,
                      PlayerThemeProps(
                        state: state,
                        cubit: themeCubit,
                        activeColor: Colors.deepPurple,
                        bgColor: Colors.black,
                      ),
                    ),
                    activeColor: Colors.deepPurple,
                    bgColor: Colors.black,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Test Song'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });

  group('Adaptive sheet constraints and short-height metrics', () {
    testWidgets(
        'Sheet constraints clamp both width and height relative to display',
        (tester) async {
      tester.view.physicalSize = const Size(400, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              final maxH = Adaptive.sheetMaxHeight(context);
              final constraints = Adaptive.sheetConstraints(context);

              expect(maxH, lessThan(700));
              expect(maxH, greaterThan(400));
              expect(constraints.maxHeight, equals(maxH));
              expect(constraints.maxWidth, equals(620.0));

              return const SizedBox.shrink();
            },
          ),
        ),
      );
    });

    testWidgets(
        'PlayerThemeMetrics scales controls down on short screens to preserve artwork',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              final shortMetrics = PlayerThemeMetrics.calculate(
                context,
                const BoxConstraints(maxWidth: 390, maxHeight: 660),
              );
              final tallMetrics = PlayerThemeMetrics.calculate(
                context,
                const BoxConstraints(maxWidth: 390, maxHeight: 890),
              );

              expect(shortMetrics.isShortHeight, isTrue);
              expect(tallMetrics.isShortHeight, isFalse);

              // Buttons scale adaptively, but transport targets never go below
              // the 48 dp accessibility minimum.
              expect(shortMetrics.mainButtonSize,
                  lessThan(tallMetrics.mainButtonSize));
              expect(shortMetrics.sideButtonSize, greaterThanOrEqualTo(48.0));
              expect(tallMetrics.sideButtonSize, greaterThanOrEqualTo(48.0));
              expect(shortMetrics.waveformHeight,
                  lessThan(tallMetrics.waveformHeight));
              expect(shortMetrics.dockBarHeight,
                  lessThanOrEqualTo(tallMetrics.dockBarHeight));

              // Spacings scale adaptively
              expect(shortMetrics.spacingSeekToControls,
                  lessThan(tallMetrics.spacingSeekToControls));
              expect(shortMetrics.spacingControlsToDock,
                  lessThan(tallMetrics.spacingControlsToDock));
              expect(shortMetrics.trackHeaderVerticalPadding,
                  lessThan(tallMetrics.trackHeaderVerticalPadding));

              return const SizedBox.shrink();
            },
          ),
        ),
      );
    });
  });
}
