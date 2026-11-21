// lib/features/player/presentation/themes/cd_player_theme.dart
import 'dart:math' as math;
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:on_audio_query/on_audio_query.dart';
import '../../../../core/motion/pulsr_motion.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/theme/player_material_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/utils/adaptive.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../core/widgets/cached_artwork.dart';
import '../../../../data/db/app_database.dart';
import '../../cubit/player_cubit.dart';
import '../../cubit/player_state.dart';
import '../../../settings/cubit/settings_cubit.dart';
import '../widgets/audio_visualizer.dart';
import '../widgets/player_gesture_scope.dart';
import 'painters/platter_scrub.dart';
import 'player_shape.dart';
import 'player_theme.dart';
import 'player_theme_chrome.dart';
import 'player_theme_scaffold.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_colors.dart';
import '../../../../core/performance/gpu_budget.dart';

part 'painters/cd_stage.dart';
part 'painters/cd_painters.dart';
part 'parts/cd_player_theme_build.dart';

/// CD Jewel Case Player Theme:
/// A rotating iridescent compact disc seated in a translucent jewel case, with
/// a hinge spine, recessed tray, spider hub, VFD read-out and an optical pickup
/// sled that lights up while playing. Deliberately unlike the vinyl plinth: no
/// tonearm, no strobe rim, no RPM badge.
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
  }

  bool _allowMotion(BuildContext context) =>
      PulsrMotion.shouldAnimate(context) && context.motionEnabled;

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
      if (!_rotationController.isAnimating) {
        _rotationController.repeat();
      }
      _velocityController.animateTo(
        1.0,
        duration: context.motionMs(650),
        curve: Curves.easeOutCubic,
      );
    } else {
      if (!allowMotion) {
        _velocityController.value = 0.0;
        if (_rotationController.isAnimating) {
          _rotationController.stop();
        }
      } else if (_rotationController.isAnimating) {
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
            _rotationController.stop();
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
        if (_rotationController.isAnimating) {
          _rotationController.stop();
        }
        _velocityController.value = 0.0;
        _pickupController.value = widget.props.state.isPlaying ? 1.0 : 0.0;
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
