// lib/features/library/presentation/widgets/genre_hierarchy_view.dart
import 'package:flutter/material.dart';
import '../../../../core/utils/l10n_extensions.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../domain/models/genre_item.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_typography.dart';

class GenreCategory {
  final String name;
  final IconData icon;
  final List<String> keywords;

  const GenreCategory(this.name, this.icon, this.keywords);
}

class GenreHierarchyView extends StatelessWidget {
  final List<GenreItem> genres;

  const GenreHierarchyView({super.key, required this.genres});

  List<GenreCategory> _categories(BuildContext context) => [
    GenreCategory(context.l10n.browseGenreRockMetal, Icons.electric_bolt_rounded,
        ['rock', 'metal', 'grunge', 'punk', 'alternative', 'روك', 'ميتال']),
    GenreCategory(context.l10n.browseGenreElectronicDance, Icons.album_rounded, [
      'electronic',
      'techno',
      'house',
      'edm',
      'ambient',
      'trance',
      'synth',
      'إلكترونك',
      'هاوس',
      'تكنو'
    ]),
    GenreCategory(context.l10n.browseGenreHipHopRnb, Icons.mic_external_on_rounded, [
      'hip hop',
      'hip-hop',
      'rap',
      'r&b',
      'trap',
      'soul',
      'راب',
      'هيب هوب',
      'تراب',
      'مهرجانات'
    ]),
    GenreCategory(context.l10n.browseGenreJazzBlues, Icons.music_note_rounded,
        ['jazz', 'blues', 'swing', 'bebop', 'جاز', 'بلوز']),
    GenreCategory(context.l10n.browseGenreClassicalInstrumental, Icons.piano_rounded, [
      'classical',
      'instrumental',
      'soundtrack',
      'orchestral',
      'score',
      'كلاسيك',
      'موسيقى كلاسيكية',
      'أوركسترا',
      'موسيقى تصويرية'
    ]),
    GenreCategory(context.l10n.browseGenrePopAcoustic, Icons.star_rounded, [
      'pop',
      'acoustic',
      'indie',
      'folk',
      'vocal',
      'بوب',
      'شعبي',
      'أكوستيك',
      'فولك'
    ]),
    GenreCategory(context.l10n.browseGenreArabicRegional, Icons.queue_music_rounded, [
      'طرب',
      'عربي',
      'خليجي',
      'مغربي',
      'شامي',
      'مصري',
      'أندلسي',
      'موشحات',
      'arabic',
      'tarab',
      'khaleeji',
      'oriental',
      'middle eastern'
    ]),
  ];

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return ListView(
      padding: const EdgeInsetsDirectional.fromSTEB(AppSpacing.md, AppSpacing.xs, AppSpacing.md, 120),
      children: [
        for (final category in _categories(context)) ...[
          _buildCategoryGroup(context, category, p),
          const SizedBox(height: AppSpacing.sm),
        ],
        // Remaining uncategorized genres
        _buildUncategorizedGroup(context, p),
      ],
    );
  }

  Widget _buildCategoryGroup(
      BuildContext context, GenreCategory cat, PulsrPalette p) {
    final matching = genres.where((g) {
      final name = g.name.toLowerCase();
      return cat.keywords.any((kw) => name.contains(kw));
    }).toList();

    if (matching.isEmpty) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: p.surfaceCard,
        borderRadius: BorderRadius.circular(AppRadii.r18),
        border: Border.all(color: p.hairline),
      ),
      child: ExpansionTile(
        initiallyExpanded: true,
        shape: const Border(),
        leading: Container(
          padding: const EdgeInsets.all(AppSpacing.xs),
          decoration: BoxDecoration(
            color: p.primary.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(cat.icon, color: p.primary, size: 20),
        ),
        title: Text(
          cat.name,
          style: TextStyle(
            color: p.textPrimary,
            fontSize: AppFontSize.callout,
            fontWeight: FontWeight.w700,
          ),
        ),
        subtitle: Text(
          '${matching.length} ${context.l10n.browseSubGenres} • ${matching.fold<int>(0, (sum, g) => sum + g.songCount)} ${context.l10n.songs}',
          style: TextStyle(color: p.textSecondary, fontSize: AppFontSize.label),
        ),
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(AppSpacing.sm, 0, AppSpacing.sm, AppSpacing.sm),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: matching.map((g) {
                return ActionChip(
                  backgroundColor: p.surfaceContainer,
                  side: BorderSide(color: p.hairline),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadii.r12)),
                  label: Text(
                    '${g.name} (${g.songCount})',
                    style: TextStyle(
                        fontSize: AppFontSize.label,
                        color: p.textPrimary,
                        fontWeight: FontWeight.w600),
                  ),
                  onPressed: () =>
                      context.push('/genre', extra: g),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUncategorizedGroup(BuildContext context, PulsrPalette p) {
    final uncategorized = genres.where((g) {
      final name = g.name.toLowerCase();
      return !_categories(context)
          .any((cat) => cat.keywords.any((kw) => name.contains(kw)));
    }).toList();

    if (uncategorized.isEmpty) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: p.surfaceCard,
        borderRadius: BorderRadius.circular(AppRadii.r18),
        border: Border.all(color: p.hairline),
      ),
      child: ExpansionTile(
        shape: const Border(),
        leading: Container(
          padding: const EdgeInsets.all(AppSpacing.xs),
          decoration: BoxDecoration(
            color: p.accent.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.category_rounded, color: p.accent, size: 20),
        ),
        title: Text(context.l10n.otherGenres,
          style: TextStyle(
            color: p.textPrimary,
            fontSize: AppFontSize.callout,
            fontWeight: FontWeight.w700,
          ),
        ),
        subtitle: Text(
          '${uncategorized.length} ${context.l10n.genres}',
          style: TextStyle(color: p.textSecondary, fontSize: AppFontSize.label),
        ),
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(AppSpacing.sm, 0, AppSpacing.sm, AppSpacing.sm),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: uncategorized.map((g) {
                return ActionChip(
                  backgroundColor: p.surfaceContainer,
                  side: BorderSide(color: p.hairline),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadii.r12)),
                  label: Text(
                    '${g.name} (${g.songCount})',
                    style: TextStyle(
                        fontSize: AppFontSize.label,
                        color: p.textPrimary,
                        fontWeight: FontWeight.w600),
                  ),
                  onPressed: () =>
                      context.push('/genre', extra: g),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}
