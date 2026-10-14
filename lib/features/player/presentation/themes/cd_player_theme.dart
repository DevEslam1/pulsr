// lib/features/player/presentation/themes/cd_player_theme.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:on_audio_query/on_audio_query.dart';
import '../../../../core/motion/pulsr_motion.dart';
import '../../../../core/utils/adaptive.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../core/widgets/cached_artwork.dart';
import '../../../../data/db/app_database.dart';
import '../../../settings/cubit/settings_cubit.dart';
import '../../../settings/cubit/settings_state.dart';
import '../../cubit/player_cubit.dart';
import '../../cubit/player_state.dart';
import '../widgets/lyrics_view.dart';
import '../widgets/now_playing_queue_view.dart';
import 'player_theme.dart';
import 'player_theme_chrome.dart';
import 'player_theme_scaffold.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_colors.dart';
import '../../../../core/utils/pulsr_haptics.dart';

part 'painters/cd_stage.dart';
part 'painters/cd_painters.dart';
part 'parts/cd_player_theme_build.dart';

/// CD Turntable Player Theme:
/// Features a rotating iridescent compact disc with circular song cover,
/// animated tonearm/stylus stick that moves onto the CD to play, and
/// responsive mobile/tablet layout in portrait and landscape.
class CdPlayerTheme extends StatefulWidget {
  final PlayerThemeProps props;

  const CdPlayerTheme({super.key, required this.props});

  @override
  State<CdPlayerTheme> createState() => _CdPlayerThemeState();
}

class _CdPlayerThemeState extends State<CdPlayerTheme>
    with TickerProviderStateMixin {
  late final AnimationController _rotationController;
  late final AnimationController _tonearmController;
  late final Animation<double> _tonearmAnimation;

  @override
  void initState() {
    super.initState();
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    );

    _tonearmController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
      value: widget.props.state.isPlaying ? 1.0 : 0.0,
    );

    _tonearmAnimation = CurvedAnimation(
      parent: _tonearmController,
      curve: Curves.easeInOutCubic,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _tonearmController.duration = context.motionMs(850);
    _syncRotation();
  }

  void _syncRotation() {
    final shouldSpin = widget.props.state.isPlaying && context.motionEnabled;
    if (shouldSpin) {
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
  void didUpdateWidget(covariant CdPlayerTheme oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.props.state.isPlaying != oldWidget.props.state.isPlaying) {
      if (widget.props.state.isPlaying) {
        _tonearmController.forward();
      } else {
        _tonearmController.reverse();
      }
    }
    _syncRotation();
  }

  @override
  void dispose() {
    _rotationController.dispose();
    _tonearmController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _buildBody(context);
}
