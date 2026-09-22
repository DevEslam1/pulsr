import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/core/widgets/spinning_vinyl_disc.dart';
import 'package:pulsr/core/widgets/waveform_logo.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/core/widgets/song_tile.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/player/presentation/themes/player_theme_chrome.dart';
import 'package:pulsr/features/player/presentation/widgets/waveform_seek_bar.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

class MockPlayerCubit extends Mock implements PlayerCubit {}

/// Calculates the WCAG 2.1 contrast ratio between two colors using relative luminance.
double _calculateContrastRatio(Color foreground, Color background) {
  final lum1 = foreground.computeLuminance();
  final lum2 = background.computeLuminance();
  final lighter = math.max(lum1, lum2);
  final darker = math.min(lum1, lum2);
  return (lighter + 0.05) / (darker + 0.05);
}

Widget _buildA11yHarness({
  required Widget child,
  double textScale = 1.0,
  Size size = const Size(390, 844),
  PlayerCubit? playerCubit,
}) {
  Widget content = MediaQuery(
    data: MediaQueryData(
      size: size,
      textScaler: TextScaler.linear(textScale),
    ),
    child: Scaffold(
      body: Center(child: child),
    ),
  );

  if (playerCubit != null) {
    content = BlocProvider<PlayerCubit>.value(
      value: playerCubit,
      child: content,
    );
  }

  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: ThemeData.dark().copyWith(
      extensions: [AuraTheme.defaultDark],
    ),
    home: content,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Phase J: Accessibility 10/10 Compliance Tests', () {
    test('1. WCAG 2.1 AA Contrast Ratio: all core text pairs exceed 4.5:1', () {
      final palette = AuraTheme.defaultDark;

      // Text primary against dark background
      final textBgContrast =
          _calculateContrastRatio(palette.textPrimary, palette.bg);
      expect(textBgContrast, greaterThanOrEqualTo(4.5),
          reason: 'Text primary on bg must meet WCAG 2.1 AA (>= 4.5:1)');

      // Text primary against surface container
      final textSurfaceContrast = _calculateContrastRatio(
          palette.textPrimary, palette.surfaceContainer);
      expect(textSurfaceContrast, greaterThanOrEqualTo(4.5),
          reason:
              'Text primary on surfaceContainer must meet WCAG 2.1 AA (>= 4.5:1)');

      // Guaranteed high-contrast text on accent
      final textOnAccentContrast =
          _calculateContrastRatio(palette.textOnAccent, palette.accent);
      expect(textOnAccentContrast, greaterThanOrEqualTo(4.5),
          reason: 'textOnAccent on accent must meet WCAG 2.1 AA (>= 4.5:1)');
    });

    testWidgets(
        '2. Minimum touch target size: interactive buttons meet 48x48dp constraint',
        (tester) async {
      await tester.pumpWidget(
        _buildA11yHarness(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              PlayerSwitcherItem(
                label: 'Lyrics',
                icon: Icons.lyrics_rounded,
                isSelected: true,
                activeColor: Colors.tealAccent,
                onTap: () {},
              ),
              PlayerAnimatedFavoriteButton(
                isFavorite: true,
                favoriteColor: Colors.redAccent,
                inactiveColor: Colors.grey,
                semanticLabel: 'Favorite song',
                onTap: () {},
              ),
              PlayerDockIconButton(
                icon: Icons.equalizer_rounded,
                tooltip: 'Equalizer',
                isActive: false,
                activeColor: Colors.tealAccent,
                inactiveColor: Colors.white70,
                onTap: () {},
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      final switcherSize = tester.getSize(find.byType(PlayerSwitcherItem));
      expect(switcherSize.width, greaterThanOrEqualTo(48.0));
      expect(switcherSize.height, greaterThanOrEqualTo(48.0));

      final favSize =
          tester.getSize(find.byType(PlayerAnimatedFavoriteButton));
      expect(favSize.width, greaterThanOrEqualTo(48.0));
      expect(favSize.height, greaterThanOrEqualTo(48.0));

      final dockBtnSize = tester.getSize(find.byType(PlayerDockIconButton));
      expect(dockBtnSize.width, greaterThanOrEqualTo(48.0));
      expect(dockBtnSize.height, greaterThanOrEqualTo(48.0));
    });

    testWidgets(
        '3. Decorative element semantics: ExcludeSemantics applied to visualizers',
        (tester) async {
      await tester.pumpWidget(
        _buildA11yHarness(
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              WaveformLogo(size: 32),
              SpinningVinylDisc(id: 101, size: 64, onTap: null),
            ],
          ),
        ),
      );
      // Pump initial frames without pumpAndSettle to support looping animations
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // WaveformLogo should wrap its child in ExcludeSemantics
      final waveformLogoFinder = find.byType(WaveformLogo);
      expect(waveformLogoFinder, findsOneWidget);
      final waveformExclude = find.descendant(
        of: waveformLogoFinder,
        matching: find.byType(ExcludeSemantics),
      );
      expect(waveformExclude, findsOneWidget);

      // SpinningVinylDisc without onTap should be wrapped in ExcludeSemantics
      final vinylFinder = find.byType(SpinningVinylDisc);
      expect(vinylFinder, findsOneWidget);
      final vinylExclude = find.descendant(
        of: vinylFinder,
        matching: find.byType(ExcludeSemantics),
      );
      expect(vinylExclude, findsAtLeastNWidgets(1));
    });

    testWidgets('4. Slider accessibility: WaveformSeekBar exposes full slider semantics',
        (tester) async {
      Duration? seekTarget;

      await tester.pumpWidget(
        _buildA11yHarness(
          child: WaveformSeekBar(
            position: const Duration(seconds: 45),
            duration: const Duration(minutes: 3),
            samples: const [0.2, 0.5, 0.8, 0.4, 0.9, 0.3],
            onSeek: (d) => seekTarget = d,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify Semantics properties of the seek bar
      final semanticsFinder = find.descendant(
        of: find.byType(WaveformSeekBar),
        matching: find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.slider == true,
        ),
      );
      expect(semanticsFinder, findsOneWidget);

      final Semantics semanticsWidget = tester.widget(semanticsFinder);
      expect(semanticsWidget.properties.slider, isTrue);
      expect(semanticsWidget.properties.value, equals('0:45 / 3:00'));
      expect(semanticsWidget.properties.increasedValue, equals('0:55 / 3:00'));
      expect(semanticsWidget.properties.decreasedValue, equals('0:35 / 3:00'));

      // Test accessibility actions (increase & decrease by 10s step)
      semanticsWidget.properties.onIncrease?.call();
      expect(seekTarget, equals(const Duration(seconds: 55)));

      semanticsWidget.properties.onDecrease?.call();
      expect(seekTarget, equals(const Duration(seconds: 35)));
    });

    testWidgets(
        '5. Dynamic Type 2.0x Stress Test: zero RenderFlex overflow under 200% font scaling',
        (tester) async {
      final mockPlayerCubit = MockPlayerCubit();
      when(() => mockPlayerCubit.state).thenReturn(const PlayerState());
      when(() => mockPlayerCubit.stream)
          .thenAnswer((_) => const Stream.empty());

      const song = SongsTableData(
        id: 999,
        title: 'Extremely Long Song Title That Might Cause Layout Overflow',
        artist: 'Legendary Symphony Orchestra with Very Long Artist Name',
        album: 'Deluxe Remastered Anniversary Collector Edition Album',
        durationMs: 312000,
        path: '/storage/emulated/0/Music/test.mp3',
        source: SongSource.local,
        playCount: 0,
        dateAdded: 0,
        isFavorite: false,
        isMissing: false,
        isDownloaded: false,
        lastPositionMs: 0,
      );

      // Pump layout with 2.0x text scaling factor (WCAG dynamic type stress)
      await tester.pumpWidget(
        _buildA11yHarness(
          playerCubit: mockPlayerCubit,
          textScale: 2.0,
          size: const Size(360, 640), // Compact screen at 2.0x
          child: ListView(
            shrinkWrap: true,
            children: [
              SongTile(
                song: song,
                onTap: () {},
                onMorePressed: () {},
              ),
              const SizedBox(height: 16),
              PlayerDockIconButton(
                icon: Icons.equalizer_rounded,
                tooltip: 'Parametric Equalizer and DSP Suite',
                isActive: true,
                badgeText: 'DSP',
                activeColor: Colors.tealAccent,
                inactiveColor: Colors.white54,
                onTap: () {},
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Zero exceptions (zero RenderFlex overflow errors)
      expect(tester.takeException(), isNull);
    });
  });
}
