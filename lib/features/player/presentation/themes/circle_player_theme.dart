// lib/features/player/presentation/themes/circle_player_theme.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:on_audio_query/on_audio_query.dart';
import '../../../../core/motion/pulsr_motion.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/adaptive.dart';
import '../../../../core/widgets/cached_artwork.dart';
import '../../../../data/db/app_database.dart';
import '../../../settings/cubit/settings_cubit.dart';
import '../../../settings/cubit/settings_state.dart';
import '../widgets/lyrics_view.dart';
import '../widgets/now_playing_queue_view.dart';
import 'player_theme.dart';
import 'player_theme_chrome.dart';
import 'player_theme_scaffold.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_colors.dart';

part 'painters/circle_stage.dart';
part 'parts/circle_player_theme_build.dart';

class CirclePlayerTheme extends StatefulWidget {
  final PlayerThemeProps props;

  const CirclePlayerTheme({super.key, required this.props});

  @override
  State<CirclePlayerTheme> createState() => _CirclePlayerThemeState();
}

class _CirclePlayerThemeState extends State<CirclePlayerTheme>
    with SingleTickerProviderStateMixin {
  late final AnimationController _rotationController;

  @override
  void initState() {
    super.initState();
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 15),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _rotationController.duration = context.motionMs(15000);
    _syncRotation();
  }

  void _syncRotation() {
    final shouldAnimate = widget.props.state.isPlaying && context.motionEnabled;
    if (shouldAnimate) {
      if (!_rotationController.isAnimating) {
        _rotationController.repeat();
      }
    } else {
      if (_rotationController.isAnimating) {
        _rotationController.stop();
      }
    }
  }

  @override
  void didUpdateWidget(covariant CirclePlayerTheme oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncRotation();
  }

  @override
  void dispose() {
    _rotationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _buildBody(context);
}
