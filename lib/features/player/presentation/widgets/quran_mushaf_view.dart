// lib/features/player/presentation/widgets/quran_mushaf_view.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/constants/app_radii.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../core/motion/pulsr_motion.dart';
import '../../../../core/widgets/pulsr_adaptive_sheet.dart';
import '../../../../domain/models/quran_metadata.dart';
import '../../../../domain/models/quran_surah.dart';
import '../../../../domain/repositories/quran_repository.dart';
import '../../../../core/di/injection.dart';
import '../../../../data/repositories/quran_repository_impl.dart';
import '../../../../data/quran/quran_uthmani_text.dart';
import 'quran_text_attribution.dart';

/// Bundled Quran reader with timing-based highlighting, tap-to-seek,
/// and Hifz (memorization) blind recall masking.
class QuranMushafView extends StatefulWidget {
  final QuranMetadata? metadata;
  final Duration currentPosition;
  final ValueChanged<Duration>? onSeek;
  final ValueChanged<int>? onSelectSurah;

  const QuranMushafView({
    super.key,
    this.metadata,
    required this.currentPosition,
    this.onSeek,
    this.onSelectSurah,
  });

  @override
  State<QuranMushafView> createState() => _QuranMushafViewState();
}

class _QuranMushafViewState extends State<QuranMushafView> {
  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _ayahKeys = {};
  bool _blindRecallMode = false;
  final Set<int> _revealedAyahs = {};
  int _lastActiveAyah = -1;
  int? _browsedSurah;

