// lib/features/player/presentation/themes/vinyl_player_theme.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:on_audio_query/on_audio_query.dart';
import '../../../../core/motion/pulsr_motion.dart';
import '../../../../core/utils/adaptive.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../core/widgets/cached_artwork.dart';
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
import 'package:pulsr/core/constants/app_typography.dart';
import 'package:pulsr/core/constants/app_colors.dart';

part 'painters/vinyl_deck.dart';
part 'painters/vinyl_painters.dart';
part 'parts/vinyl_player_theme_build.dart';

class VinylPlayerTheme extends StatefulWidget {
  final PlayerThemeProps props;

  const VinylPlayerTheme({super.key, required this.props});

  @override
  State<VinylPlayerTheme> createState() => _VinylPlayerThemeState();
}

class _VinylPlayerThemeState extends State<VinylPlayerTheme>
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
  void didUpdateWidget(covariant VinylPlayerTheme oldWidget) {
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
