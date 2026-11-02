// lib/core/widgets/spinning_vinyl_disc.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import '../constants/app_colors.dart';
import '../motion/pulsr_motion.dart';
import '../utils/l10n_extensions.dart';
import '../widgets/cached_artwork.dart';

/// {@category DesignSystem}
/// An animated vinyl record disc that smoothly rotates when [isPlaying] is true
/// and halts when false. Concentric micro-grooves and anisotropic light reflection
/// provide a tactile analog aesthetic matching Pulsr's glass & dark/AMOLED UI.
class SpinningVinylDisc extends StatefulWidget {
  final int id;
  final String? remoteArtworkUrl;
  final double size;
  final bool isPlaying;
  final Duration rotationPeriod;
  final VoidCallback? onTap;

  const SpinningVinylDisc({
    super.key,
    required this.id,
    this.remoteArtworkUrl,
    this.size = 48.0,
    this.isPlaying = true,
    this.rotationPeriod = const Duration(seconds: 12),
    this.onTap,
  });

  @override
  State<SpinningVinylDisc> createState() => _SpinningVinylDiscState();
}

class _SpinningVinylDiscState extends State<SpinningVinylDisc>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.rotationPeriod,
    );
  }

  void _syncAnimation() {
    final shouldSpin = widget.isPlaying && context.motionEnabled;
    if (shouldSpin && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!shouldSpin && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant SpinningVinylDisc oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.rotationPeriod != widget.rotationPeriod) {
      _controller.duration = widget.rotationPeriod;
    }
    _syncAnimation();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final discSize = widget.size;
    final labelSize = discSize * 0.44;
    final spindleSize = discSize * 0.085;

    final content = RepaintBoundary(
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          width: discSize,
          height: discSize,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.vinylDiscBase,
            boxShadow: const [
              BoxShadow(
                color: AppColors.scrimLight,
                blurRadius: 10,
                offset: Offset(0, 3),
              ),
            ],
            border: Border.all(
              color: AppColors.vinylDiscRim,
              width: 1.2,
            ),
          ),
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return Transform.rotate(
                angle: _controller.value * 2 * math.pi,
                child: child,
              );
            },
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Concentric micro-grooves + anisotropic vinyl luster
                CustomPaint(
                  size: Size(discSize, discSize),
                  painter: const _VinylGroovePainter(),
                ),

                // Center album art label with recessed collar
                Container(
                  width: labelSize + 3.0,
                  height: labelSize + 3.0,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.black.withValues(alpha: 0.55),
                  ),
                ),

                ClipOval(
                  child: SizedBox(
                    width: labelSize,
                    height: labelSize,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        CachedArtwork(
                          id: widget.id,
                          remoteUrl: widget.remoteArtworkUrl,
                          type: ArtworkType.AUDIO,
                          size: labelSize,
                          borderRadius: 999,
                          fallbackIcon: Icons.music_note_rounded,
                        ),
                        // Inner label rim border
                        Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppColors.specularAt(0.28),
                              width: 1.0,
                            ),
                          ),
                        ),
                        // Metallic Center Spindle Ring & Hole
                        Container(
                          width: spindleSize * 1.45,
                          height: spindleSize * 1.45,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.specularAt(0.22),
                          ),
                        ),
                        Container(
                          width: spindleSize,
                          height: spindleSize,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.vinylSpindle,
                            border: Border.all(
                              color: AppColors.specularAt(0.45),
                              width: 0.7,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (widget.onTap == null) {
      return ExcludeSemantics(child: content);
    }
    return Semantics(
      button: true,
      label: context.l10n.vinylDisc,
      child: content,
    );
  }
}

class _VinylGroovePainter extends CustomPainter {
  const _VinylGroovePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = (size.width / 2) - 1.2;
    final minRadius = maxRadius * 0.47;
    if (maxRadius <= minRadius) return;

    // 1. Subtle dual-cone anisotropic reflection across the vinyl surface
    final rect = Rect.fromCircle(center: center, radius: maxRadius);
    final sheenPaint = Paint()
      ..shader = SweepGradient(
        colors: [
          Colors.transparent,
          Colors.white.withValues(alpha: 0.06),
          Colors.transparent,
          Colors.transparent,
          Colors.white.withValues(alpha: 0.06),
          Colors.transparent,
        ],
        stops: const [0.0, 0.14, 0.30, 0.50, 0.64, 0.80],
      ).createShader(rect);
    canvas.drawCircle(center, maxRadius, sheenPaint);

    // 2. Concentric micro-grooves
    final groovePaint = Paint()
      ..color = AppColors.highlightSoft
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6;

    final accentGroovePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.09)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;

    final ringSteps = math.max(3, (maxRadius - minRadius) ~/ 3.2);
    for (int i = 1; i <= ringSteps; i++) {
      final r = minRadius + (maxRadius - minRadius) * (i / ringSteps);
      canvas.drawCircle(
        center,
        r,
        (i == 1 || i == ringSteps || i == ringSteps ~/ 2)
            ? accentGroovePaint
            : groovePaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
