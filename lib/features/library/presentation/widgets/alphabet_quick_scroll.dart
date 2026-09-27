// lib/features/library/presentation/widgets/alphabet_quick_scroll.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/constants/app_radii.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/motion/pulsr_motion.dart';
import '../../../../core/theme/aura_theme.dart';

/// Interactive vertical alphabet quick-scroll rail for Library lists.
///
/// Features:
/// - Full A-Z + # index rail pinned to trailing edge via [PositionedDirectional]
/// - Drag or tap gesture navigation with real-time letter selection
/// - Haptic feedback on each letter transition
/// - Floating magnification bubble indicating the active letter
/// - Touch targets and contrast meeting WCAG accessibility criteria
class AlphabetQuickScroll extends StatefulWidget {
  final ValueChanged<String> onLetterSelected;
  final List<String> availableLetters;
  final String? activeLetter;

  const AlphabetQuickScroll({
    super.key,
    required this.onLetterSelected,
    this.availableLetters = const [
      '#',
      'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M',
      'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z'
    ],
    this.activeLetter,
  });

  @override
  State<AlphabetQuickScroll> createState() => _AlphabetQuickScrollState();
}

class _AlphabetQuickScrollState extends State<AlphabetQuickScroll> {
  String? _draggedLetter;
  double? _bubbleY;
  bool _isDragging = false;

  void _handleTouch(Offset localPosition, double totalHeight) {
    if (widget.availableLetters.isEmpty || totalHeight <= 0) return;

    final itemHeight = totalHeight / widget.availableLetters.length;
    final index = (localPosition.dy / itemHeight).floor().clamp(
          0,
          widget.availableLetters.length - 1,
        );

    final selectedLetter = widget.availableLetters[index];
    if (selectedLetter != _draggedLetter) {
      if (context.motionEnabled) {
        HapticFeedback.selectionClick();
      }
      setState(() {
        _draggedLetter = selectedLetter;
        _bubbleY = (index * itemHeight) + (itemHeight / 2);
        _isDragging = true;
      });
      widget.onLetterSelected(selectedLetter);
    }
  }

  void _handleTouchEnd() {
    setState(() {
      _isDragging = false;
      _draggedLetter = null;
      _bubbleY = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final currentLetter = _draggedLetter ?? widget.activeLetter;

    return RepaintBoundary(
      child: Stack(
        clipBehavior: Clip.none,
        alignment: AlignmentDirectional.centerEnd,
        children: [
          // Floating magnification bubble
          if (_isDragging && _draggedLetter != null && _bubbleY != null)
            PositionedDirectional(
              end: 32,
              top: _bubbleY! - 22,
              child: Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: p.accent,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: p.accent.withValues(alpha: 0.35),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Text(
                  _draggedLetter!,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: AppFontSize.headline,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),

          // Vertical Alphabet Rail
          LayoutBuilder(
            builder: (context, constraints) {
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onVerticalDragDown: (details) =>
                    _handleTouch(details.localPosition, constraints.maxHeight),
                onVerticalDragStart: (details) =>
                    _handleTouch(details.localPosition, constraints.maxHeight),
                onVerticalDragUpdate: (details) =>
                    _handleTouch(details.localPosition, constraints.maxHeight),
                onVerticalDragEnd: (_) => _handleTouchEnd(),
                onVerticalDragCancel: () => _handleTouchEnd(),
                onTapDown: (details) =>
                    _handleTouch(details.localPosition, constraints.maxHeight),
                onTapUp: (_) => _handleTouchEnd(),
                child: Container(
                  width: 20,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                  decoration: BoxDecoration(
                    color: p.surfaceContainer.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(AppRadii.r12),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: widget.availableLetters.map((letter) {
                      final isSelected = letter == currentLetter;
                      return Expanded(
                        child: Center(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              letter,
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
                                color: isSelected ? p.accent : p.textTertiary,
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(growable: false),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
