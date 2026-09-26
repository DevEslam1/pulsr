// test/features/player/player_themes_render_test.dart
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

  group('Player Themes Suite (I18)', () {
    final fakeCubit = _FakePlayerCubit();
    final dummyProps = PlayerThemeProps(
      state: const PlayerState(),
      cubit: fakeCubit,
      activeColor: const Color(0xFF6750A4),
      bgColor: const Color(0xFF1C1B1F),
    );

    test('All 8 PlayerThemeModes resolve to concrete theme widget instances', () {
      expect(
        ThemeRegistry.build(PlayerThemeMode.classic, dummyProps),
        isA<ClassicPlayerTheme>(),
      );
      expect(
        ThemeRegistry.build(PlayerThemeMode.card, dummyProps),
        isA<CardPlayerTheme>(),
      );
      expect(
        ThemeRegistry.build(PlayerThemeMode.circle, dummyProps),
        isA<CirclePlayerTheme>(),
      );
      expect(
        ThemeRegistry.build(PlayerThemeMode.minimal, dummyProps),
        isA<MinimalPlayerTheme>(),
      );
      expect(
        ThemeRegistry.build(PlayerThemeMode.vinyl, dummyProps),
        isA<VinylPlayerTheme>(),
      );
      expect(
        ThemeRegistry.build(PlayerThemeMode.cassette, dummyProps),
        isA<CassettePlayerTheme>(),
      );
      expect(
        ThemeRegistry.build(PlayerThemeMode.waveform, dummyProps),
        isA<WaveformPlayerTheme>(),
      );
      expect(
        ThemeRegistry.build(PlayerThemeMode.lyricsFocus, dummyProps),
        isA<LyricsPlayerTheme>(),
      );
    });

    test('ThemeRegistry allows registration of overrides and safe reset', () {
      ThemeRegistry.register(
        PlayerThemeMode.classic,
        (props) => const SizedBox(key: ValueKey('custom_classic')),
      );

      final overridden = ThemeRegistry.build(PlayerThemeMode.classic, dummyProps);
      expect(overridden, isA<SizedBox>());

      ThemeRegistry.reset();

      final restored = ThemeRegistry.build(PlayerThemeMode.classic, dummyProps);
      expect(restored, isA<ClassicPlayerTheme>());
    });
  });
}
