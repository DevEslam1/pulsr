// lib/features/player/presentation/themes/vinyl_player_theme.dart
import 'dart:math' as math;

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
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
import '../../../../core/utils/adaptive.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../core/utils/pulsr_haptics.dart';
import '../../../../core/widgets/cached_artwork.dart';
import '../../../../core/widgets/marquee_text.dart';
import '../../../../core/widgets/pulsr_slider.dart';
import '../../../../core/widgets/pulsr_toast.dart';
import '../../../../data/db/app_database.dart';
import '../../../../data/services/cast_service.dart';
import '../../../../domain/models/audio_output_info.dart';
import '../../../settings/cubit/settings_cubit.dart';
import '../../../settings/cubit/settings_state.dart';
import '../../../sheets/add_to_playlist_sheet.dart';
import '../../../sheets/song_options_sheet.dart';
import '../../../ytm_search/presentation/widgets/ytm_download_button.dart';
import '../../cubit/player_cubit.dart';
import '../../cubit/player_state.dart';
import '../widgets/audio_quality_sheet.dart';
import '../widgets/audio_visualizer.dart';
import '../widgets/player_gesture_scope.dart';
import '../widgets/player_volume_bar.dart';
import '../widgets/radio_now_playing_recommendations.dart';
import '../widgets/waveform_seek_bar.dart';
import 'painters/platter_scrub.dart';
import 'player_shape.dart';
import 'player_theme.dart';
import 'player_theme_chrome.dart';
import 'player_theme_scaffold.dart' show PlayerThemePreviewScope;

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
  late final AnimationController _velocityController;
  late final AnimationController _tonearmController;
  late final CurvedAnimation _tonearmAnimation;
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

    _tonearmController = AnimationController(
      vsync: this,
      duration: Duration.zero,
      value: widget.props.state.isPlaying ? 1.0 : 0.0,
    );

    _tonearmAnimation = CurvedAnimation(
      parent: _tonearmController,
      curve: Curves.easeInOutCubic,
      reverseCurve: Curves.easeInOutCubic,
    );
  }

  bool _allowMotion(BuildContext context) =>
      !PlayerThemePreviewScope.of(context) &&
      PulsrMotion.shouldAnimate(context) &&
      context.motionEnabled;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _tonearmController.duration = context.motionMs(400);
    _velocityController.duration = context.motionMs(650);
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
        _velocityController.stop();
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
  void didUpdateWidget(covariant VinylPlayerTheme oldWidget) {
    super.didUpdateWidget(oldWidget);
    final allowMotion = _allowMotion(context);
    if (widget.props.state.isPlaying != oldWidget.props.state.isPlaying) {
      if (!allowMotion) {
        _tonearmController.stop();
        _tonearmController.value = widget.props.state.isPlaying ? 1.0 : 0.0;
      } else if (widget.props.state.isPlaying) {
        _tonearmController.forward();
      } else {
        _tonearmController.reverse();
      }
    }
    _syncRotation(allowMotionOverride: allowMotion);
  }

  @override
  void dispose() {
    _tonearmAnimation.dispose();
    _velocityController.dispose();
    _rotationController.dispose();
    _tonearmController.dispose();
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
        _velocityController.stop();
        _velocityController.value = 0.0;
        _tonearmController.stop();
        _tonearmController.value = widget.props.state.isPlaying ? 1.0 : 0.0;
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _syncRotation(allowMotionOverride: allowMotion);
        });
      }
    }
    return _buildBody(context);
  }
}
