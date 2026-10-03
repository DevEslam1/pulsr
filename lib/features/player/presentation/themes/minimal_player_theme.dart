// lib/features/player/presentation/themes/minimal_player_theme.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:on_audio_query/on_audio_query.dart';
import '../../../../core/motion/pulsr_motion.dart';
import '../../../../core/utils/adaptive.dart';
import '../../../../core/widgets/cached_artwork.dart';
import '../../../settings/cubit/settings_cubit.dart';
import '../../../settings/cubit/settings_state.dart';
import '../widgets/audio_visualizer.dart';
import '../widgets/lyrics_view.dart';
import '../widgets/now_playing_queue_view.dart';
import 'player_shape.dart';
import 'player_theme.dart';
import 'player_theme_chrome.dart';
import 'player_theme_scaffold.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
part 'parts/minimal_player_theme_build.dart';

class MinimalPlayerTheme extends StatelessWidget {
  final PlayerThemeProps props;

  const MinimalPlayerTheme({super.key, required this.props});

  @override
  Widget build(BuildContext context) => _buildBody(context);
}
