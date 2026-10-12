import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_typography.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/domain/models/lyrics_line.dart';

/// Advanced word-level / syllable sweep karaoke lyrics renderer.
///
/// Features:
/// - Syllable sweep fill using `ShaderMask` + `LinearGradient` across word `startMs` & `endMs`.
/// - Subtle glow and physical lift for the active word being sung.
/// - Background vocal detection and styling (italics + muted opacity).
/// - Duet alignment (start vs end alignment per line).
/// - Translation & Romanization sub-line display.
/// - Auto-scrolling to the active line with manual scroll detection.
class AdvancedLyricsView extends StatefulWidget {
  final List<LyricsLine> lyrics;
  final Duration currentPosition;
  final Color activeColor;
  final ValueChanged<Duration>? onLineTapped;
  final void Function(int lineIndex)? onLineLongPressed;
  final bool showTranslation;
  final bool replaceOriginalWithTranslation;

  const AdvancedLyricsView({
    super.key,
    required this.lyrics,
    required this.currentPosition,
    required this.activeColor,
    this.onLineTapped,
    this.onLineLongPressed,
    this.showTranslation = false,
    this.replaceOriginalWithTranslation = false,
  });

  @override
  State<AdvancedLyricsView> createState() => _AdvancedLyricsViewState();
}

