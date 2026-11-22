// lib/core/widgets/mesh_gradient_placeholder.dart
import 'dart:math' as math;
import 'package:material_ui/material_ui.dart';
import '../constants/app_radii.dart';

/// {@category DesignSystem}
/// Dynamic, deterministic, tasteful seeded mesh-gradient artwork placeholder.
///
/// Incorporates subtle track initials or category glyph, seeded by song
/// title/artist/id, providing vibrant and unique artwork placeholders even
/// before album art is cached or backfilled.
class MeshGradientPlaceholder extends StatelessWidget {
  final double size;
  final double borderRadius;
  final IconData? icon;
  final int? seed;
  final String? title;
  final String? artist;

  const MeshGradientPlaceholder({
    super.key,
    this.size = 56.0,
    this.borderRadius = 12.0,
    this.icon,
    this.seed,
    this.title,
    this.artist,
  });

  /// Computes a stable 32-bit integer seed from track metadata.
  static int computeSeed({int? seed, String? title, String? artist}) {
    var h = (seed ?? 0).abs();
    if (title != null && title.isNotEmpty) {
      for (var i = 0; i < title.length; i++) {
        h = ((h * 31) + title.codeUnitAt(i)) & 0x7FFFFFFF;
      }
    }
    if (artist != null && artist.isNotEmpty) {
      for (var i = 0; i < artist.length; i++) {
        h = ((h * 37) + artist.codeUnitAt(i)) & 0x7FFFFFFF;
      }
    }
    return h == 0 ? 42 : h;
  }

  /// Extracts 1 or 2 subtle track initials from title and artist.
  static String extractInitials({String? title, String? artist}) {
    String clean(String s) {
      var text = s.replaceAll(RegExp(r'\([^)]*\)|\[[^\]]*\]'), '').trim();
      text = text.replaceAll(
          RegExp(r'^[^\w\u0600-\u06FF]+|[^\w\u0600-\u06FF]+$'), '');
      return text;
    }

    final cleanTitle = clean(title ?? '');
    final cleanArtist = clean(artist ?? '');

    final titleWords = cleanTitle
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();

    if (titleWords.isEmpty) {
      if (cleanArtist.isNotEmpty) {
        final artistWords = cleanArtist
            .split(RegExp(r'\s+'))
            .where((w) => w.isNotEmpty)
            .toList();
        if (artistWords.length >= 2) {
          final first = artistWords[0].characters.first;
          final second = artistWords[1].characters.first;
          return '$first$second'.toUpperCase();
        } else if (artistWords.isNotEmpty) {
          final word = artistWords[0];
          return word.substring(0, math.min(2, word.length)).toUpperCase();
        }
      }
      return '';
    }

    if (titleWords.length >= 2) {
      final first = titleWords[0].characters.first;
      final second = titleWords[1].characters.first;
      return '$first$second'.toUpperCase();
    } else {
      final word = titleWords[0];
      return (word.length >= 2 ? word.substring(0, 2) : word).toUpperCase();
    }
  }

