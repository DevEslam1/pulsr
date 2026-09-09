import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import '../widgets/cached_artwork.dart';

/// An animated vinyl record disc that smoothly rotates when [isPlaying] is true
/// and halts when false. Concentric micro-grooves and light reflection provide a
/// tactile analog aesthetic matching Pulsr's glass & dark/AMOLED UI.
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
    if (widget.isPlaying) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant SpinningVinylDisc oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.isPlaying && _controller.isAnimating) {
      _controller.stop();
    }
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
    final spindleSize = discSize * 0.08;

    return GestureDetector(
      onTap: widget.onTap,
      child: SizedBox(
        width: discSize,
        height: discSize,
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
              // Outer vinyl record with dark grooves
              Container(
                width: discSize,
                height: discSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF0D0E12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.45),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                  border: Border.all(
                    color: const Color(0xFF1E2028),
                    width: 1.2,
                  ),
                ),
                child: CustomPaint(
                  size: Size(discSize, discSize),
                  painter: _VinylGroovePainter(),
                ),
              ),

              // Specular reflection gradient sheen
              Container(
                width: discSize,
                height: discSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: SweepGradient(
                    center: Alignment.center,
                    colors: [
                      Colors.transparent,
                      Colors.white.withValues(alpha: 0.06),
                      Colors.transparent,
                      Colors.white.withValues(alpha: 0.04),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.25, 0.5, 0.75, 1.0],
                  ),
                ),
              ),

              // Center album art label
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
                            color: Colors.white.withValues(alpha: 0.25),
                            width: 1.0,
                          ),
                        ),
                      ),
                      // Center Spindle Hole
                      Container(
                        width: spindleSize,
                        height: spindleSize,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFF090A0D),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.4),
                            width: 0.6,
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
    );
  }
}

class _VinylGroovePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width / 2;
    final minRadius = maxRadius * 0.48;

    final groovePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.04)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6;

    final ringSteps = math.max(3, (maxRadius - minRadius) ~/ 3.5);
    for (int i = 1; i <= ringSteps; i++) {
      final r = minRadius + (maxRadius - minRadius) * (i / ringSteps);
      canvas.drawCircle(center, r, groovePaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
