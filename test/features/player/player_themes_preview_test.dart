// test/features/player/player_themes_preview_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/player/presentation/themes/card_player_theme.dart';
import 'package:pulsr/features/player/presentation/themes/cassette_player_theme.dart';
import 'package:pulsr/features/player/presentation/themes/circle_player_theme.dart';
import 'package:pulsr/features/player/presentation/themes/classic_player_theme.dart';
import 'package:pulsr/features/player/presentation/themes/lyrics_player_theme.dart';
import 'package:pulsr/features/player/presentation/themes/minimal_player_theme.dart';
import 'package:pulsr/features/player/presentation/themes/player_theme.dart';
import 'package:pulsr/features/player/presentation/themes/theme_registry.dart';
import 'package:pulsr/features/player/presentation/themes/vinyl_player_theme.dart';
import 'package:pulsr/features/player/presentation/themes/waveform_player_theme.dart';
import 'package:pulsr/features/settings/cubit/settings_state.dart';

class _FakePlayerCubit extends Fake implements PlayerCubit {}

void main() {
  setUp(() {
    ThemeRegistry.reset();
  });

  tearDown(() {
    ThemeRegistry.reset();
  });

  group('Player Themes Preview Suite (ThemeRegistry.preview)', () {
    final fakeCubit = _FakePlayerCubit();
    final dummyProps = PlayerThemeProps(
      state: const PlayerState(),
      cubit: fakeCubit,
      activeColor: const Color(0xFF6750A4),
      bgColor: const Color(0xFF1C1B1F),
    );

    test('preview() wraps built theme with IgnorePointer and 360x640 bounds',
        () {
      final previewWidget = ThemeRegistry.preview(
        PlayerThemeMode.classic,
        dummyProps,
        scale: 0.5,
      );

      expect(previewWidget, isA<IgnorePointer>());
      final ignorePointer = previewWidget as IgnorePointer;
      expect(ignorePointer.child, isA<SizedBox>());

      final bounds = ignorePointer.child! as SizedBox;
      expect(bounds.width, 180);
      expect(bounds.height, 320);
      final fitted = bounds.child! as FittedBox;
      final sizedBox = fitted.child! as SizedBox;
      expect(sizedBox.width, 360);
      expect(sizedBox.height, 640);
      expect(sizedBox.child, isA<ClassicPlayerTheme>());
    });

    test('preview() correctly builds all 8 theme modes', () {
      final modes = <PlayerThemeMode, Type>{
        PlayerThemeMode.classic: ClassicPlayerTheme,
        PlayerThemeMode.card: CardPlayerTheme,
        PlayerThemeMode.circle: CirclePlayerTheme,
        PlayerThemeMode.minimal: MinimalPlayerTheme,
        PlayerThemeMode.vinyl: VinylPlayerTheme,
        PlayerThemeMode.cassette: CassettePlayerTheme,
        PlayerThemeMode.waveform: WaveformPlayerTheme,
        PlayerThemeMode.lyricsFocus: LyricsPlayerTheme,
      };

      for (final entry in modes.entries) {
        final preview = ThemeRegistry.preview(entry.key, dummyProps);
        final ignorePointer = preview as IgnorePointer;
        final bounds = ignorePointer.child! as SizedBox;
        final fitted = bounds.child! as FittedBox;
        final sizedBox = fitted.child! as SizedBox;
        expect(
          sizedBox.child.runtimeType,
          entry.value,
          reason: 'Expected ${entry.key} to build ${entry.value}',
        );
      }
    });

    test('preview() scale sets layout dimensions as well as visual size', () {
      const targetScale = 0.35;
      final preview = ThemeRegistry.preview(PlayerThemeMode.minimal, dummyProps,
          scale: targetScale) as IgnorePointer;
      final bounds = preview.child! as SizedBox;
      expect(bounds.width, closeTo(360 * targetScale, 0.001));
      expect(bounds.height, closeTo(640 * targetScale, 0.001));
      expect((bounds.child! as FittedBox).fit, BoxFit.contain);
    });
  });
}