  static const List<_MeshPalette> _palettes = [
    // 0: Deep Indigo & Cyan
    _MeshPalette(
      background: Color(0xFF0F172A),
      primary: Color(0xFF4338CA),
      secondary: Color(0xFF06B6D4),
      tertiary: Color(0xFF818CF8),
    ),
    // 1: Midnight Violet & Magenta
    _MeshPalette(
      background: Color(0xFF1E0B2B),
      primary: Color(0xFF7E22CE),
      secondary: Color(0xFFE11D48),
      tertiary: Color(0xFFC084FC),
    ),
    // 2: Oceanic Emerald & Mint
    _MeshPalette(
      background: Color(0xFF022C22),
      primary: Color(0xFF059669),
      secondary: Color(0xFF14B8A6),
      tertiary: Color(0xFF34D399),
    ),
    // 3: Dark Amber & Tangerine
    _MeshPalette(
      background: Color(0xFF271305),
      primary: Color(0xFFB45309),
      secondary: Color(0xFFEA580C),
      tertiary: Color(0xFFFBBF24),
    ),
    // 4: Royal Blue & Electric Purple
    _MeshPalette(
      background: Color(0xFF0B192C),
      primary: Color(0xFF1D4ED8),
      secondary: Color(0xFF7C3AED),
      tertiary: Color(0xFF60A5FA),
    ),
    // 5: Crimson Noir & Rose
    _MeshPalette(
      background: Color(0xFF23070E),
      primary: Color(0xFF9F1239),
      secondary: Color(0xFFF43F5E),
      tertiary: Color(0xFFFDA4AF),
    ),
    // 6: Deep Teal & Lime
    _MeshPalette(
      background: Color(0xFF042F2E),
      primary: Color(0xFF0F766E),
      secondary: Color(0xFF84CC16),
      tertiary: Color(0xFF2DD4BF),
    ),
    // 7: Plum & Bubblegum
    _MeshPalette(
      background: Color(0xFF240A28),
      primary: Color(0xFF86198F),
      secondary: Color(0xFFD946EF),
      tertiary: Color(0xFFF0ABFC),
    ),
    // 8: Obsidian & Ice Azure
    _MeshPalette(
      background: Color(0xFF0A1120),
      primary: Color(0xFF0369A1),
      secondary: Color(0xFF38BDF8),
      tertiary: Color(0xFF7DD3FC),
    ),
    // 9: Blackberry & Gold
    _MeshPalette(
      background: Color(0xFF1A0B2E),
      primary: Color(0xFF5B21B6),
      secondary: Color(0xFFD97706),
      tertiary: Color(0xFFFDE68A),
    ),
    // 10: Forest & Chartreuse
    _MeshPalette(
      background: Color(0xFF062816),
      primary: Color(0xFF15803D),
      secondary: Color(0xFF65A30D),
      tertiary: Color(0xFF4ADE80),
    ),
    // 11: Amethyst & Peach
    _MeshPalette(
      background: Color(0xFF1F1135),
      primary: Color(0xFF7E22CE),
      secondary: Color(0xFFFB923C),
      tertiary: Color(0xFFA855F7),
    ),
    // 12: Steel Blue & Neon Pink
    _MeshPalette(
      background: Color(0xFF0E1A2B),
      primary: Color(0xFF2563EB),
      secondary: Color(0xFFEC4899),
      tertiary: Color(0xFF93C5FD),
    ),
    // 13: Copper & Ruby
    _MeshPalette(
      background: Color(0xFF240E06),
      primary: Color(0xFFC2410C),
      secondary: Color(0xFFBE123C),
      tertiary: Color(0xFFFB7185),
    ),
    // 14: Dark Sapphire & Electric Cyan
    _MeshPalette(
      background: Color(0xFF081B33),
      primary: Color(0xFF0284C7),
      secondary: Color(0xFF00E5FF),
      tertiary: Color(0xFF38BDF8),
    ),
    // 15: Deep Wine & Rose Quartz
    _MeshPalette(
      background: Color(0xFF220914),
      primary: Color(0xFF881337),
      secondary: Color(0xFFFB7185),
      tertiary: Color(0xFFFFD1DC),
    ),
  ];

  static const List<IconData> _categoryGlyphs = [
    Icons.music_note_rounded,
    Icons.graphic_eq_rounded,
    Icons.album_rounded,
    Icons.headphones_rounded,
    Icons.waves_rounded,
    Icons.audiotrack_rounded,
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final hasTightW = constraints.hasTightWidth;
        final hasTightH = constraints.hasTightHeight;
        final isBounded = size.isFinite && size > 0;

        final double effectiveWidth = hasTightW
            ? constraints.maxWidth
            : (isBounded
                ? size
                : (constraints.maxWidth.isFinite && constraints.maxWidth > 0
                    ? constraints.maxWidth
                    : 56.0));

        final double effectiveHeight = hasTightH
            ? constraints.maxHeight
            : (isBounded
                ? size
                : (constraints.maxHeight.isFinite && constraints.maxHeight > 0
                    ? constraints.maxHeight
                    : 56.0));

        final double effectiveSize = math.min(effectiveWidth, effectiveHeight);
        final double effectiveRadius =
            borderRadius.isFinite ? borderRadius : 12.0;

        final effectiveSeed = computeSeed(
          seed: seed,
          title: title,
          artist: artist,
        );

        final palette = _palettes[effectiveSeed % _palettes.length];
        final initials = extractInitials(title: title, artist: artist);
        final bool showInitials = icon == null && initials.isNotEmpty;

        final discSize = (effectiveSize * 0.48).clamp(20.0, 72.0);
        final iconSize = (discSize * 0.58).clamp(12.0, 36.0);
        final fontSize = (discSize * 0.44).clamp(10.0, 30.0);

        Widget centerContent;
        if (icon != null) {
          centerContent = Icon(
            icon,
            color: Colors.white.withValues(alpha: 0.92),
            size: iconSize,
          );
        } else if (showInitials) {
          centerContent = Text(
            initials,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.94),
              fontSize: fontSize,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
              height: 1.0,
              shadows: [
                Shadow(
                  color: Colors.black.withValues(alpha: 0.45),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
          );
        } else {
          final glyph =
              _categoryGlyphs[effectiveSeed % _categoryGlyphs.length];
          centerContent = Icon(
            glyph,
            color: Colors.white.withValues(alpha: 0.88),
            size: iconSize,
          );
        }

        return ClipRRect(
          borderRadius: AppRadii.circular(effectiveRadius),
          child: SizedBox(
            width: effectiveWidth,
            height: effectiveHeight,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CustomPaint(
                  painter: _MeshGradientPainter(
                    palette: palette,
                    seed: effectiveSeed,
                  ),
                ),
                Center(
                  child: ExcludeSemantics(
                    child: Container(
                      width: discSize,
                      height: discSize,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.black.withValues(alpha: 0.28),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.18),
                          width: 1.0,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.25),
                            blurRadius: 8,
                            spreadRadius: -1,
                          ),
                        ],
                      ),
                      child: Center(child: centerContent),
                    ),
                  ),
                ),
                // Subtle 1px hairline border around the container
                DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: AppRadii.circular(effectiveRadius),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.12),
                      width: 1.0,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _MeshPalette {
  final Color background;
  final Color primary;
  final Color secondary;
  final Color tertiary;

  const _MeshPalette({
    required this.background,
    required this.primary,
    required this.secondary,
    required this.tertiary,
  });
}

