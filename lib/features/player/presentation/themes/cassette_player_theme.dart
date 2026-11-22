// lib/features/player/presentation/themes/cassette_player_theme.dart
import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pulsr/core/constants/app_colors.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_typography.dart';

import '../../../../core/motion/pulsr_motion.dart';
import '../../../../core/performance/gpu_budget.dart';
import '../../../../core/services/waveform_service.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/theme/player_material_colors.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../core/utils/pulsr_haptics.dart';
import '../../../../core/widgets/marquee_text.dart';
import '../../../../core/widgets/pulsr_slider.dart';
import '../../../../core/widgets/pulsr_toast.dart';
import '../../../../data/db/app_database.dart';
import '../../../settings/cubit/settings_cubit.dart';
import '../../../settings/cubit/settings_state.dart';
import '../../../sheets/song_options_sheet.dart';
import '../../cubit/player_cubit.dart';
import '../../cubit/player_state.dart';
import '../widgets/audio_quality_sheet.dart';
import '../widgets/audio_visualizer.dart';
import '../widgets/player_gesture_scope.dart';
import '../widgets/player_volume_bar.dart';
import '../widgets/radio_now_playing_recommendations.dart';
import '../widgets/waveform_seek_bar.dart';
import 'player_shape.dart';
import 'player_theme.dart';
import 'player_theme_chrome.dart';
import 'player_theme_scaffold.dart' show PlayerThemePreviewScope;

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
  late final Ticker _ticker;
  Duration? _lastTick;
  double _phase = 0.0;
  double _baseSpoolPeriodSeconds = 4.0;
  bool? _lastAllowMotion;

  @visibleForTesting
  bool get isSpoolAnimating => _ticker.isActive;

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

    _ticker = createTicker(_onTick);
  }

  void _onTick(Duration elapsed) {
    final last = _lastTick;
    _lastTick = elapsed;
    if (last == null) return;
    final dt = (elapsed - last).inMicroseconds / 1000000.0;
    if (dt <= 0.0 || dt > 0.5) return;

    final velocity = _spoolVelocityController.value;
    if (velocity > 0.0) {
      final period =
          _baseSpoolPeriodSeconds > 0 ? _baseSpoolPeriodSeconds : 4.0;
      final delta = (dt / period) * velocity;
      _phase = (_phase + delta) % 1.0;
      _spoolController.value = _phase;
    } else if (!_spoolVelocityController.isAnimating) {
      _ticker.stop();
      _lastTick = null;
    }
  }

  bool _allowMotion(BuildContext context) =>
      !PlayerThemePreviewScope.of(context) &&
      PulsrMotion.shouldAnimate(context) &&
      context.motionEnabled;

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
    _baseSpoolPeriodSeconds = math.max(0.001, baseDurationMs / 1000.0);
    _spoolController.duration =
        Duration(milliseconds: math.max(1, baseDurationMs));
  }

  void _syncSpool({bool restartIfAnimating = false, bool? allowMotionOverride}) {
    final allowMotion = allowMotionOverride ?? _allowMotion(context);
    final duration = _spoolController.duration;
    final hasValidDuration = duration != null && duration > Duration.zero;
    final shouldAnimate =
        widget.props.state.isPlaying && allowMotion && hasValidDuration;
    if (shouldAnimate) {
      if (!_ticker.isActive || restartIfAnimating) {
        _lastTick = null;
        if (!_ticker.isActive) _ticker.start();
      }
      _spoolVelocityController.animateTo(
        1.0,
        duration: context.motionMs(650),
        curve: context.motionCurve(PulsrMotion.enter),
      );
    } else {
      if (!allowMotion || !hasValidDuration) {
        _spoolVelocityController.stop();
        _spoolVelocityController.value = 0.0;
        if (_ticker.isActive) {
          _ticker.stop();
          _lastTick = null;
        }
      } else if (_ticker.isActive || _spoolVelocityController.value > 0.0) {
        if (!_ticker.isActive) {
          _lastTick = null;
          _ticker.start();
        }
        _spoolVelocityController
            .animateTo(
          0.0,
          duration: context.motionMs(650),
          curve: context.motionCurve(PulsrMotion.decelerate),
        )
            .whenComplete(() {
          if (mounted &&
              !widget.props.state.isPlaying &&
              _spoolVelocityController.value == 0.0) {
            if (_ticker.isActive) {
              _ticker.stop();
              _lastTick = null;
            }
          }
        });
      }
    }
  }

  @override
  void didUpdateWidget(covariant CassettePlayerTheme oldWidget) {
    super.didUpdateWidget(oldWidget);
    final speedChanged =
        widget.props.state.playbackSpeed != oldWidget.props.state.playbackSpeed;
    if (speedChanged) {
      _updateSpoolSpeed();
    }
    _syncSpool(restartIfAnimating: speedChanged);
  }

  @override
  void dispose() {
    _ticker.dispose();
    _spoolVelocityController.dispose();
    _spoolController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final allowMotion = _allowMotion(context);
    if (_lastAllowMotion != allowMotion) {
      _lastAllowMotion = allowMotion;
      if (!allowMotion) {
        _spoolVelocityController.stop();
        _spoolVelocityController.value = 0.0;
        if (_ticker.isActive) {
          _ticker.stop();
          _lastTick = null;
        }
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _syncSpool(allowMotionOverride: allowMotion);
        });
      }
    }
    return _buildBody(context);
  }
}
