// lib/core/widgets/mesh_gradient_placeholder.dart
import 'dart:math' as math;
import 'package:material_ui/material_ui.dart';
import '../constants/app_colors.dart';
import '../constants/app_radii.dart';
import '../constants/app_typography.dart';

/// {@category DesignSystem}
/// Dynamic, deterministic, editorial seeded mesh-gradient artwork placeholder.
///
/// Incorporates a frosted luminous monogram medallion or category glyph,
/// seeded by song title/artist/id, providing vibrant and deliberate artwork
/// placeholders even before album art is cached or backfilled.
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

    final titleWords =
        cleanTitle.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();

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

  static final RegExp _arabicChars = RegExp(r'[\u0600-\u06FF]');

  /// Curated HSL palette specifications (zero raw hex literals).
  /// Each entry defines (background, primary, secondary, tertiary) as
  /// (hue, saturation, lightness) triples matching Pulsr's dark editorial mesh.
  static const List<_MeshPaletteSpec> _paletteSpecs = [
    // 0: Deep Indigo & Cyan
    _MeshPaletteSpec(
      bg: (222, 0.47, 0.11),
      primary: (245, 0.58, 0.51),
      secondary: (189, 0.94, 0.43),
      tertiary: (234, 0.89, 0.74),
    ),
    // 1: Midnight Violet & Magenta
    _MeshPaletteSpec(
      bg: (276, 0.59, 0.11),
      primary: (273, 0.72, 0.47),
      secondary: (347, 0.77, 0.50),
      tertiary: (270, 0.95, 0.75),
    ),
    // 2: Oceanic Emerald & Mint
    _MeshPaletteSpec(
      bg: (166, 0.91, 0.09),
      primary: (161, 0.94, 0.30),
      secondary: (173, 0.80, 0.40),
      tertiary: (158, 0.64, 0.52),
    ),
    // 3: Dark Amber & Tangerine
    _MeshPaletteSpec(
      bg: (25, 0.77, 0.09),
      primary: (26, 0.90, 0.37),
      secondary: (21, 0.90, 0.48),
      tertiary: (43, 0.96, 0.56),
    ),
    // 4: Royal Blue & Electric Purple
    _MeshPaletteSpec(
      bg: (215, 0.60, 0.11),
      primary: (224, 0.76, 0.48),
      secondary: (262, 0.83, 0.58),
      tertiary: (213, 0.94, 0.68),
    ),
    // 5: Crimson Noir & Rose
    _MeshPaletteSpec(
      bg: (345, 0.67, 0.08),
      primary: (343, 0.80, 0.35),
      secondary: (350, 0.89, 0.60),
      tertiary: (351, 0.95, 0.82),
    ),
    // 6: Deep Teal & Lime
    _MeshPaletteSpec(
      bg: (179, 0.84, 0.10),
      primary: (175, 0.77, 0.26),
      secondary: (84, 0.81, 0.44),
      tertiary: (171, 0.66, 0.52),
    ),
    // 7: Plum & Bubblegum
    _MeshPaletteSpec(
      bg: (292, 0.60, 0.10),
      primary: (295, 0.70, 0.33),
      secondary: (292, 0.84, 0.61),
      tertiary: (291, 0.93, 0.83),
    ),
    // 8: Obsidian & Ice Azure
    _MeshPaletteSpec(
      bg: (221, 0.52, 0.08),
      primary: (201, 0.96, 0.32),
      secondary: (198, 0.93, 0.60),
      tertiary: (199, 0.95, 0.74),
    ),
    // 9: Blackberry & Gold
    _MeshPaletteSpec(
      bg: (266, 0.61, 0.11),
      primary: (263, 0.69, 0.42),
      secondary: (32, 0.95, 0.44),
      tertiary: (48, 0.97, 0.77),
    ),
    // 10: Forest & Chartreuse
    _MeshPaletteSpec(
      bg: (148, 0.74, 0.09),
      primary: (142, 0.72, 0.29),
      secondary: (85, 0.85, 0.35),
      tertiary: (142, 0.69, 0.58),
    ),
    // 11: Amethyst & Peach
    _MeshPaletteSpec(
      bg: (263, 0.51, 0.14),
      primary: (273, 0.72, 0.47),
      secondary: (27, 0.96, 0.61),
      tertiary: (271, 0.91, 0.65),
    ),
    // 12: Steel Blue & Neon Pink
    _MeshPaletteSpec(
      bg: (215, 0.51, 0.11),
      primary: (221, 0.83, 0.53),
      secondary: (330, 0.81, 0.60),
      tertiary: (212, 0.96, 0.78),
    ),
    // 13: Copper & Ruby
    _MeshPaletteSpec(
      bg: (16, 0.71, 0.08),
      primary: (17, 0.88, 0.40),
      secondary: (345, 0.83, 0.41),
      tertiary: (351, 0.95, 0.71),
    ),
    // 14: Dark Sapphire & Electric Cyan
    _MeshPaletteSpec(
      bg: (213, 0.73, 0.12),
      primary: (200, 0.98, 0.39),
      secondary: (186, 1.00, 0.50),
      tertiary: (198, 0.93, 0.60),
    ),
    // 15: Deep Wine & Rose Quartz
    _MeshPaletteSpec(
      bg: (334, 0.58, 0.08),
      primary: (342, 0.75, 0.30),
      secondary: (351, 0.95, 0.71),
      tertiary: (346, 1.00, 0.91),
    ),
  ];

  static final List<_MeshPalette> _palettes = [
    for (final spec in _paletteSpecs) spec.resolve(),
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

        final discSize = (effectiveSize * 0.46).clamp(22.0, 68.0);
        final iconSize = (discSize * 0.54).clamp(12.0, 34.0);
        final computedFontSize = (discSize * 0.42).clamp(10.0, 28.0);
        final isArabic = _arabicChars.hasMatch(initials);
        final bool isCardSize = effectiveSize >= 72.0;

        Widget centerContent;
        if (icon != null) {
          centerContent = Icon(
            icon,
            color: AppColors.specularAt(0.94),
            size: iconSize,
          );
        } else if (showInitials) {
          centerContent = Text(
            initials,
            style: TextStyle(
              color: AppColors.specularAt(0.96),
              fontSize: computedFontSize,
              fontWeight: FontWeight.w700,
              letterSpacing: isArabic ? AppTracking.none : AppTracking.overline,
              height: 1.0,
              shadows: [
                Shadow(
                  color: AppColors.scrimAt(0.42),
                  blurRadius: 6,
                  offset: const Offset(0, 1.5),
                ),
              ],
            ),
          );
        } else {
          final glyph = _categoryGlyphs[effectiveSeed % _categoryGlyphs.length];
          centerContent = Icon(
            glyph,
            color: AppColors.specularAt(0.90),
            size: iconSize,
          );
        }

        // Skip per-card BackdropFilter so scrolling grids/lists avoid dozens
        // of live blur passes; the translucent medallion gradient preserves
        // the frosted-glass look over the mesh background.
        final Widget medallionCore = Container(
          width: discSize,
          height: discSize,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.alphaBlend(
                  palette.tertiary.withValues(alpha: 0.16),
                  AppColors.specularAt(0.16),
                ),
                AppColors.scrimAt(0.34),
                AppColors.scrimAt(0.48),
              ],
              stops: const [0.0, 0.52, 1.0],
            ),
            border: Border.all(
              color: AppColors.specularAt(0.32),
              width: isCardSize ? 1.2 : 0.9,
            ),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Delicate luminous inner ring for editorial medallion depth
              if (discSize >= 36.0)
                Padding(
                  padding: const EdgeInsets.all(2.5),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppColors.specularAt(0.14),
                        width: 0.75,
                      ),
                    ),
                  ),
                ),
              Center(child: centerContent),
            ],
          ),
        );

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
                    showEditorialRings: isCardSize,
                  ),
                ),
                Center(
                  child: ExcludeSemantics(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.scrimAt(0.30),
                            blurRadius: isCardSize ? 14 : 6,
                            spreadRadius: -1,
                            offset: Offset(0, isCardSize ? 4 : 1.5),
                          ),
                          if (isCardSize)
                            BoxShadow(
                              color: palette.tertiary.withValues(alpha: 0.16),
                              blurRadius: 16,
                              spreadRadius: -2,
                            ),
                        ],
                      ),
                      child: ClipOval(child: medallionCore),
                    ),
                  ),
                ),
                // Subtle 1px specular hairline border around the artwork tile
                DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: AppRadii.circular(effectiveRadius),
                    border: Border.all(
                      color: AppColors.specularAt(0.14),
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

class _MeshPaletteSpec {
  final (double, double, double) bg;
  final (double, double, double) primary;
  final (double, double, double) secondary;
  final (double, double, double) tertiary;

  const _MeshPaletteSpec({
    required this.bg,
    required this.primary,
    required this.secondary,
    required this.tertiary,
  });

  static Color _hsl((double, double, double) t) =>
      HSLColor.fromAHSL(1.0, t.$1, t.$2, t.$3).toColor();

  _MeshPalette resolve() => _MeshPalette(
        background: _hsl(bg),
        primary: _hsl(primary),
        secondary: _hsl(secondary),
        tertiary: _hsl(tertiary),
      );
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
  final bool showEditorialRings;

  _MeshGradientPainter({
    required this.palette,
    required this.seed,
    required this.showEditorialRings,
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
          palette.primary.withValues(alpha: 0.38),
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
          palette.primary.withValues(alpha: 0.82),
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
          palette.secondary.withValues(alpha: 0.72),
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
          palette.tertiary.withValues(alpha: 0.48),
          palette.tertiary.withValues(alpha: 0.0),
        ],
      ).createShader(rect);
    canvas.drawRect(rect, blob3);

    // 4. Crisp subtle diagonal editorial sheen + soft bottom grounding
    final diagonalSheen = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          AppColors.specularAt(0.16),
          AppColors.specularAt(0.05),
          AppColors.fadeStopTransparent,
          AppColors.scrimAt(0.24),
        ],
        stops: const [0.0, 0.28, 0.58, 1.0],
      ).createShader(rect);
    canvas.drawRect(rect, diagonalSheen);

    // 5. Delicate concentric editorial halo ring on card-sized placeholders
    if (showEditorialRings) {
      final center = Offset(w * 0.5, h * 0.5);
      final minDim = math.min(w, h);
      final haloPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.9
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.specularAt(0.20),
            AppColors.specularAt(0.04),
            AppColors.specularAt(0.14),
          ],
        ).createShader(rect);
      canvas.drawCircle(center, minDim * 0.34, haloPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _MeshGradientPainter oldDelegate) {
    return oldDelegate.seed != seed ||
        oldDelegate.palette != palette ||
        oldDelegate.showEditorialRings != showEditorialRings;
  }
}
