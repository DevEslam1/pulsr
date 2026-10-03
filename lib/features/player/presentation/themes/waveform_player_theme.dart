// lib/features/player/presentation/themes/waveform_player_theme.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:on_audio_query/on_audio_query.dart';
import '../../../../core/motion/pulsr_motion.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/adaptive.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../core/widgets/cached_artwork.dart';
import '../../../../data/db/app_database.dart';
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
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_typography.dart';
import 'package:pulsr/core/constants/app_colors.dart';

part 'painters/waveform_stage.dart';
part 'parts/waveform_player_theme_build.dart';

class WaveformPlayerTheme extends StatefulWidget {
  final PlayerThemeProps props;

  const WaveformPlayerTheme({super.key, required this.props});

  @override
  State<WaveformPlayerTheme> createState() => _WaveformPlayerThemeState();
}

class _WaveformPlayerThemeState extends State<WaveformPlayerTheme>
    with SingleTickerProviderStateMixin {
  late final AnimationController _waveController;

  @override
  void initState() {
    super.initState();
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _waveController.duration = context.motionMs(4000);
    _syncWave();
  }

  void _syncWave() {
    final shouldAnimate = widget.props.state.isPlaying && context.motionEnabled;
    if (shouldAnimate) {
      if (!_waveController.isAnimating) {
        _waveController.repeat();
      }
    } else {
      if (_waveController.isAnimating) {
        _waveController.stop();
      }
    }
  }

  @override
  void didUpdateWidget(covariant WaveformPlayerTheme oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncWave();
  }

  @override
  void dispose() {
    _waveController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _buildBody(context);
}
