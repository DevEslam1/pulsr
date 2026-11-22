// lib/features/player/presentation/themes/cd_player_theme.dart
import 'dart:math' as math;
import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:on_audio_query/on_audio_query.dart';
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
import '../../../../core/widgets/cached_artwork.dart';
import '../../../../core/widgets/marquee_text.dart';
import '../../../../core/widgets/pulsr_slider.dart';
import '../../../../core/widgets/pulsr_toast.dart';
import '../../../settings/cubit/settings_cubit.dart';
import '../../../settings/cubit/settings_state.dart';
import '../../../sheets/song_options_sheet.dart';
import '../../cubit/player_cubit.dart';
import '../../cubit/player_state.dart';
import '../widgets/audio_quality_sheet.dart';
import '../widgets/audio_visualizer.dart';
import '../widgets/player_gesture_scope.dart';
import '../widgets/player_volume_bar.dart';
import '../widgets/waveform_seek_bar.dart';
import 'painters/platter_scrub.dart';
import 'player_shape.dart';
import 'player_theme.dart';
import 'player_theme_chrome.dart';
import 'player_theme_scaffold.dart' show PlayerThemePreviewScope;

part 'painters/cd_stage.dart';
part 'painters/cd_painters.dart';
part 'parts/cd_player_theme_build.dart';

/// CD Turntable Player Theme (Y2K Transparent Jewel Case / Discman):
/// Full-screen brushed cool-silver/titanium Discman faceplate framing an
/// iridescent spinning compact disc inside a realistic transparent acrylic
/// jewel case with a vertical ribbed spine, backlit monospace dot-matrix LCD
/// track/time readout, slim metallic seek bar, and precision rectangular
/// brushed-metal transport keys.
class CdPlayerTheme extends StatefulWidget {
  final PlayerThemeProps props;

  const CdPlayerTheme({super.key, required this.props});

  @override
  State<CdPlayerTheme> createState() => _CdPlayerThemeState();
}

class _CdPlayerThemeState extends State<CdPlayerTheme>
    with TickerProviderStateMixin {
  late final AnimationController _rotationController;
  late final AnimationController _velocityController;
  late final AnimationController _pickupController;
  late final CurvedAnimation _pickupAnimation;
  late final AnimationController _glossController;
  late final Ticker _ticker;
  Duration? _lastTick;
  double _phase = 0.0;
  bool? _lastAllowMotion;

  @override
  void initState() {
    super.initState();
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    );

    _velocityController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
      value: widget.props.state.isPlaying ? 1.0 : 0.0,
    );

    _pickupController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
      value: widget.props.state.isPlaying ? 1.0 : 0.0,
    );

    _pickupAnimation = CurvedAnimation(
      parent: _pickupController,
      curve: Curves.easeInOutBack,
    );

    // The lid highlight parks past the case (value 1) so nothing sweeps across
    // the jewel case until playback actually starts or stops.
    _glossController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
      value: 1.0,
    );

    _ticker = createTicker(_onTick);
  }

  void _onTick(Duration elapsed) {
    final last = _lastTick;
    _lastTick = elapsed;
    if (last == null) return;
    final dt = (elapsed - last).inMicroseconds / 1000000.0;
    if (dt <= 0.0 || dt > 0.5) return;

    final velocity = _velocityController.value;
    if (velocity > 0.0) {
      // 12 seconds per revolution at full velocity (1.0)
      final delta = (dt / 12.0) * velocity;
      _phase = (_phase + delta) % 1.0;
      _rotationController.value = _phase;
    } else if (!_velocityController.isAnimating) {
      _ticker.stop();
      _lastTick = null;
    }
  }

  bool _allowMotion(BuildContext context) =>
      PulsrMotion.shouldAnimate(context) &&
      context.motionEnabled &&
      !PlayerThemePreviewScope.of(context);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _pickupController.duration = context.motionMs(400);
    _velocityController.duration = context.motionMs(650);
    _glossController.duration = context.motionMs(900);
    _syncRotation();
  }

  void _syncRotation({bool? allowMotionOverride}) {
    final allowMotion = allowMotionOverride ?? _allowMotion(context);
    final shouldSpin = widget.props.state.isPlaying && allowMotion;
    if (shouldSpin) {
      if (!_ticker.isActive) {
        _lastTick = null;
        _ticker.start();
      }
      _velocityController.animateTo(
        1.0,
        duration: context.motionMs(650),
        curve: Curves.easeOutCubic,
      );
    } else {
      if (!allowMotion) {
        _velocityController.stop();
        _velocityController.value = 0.0;
        if (_ticker.isActive) {
          _ticker.stop();
          _lastTick = null;
        }
      } else if (_ticker.isActive || _velocityController.value > 0.0) {
        if (!_ticker.isActive) {
          _lastTick = null;
          _ticker.start();
        }
        _velocityController
            .animateTo(
          0.0,
          duration: context.motionMs(650),
          curve: Curves.decelerate,
        )
            .whenComplete(() {
          if (mounted &&
              !widget.props.state.isPlaying &&
              _velocityController.value == 0.0) {
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
  void didUpdateWidget(covariant CdPlayerTheme oldWidget) {
    super.didUpdateWidget(oldWidget);
    final allowMotion = _allowMotion(context);
    if (widget.props.state.isPlaying != oldWidget.props.state.isPlaying) {
      if (!allowMotion) {
        _pickupController.value = widget.props.state.isPlaying ? 1.0 : 0.0;
        _glossController.value = 1.0;
      } else {
        if (widget.props.state.isPlaying) {
          _pickupController.forward();
        } else {
          _pickupController.reverse();
        }
        _sweepCaseGloss();
      }
    }
    _syncRotation(allowMotionOverride: allowMotion);
  }

  /// Replays the jewel-case highlight whenever playback starts or stops.
  ///
  /// With motion disabled the band is parked past the case instead of running,
  /// so a reduced-motion build never animates the lid.
  void _sweepCaseGloss() {
    if (!_allowMotion(context)) {
      _glossController.value = 1.0;
      return;
    }
    _glossController.forward(from: 0.0);
  }

  @override
  void dispose() {
    _ticker.dispose();
    _pickupAnimation.dispose();
    _glossController.dispose();
    _velocityController.dispose();
    _rotationController.dispose();
    _pickupController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final allowMotion = _allowMotion(context);
    if (_lastAllowMotion != allowMotion) {
      _lastAllowMotion = allowMotion;
      if (!allowMotion) {
        if (_ticker.isActive) {
          _ticker.stop();
          _lastTick = null;
        }
        _velocityController.stop();
        _velocityController.value = 0.0;
        _pickupController.stop();
        _pickupController.value = widget.props.state.isPlaying ? 1.0 : 0.0;
        _glossController.stop();
        _glossController.value = 1.0;
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _syncRotation(allowMotionOverride: allowMotion);
        });
      }
    }
    return _buildBody(context);
  }
}
