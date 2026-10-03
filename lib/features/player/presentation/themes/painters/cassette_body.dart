part of '../cassette_player_theme.dart';

/// Cassette shell hero stage with spinning spools and label.
class _CassetteBody extends StatelessWidget {
  final SongsTableData? song;
  final Color activeColor;
  final AnimationController spoolController;
  final bool isLandscape;
  final bool isTablet;

  const _CassetteBody({
    required this.song,
    required this.activeColor,
    required this.spoolController,
    required this.isLandscape,
    required this.isTablet,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: isLandscape ? 260 : (isTablet ? 360 : 300),
          maxWidth: isLandscape ? 390 : (isTablet ? 540 : 440),
        ),
        child: AspectRatio(
          aspectRatio: 1.5,
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.s14),
            decoration: BoxDecoration(
              color: const Color(0xFF1E2028),
              borderRadius: BorderRadius.circular(AppRadii.r20),
              border: Border.all(color: const Color(0xFF323646), width: 3),
              boxShadow: [
                BoxShadow(
                  color: AppColors.scrimAt(0.5),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              children: [
                // Cassette Label Header
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm, vertical: AppSpacing.s6),
                  decoration: BoxDecoration(
                    color: activeColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(AppRadii.r8),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        context.l10n.cassetteSideA,
                        style: const TextStyle(
                          fontSize: AppFontSize.tiny,
                          fontWeight: FontWeight.w700,
                          color: Colors.white70,
                          letterSpacing: AppTracking.wide,
                        ),
                      ),
                      Text(
                        context.l10n.cassettePulsrTape,
                        style: TextStyle(
                          fontSize: AppFontSize.tiny,
                          fontWeight: FontWeight.w900,
                          color: activeColor,
                          letterSpacing: AppTracking.wide,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),

                // Cassette Center Window with Spinning Spools
                Expanded(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: AppSpacing.s20),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F1116),
                      borderRadius: BorderRadius.circular(AppRadii.r12),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Left Spool
                        _buildSpool(),
                        // Center Tape Window
                        Container(
                          width: 70,
                          height: 36,
                          decoration: BoxDecoration(
                            color: AppColors.specularAt(0.05),
                            borderRadius: BorderRadius.circular(AppRadii.r6),
                            border: Border.all(color: Colors.white10),
                          ),
                          child: Center(
                            child: Container(
                              height: 12,
                              width: 50,
                              color: const Color(0xFF5A3825),
                            ),
                          ),
                        ),
                        // Right Spool
                        _buildSpool(),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),

                // Track Title on Cassette Body
                Text(
                  song?.title ?? context.l10n.dspTapeLoaded,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: AppFontSize.label,
                    fontWeight: FontWeight.w700,
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSpool() {
    return RotationTransition(
      turns: spoolController,
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white,
          border: Border.all(color: Colors.grey.shade400, width: 3),
        ),
        child: Center(
          child: Container(
            width: 22,
            height: 22,
            decoration: const BoxDecoration(
              color: Color(0xFF0F1116),
              shape: BoxShape.circle,
            ),
            child: CustomPaint(painter: _SpoolTeethPainter()),
          ),
        ),
      ),
    );
  }
}

class _SpoolTeethPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 2.0;

    for (int i = 0; i < 6; i++) {
      final angle = i * (math.pi / 3);
      final p1 = Offset(
        center.dx + 4 * math.cos(angle),
        center.dy + 4 * math.sin(angle),
      );
      final p2 = Offset(
        center.dx + 10 * math.cos(angle),
        center.dy + 10 * math.sin(angle),
      );
      canvas.drawLine(p1, p2, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
