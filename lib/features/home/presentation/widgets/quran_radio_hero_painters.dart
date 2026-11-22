part of 'quran_radio_hero_carousel.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Illumination palette: manuscript gilt derived from the active theme accent,
// so ornamentation stays coherent across all ten Pulsr themes.
// ─────────────────────────────────────────────────────────────────────────────

Color _giltOf(BuildContext context) {
  final p = context.palette;
  return Color.lerp(
    p.accent,
    AppColors.giltGold,
    p.isDark ? 0.66 : 0.56,
  )!;
}

Color _onGilt(Color gilt) {
  return gilt.computeLuminance() > 0.198
      ? AppColors.onGiltDark
      : AppColors.onGiltLight;
}

// ─────────────────────────────────────────────────────────────────────────────
// Geometry: eight-pointed khatam star + pointed mihrab arch path.
// ─────────────────────────────────────────────────────────────────────────────

Path _eightPointStarPath(Offset center, double radius) {
  const points = 8;
  final inner = radius * 0.46;
  final path = Path();
  for (var i = 0; i < points * 2; i++) {
    final r = i.isEven ? radius : inner;
    final a = -math.pi / 2 + i * math.pi / points;
    final pt = Offset(
      center.dx + r * math.cos(a),
      center.dy + r * math.sin(a),
    );
    if (i == 0) {
      path.moveTo(pt.dx, pt.dy);
    } else {
      path.lineTo(pt.dx, pt.dy);
    }
  }
  path.close();
  return path;
}

Path _mihrabPath(double w, double h) {
  final shoulder = h * 0.34;
  const r = 12.0;
  final path = Path()
    ..moveTo(0, h - r)
    ..lineTo(0, shoulder)
    ..cubicTo(0, h * 0.12, w * 0.22, h * 0.045, w / 2, 0)
    ..cubicTo(w * 0.78, h * 0.045, w, h * 0.12, w, shoulder)
    ..lineTo(w, h - r)
    ..quadraticBezierTo(w, h, w - r, h)
    ..lineTo(r, h)
    ..quadraticBezierTo(0, h, 0, h - r)
    ..close();
  return path;
}

class _MihrabClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) => _mihrabPath(size.width, size.height);

  @override
  bool shouldReclip(covariant _MihrabClipper oldClipper) => false;
}

/// Gilt rim stroked over the arch aperture, with a soft broadcast glow and a
/// finial bead at the apex. [glow] animates 0→1 while the station is on air.
class _MihrabRimPainter extends CustomPainter {
  final Color color;
  final double glow;
  final TextDirection textDirection;

  const _MihrabRimPainter({
    required this.color,
    required this.glow,
    this.textDirection = TextDirection.ltr,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final path = _mihrabPath(size.width, size.height);
    final rect = Offset.zero & size;
    if (glow > 0.01) {
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5.5
          ..color = color.withValues(alpha: 0.26 * glow)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
      );
    }
    final rimShader = LinearGradient(
      begin: AlignmentDirectional.topEnd.resolve(textDirection),
      end: AlignmentDirectional.bottomStart.resolve(textDirection),
      colors: [
        color.withValues(alpha: 0.44 + 0.36 * glow),
        color.withValues(alpha: 0.28 + 0.32 * glow),
        color.withValues(alpha: 0.12 + 0.24 * glow),
      ],
      stops: const [0.0, 0.55, 1.0],
    ).createShader(rect);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.15
        ..shader = rimShader,
    );
    canvas.drawCircle(
      Offset(size.width / 2, 2.2),
      1.8,
      Paint()..color = color.withValues(alpha: 0.78 + 0.20 * glow),
    );
  }

  @override
  bool shouldRepaint(covariant _MihrabRimPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.glow != glow ||
      oldDelegate.textDirection != textDirection;
}

/// Faint eight-fold star lattice etched across the card surface — painted once
/// inside a [RepaintBoundary], never per scroll frame.
class _KhatamLatticePainter extends CustomPainter {
  static const double cell = 46.0;
  final Color color;

