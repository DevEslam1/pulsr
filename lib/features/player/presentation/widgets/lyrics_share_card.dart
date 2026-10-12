import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_typography.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/core/utils/error_logger.dart';
import 'package:pulsr/core/widgets/pulsr_bottom_sheet.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/domain/models/lyrics_line.dart';
import 'package:share_plus/share_plus.dart';

/// Renders a high-resolution 1080x1920 (9:16) Story Card bitmap using Flutter's Canvas.
class LyricsShareCardRenderer {
  static const double cardWidth = 1080.0;
  static const double cardHeight = 1920.0;
  static const double horizontalMargin = 84.0;
  static const double contentWidth = cardWidth - (horizontalMargin * 2);

  /// Generates PNG bytes for the 1080x1920 share card.
  static Future<Uint8List> renderCard({
    required SongsTableData? song,
    required List<LyricsLine> selectedLines,
    required Color accentColor,
    ui.Image? artworkImage,
    bool showTranslation = false,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      const Rect.fromLTWH(0, 0, cardWidth, cardHeight),
    );

    // 1. Draw Backdrop
    _drawBackdrop(canvas, artworkImage, accentColor);

    // 2. Draw Pulsr Branding Badge
    _drawHeaderBrand(canvas, accentColor);

    // 3. Draw Lyrics Passage (Selected 1-6 lines)
    _drawLyricsPassage(canvas, selectedLines, accentColor, showTranslation);

    // 4. Draw Footer (Artwork thumbnail, Title, Artist)
    _drawFooter(canvas, song, artworkImage, accentColor);

    final picture = recorder.endRecording();
    final image = await picture.toImage(cardWidth.toInt(), cardHeight.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  static void _drawBackdrop(
    Canvas canvas,
    ui.Image? artworkImage,
    Color accentColor,
  ) {
    final rect = const Rect.fromLTWH(0, 0, cardWidth, cardHeight);

    if (artworkImage != null) {
      // Draw artwork scaled to cover the card
      final paint = Paint()..filterQuality = FilterQuality.high;
      final srcRect = Rect.fromLTWH(
        0,
        0,
        artworkImage.width.toDouble(),
        artworkImage.height.toDouble(),
      );
      canvas.drawImageRect(artworkImage, srcRect, rect, paint);

      // Dark gradient overlay to ensure high contrast for typography
      final overlayGradient = ui.Gradient.linear(
        const Offset(0, 0),
        const Offset(0, cardHeight),
        [
          const Color(0xCC08080C),
          const Color(0xDD0D0D14),
          const Color(0xF208080C),
        ],
        [0.0, 0.5, 1.0],
      );
      canvas.drawRect(rect, Paint()..shader = overlayGradient);
    } else {
      // Mesh/rich gradient fallback
      final bgGradient = ui.Gradient.linear(
        const Offset(0, 0),
        const Offset(cardWidth, cardHeight),
        [
          const Color(0xFF101018),
          const Color(0xFF161524),
          const Color(0xFF09090E),
        ],
        [0.0, 0.5, 1.0],
      );
      canvas.drawRect(rect, Paint()..shader = bgGradient);

      // Soft glow orb behind lyrics
      final glowPaint = Paint()
        ..color = accentColor.withValues(alpha: 0.18)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 180);
      canvas.drawCircle(
        const Offset(cardWidth / 2, cardHeight * 0.45),
        360,
        glowPaint,
      );
    }
  }

  static void _drawHeaderBrand(Canvas canvas, Color accentColor) {
    const brandText = 'PULSR MUSIC';
    const topY = 130.0;

    // Glowing badge outline pill
    final badgeRect = RRect.fromRectAndRadius(
      const Rect.fromLTWH(horizontalMargin, topY, 260, 56),
      const Radius.circular(28),
    );

    final bgPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(badgeRect, bgPaint);

    final borderPaint = Paint()
      ..color = accentColor.withValues(alpha: 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawRRect(badgeRect, borderPaint);

    // Brand label
    final textPainter = TextPainter(
      text: TextSpan(
        text: brandText,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.95),
          fontSize: 22,
          fontWeight: FontWeight.w800,
          letterSpacing: 3.5,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(
        horizontalMargin + (260 - textPainter.width) / 2,
        topY + (56 - textPainter.height) / 2,
      ),
    );
  }

  static void _drawLyricsPassage(
    Canvas canvas,
    List<LyricsLine> lines,
    Color accentColor,
    bool showTranslation,
  ) {
    if (lines.isEmpty) return;

    // Ladder of font sizes based on total lines and characters
    final totalChars = lines.fold<int>(0, (sum, l) => sum + l.text.length);
    double fontSize = 54.0;
    if (lines.length > 4 || totalChars > 160) {
      fontSize = 38.0;
    } else if (lines.length > 2 || totalChars > 80) {
      fontSize = 46.0;
    }

    final subFontSize = (fontSize * 0.62).clamp(22.0, 32.0);

    // Measure total passage height
    final List<TextPainter> painters = [];
    final List<TextPainter?> subPainters = [];
    double totalPassageHeight = 0.0;

    for (final line in lines) {
      final tp = TextPainter(
        text: TextSpan(
          text: line.text,
          style: TextStyle(
            color: Colors.white,
            fontSize: fontSize,
            fontWeight: FontWeight.w800,
            height: 1.35,
            letterSpacing: -0.5,
            shadows: [
              Shadow(
                color: accentColor.withValues(alpha: 0.45),
                blurRadius: 28,
              ),
              Shadow(
                color: Colors.black.withValues(alpha: 0.8),
                blurRadius: 10,
              ),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      tp.layout(maxWidth: contentWidth);
      painters.add(tp);

      TextPainter? subTp;
      final sub = (showTranslation
          ? (line.translation ?? line.romanization)
          : null);
      if (sub != null && sub.isNotEmpty && sub != line.text) {
        subTp = TextPainter(
          text: TextSpan(
            text: sub,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.72),
              fontSize: subFontSize,
              fontWeight: FontWeight.w500,
              fontStyle: FontStyle.italic,
              height: 1.3,
            ),
          ),
          textDirection: TextDirection.ltr,
        );
        subTp.layout(maxWidth: contentWidth);
      }
      subPainters.add(subTp);

      totalPassageHeight += tp.height + (subTp?.height ?? 0.0) + 36.0;
    }

    // Vertically center in the area between top (240) and footer (1620)
    const availableTop = 260.0;
    const availableBottom = 1600.0;
    final availableHeight = availableBottom - availableTop;
    double currentY = availableTop +
        math.max(0.0, (availableHeight - totalPassageHeight) / 2);

    for (int i = 0; i < painters.length; i++) {
      final tp = painters[i];
      tp.paint(canvas, Offset(horizontalMargin, currentY));
      currentY += tp.height + 8.0;

      final subTp = subPainters[i];
      if (subTp != null) {
        subTp.paint(canvas, Offset(horizontalMargin, currentY));
        currentY += subTp.height + 28.0;
      } else {
        currentY += 28.0;
      }
    }
  }

  static void _drawFooter(
    Canvas canvas,
    SongsTableData? song,
    ui.Image? artworkImage,
    Color accentColor,
  ) {
    const footerY = 1660.0;
    const thumbSize = 150.0;

    // 1. Artwork thumbnail
    final thumbRect = RRect.fromRectAndRadius(
      const Rect.fromLTWH(horizontalMargin, footerY, thumbSize, thumbSize),
      const Radius.circular(24),
    );

    if (artworkImage != null) {
      canvas.save();
      canvas.clipRRect(thumbRect);
      final srcRect = Rect.fromLTWH(
        0,
        0,
        artworkImage.width.toDouble(),
        artworkImage.height.toDouble(),
      );
      canvas.drawImageRect(
        artworkImage,
        srcRect,
        thumbRect.outerRect,
        Paint()..filterQuality = FilterQuality.high,
      );
      canvas.restore();
    } else {
      final thumbPaint = Paint()..color = const Color(0xFF222230);
      canvas.drawRRect(thumbRect, thumbPaint);
      final iconPainter = TextPainter(
        text: TextSpan(
          text: '♫',
          style: TextStyle(
            color: accentColor,
            fontSize: 60,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      iconPainter.layout();
      iconPainter.paint(
        canvas,
        Offset(
          horizontalMargin + (thumbSize - iconPainter.width) / 2,
          footerY + (thumbSize - iconPainter.height) / 2,
        ),
      );
    }

    // Border around artwork thumbnail
    final borderPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawRRect(thumbRect, borderPaint);

    // 2. Title & Artist
    final textX = horizontalMargin + thumbSize + 36.0;
    final textWidth = cardWidth - horizontalMargin - textX;

    final title = song?.title ?? 'Unknown Track';
    final artist = song?.artist ?? 'Unknown Artist';

    final titlePainter = TextPainter(
      text: TextSpan(
        text: title,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 44,
          fontWeight: FontWeight.w800,
        ),
      ),
      maxLines: 1,
      ellipsis: '...',
      textDirection: TextDirection.ltr,
    );
    titlePainter.layout(maxWidth: textWidth);
    titlePainter.paint(canvas, Offset(textX, footerY + 22.0));

    final artistPainter = TextPainter(
      text: TextSpan(
        text: artist,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.75),
          fontSize: 34,
          fontWeight: FontWeight.w600,
        ),
      ),
      maxLines: 1,
      ellipsis: '...',
      textDirection: TextDirection.ltr,
    );
    artistPainter.layout(maxWidth: textWidth);
    artistPainter.paint(canvas, Offset(textX, footerY + 84.0));
  }
}

/// Modal dialog sheet allowing users to select 1-6 lyric lines and share/save the 9:16 card.
class LyricsShareSheet extends StatefulWidget {
  final List<LyricsLine> lyrics;
  final SongsTableData? song;
  final Color activeColor;
  final int initialLineIndex;
  final bool initialShowTranslation;

  const LyricsShareSheet({
    super.key,
    required this.lyrics,
    required this.song,
    required this.activeColor,
    this.initialLineIndex = 0,
    this.initialShowTranslation = false,
  });

  static Future<void> show({
    required BuildContext context,
    required List<LyricsLine> lyrics,
    required SongsTableData? song,
    required Color activeColor,
    int initialLineIndex = 0,
    bool showTranslation = false,
  }) async {
    await PulsrSheetHelper.showPulsrSheet<void>(
      context: context,
      wrapWithContainer: false,
      builder: (_) => LyricsShareSheet(
        lyrics: lyrics,
        song: song,
        activeColor: activeColor,
        initialLineIndex: initialLineIndex,
        initialShowTranslation: showTranslation,
      ),
    );
  }

  @override
  State<LyricsShareSheet> createState() => _LyricsShareSheetState();
}

class _LyricsShareSheetState extends State<LyricsShareSheet> {
  late final Set<int> _selectedIndices;
  bool _isGenerating = false;
  late bool _showTranslation;

  @override
  void initState() {
    super.initState();
    _showTranslation = widget.initialShowTranslation;
    _selectedIndices = {
      widget.initialLineIndex.clamp(0, widget.lyrics.length - 1)
    };
  }

  void _toggleIndex(int idx) {
    setState(() {
      if (_selectedIndices.contains(idx)) {
        if (_selectedIndices.length > 1) {
          _selectedIndices.remove(idx);
        }
      } else {
        if (_selectedIndices.length < 6) {
          _selectedIndices.add(idx);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('You can select up to 6 lines for the story card.'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    });
  }

  Future<void> _shareImage() async {
    setState(() => _isGenerating = true);
    try {
      final sortedIndices = _selectedIndices.toList()..sort();
      final lines = sortedIndices.map((i) => widget.lyrics[i]).toList();

      final pngBytes = await LyricsShareCardRenderer.renderCard(
        song: widget.song,
        selectedLines: lines,
        accentColor: widget.activeColor,
        showTranslation: _showTranslation,
      );

      final tempDir = await getTemporaryDirectory();
      final file = File(
          '${tempDir.path}/pulsr_story_${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(pngBytes, flush: true);

      final title = widget.song?.title ?? 'Track';
      final artist = widget.song?.artist ?? 'Artist';
      // ignore: deprecated_member_use
      await Share.shareXFiles(
        [XFile(file.path)],
        text: '$title - $artist | Pulsr Music',
      );
    } catch (e, st) {
      ErrorLogger.log('Sharing lyrics card failed',
          error: e, stackTrace: st, category: 'LyricsShare');
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  Future<void> _saveImage() async {
    setState(() => _isGenerating = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final sortedIndices = _selectedIndices.toList()..sort();
      final lines = sortedIndices.map((i) => widget.lyrics[i]).toList();

      final pngBytes = await LyricsShareCardRenderer.renderCard(
        song: widget.song,
        selectedLines: lines,
        accentColor: widget.activeColor,
        showTranslation: _showTranslation,
      );

      final dir = await getApplicationDocumentsDirectory();
      final file = File(
          '${dir.path}/pulsr_lyrics_${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(pngBytes, flush: true);

      messenger.showSnackBar(
        SnackBar(
          content: Text('Card saved to: ${file.path}'),
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e, st) {
      ErrorLogger.log('Saving lyrics card failed',
          error: e, stackTrace: st, category: 'LyricsShare');
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(AppRadii.r24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            width: 44,
            height: 4,
            decoration: BoxDecoration(
              color: p.textTertiary.withValues(alpha: 0.3),
              borderRadius: AppRadii.r10All,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          // Title row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Share Lyrics Card',
                style: TextStyle(
                  fontSize: AppFontSize.titleLarge,
                  fontWeight: FontWeight.w800,
                  color: p.textPrimary,
                ),
              ),
              Text(
                '${_selectedIndices.length}/6 lines',
                style: TextStyle(
                  fontSize: AppFontSize.label,
                  fontWeight: FontWeight.w700,
                  color: widget.activeColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Select 1 to 6 lines to create a 9:16 story card.',
            style: TextStyle(
              fontSize: AppFontSize.bodySmall,
              color: p.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          // Selectable lines list
          Expanded(
            child: ListView.builder(
              itemCount: widget.lyrics.length,
              itemBuilder: (context, index) {
                final line = widget.lyrics[index];
                final isSelected = _selectedIndices.contains(index);

                return CheckboxListTile(
                  value: isSelected,
                  activeColor: widget.activeColor,
                  checkColor: Colors.black,
                  contentPadding: EdgeInsets.zero,
                  onChanged: (_) => _toggleIndex(index),
                  title: Text(
                    line.text,
                    style: TextStyle(
                      fontSize: AppFontSize.body,
                      fontWeight:
                          isSelected ? FontWeight.w700 : FontWeight.w500,
                      color: isSelected ? p.textPrimary : p.textSecondary,
                    ),
                  ),
                  subtitle: (_showTranslation &&
                          (line.translation != null ||
                              line.romanization != null))
                      ? Text(
                          line.translation ?? line.romanization!,
                          style: TextStyle(
                            fontSize: AppFontSize.caption,
                            fontStyle: FontStyle.italic,
                            color: widget.activeColor.withValues(alpha: 0.8),
                          ),
                        )
                      : null,
                );
              },
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          // Actions: Save & Share
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isGenerating ? null : _saveImage,
                  icon: const Icon(Icons.download_rounded, size: 20),
                  label: const Text('Save Image'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: widget.activeColor,
                    padding:
                        const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                    shape:
                        RoundedRectangleBorder(borderRadius: AppRadii.r12All),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _isGenerating ? null : _shareImage,
                  icon: _isGenerating
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.share_rounded, size: 20),
                  label: const Text('Share'),
                  style: FilledButton.styleFrom(
                    backgroundColor: widget.activeColor,
                    foregroundColor: Colors.black,
                    padding:
                        const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                    shape:
                        RoundedRectangleBorder(borderRadius: AppRadii.r12All),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
      ),
    );
  }
}