class _MeshGradientPainter extends CustomPainter {
  final _MeshPalette palette;
  final int seed;

  _MeshGradientPainter({
    required this.palette,
    required this.seed,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final rect = Offset.zero & size;

    // 1. Fill base dark background
    final basePaint = Paint()..color = palette.background;
    canvas.drawRect(rect, basePaint);

    // 2. Base diagonal linear wash
    final linearPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          palette.background,
          palette.primary.withValues(alpha: 0.35),
        ],
      ).createShader(rect);
    canvas.drawRect(rect, linearPaint);

    // 3. Deterministic mesh points
    final s = seed.abs();
    final p1 = Offset(
      w * (0.15 + (s % 30) / 100.0),
      h * (0.15 + ((s >> 2) % 30) / 100.0),
    );
    final p2 = Offset(
      w * (0.85 - ((s >> 4) % 30) / 100.0),
      h * (0.85 - ((s >> 6) % 30) / 100.0),
    );
    final p3 = Offset(
      w * (0.75 - ((s >> 8) % 25) / 100.0),
      h * (0.20 + ((s >> 10) % 25) / 100.0),
    );

    // Primary blob
    final r1 = w * 0.85;
    final blob1 = Paint()
      ..shader = RadialGradient(
        center: Alignment(
          (p1.dx / w) * 2 - 1,
          (p1.dy / h) * 2 - 1,
        ),
        radius: r1 / w,
        colors: [
          palette.primary.withValues(alpha: 0.80),
          palette.primary.withValues(alpha: 0.0),
        ],
      ).createShader(rect);
    canvas.drawRect(rect, blob1);

    // Secondary blob
    final r2 = w * 0.75;
    final blob2 = Paint()
      ..shader = RadialGradient(
        center: Alignment(
          (p2.dx / w) * 2 - 1,
          (p2.dy / h) * 2 - 1,
        ),
        radius: r2 / w,
        colors: [
          palette.secondary.withValues(alpha: 0.70),
          palette.secondary.withValues(alpha: 0.0),
        ],
      ).createShader(rect);
    canvas.drawRect(rect, blob2);

    // Tertiary highlight blob
    final r3 = w * 0.55;
    final blob3 = Paint()
      ..shader = RadialGradient(
        center: Alignment(
          (p3.dx / w) * 2 - 1,
          (p3.dy / h) * 2 - 1,
        ),
        radius: r3 / w,
        colors: [
          palette.tertiary.withValues(alpha: 0.45),
          palette.tertiary.withValues(alpha: 0.0),
        ],
      ).createShader(rect);
    canvas.drawRect(rect, blob3);

    // 4. Subtle top-down specular sheen overlay
    final sheenPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.white.withValues(alpha: 0.12),
          Colors.transparent,
          Colors.black.withValues(alpha: 0.20),
        ],
      ).createShader(rect);
    canvas.drawRect(rect, sheenPaint);
  }

  @override
  bool shouldRepaint(covariant _MeshGradientPainter oldDelegate) {
    return oldDelegate.seed != seed || oldDelegate.palette != palette;
  }
}