class _AdvancedLyricsViewState extends State<AdvancedLyricsView> {
  final ScrollController _scrollController = ScrollController();
  int _lastActiveIndex = -1;
  bool _userIsScrolling = false;
  DateTime _lastUserScrollTime = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void didUpdateWidget(covariant AdvancedLyricsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final activeIdx = _findActiveIndex(widget.currentPosition);
    if (activeIdx != _lastActiveIndex) {
      _lastActiveIndex = activeIdx;
      _scrollToActiveIndex(activeIdx);
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  int _findActiveIndex(Duration position) {
    if (widget.lyrics.isEmpty) return -1;
    final posMs = position.inMilliseconds;
    int index = -1;
    for (int i = 0; i < widget.lyrics.length; i++) {
      if (widget.lyrics[i].timestamp.inMilliseconds <= posMs) {
        index = i;
      } else {
        break;
      }
    }
    return index;
  }

  void _scrollToActiveIndex(int index) {
    if (index < 0 || !_scrollController.hasClients) return;
    final now = DateTime.now();
    if (_userIsScrolling && now.difference(_lastUserScrollTime).inSeconds < 3) {
      return; // Pause auto-scroll briefly when user touched the list
    }
    _userIsScrolling = false;

    // Estimate position: ~68px per item average
    final targetOffset = (index * 68.0).clamp(
      0.0,
      _scrollController.position.maxScrollExtent,
    );

    _scrollController.animateTo(
      targetOffset,
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final activeIdx = _findActiveIndex(widget.currentPosition);
    final posMs = widget.currentPosition.inMilliseconds;

    return NotificationListener<UserScrollNotification>(
      onNotification: (_) {
        _userIsScrolling = true;
        _lastUserScrollTime = DateTime.now();
        return false;
      },
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(
          vertical: AppSpacing.xxl,
          horizontal: AppSpacing.lg,
        ),
        itemCount: widget.lyrics.length,
        itemBuilder: (context, index) {
          final line = widget.lyrics[index];
          final isActive = index == activeIdx;
          final isPast = index < activeIdx;

          return _LyricLineWidget(
            line: line,
            positionMs: posMs,
            isActive: isActive,
            isPast: isPast,
            activeColor: widget.activeColor,
            palette: p,
            showTranslation: widget.showTranslation,
            replaceOriginalWithTranslation:
                widget.replaceOriginalWithTranslation,
            onTap: () {
              widget.onLineTapped?.call(line.timestamp);
            },
            onLongPress: () {
              widget.onLineLongPressed?.call(index);
            },
          );
        },
      ),
    );
  }
}

class _LyricLineWidget extends StatelessWidget {
  final LyricsLine line;
  final int positionMs;
  final bool isActive;
  final bool isPast;
  final Color activeColor;
  final PulsrPalette palette;
  final bool showTranslation;
  final bool replaceOriginalWithTranslation;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _LyricLineWidget({
    required this.line,
    required this.positionMs,
    required this.isActive,
    required this.isPast,
    required this.activeColor,
    required this.palette,
    required this.showTranslation,
    required this.replaceOriginalWithTranslation,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final isBackground = line.isBackgroundLine;
    final alignEnd = line.alignment == LyricAlignment.end;

    final String displayText = (replaceOriginalWithTranslation &&
            (line.translation != null || line.romanization != null))
        ? (line.translation ?? line.romanization ?? line.text)
        : line.text;

    final String? subText = (!replaceOriginalWithTranslation &&
            showTranslation &&
            (line.translation != null || line.romanization != null))
        ? (line.translation ?? line.romanization)
        : null;

    final alignment = alignEnd ? Alignment.centerRight : Alignment.centerLeft;
    final textAlign = alignEnd ? TextAlign.end : TextAlign.start;

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: AppRadii.r12All,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(
          vertical: AppSpacing.s8,
          horizontal: AppSpacing.sm,
        ),
        alignment: alignment,
        child: Column(
          crossAxisAlignment:
              alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (line.words.isNotEmpty &&
                isActive &&
                !replaceOriginalWithTranslation)
              _buildWordLevelKaraokeLine(isBackground, alignEnd)
            else
              _buildStandardLine(displayText, isBackground, textAlign),
            if (subText != null && subText.isNotEmpty && subText != displayText)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xxs),
                child: Text(
                  subText,
                  textAlign: textAlign,
                  style: TextStyle(
                    fontSize: AppFontSize.body,
                    fontWeight: FontWeight.w500,
                    fontStyle: FontStyle.italic,
                    color: isActive
                        ? activeColor.withValues(alpha: 0.85)
                        : palette.textTertiary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStandardLine(
      String text, bool isBackground, TextAlign textAlign) {
    final TextStyle baseStyle = TextStyle(
      fontSize: isBackground ? 17.0 : (isActive ? 22.0 : 19.0),
      fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
      fontStyle: isBackground ? FontStyle.italic : FontStyle.normal,
      height: 1.35,
      color: isActive
          ? activeColor
          : (isPast
              ? palette.textSecondary.withValues(alpha: 0.5)
              : palette.textSecondary.withValues(alpha: 0.75)),
      shadows: isActive
          ? [
              Shadow(
                color: activeColor.withValues(alpha: 0.45),
                blurRadius: 16,
              ),
            ]
          : null,
    );

    return Text(
      text,
      textAlign: textAlign,
      style: baseStyle,
    );
  }

  Widget _buildWordLevelKaraokeLine(bool isBackground, bool alignEnd) {
    return Wrap(
      alignment: alignEnd ? WrapAlignment.end : WrapAlignment.start,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 6.0,
      runSpacing: 4.0,
      children: [
        for (final word in line.words)
          _KaraokeWordView(
            word: word,
            positionMs: positionMs,
            activeColor: activeColor,
            palette: palette,
            isBackground: isBackground,
          ),
      ],
    );
  }
}

class _KaraokeWordView extends StatelessWidget {
  final WordTimestamp word;
  final int positionMs;
  final Color activeColor;
  final PulsrPalette palette;
  final bool isBackground;

  const _KaraokeWordView({
    required this.word,
    required this.positionMs,
    required this.activeColor,
    required this.palette,
    required this.isBackground,
  });

  @override
  Widget build(BuildContext context) {
    final progress = word.progressAt(positionMs);
    final isSung = progress >= 1.0;
    final isSinging = progress > 0.0 && progress < 1.0;

    // Lift calculation: peak lift of -3.5dp when in the middle of being sung
    final double lift = isSinging ? -3.5 * math.sin(progress * math.pi) : 0.0;

    final inactiveColor = isBackground
        ? palette.textTertiary.withValues(alpha: 0.4)
        : palette.textSecondary.withValues(alpha: 0.55);

    final style = TextStyle(
      fontSize: isBackground ? 17.0 : 22.0,
      fontWeight: (isSung || isSinging) ? FontWeight.w900 : FontWeight.w600,
      fontStyle: isBackground ? FontStyle.italic : FontStyle.normal,
      color: isSung ? activeColor : inactiveColor,
      shadows: isSinging
          ? [
              Shadow(
                color: activeColor.withValues(alpha: 0.65),
                blurRadius: 18,
              ),
              Shadow(
                color: activeColor.withValues(alpha: 0.4),
                blurRadius: 6,
              ),
            ]
          : (isSung
              ? [
                  Shadow(
                    color: activeColor.withValues(alpha: 0.3),
                    blurRadius: 8,
                  ),
                ]
              : null),
    );

    Widget child = Text(word.word, style: style);

    if (isSinging) {
      // Syllable sweep gradient fill
      child = ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: (bounds) {
          final clampedProgress = progress.clamp(0.0, 1.0);
          return LinearGradient(
            colors: [
              activeColor,
              activeColor,
              inactiveColor,
              inactiveColor,
            ],
            stops: [
              0.0,
              clampedProgress,
              clampedProgress,
              1.0,
            ],
          ).createShader(bounds);
        },
        child: Text(
          word.word,
          style: style.copyWith(color: Colors.white),
        ),
      );
    }

    if (lift != 0.0) {
      child = Transform.translate(
        offset: Offset(0, lift),
        child: child,
      );
    }

    return child;
  }
}
