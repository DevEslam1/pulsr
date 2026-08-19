// lib/features/player/presentation/themes/player_theme.dart
import 'package:flutter/material.dart';
import '../../../../data/repositories/music_repository.dart';
import '../../cubit/player_cubit.dart';
import '../../cubit/player_state.dart';

class PlayerThemeProps {
  final PlayerState state;
  final PlayerCubit cubit;
  final MusicRepository repository;
  final Color activeColor;
  final Color bgColor;

  const PlayerThemeProps({
    required this.state,
    required this.cubit,
    required this.repository,
    required this.activeColor,
    required this.bgColor,
  });
}
