// lib/features/player/presentation/now_playing_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/theme/dynamic_theme_cubit.dart';
import '../../../data/repositories/music_repository.dart';
import '../../settings/cubit/settings_cubit.dart';
import '../../settings/cubit/settings_state.dart';
import '../cubit/player_cubit.dart';
import '../cubit/player_state.dart';
import 'themes/card_player_theme.dart';
import 'themes/circle_player_theme.dart';
import 'themes/classic_player_theme.dart';
import 'themes/minimal_player_theme.dart';
import 'themes/player_theme.dart';

class NowPlayingScreen extends StatelessWidget {
  const NowPlayingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settingsState = context.watch<SettingsCubit>().state;

    return BlocBuilder<PlayerCubit, PlayerState>(
      builder: (context, state) {
        final song = state.currentSong;
        final cubit = context.read<PlayerCubit>();
        final repository = context.read<MusicRepository>();
        final dynamicTheme = context.watch<DynamicThemeCubit>().state;

        // Trigger dynamic color extraction whenever song changes
        if (song != null) {
          context.read<DynamicThemeCubit>().updateFromSongId(song.id);
        }

        final activeColor = dynamicTheme.primaryColor;
        final bgColor = dynamicTheme.backgroundColor;

        final props = PlayerThemeProps(
          state: state,
          cubit: cubit,
          repository: repository,
          activeColor: activeColor,
          bgColor: bgColor,
        );

        Widget themeWidget;
        switch (settingsState.playerThemeMode) {
          case PlayerThemeMode.classic:
            themeWidget = ClassicPlayerTheme(props: props);
            break;
          case PlayerThemeMode.card:
            themeWidget = CardPlayerTheme(props: props);
            break;
          case PlayerThemeMode.circle:
            themeWidget = CirclePlayerTheme(props: props);
            break;
          case PlayerThemeMode.minimal:
            themeWidget = MinimalPlayerTheme(props: props);
            break;
        }

        return Dismissible(
          key: const Key('now_playing_dismissible'),
          direction: DismissDirection.down,
          onDismissed: (_) => Navigator.of(context).pop(),
          child: Scaffold(
            body: themeWidget,
          ),
        );
      },
    );
  }
}