  const _KhatamLatticePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final star = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..color = color;
    final dot = Paint()..color = color;
    for (double y = cell / 2; y < size.height + cell; y += cell) {
      for (double x = cell / 2; x < size.width + cell; x += cell) {
        canvas.drawPath(_eightPointStarPath(Offset(x, y), cell * 0.30), star);
      }
    }
    for (double y = 0; y <= size.height + cell; y += cell) {
      for (double x = 0; x <= size.width + cell; x += cell) {
        canvas.drawCircle(Offset(x, y), 0.9, dot);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _KhatamLatticePainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Small filled eight-point star used as a station seal / ornamental glyph.
class _StarGlyph extends StatelessWidget {
  final double size;
  final Color color;

  const _StarGlyph({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _StarFillPainter(color)),
    );
  }
}

class _StarFillPainter extends CustomPainter {
  final Color color;

  const _StarFillPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      _eightPointStarPath(
        Offset(size.width / 2, size.height / 2),
        math.min(size.width, size.height) / 2,
      ),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _StarFillPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Hairline rule interrupted by a gilt diamond and flanking beads.
class _OrnamentDivider extends StatelessWidget {
  const _OrnamentDivider();

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return SizedBox(
      height: 12,
      width: double.infinity,
      child: CustomPaint(
        painter: _OrnamentDividerPainter(
          line: p.hairline,
          ornament: _giltOf(context),
        ),
      ),
    );
  }
}

class _OrnamentDividerPainter extends CustomPainter {
  final Color line;
  final Color ornament;

  const _OrnamentDividerPainter({required this.line, required this.ornament});

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    final cx = size.width / 2;
    final lp = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..color = line;
    canvas.drawLine(Offset(0, y), Offset(cx - 14, y), lp);
    canvas.drawLine(Offset(cx + 14, y), Offset(size.width, y), lp);
    final diamond = Path()
      ..moveTo(cx, y - 4)
      ..lineTo(cx + 4, y)
      ..lineTo(cx, y + 4)
      ..lineTo(cx - 4, y)
      ..close();
    canvas.drawPath(diamond, Paint()..color = ornament);
    final bead = Paint()..color = ornament.withValues(alpha: 0.7);
    canvas.drawCircle(Offset(cx - 9, y), 1.1, bead);
    canvas.drawCircle(Offset(cx + 9, y), 1.1, bead);
  }

  @override
  bool shouldRepaint(covariant _OrnamentDividerPainter oldDelegate) =>
      oldDelegate.line != line || oldDelegate.ornament != ornament;
}

/// Miniature arch-framed artwork used in the options sheet header.
class _ArchThumb extends StatelessWidget {
  final QuranHeroItem item;
  final double width;
  final double height;

