// lib/features/player/presentation/themes/cassette_player_theme.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/motion/pulsr_motion.dart';
import '../../../../core/utils/adaptive.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../data/db/app_database.dart';
import '../../../settings/cubit/settings_cubit.dart';
import '../../../settings/cubit/settings_state.dart';
import '../widgets/lyrics_view.dart';
import '../widgets/now_playing_queue_view.dart';
import 'player_theme.dart';
import 'player_theme_chrome.dart';
import 'player_theme_scaffold.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_typography.dart';
import 'package:pulsr/core/constants/app_colors.dart';

part 'painters/cassette_body.dart';
part 'parts/cassette_player_theme_build.dart';

class CassettePlayerTheme extends StatefulWidget {
  final PlayerThemeProps props;

  const CassettePlayerTheme({super.key, required this.props});

  @override
  State<CassettePlayerTheme> createState() => _CassettePlayerThemeState();
}

class _CassettePlayerThemeState extends State<CassettePlayerTheme>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spoolController;

  @override
  void initState() {
    super.initState();
    _spoolController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateSpoolSpeed();
    _syncSpool();
  }

  void _updateSpoolSpeed() {
    final speed = widget.props.state.playbackSpeed.clamp(0.25, 4.0);
    final baseDurationMs = (4000 / speed).round();
    _spoolController.duration = context.motionMs(baseDurationMs);
  }

  void _syncSpool() {
    final shouldAnimate = widget.props.state.isPlaying && context.motionEnabled;
    if (shouldAnimate) {
      if (!_spoolController.isAnimating) {
        _spoolController.repeat();
      }
    } else {
      if (_spoolController.isAnimating) {
        _spoolController.stop();
      }
    }
  }

  @override
  void didUpdateWidget(covariant CassettePlayerTheme oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.props.state.playbackSpeed !=
        oldWidget.props.state.playbackSpeed) {
      _updateSpoolSpeed();
      if (_spoolController.isAnimating) {
        _spoolController.repeat();
      }
    }
    _syncSpool();
  }

  @override
  void dispose() {
    _spoolController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _buildBody(context);
}
