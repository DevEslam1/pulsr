// lib/features/player/presentation/themes/cassette_player_theme.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../../core/motion/pulsr_motion.dart';
import '../../../../core/theme/player_material_colors.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../data/db/app_database.dart';
import '../widgets/player_gesture_scope.dart';
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
    with TickerProviderStateMixin {
  late final AnimationController _spoolController;
  late final AnimationController _spoolVelocityController;

  @visibleForTesting
  bool get isSpoolAnimating => _spoolController.isAnimating;

  @visibleForTesting
  AnimationController get spoolController => _spoolController;

  @override
  void initState() {
    super.initState();
    _spoolController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    );

    _spoolVelocityController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
      value: widget.props.state.isPlaying ? 1.0 : 0.0,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateSpoolSpeed();
    _spoolVelocityController.duration = context.motionMs(650);
    _syncSpool();
  }

  void _updateSpoolSpeed() {
    final speed = widget.props.state.playbackSpeed.clamp(0.25, 4.0);
    final baseDurationMs = (4000 / speed).round();
    _spoolController.duration =
        Duration(milliseconds: math.max(1, baseDurationMs));
  }

  void _syncSpool({bool restartIfAnimating = false}) {
    final duration = _spoolController.duration;
    final hasValidDuration = duration != null && duration > Duration.zero;
    final shouldAnimate =
        widget.props.state.isPlaying && context.motionEnabled && hasValidDuration;
    if (shouldAnimate) {
      if (!_spoolController.isAnimating || restartIfAnimating) {
        _spoolController.repeat();
      }
      _spoolVelocityController.animateTo(
        1.0,
        duration: context.motionMs(650),
        curve: Curves.easeOutCubic,
      );
    } else {
      if (!context.motionEnabled || !hasValidDuration) {
        _spoolVelocityController.stop();
        _spoolVelocityController.value = 0.0;
        if (_spoolController.isAnimating) {
          _spoolController.stop();
        }
      } else if (_spoolController.isAnimating) {
        _spoolVelocityController
            .animateTo(
              0.0,
              duration: context.motionMs(650),
              curve: Curves.decelerate,
            )
            .whenComplete(() {
              if (mounted &&
                  !widget.props.state.isPlaying &&
                  _spoolVelocityController.value == 0.0) {
                _spoolController.stop();
              }
            });
      }
    }
  }

  @override
  void didUpdateWidget(covariant CassettePlayerTheme oldWidget) {
    super.didUpdateWidget(oldWidget);
    final speedChanged = widget.props.state.playbackSpeed !=
        oldWidget.props.state.playbackSpeed;
    if (speedChanged) {
      _updateSpoolSpeed();
    }
    _syncSpool(restartIfAnimating: speedChanged);
  }

  @override
  void dispose() {
    _spoolVelocityController.dispose();
    _spoolController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _buildBody(context);
}
