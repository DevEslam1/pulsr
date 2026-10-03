part of '../circle_player_theme.dart';

/// Spinning vinyl-disc hero stage with centre artwork.
class _CircleArtwork extends StatelessWidget {
  final SongsTableData? song;
  final Color activeColor;
  final AnimationController rotationController;
  final bool isTablet;
  final bool isLandscape;

  const _CircleArtwork({
    required this.song,
    required this.activeColor,
    required this.rotationController,
    required this.isTablet,
    required this.isLandscape,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final currentSong = song;
    return RotationTransition(
      turns: rotationController,
      child: LayoutBuilder(
        builder: (context, vinylConstraints) {
          final maxDimension = isLandscape ? 300.0 : (isTablet ? 540.0 : 420.0);
          final vinylSize = math.min(
            math.min(vinylConstraints.maxWidth, vinylConstraints.maxHeight) *
                0.95,
            maxDimension,
          );
          return Container(
            width: vinylSize,
            height: vinylSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF121212),
              border: Border.all(
                color: p.hairline.withValues(alpha: 0.6),
                width: 3,
              ),
              boxShadow: [
                BoxShadow(
                  color: activeColor.withValues(alpha: 0.35),
                  blurRadius: 36,
                  spreadRadius: 4,
                ),
              ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Outer vinyl grooves
                CustomPaint(
                  size: Size(vinylSize, vinylSize),
                  painter: _VinylGroovesPainter(),
                ),
                // Center circular artwork
                Container(
                  width: vinylSize * 0.58,
                  height: vinylSize * 0.58,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white24,
                      width: 2,
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: currentSong != null
                      ? CachedArtwork(
                          id: currentSong.id,
                          albumId: currentSong.albumId,
                          remoteUrl: currentSong.remoteArtworkUrl ??
                              currentSong.artworkUri,
                          type: ArtworkType.AUDIO,
                          size: vinylSize * 0.58,
                          borderRadius: 999,
                          highQuality: true,
                        )
                      : Icon(
                          Icons.album_rounded,
                          size: vinylSize * 0.25,
                          color: Colors.white54,
                        ),
                ),
                // Center Spindle Hole
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: p.bg,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white38,
                      width: 2,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _VinylGroovesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    final groovePaint = Paint()
      ..color = AppColors.highlightSoft
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    for (double r = radius * 0.58; r < radius - 8; r += 8) {
      canvas.drawCircle(center, r, groovePaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