  QuranRepository get _repo => getIt.isRegistered<QuranRepository>()
      ? getIt<QuranRepository>()
      : QuranRepositoryImpl();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant QuranMushafView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.metadata != widget.metadata) {
      _browsedSurah = null;
      _resetReadingState();
    }
  }

  void _resetReadingState() {
    _revealedAyahs.clear();
    _ayahKeys.clear();
    _lastActiveAyah = -1;
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
  }

  void _scrollToActiveAyah(int ayah) {
    if (_lastActiveAyah == ayah) return;
    _lastActiveAyah = ayah;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final target = _ayahKeys[ayah]?.currentContext;
      if (target == null) return;
      _scrollController.position.ensureVisible(
        target.findRenderObject()!,
        alignment: 0.15,
        duration: context.motionMs(300),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _showSurahPicker(BuildContext context, PulsrPalette p) {
    final surahs = _repo.getSurahs();
    PulsrAdaptiveSheet.show<void>(
      context: context,
      titleText: context.l10n.quranSurahIndex,
      builder: (ctx) {
        return ListView.separated(
          shrinkWrap: true,
          physics: const ClampingScrollPhysics(),
          itemCount: surahs.length,
          separatorBuilder: (_, __) => Divider(height: 1, color: p.hairline),
          itemBuilder: (_, i) {
            final s = surahs[i];
            final isSelected =
                (_browsedSurah ?? widget.metadata?.surahNumber ?? 1) ==
                    s.number;
            return ListTile(
              selected: isSelected,
              selectedTileColor: p.accent.withValues(alpha: 0.12),
              leading: CircleAvatar(
                radius: 16,
                backgroundColor: isSelected ? p.accent : p.surfaceContainerHigh,
                child: Text(
                  '${s.number}',
                  style: TextStyle(
                    fontSize: AppFontSize.caption,
                    fontWeight: FontWeight.w700,
                    color: isSelected ? p.onAccent : p.textSecondary,
                  ),
                ),
              ),
              title: Text(
                '${s.nameTransliteration} (${s.nameArabic})',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: isSelected ? p.accent : p.textPrimary,
                ),
              ),
              subtitle: Text(
                '${s.nameEnglish} • ${s.totalAyahs} Ayahs • ${s.revelationPlace}',
                style: TextStyle(
                    fontSize: AppFontSize.caption, color: p.textSecondary),
              ),
              trailing: Text(
                s.nameArabic,
                style: TextStyle(
                  fontSize: AppFontSize.title,
                  fontWeight: FontWeight.w700,
                  color: isSelected ? p.accent : p.textSecondary,
                ),
              ),
              onTap: () {
                Navigator.of(ctx).pop();
                setState(() {
                  _browsedSurah = s.number;
                  _resetReadingState();
                });
                widget.onSelectSurah?.call(s.number);
              },
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final surahNumber = _browsedSurah ?? widget.metadata?.surahNumber ?? 1;
    final meta =
        widget.metadata?.surahNumber == surahNumber && widget.metadata!.isValid
            ? widget.metadata
            : null;
    final surah = _repo.getSurah(surahNumber) ?? QuranSurah.byNumber(1)!;
    final ayahs = _repo.getAyahsForSurah(surahNumber);
    final activeAyah = meta != null && meta.ayahTimings.isNotEmpty
        ? meta.ayahAt(widget.currentPosition)
        : null;

    if (activeAyah != null) _scrollToActiveAyah(activeAyah);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.s20),
      padding: const EdgeInsets.all(AppSpacing.s16),
      decoration: BoxDecoration(
        color: p.surfaceContainer,
        borderRadius: AppRadii.r20All,
        border: Border.all(color: p.accent.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header: Surah Details & Actions
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(AppSpacing.s8),
                decoration: BoxDecoration(
                  color: p.accent.withValues(alpha: 0.14),
                  borderRadius: AppRadii.r12All,
                ),
                child:
                    Icon(Icons.auto_stories_rounded, color: p.accent, size: 22),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${surah.nameTransliteration} • ${surah.nameArabic}',
                          style: TextStyle(
                            fontSize: AppFontSize.body,
                            fontWeight: FontWeight.w800,
                            color: p.textPrimary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: p.accent.withValues(alpha: 0.16),
                            borderRadius: AppRadii.r6All,
                          ),
                          child: Text(
                            activeAyah == null
                                ? context.l10n.quranReadingOnly
                                : 'Ayah $activeAyah / ${surah.totalAyahs}',
                            style: TextStyle(
                              fontSize: AppFontSize.tiny,
                              fontWeight: FontWeight.w700,
                              color: p.accent,
                            ),
                          ),
                        ),
                      ],
                    ),
                    Text(
                      '${surah.nameEnglish} • ${surah.revelationPlace} (${surah.totalAyahs} Verses)',
                      style: TextStyle(
                          fontSize: AppFontSize.caption,
                          color: p.textSecondary),
                    ),
                  ],
                ),
              ),
              // Index button
              IconButton(
                tooltip: context.l10n.quranSurahIndex,
                icon: Icon(Icons.list_alt_rounded, color: p.accent, size: 22),
                onPressed: () => _showSurahPicker(context, p),
              ),
              // Hifz Blind Recall Toggle
              IconButton(
                tooltip: _blindRecallMode
                    ? context.l10n.quranShowText
                    : context.l10n.quranBlindRecall,
                icon: Icon(
                  _blindRecallMode
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded,
                  color: _blindRecallMode ? p.accent : p.textSecondary,
                  size: 22,
                ),
                onPressed: () {
                  HapticFeedback.selectionClick();
                  setState(() {
                    _blindRecallMode = !_blindRecallMode;
                    if (!_blindRecallMode) _revealedAyahs.clear();
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s12),
          Divider(height: 1, color: p.hairline),
          const SizedBox(height: AppSpacing.s12),

          // Basmalah (except for Surah At-Tawbah 9)
          if (surahNumber != 1 && surahNumber != 9 && ayahs.isNotEmpty) ...[
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                child: Text(
                  quranUthmaniText[1]!.first,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: AppFontSize.title,
                    fontWeight: FontWeight.w700,
                    color: p.accent,
                    fontFamily: 'serif',
                    height: 1.6,
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
          ],

          // Ayah List Container
          if (ayahs.isEmpty)
            Padding(
              padding: const EdgeInsets.all(AppSpacing.s12),
              child: Text(context.l10n.quranTextUnavailable,
                  style: TextStyle(color: p.textSecondary)),
            ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 340),
            child: SingleChildScrollView(
              controller: _scrollController,
              child: Column(
                  children: List.generate(ayahs.length, (idx) {
                final ayah = ayahs[idx];
                final isCurrent = ayah.ayahNumber == activeAyah;
                final isRevealed = _revealedAyahs.contains(ayah.ayahNumber);
                final shouldBlur = _blindRecallMode && !isRevealed;

                _ayahKeys[ayah.ayahNumber] ??= GlobalKey();

                return Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.s8),
                  child: GestureDetector(
                    key: _ayahKeys[ayah.ayahNumber],
                    onTap: () {
                      HapticFeedback.selectionClick();
                      if (_blindRecallMode && !isRevealed) {
                        setState(() => _revealedAyahs.add(ayah.ayahNumber));
                      }
                      if (meta != null && meta.ayahTimings.isNotEmpty) {
                        final timing = meta.timingForAyah(ayah.ayahNumber);
                        if (timing != null) {
                          widget.onSeek?.call(timing.start);
                        }
                      }
                    },
                    child: AnimatedContainer(
                      duration: context.motionMs(250),
                      curve: Curves.easeOutCubic,
                      padding: const EdgeInsets.all(AppSpacing.s12),
                      decoration: BoxDecoration(
                        color: isCurrent
                            ? p.accent.withValues(alpha: 0.14)
                            : p.surfaceContainerHigh.withValues(alpha: 0.5),
                        borderRadius: AppRadii.r14All,
                        border: Border.all(
                          color: isCurrent ? p.accent : p.hairline,
                          width: isCurrent ? 1.6 : 1.0,
                        ),
                        boxShadow: isCurrent
                            ? [
                                BoxShadow(
                                  color: p.accent.withValues(alpha: 0.15),
                                  blurRadius: 10,
                                  offset: const Offset(0, 2),
                                )
                              ]
                            : null,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Verse Arabic Text
                          Directionality(
                            textDirection: TextDirection.rtl,
                            child: Stack(
                              children: [
                                ExcludeSemantics(
                                  excluding: shouldBlur,
                                  child: Text(
                                    '${ayah.textArabic} ﴿${ayah.ayahNumber}﴾',
                                    style: TextStyle(
                                      fontSize: AppFontSize.titleLarge,
                                      fontWeight: FontWeight.w700,
                                      color:
                                          isCurrent ? p.accent : p.textPrimary,
                                      fontFamily: 'serif',
                                      height: 1.8,
                                    ),
                                  ),
                                ),
                                if (shouldBlur)
                                  Positioned.fill(
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: p.surfaceContainer,
                                        borderRadius: AppRadii.r10All,
                                      ),
                                      alignment: Alignment.center,
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.touch_app_rounded,
                                              size: 16, color: p.accent),
                                          const SizedBox(width: AppSpacing.xxs),
                                          Text(
                                            context.l10n.quranTapToReveal,
                                            style: TextStyle(
                                              fontSize: AppFontSize.caption,
                                              fontWeight: FontWeight.w700,
                                              color: p.accent,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          if (!shouldBlur && ayah.textEnglish.isNotEmpty) ...[
                            const SizedBox(height: AppSpacing.xs),
                            Directionality(
                              textDirection: TextDirection.ltr,
                              child: Text(
                                ayah.textEnglish,
                                style: TextStyle(
                                  fontSize: AppFontSize.caption,
                                  color: isCurrent
                                      ? p.textPrimary
                                      : p.textSecondary,
                                  fontStyle: FontStyle.italic,
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              })),
            ),
          ),
          const QuranTextAttribution(),
        ],
      ),
    );
  }
}