  const _ArchThumb({
    required this.item,
    required this.width,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final isNetwork = item.artworkAsset.startsWith('http://') ||
        item.artworkAsset.startsWith('https://');
    final isHomeCard = item.artworkAsset.contains('home card') ||
        item.artworkAsset.contains('home_card');
    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipPath(
            clipper: _MihrabClipper(),
            child: isNetwork
                ? CachedArtwork(
                    id: 0,
                    remoteUrl: item.artworkAsset,
                    size: width,
                    fallbackIcon: Icons.radio_rounded,
                  )
                : Image.asset(
                    item.artworkAsset,
                    fit: BoxFit.cover,
                    alignment: isHomeCard
                        ? Alignment.centerRight
                        : const Alignment(0.0, -0.15),
                    errorBuilder: (_, __, ___) => Container(
                      color: p.accentContainer.withValues(alpha: 0.2),
                      child: Icon(
                        Icons.radio_rounded,
                        size: 20,
                        color: p.accent.withValues(alpha: 0.4),
                      ),
                    ),
                  ),
          ),
          IgnorePointer(
            child: CustomPaint(
              painter: _MihrabRimPainter(
                color: _giltOf(context),
                glow: 0,
                textDirection: Directionality.of(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Tactile pill selector for radio card sorting options inside the long-press sheet.
class _SortOptionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SortOptionChip({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Expanded(
      child: Material(
        color: AppColors.fadeStopTransparent,
        borderRadius: AppRadii.r12All,
        child: InkWell(
          borderRadius: AppRadii.r12All,
          onTap: onTap,
          child: AnimatedContainer(
            duration: context.motion(PulsrMotion.layout),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            decoration: BoxDecoration(
              color: selected
                  ? p.accent.withValues(alpha: 0.16)
                  : p.surfaceContainerHigh.withValues(alpha: 0.55),
              borderRadius: AppRadii.r12All,
              border: Border.all(
                color: selected ? p.accent.withValues(alpha: 0.60) : p.hairline,
                width: selected ? 1.2 : 0.8,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: selected ? p.accent : p.textSecondary,
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected ? p.accent : p.textPrimary,
                    fontSize: AppFontSize.caption,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Bounded sliding-window indicator: gilt lozenge for the active page,
/// rotated-square diamonds for the rest, faded micro-diamonds at clipped edges.
class _CarouselWindowedDots extends StatelessWidget {
  final int total;
  final int currentPage;
  final ValueChanged<int> onDotTap;

  const _CarouselWindowedDots({
    required this.total,
    required this.currentPage,
    required this.onDotTap,
  });

  static const int _maxVisible = 7;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final gilt = _giltOf(context);
    if (total <= 0) return const SizedBox.shrink();
    final visibleCount = math.min(total, _maxVisible);
    final half = visibleCount ~/ 2;
    final start = total <= _maxVisible
        ? 0
        : (currentPage - half).clamp(0, total - visibleCount);
    final end = start + visibleCount;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = start; i < end; i++)
          Builder(
            builder: (context) {
              final isActive = i == currentPage;
              final isEdgeClipped =
                  (i == start && start > 0) || (i == end - 1 && end < total);
              final dotSize = isEdgeClipped ? 3.0 : 4.2;
              Widget glyph = AnimatedContainer(
                duration: context.motion(PulsrMotion.layout),
                curve: context.motionCurve(PulsrMotion.enter),
                width: isActive ? 18.0 : dotSize,
                height: isActive ? 4.5 : dotSize,
                decoration: BoxDecoration(
                  color: isActive
                      ? null
                      : p.textTertiary
                          .withValues(alpha: isEdgeClipped ? 0.20 : 0.34),
                  gradient: isActive
                      ? LinearGradient(
                          begin: AlignmentDirectional.centerStart,
                          end: AlignmentDirectional.centerEnd,
                          colors: [
                            Color.alphaBlend(
                              AppColors.specularAt(0.18),
                              gilt,
                            ),
                            gilt,
                          ],
                        )
                      : null,
                  borderRadius: BorderRadius.circular(isActive ? 999 : 1.0),
                  boxShadow: isActive
                      ? [
                          BoxShadow(
                            color: gilt.withValues(alpha: 0.28),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          ),
                        ]
                      : null,
                ),
              );
              if (!isActive) {
                glyph = Transform.rotate(angle: math.pi / 4, child: glyph);
              }
              return Semantics(
                button: true,
                label: '${i + 1} / $total',
                child: GestureDetector(
                  onTap: () => onDotTap(i),
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 2.5,
                      vertical: 4.0,
                    ),
                    child: glyph,
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}

/// Pulsing dot indicating live broadcast in theme accent color.
class _PulsingLiveDot extends StatefulWidget {
  const _PulsingLiveDot();

  @override
  State<_PulsingLiveDot> createState() => _PulsingLiveDotState();
}

class _PulsingLiveDotState extends State<_PulsingLiveDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (PulsrMotion.shouldAnimate(context) && context.motionEnabled) {
      if (!_controller.isAnimating) {
        _controller.repeat(reverse: true);
      }
    } else {
      _controller.stop();
      _controller.value = 1.0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dotColor = context.palette.accent;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final alpha = 0.5 + (_controller.value * 0.5);
        return Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            color: dotColor.withValues(alpha: alpha),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: dotColor.withValues(alpha: _controller.value * 0.7),
                blurRadius: 4,
                spreadRadius: 1,
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Mini animated 4-bar equalizer that pulses smoothly when live audio plays.
class _MiniEqualizerBars extends StatefulWidget {
  final bool isPlaying;
  final Color? color;

  const _MiniEqualizerBars({required this.isPlaying, this.color});

  @override
  State<_MiniEqualizerBars> createState() => _MiniEqualizerBarsState();
}

class _MiniEqualizerBarsState extends State<_MiniEqualizerBars>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAnimation();
  }

  void _syncAnimation() {
    if (widget.isPlaying &&
        PulsrMotion.shouldAnimate(context) &&
        context.motionEnabled) {
      if (!_anim.isAnimating) {
        _anim.repeat();
      }
    } else {
      _anim.stop();
      _anim.reset();
    }
  }

  @override
  void didUpdateWidget(covariant _MiniEqualizerBars oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying != oldWidget.isPlaying) {
      _syncAnimation();
    }
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final barColor = widget.color ?? p.accent;
    return AnimatedBuilder(
      animation: _anim,
      builder: (context, child) {
        final t = _anim.value * 2 * math.pi;
        final h1 =
            widget.isPlaying ? (5.0 + 7.0 * (0.5 + 0.5 * math.sin(t))) : 4.0;
        final h2 = widget.isPlaying
            ? (5.0 + 9.0 * (0.5 + 0.5 * math.sin(t + 1.2)))
            : 7.0;
        final h3 = widget.isPlaying
            ? (4.0 + 8.0 * (0.5 + 0.5 * math.sin(t + 2.5)))
            : 5.0;
        final h4 = widget.isPlaying
            ? (5.0 + 6.0 * (0.5 + 0.5 * math.sin(t + 3.8)))
            : 6.0;
        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _buildBar(h1, barColor),
            const SizedBox(width: 2.2),
            _buildBar(h2, barColor),
            const SizedBox(width: 2.2),
            _buildBar(h3, barColor),
            const SizedBox(width: 2.2),
            _buildBar(h4, barColor),
          ],
        );
      },
    );
  }

  Widget _buildBar(double height, Color color) {
    return Container(
      width: 2.5,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(1.5),
      ),
    );
  }
}
