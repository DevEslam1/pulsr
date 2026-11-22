import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:pulsr/core/constants/app_colors.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_typography.dart';
import 'package:pulsr/core/motion/pulsr_motion.dart';
import 'package:pulsr/core/responsive/responsive_values.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/core/utils/adaptive.dart';

/// Scales a crisp single-line card title box (20px phone / 22px tablet at
/// default text scale) with the user's Dynamic Type setting so large text
/// never clips and single-line titles never push the artist subtitle down
/// with an empty second-line gap.
double scaledTitleBoxHeight(BuildContext context) {
  final base = Adaptive.isTablet(context) ? 22.0 : 20.0;
  return MediaQuery.textScalerOf(context).scale(base).clamp(base, 64.0);
}

/// Dynamically calculates the carousel height to comfortably fit framed card
/// artwork, single-line bold title, muted artist subtitle, and elevation
/// breathing room without overflowing at 100%–300% text scale.
double scaledCarouselHeight(BuildContext context, bool isTablet) {
  final cardWidth =
      context.responsive.value(compact: 138.0, medium: 150.0, expanded: 158.0);
  final titleHeight = scaledTitleBoxHeight(context);
  final artistScale =
      MediaQuery.textScalerOf(context).scale(AppFontSize.caption);
  final artistHeight = artistScale * 1.4;
  return cardWidth +
      AppSpacing.xs +
      titleHeight +
      AppSpacing.s2 +
      artistHeight +
      AppSpacing.sm;
}

/// Frames square home-carousel cover artwork with subtle physical elevation and
/// a crisp 1px inner hairline sheen so both bright white and deep dark covers
/// sit cleanly against light, dark, and AMOLED surfaces.
class HomeCardArtworkFrame extends StatelessWidget {
  final Widget child;
  final double radius;

  const HomeCardArtworkFrame({
    super.key,
    required this.child,
    this.radius = AppRadii.r18,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final borderRadius = AppRadii.circular(radius);
    return Container(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: PulsrElevation.level1(context),
      ),
      foregroundDecoration: BoxDecoration(
        borderRadius: borderRadius,
        border: Border.all(
          color: p.hairline,
          width: 1.0,
        ),
      ),
      child: child,
    );
  }
}

/// Refined frosted/scrim-backed circular corner play badge for Home carousel
/// cards. Uses a zero-saveLayer translucent tinted surface with a crisp hairline
/// specular border, and an animated accent equalizer when the track is playing.
class HomeCardPlayBadge extends StatelessWidget {
  final bool isCurrent;
  final bool isPlaying;
  final double size;

  const HomeCardPlayBadge({
    super.key,
    this.isCurrent = false,
    this.isPlaying = false,
    this.size = 34.0,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final isActivePlaying = isCurrent && isPlaying;

    final Color fillColor;
    final Color borderColor;
    final double borderWidth;
    final List<BoxShadow> shadows;

    if (isActivePlaying) {
      fillColor = p.accent.withValues(alpha: 0.95);
      borderColor = AppColors.specularAt(0.35);
      borderWidth = 1.0;
      shadows = [
        ...PulsrElevation.level1(context),
        if (!p.isCalmDensity)
          BoxShadow(
            color: p.accent.withValues(alpha: 0.34 * p.chromeGlowScale),
            blurRadius: 10,
            spreadRadius: -1,
          ),
      ];
    } else if (isCurrent) {
      fillColor = AppColors.scrimAt(0.78);
      borderColor = p.accent.withValues(alpha: 0.90);
      borderWidth = 1.5;
      shadows = PulsrElevation.level1(context);
    } else {
      fillColor = AppColors.scrimAt(0.68);
      borderColor = AppColors.specularAt(0.32);
      borderWidth = 1.0;
      shadows = PulsrElevation.level1(context);
    }

    final Widget glyph = AnimatedSwitcher(
      duration: context.motion(PulsrMotion.state),
      switchInCurve: context.motionCurve(PulsrMotion.enter),
      switchOutCurve: context.motionCurve(PulsrMotion.exit),
      child: isActivePlaying
          ? _CardEqualizerBars(
              key: const ValueKey('eq'),
              isPlaying: true,
              color: p.onAccent,
            )
          : Icon(
              Icons.play_arrow_rounded,
              key: const ValueKey('play'),
              color: AppColors.fadeStopOpaque,
              size: 20,
            ),
    );

    final Widget badgeBody = AnimatedContainer(
      duration: context.motion(PulsrMotion.state),
      curve: context.motionCurve(PulsrMotion.move),
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: fillColor,
        shape: BoxShape.circle,
        border: Border.all(
          color: borderColor,
          width: borderWidth,
        ),
      ),
      child: Center(child: glyph),
    );

    return ExcludeSemantics(
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: shadows,
        ),
        child: ClipOval(child: badgeBody),
      ),
    );
  }
}

/// Compact 3-bar equalizer indicator for the currently playing Home card.
class _CardEqualizerBars extends StatefulWidget {
  final bool isPlaying;
  final Color color;

  const _CardEqualizerBars({
    super.key,
    required this.isPlaying,
    required this.color,
  });

  @override
  State<_CardEqualizerBars> createState() => _CardEqualizerBarsState();
}

class _CardEqualizerBarsState extends State<_CardEqualizerBars>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant _CardEqualizerBars oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isPlaying != widget.isPlaying) {
      _syncAnimation();
    }
  }

  void _syncAnimation() {
    if (widget.isPlaying &&
        PulsrMotion.shouldAnimate(context) &&
        context.motionEnabled) {
      if (!_controller.isAnimating) {
        _controller.repeat();
      }
    } else {
      _controller.stop();
      _controller.reset();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value * 2 * math.pi;
        final animate = widget.isPlaying && _controller.isAnimating;
        final h1 = animate ? (5.0 + 6.0 * (0.5 + 0.5 * math.sin(t))) : 6.0;
        final h2 =
            animate ? (6.0 + 7.0 * (0.5 + 0.5 * math.sin(t + 1.5))) : 11.0;
        final h3 =
            animate ? (5.0 + 6.0 * (0.5 + 0.5 * math.sin(t + 3.0))) : 8.0;
        return SizedBox(
          height: 14,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _bar(h1),
              const SizedBox(width: 2.2),
              _bar(h2),
              const SizedBox(width: 2.2),
              _bar(h3),
            ],
          ),
        );
      },
    );
  }

  Widget _bar(double height) {
    return Container(
      width: 2.6,
      height: height,
      decoration: BoxDecoration(
        color: widget.color,
        borderRadius: AppRadii.r1_5All,
      ),
    );
  }
}
